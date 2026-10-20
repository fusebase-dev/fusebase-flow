"""`flow.py install --wire-hooks`: Flow's two tool handlers merged into each declared provider's hook settings.

The settings files are CLI-owned: Flow adds its entries beside the CLI's and never replaces or reformats the file. A
file whose formatting a JSON round trip would change is refused with the entries to add by hand (handoff WP 11, 4a).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

MATCHER = "Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit"  # TRIPWIRE: COMMAND_TOOL_NAMES in hooks/shared/command_policy.py
CLAUDE = 'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/{}.py'
CODEX = "bash hooks/local/run-handler.sh hooks/handlers/{}.py"
# {provider: (settings file, {event: (handler stem, matcher)}, command form, timeout in seconds)}. Codex has no failure
# event and reports edits as apply_patch, which the handlers do not parse, so its arms are Bash only (Codex: unproven).
PROVIDERS = {
    "claude": (".claude/settings.json", {"PreToolUse": ("pre_tool_use", MATCHER), "PostToolUse": ("post_tool_use", MATCHER),
                                         "PostToolUseFailure": ("post_tool_use", MATCHER)}, CLAUDE, 30),
    "codex": (".codex/hooks.json", {"PreToolUse": ("pre_tool_use", "Bash"), "PostToolUse": ("post_tool_use", "Bash")},
              CODEX, 5),
}


def entries(provider: str) -> dict[str, dict]:
    _, events, form, timeout = PROVIDERS[provider]
    return {event: {"matcher": matcher, "hooks": [{"type": "command", "command": form.format(stem), "timeout": timeout}]}
            for event, (stem, matcher) in events.items()}


def layout(text: str) -> dict | None:
    """The json.dumps arguments that reproduce `text` byte for byte (line endings aside), or None."""
    body = text.replace("\r\n", "\n")
    lead = re.search(r"^([ \t]+)\S", body, re.M)
    try:
        doc = json.loads(body)
    except ValueError:
        return None
    for ascii_only in (False, True):
        args = {"indent": lead[1] if lead else 2, "ensure_ascii": ascii_only}
        if json.dumps(doc, **args) == body.rstrip("\n"):
            return args
    return None


def merge(doc: dict, provider: str) -> list[str]:
    """Adds each missing Flow entry; a block holding only Flow's command gets Flow's matcher. What changed, by event."""
    hooks, changed = doc.setdefault("hooks", {}), []
    for event, want in entries(provider).items():
        blocks, command = hooks.setdefault(event, []), want["hooks"][0]["command"]
        mine = [b for b in blocks if any(h.get("command") == command for h in b.get("hooks") or [])]
        if not mine:
            blocks.append(want)
            changed.append(f"{event} added")
        elif len(mine[0]["hooks"]) == 1 and mine[0].get("matcher") != want["matcher"]:
            mine[0]["matcher"] = want["matcher"]
            changed.append(f"{event} matcher set to {want['matcher']}")
    return changed


def shape_error(doc: object) -> str | None:
    if not isinstance(doc, dict) or not isinstance(doc.get("hooks", {}), dict):
        return "its top level, or its `hooks`, is not a JSON object"
    for event, blocks in doc.get("hooks", {}).items():
        if not isinstance(blocks, list) or not all(isinstance(b, dict) and isinstance(b.get("hooks", []), list)
                                                   and all(isinstance(h, dict) for h in b.get("hooks", [])) for b in blocks):
            return f"`hooks.{event}` is not a list of blocks with a `hooks` list"
    return None


def wire(target: Path, provider: str) -> tuple[int, list[str]]:
    """Merges the provider's file; 0 merged or already current, 1 refused (the file untouched)."""
    rel = PROVIDERS[provider][0]
    path = target / rel
    # The shape merge writes: a list of matcher groups per event (Claude Code's schema), never a bare object.
    by_hand = json.dumps({"hooks": {event: [group] for event, group in entries(provider).items()}}, indent=2)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        return 1, [f"{provider}: {rel} is a symlink or not a regular file; nothing written. Add by hand:", by_hand]
    before = path.read_bytes().decode("utf-8") if path.is_file() else None
    args = layout(before) if before is not None else {"indent": 2, "ensure_ascii": False}
    doc = {} if before is None else json.loads(before.replace("\r\n", "\n")) if args else None
    why = shape_error(doc) if args else "a JSON round trip would change its formatting (or it is not valid JSON)"
    if why:
        return 1, [f"{provider}: {rel} is left as it is: {why}. Add these entries by hand:", by_hand]
    changed = merge(doc, provider)
    if not changed:
        return 0, [f"{provider}: {rel} already carries Flow's entries; nothing written"]
    nl, end = "\r\n" if before and "\r\n" in before else "\n", "" if before and not before.endswith("\n") else "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".flow-tmp")
    tmp.write_bytes((json.dumps(doc, **args) + end).replace("\n", nl).encode("utf-8"))
    tmp.replace(path)
    note = ("; Codex asks you to trust each project hook before it runs one (Codex: unproven, no run yet)"
            if provider == "codex" else "")
    return 0, [f"{provider}: {rel} {'created' if before is None else 'merged'}: {', '.join(changed)}{note}"]
