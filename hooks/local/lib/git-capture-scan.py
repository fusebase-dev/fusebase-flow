#!/usr/bin/env python3
"""Reject command substitutions that reach git (or a Flow git hook) in gated shell files.

WHY: docs/problem-catalog/msys-git-command-substitution-hang/problem.md. Under MSYS a
Windows-native git descendant can retain the write end of the pipe backing `$(...)`, so the
shell never sees EOF and blocks forever. The 2026-07-03 fix converted one call site and the
regression guard matched that site's exact spelling, so the class walked back in through a
wrapper function and cost the v4.16.3 release.

This is a SHELL-SYNTAX scan, not a string match: it blanks comments, single-quoted strings and
quoted heredocs, walks `$(...)`/backtick substitutions with nesting, and resolves same-file
function calls transitively, so `f() { git status; }; x="$(f)"` is caught with no literal
`$(git` anywhere.
"""
from __future__ import annotations

import re
import sys

HOOK_ARG = re.compile(r"(^|/)(pre-commit|commit-msg|pre-push)(-[A-Za-z0-9._-]+)?$")
RUNNERS = {"bash", "sh", "dash", "ksh", "zsh", ".", "source", "exec"}
# Words that precede the real command word in a simple command.
PREFIXES = {
    "!", "time", "exec", "command", "builtin", "env", "nohup", "then", "else", "elif",
    "do", "done", "fi", "esac", "if", "while", "until", "for", "case", "in", "eval",
}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")
FUNC_HEAD = re.compile(r"(?m)^[ \t]*(?:function[ \t]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[ \t]*\(\)[ \t]*")


def blank_inert(src: str) -> str:
    """Same-length copy with comments, single-quoted text and quoted heredocs blanked.

    Double-quoted text and UNquoted heredoc bodies stay: the shell expands `$(...)` in both.
    """
    out = list(src)
    n = len(src)
    i = 0
    prev_significant = "\n"
    pending: list[tuple[str, bool, bool]] = []  # (delimiter, quoted, strip_tabs)
    while i < n:
        c = src[i]
        if c == "\\" and i + 1 < n:
            i += 2
            prev_significant = "\\"
            continue
        if c == "'":
            j = src.find("'", i + 1)
            j = n if j < 0 else j
            for k in range(i, min(j + 1, n)):
                out[k] = " "
            i = min(j + 1, n)
            prev_significant = "'"
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            i = min(j + 1, n)
            prev_significant = '"'
            continue
        if c == "#" and prev_significant in ("\n", " ", "\t", ";", "(", ")", "&", "|"):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            prev_significant = "\n"
            continue
        if c == "<" and src.startswith("<<", i) and not src.startswith("<<<", i):
            m = re.match(r"<<(-?)[ \t]*((?:\\?[A-Za-z_][A-Za-z0-9_]*)|'[^']*'|\"[^\"]*\")", src[i:])
            if m:
                raw = m.group(2)
                quoted = raw[0] in "'\"" or raw.startswith("\\")
                delim = raw.strip("'\"").lstrip("\\")
                pending.append((delim, quoted, m.group(1) == "-"))
                i += m.end()
                prev_significant = "w"
                continue
        if c == "\n" and pending:
            i += 1
            while pending:
                delim, quoted, strip_tabs = pending.pop(0)
                end = n
                probe = i
                while probe < n:
                    nl = src.find("\n", probe)
                    nl = n if nl < 0 else nl
                    line = src[probe:nl]
                    if (line.lstrip("\t") if strip_tabs else line).rstrip("\r") == delim:
                        end = probe
                        break
                    probe = nl + 1
                if quoted:
                    for k in range(i, min(end, n)):
                        if src[k] != "\n":
                            out[k] = " "
                nl = src.find("\n", end)
                i = n if nl < 0 else nl + 1
            prev_significant = "\n"
            continue
        prev_significant = c
        i += 1
    return "".join(out)


