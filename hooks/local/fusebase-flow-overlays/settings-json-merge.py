#!/usr/bin/env python3
"""Merge the installed Fusebase Flow hook set into a Claude settings file.

Consumer hook blocks and settings outside Flow-owned commands are preserved. An alternate
hook source is accepted only through --flow-config after complete handler/matcher validation.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

# Commands route through hooks/local/run-handler.sh (interpreter auto-detect +
# graceful self-degrade on a python-less machine).
DEFAULT_FLOW_HOOKS = {
    "SessionStart":     'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/session_start.py',
    "UserPromptSubmit": 'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/user_prompt_submit.py',
    "PreToolUse":       'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_tool_use.py',
    "PostToolUse":      'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/post_tool_use.py',
    "Stop":             'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/stop.py',
    "PreCompact":       'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_compact.py',
}

# TRIPWIRE (E6): PreToolUse must name EVERY command-carrying tool the host exposes —
# Claude Code exposes `PowerShell` beside `Bash` on Windows, and a tool absent from the
# matcher never reaches pre_tool_use.py, so FR-06 denies and FR-12 approvals simply do not
# apply to it. Keep in sync with COMMAND_TOOL_NAMES in hooks/shared/command_policy.py.
DEFAULT_EVENT_MATCHERS = {
    "PreToolUse":  "Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit",
    "PostToolUse": "Edit|Write|MultiEdit|NotebookEdit",
}

# D1 (preserve-only): Flow's Stop merge NEVER static-injects a CLI hook from a
# name. It appends stop.py and preserves every Stop hook already in the file.
# This list is intentionally empty: CLI 0.25.9+ (unchanged through 0.25.16) wires its own Stop set
# (run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js) and
# wires run-typecheck-apps.js 0 times — a static re-inject duplicated typecheck.
# An older-CLI project that still wires run-typecheck-apps.js keeps it (never
# removed). Re-stale guard: do NOT re-add entries here; the CLI owns its Stop set.
CLI_STOP_HOOKS: list[tuple[str, dict[str, Any]]] = []


FLOW_HOOKS: dict[str, str] = dict(DEFAULT_FLOW_HOOKS)
EVENT_MATCHERS: dict[str, str] = dict(DEFAULT_EVENT_MATCHERS)


def make_event_block(event: str) -> dict[str, Any]:
    """Build the `[{matcher?, hooks: [...]}]` array for a given event."""
    block: dict[str, Any] = {"hooks": [{"type": "command", "command": FLOW_HOOKS[event], "timeout": 30}]}
    if event in EVENT_MATCHERS:
        block["matcher"] = EVENT_MATCHERS[event]
    return block


_HANDLER_RE = re.compile(r"hooks/handlers/([a-z_]+)\.py")


def _recognized_flow_command(cmd: Any, event: str) -> bool:
    if not isinstance(cmd, str):
        return False
    configured = FLOW_HOOKS[event]
    stem = _HANDLER_RE.search(configured)
    if stem is None:
        return False
    name = stem.group(1)
    return cmd.strip() in {
        configured.strip(),
        f'python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/{name}.py',
        f'python3 "${{PROJECT_DIR}}"/hooks/handlers/{name}.py',
    }


def _config_from_file(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    source_hooks = data.get("hooks")
    if not isinstance(source_hooks, dict):
        raise ValueError("explicit Flow config has no hooks object")
    commands: dict[str, str] = {}
    matchers: dict[str, str] = {}
    for event, expected in DEFAULT_FLOW_HOOKS.items():
        expected_match = _HANDLER_RE.search(expected)
        blocks = source_hooks.get(event)
        if expected_match is None or not isinstance(blocks, list):
            raise ValueError(f"explicit Flow config is missing {event}")
        candidates: list[str] = []
        for block in blocks:
            if not isinstance(block, dict):
                continue
            matcher = block.get("matcher")
            if event in DEFAULT_EVENT_MATCHERS and isinstance(matcher, str):
                matchers[event] = matcher
            for hook in block.get("hooks") or []:
                command = hook.get("command") if isinstance(hook, dict) else None
                match = _HANDLER_RE.search(command or "")
                if match and match.group(1) == expected_match.group(1):
                    candidates.append(command)
        if len(candidates) != 1:
            raise ValueError(
                f"explicit Flow config needs exactly one recognized {event} handler"
            )
        normalized = candidates[0].replace(
            '"${PROJECT_DIR}"', '"$CLAUDE_PROJECT_DIR"'
        ).replace("${PROJECT_DIR}", "$CLAUDE_PROJECT_DIR")
        if normalized != expected:
            raise ValueError(f"explicit Flow config has an unrecognized {event} command")
        commands[event] = normalized
    for event, required in DEFAULT_EVENT_MATCHERS.items():
        actual = _matcher_tokens(matchers.get(event))
        expected = _matcher_tokens(required)
        if actual is None or expected is None or not set(expected).issubset(actual):
            raise ValueError(f"explicit Flow config has an incomplete {event} matcher")
    return commands, matchers


def _deduplicate_flow_handlers(blocks: Any, event: str) -> int:
    if not isinstance(blocks, list):
        return 0
    seen = False
    removed = 0
    for block in blocks:
        if not isinstance(block, dict) or not isinstance(block.get("hooks"), list):
            continue
        kept = []
        for hook in block["hooks"]:
            command = hook.get("command") if isinstance(hook, dict) else None
            if _recognized_flow_command(command, event):
                if seen:
                    removed += 1
                    continue
                seen = True
            kept.append(hook)
        block["hooks"] = kept
    return removed


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


_SIMPLE_MATCHER_TOKEN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _matcher_tokens(matcher: Any) -> list[str] | None:
    """Tokens of `matcher` iff it is a plain `Tok|Tok|Tok` alternation, else None.

    None means "do not touch": an absent/empty matcher already matches every tool, and
    anything with regex structure (groups, anchors, classes) is an operator expression a
    naive `|` split would corrupt."""
    if not isinstance(matcher, str) or not matcher.strip():
        return None
    parts = [p.strip() for p in matcher.split("|")]
    if not all(_SIMPLE_MATCHER_TOKEN.match(p) for p in parts):
        return None
    return parts


def _widen_matchers(blocks: Any, event: str) -> bool:
    """Union Flow's required matcher tokens into an ALREADY-INSTALLED matcher (E6).

    Without this, only a FRESH install got a widened matcher: the add-if-missing branch
    below never runs for a consumer who already wired the event, so a security-relevant
    tool added upstream (PowerShell) would never reach the handler on an existing install
    no matter how many times they re-ran --wire-hooks. Union, never overwrite — a consumer
    who added their own tools keeps them. Only OUR block is touched (its hook chain must
    name a hooks/handlers/ command); somebody else's PreToolUse block is left alone."""
    required = _matcher_tokens(EVENT_MATCHERS.get(event, ""))
    if not required or not isinstance(blocks, list):
        return False
    changed = False
    for block in blocks:
        if not isinstance(block, dict):
            continue
        if not any(isinstance(h, dict) and "hooks/handlers/" in (h.get("command") or "")
                   for h in block.get("hooks") or []):
            continue
        existing = _matcher_tokens(block.get("matcher"))
        if existing is None:
            # A hand-written regex is never rewritten (a `|` split would corrupt it), but
            # silence here would leave that consumer ungated on the new tool without ever
            # saying so. `*`/absent already match every tool, so only a regex is warned on.
            raw = block.get("matcher")
            if isinstance(raw, str) and raw.strip() and raw.strip() != "*":
                absent = [t for t in required if t not in raw]
                if absent:
                    print(f"[settings-merge] WARNING: {event} matcher {raw!r} is a regex this "
                          f"merge will not rewrite, and it does not name {', '.join(absent)}. "
                          f"Tools it omits never reach the Flow hook (FR-06/FR-12 do not apply "
                          f"to them). Add them by hand.", file=sys.stderr)
            continue
        missing = [t for t in required if t not in existing]
        if missing:
            block["matcher"] = "|".join(existing + missing)
            changed = True
    return changed


