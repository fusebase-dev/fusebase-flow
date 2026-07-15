"""W1 (dead-end tool/script references) + W3 (missing helpers).

Conservative: only ROOT-EXPLICIT paths (starting from a known repo dir, or a
known root-prefix var stripped) are ever `broken`. A cwd-ambiguous command path
(`cd hooks && python local/x.py`) or a placeholder/variable path is `unresolved`
coverage — we never confirm a dead reference whose base we cannot prove.
"""
from __future__ import annotations

import re

from .constants import (
    W1, W3, TIER_BROKEN, CONFIRMED, SEV_MAJOR, SEV_MINOR,
    has_placeholder, strip_root_prefix, is_root_explicit, strip_heredocs,
)
from .markdown import iter_lines
from .model import Finding

_COMMAND_INFOS = {"sh", "bash", "shell", "zsh", "console", "sh-session",
                  "", "py", "python", "python3"}
_INLINE_CODE_RE = re.compile(r"`([^`]+)`")
# EXECUTION-context match only (north star = dead-end *tool calls*): an interpreter
# (bash/sh/python/py, optional sudo/env + flags) or `./` directly in front of a
# .py/.sh path. This deliberately does NOT match bare paths that are arguments to
# touch/rm/cat/ls etc., nor bare template/data-file mentions — those are not tool
# calls and were the dominant false-positive class on real specs.
_CMD_FORM_RE = re.compile(
    r"(?:(?:^|[\s|;&(])(?:sudo\s+)?(?:env\s+)?(?:bash|sh|python3?|py)\s+(?:-\S+\s+)*"
    r"|(?:^|[\s|;&(])\./)(?P<p>\"?[\w./${}()-]+\.(?:py|sh))")
# Bare (no-interpreter) path accepted ONLY inside inline code AND only under dirs
# that hold exclusively runnable scripts, so a mention IS a reference to a tool.
_RUNNABLE_BARE_RE = re.compile(
    r"(?P<full>(?:\$CLAUDE_PROJECT_DIR/|\$\{CLAUDE_PROJECT_DIR\}/|"
    r"\$\(git rev-parse --show-toplevel\)/|\$ROOT/|\$\{ROOT\}/|\./)?"
    r"(?:hooks/|\.claude/hooks/)[\w./-]*?\.(?:py|sh))")

_IGNORE_RE = re.compile(r"find-wasted-code:\s*ignore\s+(W\d)")

_SEV_MAJOR_SURFACES = ("flow-skills/", ".claude/commands/", "README.md",
                       "AGENTS.md", "CLAUDE.md")


def _severity(path):
    return SEV_MAJOR if any(s in ("/" + path) or path.startswith(s)
                            or path.endswith(s) for s in _SEV_MAJOR_SURFACES) else SEV_MINOR


def _ignored(line, rule):
    m = _IGNORE_RE.search(line)
    return bool(m and m.group(1) == rule)


def _resolve_token(tok):
    """Return ('broken'|'ok'|'unresolved', normalized_path)."""
    tok = tok.strip().strip('"').strip("'")
    stripped, _ = strip_root_prefix(tok)
    if has_placeholder(stripped):
        return "unresolved", stripped
    if not is_root_explicit(stripped):
        return "unresolved", stripped   # cwd-ambiguous — cannot prove base
    return "check", stripped


def scan_w1(inv, cov, path, text):
    cov.rules_run.add(W1)
    seen = set()
    for lineno, line, in_fence, info in iter_lines(text):
        if _ignored(line, W1):
            cov.dismiss(W1, path, lineno)
            continue
        candidates = []
        if in_fence:
            if info in _COMMAND_INFOS:
                candidates = [m.group("p") for m in _CMD_FORM_RE.finditer(line)]
        else:
            for span in _INLINE_CODE_RE.findall(line):
                candidates += [m.group("p") for m in _CMD_FORM_RE.finditer(span)]
                # A BARE path counts only when the inline-code span IS exactly that
                # path (a reference like `hooks/local/x.sh`), never when it is an
                # argument to another command (`rm hooks/local/x.sh`) — that would
                # reintroduce the touch/rm/mv false-positive class.
                bm = _RUNNABLE_BARE_RE.fullmatch(span.strip())
                if bm:
                    candidates.append(bm.group("full"))
        for tok in candidates:
            verdict, norm = _resolve_token(tok)
            key = (lineno, norm)
            if key in seen:
                continue
            seen.add(key)
            if verdict == "unresolved":
                cov.unresolve(W1, path, lineno, "cwd-ambiguous-or-placeholder: %s" % norm)
                continue
            if inv.exists(norm):
                continue
            real = inv.case_mismatch(norm)
            note = ("case-mismatch: tracked as %s" % real) if real else \
                "referenced script/doc does not exist in the repo"
            yield Finding(
                W1, TIER_BROKEN, CONFIRMED, _severity(path), path, lineno,
                norm, "Fix the path, restore the file, or remove the instruction.", note)


