#!/usr/bin/env python3
"""
Fusebase Flow — settings.json merge (Python implementation).

No `jq` dependency — Python 3 is already a Fusebase Flow hook-runtime requirement
(see hooks/handlers/*.py + hooks/requirements.txt), so this adds zero new
dependencies and works on Windows out of the box.

Adds the missing Fusebase Flow lifecycle event keys and appends Fusebase Flow's
stop.py hook to the existing Stop array — only if each piece is not already
present.

UPGRADE POSTURE:
    The set of events, handler commands, and matchers is auto-discovered at
    runtime from the upstream `.fusebase-flow-source/.claude/settings.json.example`
    file. This means minor upstream releases that add/rename/move events require
    ZERO maintenance to this script. Falls back to a hardcoded 6-event set if the
    upstream clone isn't available (e.g. fresh project install before the clone
    is set up).

Idempotent: safe to run multiple times; second run is a byte-identical no-op.

Usage:
    python3 hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json

Exit codes:
    0  merge complete (or no merge needed — already in place)
    1  file not found / not valid JSON / write error
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# Default Fusebase Flow hook commands. Used when upstream `.fusebase-flow-source/`
# clone is not available. Auto-discovered from the upstream when present.
DEFAULT_FLOW_HOOKS = {
    "SessionStart":     'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/session_start.py',
    "UserPromptSubmit": 'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/user_prompt_submit.py',
    "PreToolUse":       'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_tool_use.py',
    "PostToolUse":      'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/post_tool_use.py',
    "Stop":             'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/stop.py',
    "PreCompact":       'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_compact.py',
}

# Default matchers per Claude Code conventions. Auto-discovered from upstream
# when available.
DEFAULT_EVENT_MATCHERS = {
    "PreToolUse":  "Bash|Edit|Write|MultiEdit|NotebookEdit",
    "PostToolUse": "Edit|Write|MultiEdit|NotebookEdit",
}


def discover_flow_config_from_upstream() -> tuple[dict[str, str], dict[str, str]] | tuple[None, None]:
    """Read upstream .fusebase-flow-source/.claude/settings.json.example to
    discover the canonical event names, handler commands, and matchers.

    The upstream example uses ${PROJECT_DIR} as a placeholder; we rewrite it
    to "$CLAUDE_PROJECT_DIR" to match Claude Code's runtime substitution.

    Returns (FLOW_HOOKS, EVENT_MATCHERS) on success, or (None, None) if the
    upstream clone or its example file isn't reachable.
    """
    candidates = [
        Path('.fusebase-flow-source/.claude/settings.json.example'),
        Path('../.fusebase-flow-source/.claude/settings.json.example'),
    ]
    for example_path in candidates:
        if not example_path.is_file():
            continue
        try:
            data = json.loads(example_path.read_text(encoding='utf-8'))
        except Exception:
            continue
        hooks = data.get('hooks') or {}
        if not isinstance(hooks, dict) or not hooks:
            continue
        discovered_hooks: dict[str, str] = {}
        discovered_matchers: dict[str, str] = {}
        for event, blocks in hooks.items():
            if not isinstance(blocks, list) or not blocks:
                continue
            block = blocks[0]
            if not isinstance(block, dict):
                continue
            if isinstance(block.get('matcher'), str):
                discovered_matchers[event] = block['matcher']
            handlers = block.get('hooks')
            if not isinstance(handlers, list) or not handlers:
                continue
            cmd = handlers[0].get('command') if isinstance(handlers[0], dict) else None
            if not isinstance(cmd, str):
                continue
            # Upstream example uses ${PROJECT_DIR}; Claude Code substitutes
            # $CLAUDE_PROJECT_DIR at runtime. Normalize.
            cmd_norm = cmd.replace('${PROJECT_DIR}', '"$CLAUDE_PROJECT_DIR"')
            discovered_hooks[event] = cmd_norm
        if discovered_hooks:
            return discovered_hooks, discovered_matchers
    return None, None


# Resolve final config: prefer upstream-discovered, fall back to hardcoded defaults
_disc_hooks, _disc_matchers = discover_flow_config_from_upstream()
FLOW_HOOKS: dict[str, str] = _disc_hooks if _disc_hooks else DEFAULT_FLOW_HOOKS
EVENT_MATCHERS: dict[str, str] = _disc_matchers if _disc_matchers else DEFAULT_EVENT_MATCHERS

# Sanity: always need a Stop event for the stop.py append logic to work.
if "Stop" not in FLOW_HOOKS:
    FLOW_HOOKS["Stop"] = DEFAULT_FLOW_HOOKS["Stop"]


def make_event_block(event: str) -> dict[str, Any]:
    """Build the `[{matcher?, hooks: [...]}]` array for a given event."""
    block: dict[str, Any] = {"hooks": [{"type": "command", "command": FLOW_HOOKS[event], "timeout": 30}]}
    if event in EVENT_MATCHERS:
        block["matcher"] = EVENT_MATCHERS[event]
    return block


def merge_settings(settings: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    """Return (updated settings, list of changes applied)."""
    changes: list[str] = []
    hooks = settings.setdefault("hooks", {})

    # All non-Stop events from FLOW_HOOKS get added wholesale if missing.
    # Stop is handled separately below (it merges into existing CLI hook chain).
    for event in FLOW_HOOKS:
        if event == "Stop":
            continue
        if event not in hooks or not hooks[event]:
            hooks[event] = [make_event_block(event)]
            changes.append(f"added {event} event")

    # Stop event: preserve existing CLI hooks; append Fusebase Flow stop.py only if missing
    if "Stop" not in hooks or not hooks["Stop"]:
        hooks["Stop"] = [{"hooks": [{
            "type": "command",
            "command": FLOW_HOOKS["Stop"],
            "statusMessage": "Fusebase Flow stop hook…",
            "timeout": 30,
        }]}]
        changes.append("added Stop event with Fusebase Flow stop.py")
    else:
        # Stop array exists; check first block's hooks chain for our stop.py
        stop_block = hooks["Stop"][0]
        stop_hooks = stop_block.setdefault("hooks", [])
        already_present = any(
            "hooks/handlers/stop.py" in h.get("command", "")
            for h in stop_hooks
        )
        if not already_present:
            stop_hooks.append({
                "type": "command",
                "command": FLOW_HOOKS["Stop"],
                "statusMessage": "Fusebase Flow stop hook…",
                "timeout": 30,
            })
            changes.append("appended Fusebase Flow stop.py to existing Stop chain")

    return settings, changes


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python3 settings-json-merge.py <settings.json path>", file=sys.stderr)
        return 1

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"ERROR: {path} not found", file=sys.stderr)
        return 1

    try:
        original_text = path.read_text(encoding="utf-8")
        settings = json.loads(original_text)
    except json.JSONDecodeError as exc:
        print(f"ERROR: {path} is not valid JSON: {exc}", file=sys.stderr)
        return 1

    updated, changes = merge_settings(settings)

    if not changes:
        print(f"[settings-merge] {path}: already up to date (no changes needed)")
        return 0

    new_text = json.dumps(updated, indent=2, ensure_ascii=False) + "\n"
    if new_text == original_text:
        print(f"[settings-merge] {path}: byte-identical after merge (no-op)")
        return 0

    path.write_text(new_text, encoding="utf-8")
    print(f"[settings-merge] {path}: applied {len(changes)} change(s):")
    for c in changes:
        print(f"  - {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
