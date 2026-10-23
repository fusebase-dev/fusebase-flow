"""Fusebase Flow — command_rules: the shape of one command-policy rule.

Extracted from command_policy.py on the rule-shape responsibility seam (FR-25) when
per-rule `flags` and `any_of` landed. command_policy owns decisions; this module owns
"what is a rule, does it match, and which actions does it demand".

Rule shape (locked by decision K5's task):
    {pattern, action | any_of, flags?, reason, rule_id, only_when?}
`action` and `any_of` are mutually exclusive and exactly one is required on a
require_approval rule. `flags` accepts ["i"] only, for now.
"""
from __future__ import annotations

import contextvars
import re
from typing import Any

# TRIPWIRE: widening this map widens what a policy author can switch on per rule.
# Anything beyond case-insensitivity (DOTALL, VERBOSE, MULTILINE) changes how patterns
# read against a whole command line and needs its own review; unknown flags FAIL CLOSED.
_FLAG_MAP = {"i": re.IGNORECASE}


def rule_flags(rule: dict[str, Any], stage: str) -> tuple[int, str | None]:
    """(compiled re flags, policy-error detail). An unknown flag denies (K4)."""
    raw = rule.get("flags")
    if raw is None:
        return 0, None
    if isinstance(raw, str):
        raw = [raw]
    if not isinstance(raw, list):
        return 0, f"{stage} rule `flags` must be a list (got {type(raw).__name__})"
    out = 0
    for f in raw:
        if not isinstance(f, str) or f not in _FLAG_MAP:
            return 0, f"{stage} rule has unsupported flag {f!r} (supported: {sorted(_FLAG_MAP)})"
        out |= _FLAG_MAP[f]
    return out, None


def rule_actions(rule: dict[str, Any], stage: str) -> tuple[list[str], str | None]:
    """(actions this rule demands, policy-error detail).

    A single `action` yields one entry. `any_of` yields the full list, and the rule is
    satisfied when ANY of them has an acceptable artifact (decision K5). The FIRST entry
    is the rule's display name for the denial renderer and the --inventory report.
    """
    action = rule.get("action")
    any_of = rule.get("any_of")
    if action is not None and any_of is not None:
        return [], f"{stage} rule sets both `action` and `any_of` (mutually exclusive)"
    if any_of is not None:
        if not isinstance(any_of, list) or not any_of or not all(
            isinstance(a, str) and a.strip() for a in any_of
        ):
            return [], f"{stage} rule `any_of` must be a non-empty list of action names"
        return [a.strip() for a in any_of], None
    if isinstance(action, str) and action.strip():
        return [action.strip()], None
    if stage == "require_approval":
        return [], f"{stage} rule declares neither `action` nor `any_of`"
    return [], None


# The shell the command is written for; command_policy.evaluate sets it per call. A PowerShell line is matched on its
# raw text, as in 6.0.0-m7: the allowlist below reads bash.
SHELL: contextvars.ContextVar[str] = contextvars.ContextVar("flow_command_shell", default="bash")

# THE ALLOWLIST (6.0.0-m8, the owner's cut of 2026-10-22: 6.0.0-m7's matcher over allowlisted text, exactly as the
# kill test measured it). Two kinds of text leave a bash line before the rules see it, and nothing else does:
#   1. a heredoc body, unless the line that opens it runs a shell, ssh, a container shell, xargs or a database client
#      (RUNS_CODE): `cat > notes.md <<'EOF'` writes data, `ssh host <<'EOF'` runs its body;
#   2. the quoted arguments of grep, egrep, fgrep, printf, echo and sed (DATA_PROGRAMS), unless that echo or printf is
#      piped into a program RUNS_CODE names (`echo 'rm -rf x' | sh` runs it).
# TRIPWIRE: widening either list lets a gated command past every rule (a heredoc into `bash`, `printf ... | sh`). Text
# outside them that quotes a gated command (a commit message) is still refused and is reworded, never allowlisted.
DATA_PROGRAMS = {"grep", "egrep", "fgrep", "printf", "echo", "sed"}
RUNNER_NAMES = "bash|sh|zsh|dash|ksh|fish|ssh|docker|podman|kubectl|xargs|psql|mysql|sqlite3"
# A runner in any spelling (reviewer B's cut re-check (a)): bare, by path (/bin/bash, C:/.../bash.exe, quoted with its
# spaces), quoted ("bash"), with .exe, or with the heredoc attached (bash<<EOF).
RUNS_CODE = re.compile(r"""(?:^|[|;&(\s])(?:"[^"\n]*?[/\\]|'[^'\n]*?[/\\]|["']|[^\s"'|;&()<>]*[/\\])?"""
                       rf"(?:{RUNNER_NAMES})(?i:\.exe)?[\"']?(?=\s|$|<|[|;&)])")