# --- W3 -------------------------------------------------------------------
# A source statement that is the WHOLE line: `source <bare-path>` (+ optional comment).
_SOURCE_STMT_RE = re.compile(
    r"^\s*(?:source|\.)\s+([^\s;&|#'\"]+\.(?:sh|bash))\s*(?:#.*)?$")


def _shell_stmt_lines(lines):
    """Yield (lineno, line, starts_in_context) where starts_in_context is True when
    the line begins inside an unterminated quote or after a `\\` continuation — such
    a line is not a fresh statement, so a `source …` on it must NOT be confirmed."""
    q = None
    cont = False
    for idx, line in enumerate(lines, 1):
        yield idx, line, (q is not None or cont)
        esc = False
        prev = " "                  # start-of-line counts as a word boundary for `#`.
        for c in line:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif q is None and c == "#" and (prev.isspace() or prev in "(;&|"):
                break               # a `#` at a word boundary starts a comment — ignore the rest.
            elif q is None and c in "\"'":
                q = c
            elif c == q:
                q = None
            prev = c
        stripped = line.rstrip()
        trailing_bs = len(stripped) - len(stripped.rstrip("\\"))
        cont = (trailing_bs % 2) == 1   # an ODD run of trailing backslashes continues.
_FM_LIST_KEY_RE = re.compile(r"^(related_workflows|hook_dependencies):\s*(.*)$")
_FM_ITEM_RE = re.compile(r"^\s*-\s*(.+?)\s*$")


def _frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], 2   # body lines, starting lineno of first key
    return None


def scan_w3(inv, cov, path, text):
    cov.rules_run.add(W3)
    # (a) frontmatter related_workflows (skills/commands only).
    if path.endswith("SKILL.md") or path.startswith(".claude/commands/"):
        fm = _frontmatter(text)
        if fm:
            body, base = fm
            i = 0
            while i < len(body):
                line = body[i]
                m = _FM_LIST_KEY_RE.match(line)
                if m:
                    key, inline = m.group(1), m.group(2).strip()
                    items = []
                    if inline.startswith("[") and inline.endswith("]"):
                        items = [x.strip().strip("'\"") for x in inline[1:-1].split(",") if x.strip()]
                    else:
                        j = i + 1
                        while j < len(body):
                            im = _FM_ITEM_RE.match(body[j])
                            if not im:
                                break
                            items.append(im.group(1).strip().strip("'\""))
                            j += 1
                        i = j - 1
                    for it in items:
                        if key == "related_workflows" and it and it.lower() != "none":
                            # The field is used inconsistently across skills: some
                            # entries are workflow filenames (workflows/<x>.md), some
                            # are repo-relative script paths, some are skill names. A
                            # miss is therefore NOT provably a dead reference — resolve
                            # against every known shape and, if none match, record it as
                            # unresolved coverage rather than a confirmed defect.
                            stem = it[:-3] if it.endswith(".md") else it
                            candidates = [it, "workflows/%s" % it,
                                          "flow-skills/%s/SKILL.md" % stem]
                            if has_placeholder(it):
                                cov.unresolve(W3, path, base + i, "workflow placeholder: %s" % it)
                            elif not any(inv.exists(c) for c in candidates):
                                cov.unresolve(W3, path, base + i,
                                              "related_workflows entry resolves nowhere: %s" % it)
                        elif key == "hook_dependencies" and it and it.lower() != "none":
                            cov.unresolve(W3, path, base + i, "hook_dependencies form not resolved: %s" % it)
                i += 1
    # (b) shell `source`/`.` of a static root-explicit script. Confirmed ONLY when
    # the source is the WHOLE statement — an unquoted bare path optionally trailed by
    # a comment. Anything with quotes, guards, string context, or other commands on
    # the line does not match (a false negative at worst, never a false positive);
    # heredoc bodies are blanked so an in-heredoc `source …` is not a statement.
    if path.endswith((".sh", ".bash")):
        for lineno, line, in_context in _shell_stmt_lines(strip_heredocs(text.split("\n"))):
            if in_context or _ignored(line, W3):
                continue
            m = _SOURCE_STMT_RE.match(line)
            if not m:
                continue
            stripped, _ = strip_root_prefix(m.group(1))
            if has_placeholder(stripped) or "$" in stripped:
                cov.unresolve(W3, path, lineno, "dynamic source path: %s" % stripped)
                continue
            if not is_root_explicit(stripped):
                cov.unresolve(W3, path, lineno, "cwd-relative source: %s" % stripped)
                continue
            if not inv.exists(stripped):
                yield Finding(
                    W3, TIER_BROKEN, CONFIRMED, SEV_MAJOR, path, lineno,
                    stripped, "Restore the sourced file or fix the path.",
                    "shell sources a file that does not exist")