def match_paren(code: str, start: int) -> int:
    """Index just past the `)` closing the `(` at `start`, or len(code)."""
    depth = 0
    i = start
    n = len(code)
    while i < n:
        c = code[i]
        if c == "\\":
            i += 2
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def substitutions(code: str, lo: int = 0, hi: int | None = None):
    """Yield (open_index, body) for every command substitution in code[lo:hi]."""
    hi = len(code) if hi is None else hi
    i = lo
    while i < hi:
        if code[i] == "\\":                    # `\$(` / `\`` are literal text, not expansions
            i += 2
            continue
        if code.startswith("$((", i):          # arithmetic, not a command
            i = match_paren(code, i + 1)
            continue
        if code.startswith("$(", i):
            end = match_paren(code, i + 1)
            body = code[i + 2:max(end - 1, i + 2)]
            if not body.lstrip().startswith("<"):   # `$(<file)` reads a file, spawns nothing
                yield i, body
            i += 2
            continue
        if code[i] == "`":
            end = code.find("`", i + 1)
            end = hi if end < 0 else end
            yield i, code[i + 1:end]
            i = end + 1
            continue
        i += 1


def commands(body: str):
    """Yield the word list of every simple command in a fragment of shell text."""
    for frag in re.split(r"(?:\|\||&&|[;\n|&(){}])", body):
        words = [w for w in re.split(r"[ \t]+", frag.strip()) if w]
        while words and (ASSIGN.match(words[0]) or words[0] in PREFIXES):
            words.pop(0)
        if words:
            yield words


def basename(word: str) -> str:
    return word.rsplit("/", 1)[-1].strip("\"'")


def functions(code: str) -> dict[str, str]:
    """name -> body text, for functions defined in this file."""
    out: dict[str, str] = {}
    for m in FUNC_HEAD.finditer(code):
        brace = code.find("{", m.end())
        if brace < 0:
            continue
        depth = 0
        i = brace
        while i < len(code):
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        out[m.group(1)] = code[brace + 1:i]
    return out


def direct_reason(words: list[str]) -> str | None:
    cmd = basename(words[0])
    if cmd == "git":
        return "runs `git`"
    if cmd in RUNNERS:
        for arg in words[1:]:
            if HOOK_ARG.search(arg.strip("\"'")):
                return "runs the git hook `%s`" % arg.strip("\"'")
    if HOOK_ARG.search(words[0].strip("\"'")):
        return "runs the git hook `%s`" % words[0].strip("\"'")
    return None


def reaching(code: str) -> dict[str, str]:
    """Same-file functions that reach git/a hook, directly or through another function."""
    fns = functions(code)
    reason: dict[str, str] = {}
    for name, body in fns.items():
        for words in commands(body):
            r = direct_reason(words)
            if r:
                reason[name] = r
                break
    changed = True
    while changed:
        changed = False
        for name, body in fns.items():
            if name in reason:
                continue
            for words in commands(body):
                callee = basename(words[0])
                if callee in reason and callee != name:
                    reason[name] = "calls `%s`, which %s" % (callee, reason[callee])
                    changed = True
                    break
    return reason


def scan(src: str, path: str) -> list[str]:
    code = blank_inert(src)
    reason = reaching(code)
    findings: list[str] = []
    for start, body in substitutions(code):
        hit = None
        for words in commands(body):
            hit = direct_reason(words)
            if hit:
                break
            callee = basename(words[0])
            if callee in reason:
                hit = "calls `%s`, which %s" % (callee, reason[callee])
                break
        if hit:
            line = src.count("\n", 0, start) + 1
            snippet = " ".join(src[start:start + 90].split())
            findings.append("%s:%d: command substitution %s -- %s" % (path, line, hit, snippet))
    return findings


def main(argv: list[str]) -> int:
    paths = argv[1:]
    if not paths:
        print("usage: git-capture-scan.py FILE [FILE...]", file=sys.stderr)
        return 2
    findings: list[str] = []
    for path in paths:
        try:
            with open(path, encoding="utf-8") as fh:
                src = fh.read()
        except OSError as exc:
            print("git-capture-scan: cannot read %s (%s)" % (path, exc), file=sys.stderr)
            return 2
        findings.extend(scan(src, path))
    for f in findings:
        print(f)
    if findings:
        print(
            "\n%d command substitution(s) capture a git/hook process tree. Under MSYS a native"
            "\ngit descendant can hold that pipe open past exit and the shell blocks forever."
            "\nCapture via a FILE redirect (`git ... > f`) and read it back, or bound the run at"
            "\nthe operation with ffhc_run_bounded. See"
            "\ndocs/problem-catalog/msys-git-command-substitution-hang/problem.md."
            % len(findings)
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
