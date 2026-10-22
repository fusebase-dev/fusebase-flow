"""Whether a provider's tool hooks run Flow's handler (reader.py's status line and flow.py health; split out of
reader.py in 6.0.0-m8, its 200-line ceiling)."""
from __future__ import annotations

import json
import re
from pathlib import Path


RUNNERS = ("bash", "sh", "python", "python3", "py", "pythonw", "run-handler.sh", "pre_tool_use.py")


def load(path: Path) -> dict:
    """A settings file parsed (a UTF-8 BOM allowed), {} when absent or unreadable."""
    try:
        doc = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return {}
    return doc if isinstance(doc, dict) else {}


def runs_handler(command: str) -> bool:
    """The command runs hooks/handlers/pre_tool_use.py: it names the handler (either slash) and starts with an
    interpreter, run-handler.sh or the handler itself, never echo or printf (m7 review B #5)."""
    words = command.replace("\\", "/").replace('"', " ").replace("'", " ").split()
    first = words[0].rsplit("/", 1)[-1] if words else ""
    return any(w.endswith("hooks/handlers/pre_tool_use.py") for w in words) and (
        first in RUNNERS or first.endswith(("run-handler.sh", ".exe")))


def covers_bash(matcher: object) -> bool:
    """A PreToolUse group's matcher reaches the Bash tool: absent, "", "*", or a pattern Bash matches whole."""
    if matcher in (None, "", "*"):
        return True
    try:
        return bool(re.fullmatch(str(matcher), "Bash"))
    except re.error:
        return False


def wired(root: Path, rel: str) -> str:
    """wired when the provider's settings, parsed, register Flow's PreToolUse handler for the Bash tool: a command that
    runs hooks/handlers/pre_tool_use.py, which exists, in a group whose matcher reaches Bash. Claude Code's
    .claude/settings.local.json counts too, and `disableAllHooks: true` in either file turns every hook off. A mention
    anywhere else, a removed handler or a file that does not parse is no wiring."""
    files = [root / rel] + ([root / ".claude/settings.local.json"] if rel == ".claude/settings.json" else [])
    docs = [load(f) for f in files]
    if any(d.get("disableAllHooks") is True for d in docs):
        return "unenforced"
    for doc in docs:
        groups = (doc.get("hooks") or {}).get("PreToolUse") if isinstance(doc.get("hooks"), dict) else None
        for g in groups if isinstance(groups, list) else []:
            if isinstance(g, dict) and covers_bash(g.get("matcher")) and any(
                    isinstance(h, dict) and runs_handler(str(h.get("command", ""))) for h in g.get("hooks") or []):
                return "wired" if (root / "hooks/handlers/pre_tool_use.py").is_file() else "unenforced"
    return "unenforced"