HEREDOC = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def heredoc_openers(line: str) -> list:
    """Each `<<WORD` (or `<<-WORD`) that bash reads as a heredoc: in code, never inside quotes or a comment, and never
    `<<<` (reviewer B's cut re-check (b)). `$(...)` and backticks are code again inside double quotes, so the heredoc in
    `git commit -m "$(cat <<'EOF' ...)"` is one."""
    found, i = [], 0
    stack = [["code", 0]]  # contexts: code (with its open parentheses), a backtick, a double or a single quote
    while i < len(line):
        c, top = line[i], stack[-1]
        if top[0] == "'":
            if c == "'":
                stack.pop()
        elif top[0] == '"':
            if c == "\\":
                i += 2
                continue
            if c == '"':
                stack.pop()
            elif line.startswith("$(", i):
                stack.append(["code", 0])
                i += 2
                continue
            elif c == "`":
                stack.append(["`", 0])
        elif c == "\\":
            i += 2
            continue
        elif c in "'\"":
            stack.append([c, 0])
        elif c == "`":
            if top[0] == "`":
                stack.pop()
            else:
                stack.append(["`", 0])
        elif c == "#" and (i == 0 or line[i - 1] in " \t;&|("):
            break
        elif line.startswith("$(", i):
            stack.append(["code", 0])
            i += 2
            continue
        elif c == "(":
            top[1] += 1
        elif c == ")" and len(stack) > 1:
            if top[1]:
                top[1] -= 1
            else:
                stack.pop()
        elif line.startswith("<<<", i):
            i += 3
            continue
        elif line.startswith("<<", i):
            m = HEREDOC.match(line, i)
            if m:
                found.append(m)
                i = m.end()
                continue
        i += 1
    return found


def strip_heredocs(text: str) -> str:
    """`text` without the body of each heredoc whose opening line runs nothing RUNS_CODE names (its delimiter
    lines stay)."""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        runs_code = bool(RUNS_CODE.search(line))
        pending = [(m.group(3), m.group(1) == "-") for m in heredoc_openers(line)]
        i += 1
        for word, tabs in pending:
            while i < len(lines):
                body = lines[i].lstrip("\t") if tabs else lines[i]
                if runs_code:
                    out.append(lines[i])
                i += 1
                if body == word:
                    if not runs_code:
                        out.append(lines[i - 1])
                    break
    return "\n".join(out)


def _segments(text: str):
    """(start, end) of each stretch between the separators ; & | ( ) and a newline that stand outside quotes."""
    start, i, q = 0, 0, None
    while i < len(text):
        c = text[i]
        if q:
            if c == "\\" and q == '"':
                i += 2
                continue
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "\\":
            i += 2
            continue
        elif c in ";&|\n()":
            yield start, i
            start = i + 1
        i += 1
    yield start, len(text)


def blank_safe_quotes(text: str) -> str:
    """`text` with the quoted arguments of a DATA_PROGRAMS command blanked (each character a space), unless it is an
    echo or printf whose output is piped into a program RUNS_CODE names."""
    chars = list(text)
    spans = list(_segments(text))
    for n, (s, e) in enumerate(spans):
        words = text[s:e].split()
        k = 0
        while k < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[k]):
            k += 1
        name = re.split(r"[/\\]", words[k].strip("\"'"))[-1] if k < len(words) else ""
        name = name[:-4] if name.lower().endswith(".exe") else name
        if name not in DATA_PROGRAMS:
            continue
        if name in ("echo", "printf") and _feeds_a_runner(text, spans, n):
            continue
        i, q = s, None
        while i < e:
            c = text[i]
            if q:
                if c == "\\" and q == '"':
                    chars[i:i + 2] = [" "] * len(chars[i:i + 2])
                    i += 2
                    continue
                if c == q:
                    q = None
                else:
                    chars[i] = " "
            elif c in "'\"":
                q = c
            i += 1
    return "".join(chars)


