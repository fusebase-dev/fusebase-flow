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
    python3 .../settings-json-merge.py .claude/settings.json --baseline-out state/audit/cli-stop-baseline.json

`--baseline-out PATH` writes the durable CLI-Stop-hook receipt the health-check
reads (single-sources the "CLI-owned iff it names a file under .claude/hooks/"
rule the reporter uses). Why a receipt and not the pre-merge backup: spec D1
(post-fusebase-update.sh overwrites .pre-flow-merge before every merge).

Exit codes:
    0  merge complete (or no merge needed — already in place; receipt written)
    1  file not found / not valid JSON / write error
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

# Default Fusebase Flow hook commands. Used when upstream `.fusebase-flow-source/`
# clone is not available. Auto-discovered from the upstream when present.
# Commands route through hooks/local/run-handler.sh (interpreter auto-detect +
# graceful self-degrade on a python-less machine). The FULL handler path is passed so
# the `hooks/handlers/<x>.py` substring stays in the command — both the discovery above
# (`'hooks/handlers/' in hc`) and the Stop-detection below key on that substring.
DEFAULT_FLOW_HOOKS = {
    "SessionStart":     'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/session_start.py',
    "UserPromptSubmit": 'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/user_prompt_submit.py',
    "PreToolUse":       'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_tool_use.py',
    "PostToolUse":      'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/post_tool_use.py',
    "Stop":             'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/stop.py',
    "PreCompact":       'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_compact.py',
}

# Default matchers per Claude Code conventions. Auto-discovered from upstream
# when available.
DEFAULT_EVENT_MATCHERS = {
    "PreToolUse":  "Bash|Edit|Write|MultiEdit|NotebookEdit",
    "PostToolUse": "Edit|Write|MultiEdit|NotebookEdit",
}

DEFAULT_CLI_MCP_SERVERS = ["fusebase-dashboards", "fusebase-gate"]

# D1 (preserve-only): Flow's Stop merge NEVER static-injects a CLI hook from a
# name. It appends stop.py and preserves every Stop hook already in the file.
# This list is intentionally empty: CLI 0.25.9+ (unchanged through 0.25.16) wires its own Stop set
# (run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js) and
# wires run-typecheck-apps.js 0 times — a static re-inject duplicated typecheck.
# An older-CLI project that still wires run-typecheck-apps.js keeps it (never
# removed). Re-stale guard: do NOT re-add entries here; the CLI owns its Stop set.
CLI_STOP_HOOKS: list[tuple[str, dict[str, Any]]] = []


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
            # U14: pick the FLOW handler, not handlers[0]. On shared events (Stop)
            # the example chain lists CLI hooks BEFORE Flow's, so handlers[0] is a
            # CLI command (e.g. run-typecheck-apps.js) — discovering that as the
            # "Stop" Flow command makes the merge wire a CLI command under the Flow
            # label and never wire stop.py. Flow handlers live under hooks/handlers/.
            cmd = None
            for h in handlers:
                if isinstance(h, dict):
                    hc = h.get('command')
                    if isinstance(hc, str) and 'hooks/handlers/' in hc:
                        cmd = hc
                        break
            if cmd is None:
                first = handlers[0]
                cmd = first.get('command') if isinstance(first, dict) else None
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


_HANDLER_RE = re.compile(r"hooks/handlers/([a-z_]+)\.py")


def _is_legacy_flow_command(cmd: Any, stem: str) -> bool:
    """True iff `cmd` is EXACTLY the old canonical `python3 "$CLAUDE_PROJECT_DIR"/hooks/
    handlers/<stem>.py` form (or its legacy `${PROJECT_DIR}` placeholder variant) that the
    pre-v3.30.8 settings.json.example / DEFAULT_FLOW_HOOKS wired. EXACT match on purpose — a
    startswith/substring test clobbers operator customizations: an added interpreter flag
    (`python3 -I …`) would be silently dropped, and a DIFFERENT file whose path merely
    contains `hooks/handlers/<stem>.py` (e.g. `…/custom/hooks/handlers/<stem>.py`) would be
    replaced. When the command is not the exact canonical shape we do NOT migrate."""
    if not isinstance(cmd, str) or "run-handler.sh" in cmd:
        return False
    return cmd.strip() in {
        f'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/{stem}.py',
        f'python3 "${{PROJECT_DIR}}"/hooks/handlers/{stem}.py',
    }


def _migrate_blocks(blocks: Any, event: str) -> bool:
    """Rewrite a legacy python3 Flow command in this event's blocks to the run-handler.sh
    wrapper form (FLOW_HOOKS[event]). Idempotent: the wrapper form is not 'legacy' so a
    second pass is a no-op. Returns True if anything was migrated. This is what lets an
    EXISTING install (wired with bare python3) pick up the python-less self-degrade on
    upgrade — a fresh `cp settings.json.example` already ships the wrapper."""
    stem_m = _HANDLER_RE.search(FLOW_HOOKS.get(event, ""))
    if not stem_m or not isinstance(blocks, list):
        return False
    stem = stem_m.group(1)
    migrated = False
    for block in blocks:
        if not isinstance(block, dict):
            continue
        for hook in block.get("hooks") or []:
            if isinstance(hook, dict) and _is_legacy_flow_command(hook.get("command"), stem):
                hook["command"] = FLOW_HOOKS[event]
                migrated = True
    return migrated


