"""Whether a provider's tool hooks run Flow's handler (reader.py's status line and flow.py health; split out of
reader.py in 6.0.0-m8, its 200-line ceiling)."""
from __future__ import annotations

import json
from pathlib import Path


def wired(root: Path, rel: str) -> str:
    """wired when the provider's settings, parsed, register Flow's PreToolUse handler: a command under hooks.PreToolUse
    naming hooks/handlers/pre_tool_use.py, which exists (6.0.0-m7 item 4). A mention anywhere else in the file, a
    removed handler (a migrated 5.x wiring) or a file that does not parse is no wiring."""
    try:
        groups = json.loads((root / rel).read_text(encoding="utf-8"))["hooks"]["PreToolUse"]
        commands = [str(h.get("command", "")) for g in groups for h in g.get("hooks") or []]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return "unenforced"
    ok = (root / "hooks/handlers/pre_tool_use.py").is_file() and any("hooks/handlers/pre_tool_use.py" in c for c in commands)
    return "wired" if ok else "unenforced"