def _flow_handler_present(blocks: Any, event: str) -> bool:
    """True iff some block names an exact current or legacy Flow command."""
    stem_m = _HANDLER_RE.search(FLOW_HOOKS.get(event, ""))
    if not stem_m or not isinstance(blocks, list):
        return False
    for block in blocks:
        if not isinstance(block, dict):
            continue
        for hook in block.get("hooks") or []:
            cmd = hook.get("command") if isinstance(hook, dict) else None
            if _recognized_flow_command(cmd, event):
                return True
    return False


def merge_settings(settings: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    """Return (updated settings, list of changes applied)."""
    changes: list[str] = []

    hooks = settings.setdefault("hooks", {})

    # All non-Stop events from FLOW_HOOKS: added wholesale when the array is absent/empty,
    # added BESIDE the existing blocks when it is occupied by somebody else's hook.
    # Stop is handled separately below (it merges into existing CLI hook chain).
    for event in FLOW_HOOKS:
        if event == "Stop":
            continue
        if event not in hooks or not hooks[event]:
            hooks[event] = [make_event_block(event)]
            changes.append(f"added {event} event")
            continue
        if not isinstance(hooks[event], list):
            # Hand-edited to a non-array. Never coerce or clobber an operator's file — and
            # never let one malformed key abort the whole merge (that would take the OTHER
            # events' wiring down with it). Say so; the health arm reports the absence.
            print(f"[settings-merge] WARNING: hooks.{event} is a "
                  f"{type(hooks[event]).__name__}, not an array — leaving it untouched. Flow's "
                  f"{event} handler is NOT wired. Fix the array by hand, then re-run.",
                  file=sys.stderr)
            continue
        if _migrate_blocks(hooks[event], event):
            # Existing install wired with bare python3 -> route through run-handler.sh so a
            # python-less machine self-degrades instead of erroring every event.
            changes.append(f"migrated {event} to run-handler.sh wrapper")
        removed = _deduplicate_flow_handlers(hooks[event], event)
        if removed:
            changes.append(f"removed {removed} duplicate Fusebase Flow {event} handler(s)")
        if not _flow_handler_present(hooks[event], event):
            # ADD BESIDE, never replace. The array is occupied by somebody else's block(s), so
            # the wholesale-add branch above correctly did not fire — and _migrate_blocks /
            # _widen_matchers both skip a block naming no hooks/handlers/ command, so before
            # this branch NOTHING added Flow's block and --wire-hooks exited 0 unwired.
            # TRIPWIRE: append a SEPARATE block, never Flow's command into the consumer's chain
            # — that would inherit the consumer's matcher (measured: `Bash|Edit|Write`) and
            # re-open E6, leaving PowerShell ungated by FR-06/FR-12 on every consumer tree.
            existing = len(hooks[event])
            hooks[event].append(make_event_block(event))
            changes.append(f"added Fusebase Flow {event} block beside {existing} existing block(s)")
        elif _widen_matchers(hooks[event], event):
            # E6: an existing install must pick up a newly-gated tool on re-merge, not only
            # on a fresh `cp settings.json.example`. (A block just appended above already
            # carries the full matcher, so widening is only for a pre-existing Flow block.)
            changes.append(f"widened {event} matcher to cover every command-carrying tool")

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
        if not isinstance(hooks["Stop"], list) or not all(
            isinstance(block, dict) for block in hooks["Stop"]
        ):
            print(
                "[settings-merge] WARNING: hooks.Stop is not an array of objects; leaving it untouched.",
                file=sys.stderr,
            )
            return settings, changes
        if _migrate_blocks(hooks["Stop"], "Stop"):
            changes.append("migrated Stop to run-handler.sh wrapper")
        removed = _deduplicate_flow_handlers(hooks["Stop"], "Stop")
        if removed:
            changes.append(f"removed {removed} duplicate Fusebase Flow Stop handler(s)")
        stop_hooks = hooks["Stop"][0].setdefault("hooks", [])
        if not isinstance(stop_hooks, list):
            print(
                "[settings-merge] WARNING: hooks.Stop[0].hooks is not an array; leaving it untouched.",
                file=sys.stderr,
            )
            return settings, changes
        for marker, hook in reversed(CLI_STOP_HOOKS):
            already_cli_present = any(
                isinstance(item, dict) and marker in item.get("command", "")
                for item in stop_hooks
            )
            if not already_cli_present and Path(f".claude/hooks/{marker}").is_file():
                stop_hooks.insert(0, dict(hook))
                changes.append(f"added CLI Stop hook {marker}")
        if not _flow_handler_present(hooks["Stop"], "Stop"):
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
    global FLOW_HOOKS, EVENT_MATCHERS
    args = sys.argv[1:]
    baseline_out: str | None = None
    flow_config: str | None = None
    if "--baseline-out" in args:
        i = args.index("--baseline-out")
        if i + 1 >= len(args):
            print("Usage: --baseline-out requires a PATH", file=sys.stderr)
            return 1
        baseline_out = args[i + 1]
        del args[i:i + 2]
    if "--flow-config" in args:
        i = args.index("--flow-config")
        if i + 1 >= len(args):
            print("Usage: --flow-config requires a PATH", file=sys.stderr)
            return 1
        flow_config = args[i + 1]
        del args[i:i + 2]

    if len(args) != 1:
        print("Usage: python3 settings-json-merge.py <settings.json path> [--baseline-out PATH] [--flow-config PATH]", file=sys.stderr)
        return 1

    if flow_config is not None:
        try:
            FLOW_HOOKS, EVENT_MATCHERS = _config_from_file(Path(flow_config))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            print(f"ERROR: explicit Flow config rejected: {exc}", file=sys.stderr)
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