def merge_settings(settings: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    """Return (updated settings, list of changes applied)."""
    changes: list[str] = []

    servers = settings.setdefault("enabledMcpjsonServers", [])
    if isinstance(servers, list):
        for server in DEFAULT_CLI_MCP_SERVERS:
            if server not in servers:
                servers.append(server)
                changes.append(f"added MCP server {server}")

    hooks = settings.setdefault("hooks", {})

    # All non-Stop events from FLOW_HOOKS get added wholesale if missing.
    # Stop is handled separately below (it merges into existing CLI hook chain).
    for event in FLOW_HOOKS:
        if event == "Stop":
            continue
        if event not in hooks or not hooks[event]:
            hooks[event] = [make_event_block(event)]
            changes.append(f"added {event} event")
        elif _migrate_blocks(hooks[event], event):
            # Existing install wired with bare python3 -> route through run-handler.sh so a
            # python-less machine self-degrades instead of erroring every event.
            changes.append(f"migrated {event} to run-handler.sh wrapper")

    # Stop event: preserve existing CLI hooks; append Fusebase Flow stop.py only if missing
    if "Stop" not in hooks or not hooks["Stop"]:
        stop_chain: list[dict[str, Any]] = []
        for marker, hook in CLI_STOP_HOOKS:
            if Path(f".claude/hooks/{marker}").is_file():
                stop_chain.append(dict(hook))
                changes.append(f"added CLI Stop hook {marker}")
        stop_chain.append({
            "type": "command",
            "command": FLOW_HOOKS["Stop"],
            "statusMessage": "Fusebase Flow stop hook…",
            "timeout": 30,
        })
        hooks["Stop"] = [{"hooks": stop_chain}]
        changes.append("added Stop event with Fusebase Flow stop.py")
    else:
        # Stop array exists; check first block's hooks chain for our stop.py
        stop_block = hooks["Stop"][0]
        stop_hooks = stop_block.setdefault("hooks", [])
        # Migrate a legacy python3 stop.py IN PLACE (before the append-if-missing check —
        # already_present stays True via the substring, so we rewrite rather than duplicate).
        if _migrate_blocks(hooks["Stop"], "Stop"):
            changes.append("migrated Stop to run-handler.sh wrapper")
        for marker, hook in reversed(CLI_STOP_HOOKS):
            already_cli_present = any(marker in h.get("command", "") for h in stop_hooks)
            if not already_cli_present and Path(f".claude/hooks/{marker}").is_file():
                stop_hooks.insert(0, dict(hook))
                changes.append(f"added CLI Stop hook {marker}")
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


def cli_stop_hook_basenames(settings: dict[str, Any], cli_hook_dir: Path) -> list[str]:
    """Basenames of CLI-owned Stop hooks in `settings`. CLI-owned iff the command
    string names a file present under `cli_hook_dir` (.claude/hooks/). Single-sources
    the reporter's cli_hook_markers_in rule so the receipt and the diff never disagree.
    stop.py lives under hooks/handlers/ (not .claude/hooks/) so it is never matched."""
    if not cli_hook_dir.is_dir():
        return []
    cli_files = sorted(p.name for p in cli_hook_dir.iterdir() if p.is_file())
    hooks = settings.get("hooks") if isinstance(settings, dict) else None
    out: list[str] = []
    if isinstance(hooks, dict):
        for block in hooks.get("Stop") or []:
            if not isinstance(block, dict):
                continue
            for hook in block.get("hooks") or []:
                if not isinstance(hook, dict):
                    continue
                cmd = hook.get("command")
                if not isinstance(cmd, str):
                    continue
                for name in cli_files:
                    if name in cmd and name not in out:
                        out.append(name)
    return out


def write_baseline(settings: dict[str, Any], out_path: Path) -> None:
    """Write the durable CLI-Stop-hook receipt (spec D1). Read-only w.r.t. settings."""
    cli_hook_dir = Path(".claude/hooks")
    receipt = {
        "schema": 1,
        "cli_stop_hooks": cli_stop_hook_basenames(settings, cli_hook_dir),
        "written_by": "post-fusebase-update --wire-hooks",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"[settings-merge] baseline receipt written: {out_path} "
          f"({len(receipt['cli_stop_hooks'])} CLI Stop hook(s))")


def main() -> int:
    args = sys.argv[1:]
    baseline_out: str | None = None
    if "--baseline-out" in args:
        i = args.index("--baseline-out")
        if i + 1 >= len(args):
            print("Usage: --baseline-out requires a PATH", file=sys.stderr)
            return 1
        baseline_out = args[i + 1]
        del args[i:i + 2]

    if len(args) != 1:
        print("Usage: python3 settings-json-merge.py <settings.json path> [--baseline-out PATH]", file=sys.stderr)
        return 1

    path = Path(args[0])
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

    new_text = json.dumps(updated, indent=2, ensure_ascii=False) + "\n"
    if not changes:
        print(f"[settings-merge] {path}: already up to date (no changes needed)")
    elif new_text == original_text:
        print(f"[settings-merge] {path}: byte-identical after merge (no-op)")
    else:
        path.write_text(new_text, encoding="utf-8")
        print(f"[settings-merge] {path}: applied {len(changes)} change(s):")
        for c in changes:
            print(f"  - {c}")

    # Receipt on every path (D1): durable + self-refreshing on the no-op run too.
    if baseline_out is not None:
        write_baseline(updated, Path(baseline_out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