def _feeds_a_runner(text: str, spans: list, n: int) -> bool:
    """Whether segment n's output is piped into a RUNS_CODE program: the segments after it while each is joined by a
    pipe, up to the next other unquoted separator (reviewer B's cut re-check (c): not the rest of the line)."""
    while n + 1 < len(spans) and spans[n][1] < len(text) and text[spans[n][1]] == "|":
        n += 1
        if RUNS_CODE.search(text[spans[n][0]:spans[n][1]]):
            return True
    return False


_ALLOWLISTED: dict[tuple[str, str], str] = {}


def allowlisted(command: str) -> str:
    """The text the rules match: a bash `command` with THE ALLOWLIST applied; any other shell's, as written. Computed
    once per command and shell, not once per rule (reviewer B's cut re-check (c))."""
    shell = SHELL.get().strip().lower()
    if shell not in ("bash", "sh", ""):
        return command
    key = (command, shell)
    if key not in _ALLOWLISTED:
        if len(_ALLOWLISTED) > 16:
            _ALLOWLISTED.clear()
        _ALLOWLISTED[key] = blank_safe_quotes(strip_heredocs(command))
    return _ALLOWLISTED[key]


def rule_matches(rule: Any, command: str, stage: str) -> tuple[bool, str | None]:
    """(matched, policy-error detail). A defective rule NEVER silently skips (K4).

    TRIPWIRE: `re.error` and a malformed rule must DENY, not `continue`. The original
    code skipped both, so a typo in a deny pattern silently disabled that rule and the
    command fell through to `default: allow` — a gate whose failure mode is "allow".

    MATCHING IS REGEX OVER THE RAW COMMAND STRING (K21), after THE ALLOWLIST above takes out a heredoc body a
    non-shell reads and the quoted arguments of grep, printf, echo and sed (6.0.0-m8, the owner's cut of 2026-10-22).
    """
    if not isinstance(rule, dict):
        return False, f"{stage} rule is not a mapping"
    pattern = rule.get("pattern")
    if not isinstance(pattern, str) or not pattern:
        return False, f"{stage} rule has no usable `pattern`"
    flags, err = rule_flags(rule, stage)
    if err:
        return False, err
    try:
        return bool(re.search(pattern, allowlisted(command), flags)), None
    except re.error as e:
        return False, f"{stage} rule pattern {pattern!r} is not a valid regex ({e})."


# One whole approve-local.sh invocation, with or without a leading `bash`: each word is single-quoted, double-quoted
# with no `$`, backtick or backslash inside, or bare and free of shell syntax. A command with anything else outside its
# --command argument (`;`, `&&`, `||`, `|`, a newline, `$(...)`, backticks, a redirection) does not match.
_WORD = r"""(?:'[^']*'|"[^"$`\\]*"|[A-Za-z0-9_./:=@%+,-]+)"""
# Its action argument may be any approval action (T389, the owner's option A of 2026-10-23, reversing T284's
# destructive_file_delete only); approve-local.sh itself refuses an action the policy does not declare.
_MINT = re.compile(rf"[ \t]*(?:bash[ \t]+)?(?:\./)?hooks/local/approve-local\.sh"
                   rf"(?:[ \t]+{_WORD})*?[ \t]+--command[ \t]+({_WORD})(?:[ \t]+{_WORD})*[ \t]*")


def mint_subject(command: str) -> str:
    """The text the rules judge for `command`: the command itself, except that one whole approve-local.sh invocation,
    for any action, is judged with its --command argument blanked. That argument is the command the approval binds, not
    one that runs, so the mint is not refused by the rule it mints for (brief m5 item 6; T389 reverses T284's
    narrowing); the rest of the invocation is still judged, and the approved command itself is judged when it runs."""
    m = _MINT.fullmatch(command)
    return command if not m else f"{command[:m.start(1)]}''{command[m.end(1):]}"


__all__ = ["SHELL", "allowlisted", "blank_safe_quotes", "mint_subject", "rule_actions", "rule_flags", "rule_matches",
           "strip_heredocs"]
