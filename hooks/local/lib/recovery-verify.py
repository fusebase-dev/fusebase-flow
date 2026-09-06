#!/usr/bin/env python3
"""Verify every surface in a prevalidated Flow recovery plan."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
from pathlib import Path
from typing import Any


def native_path(raw: str) -> Path:
    if os.name == "nt" and raw.startswith("/"):
        raw = subprocess.run(
            ["cygpath", "-m", raw], check=True, text=True, capture_output=True
        ).stdout.strip()
    return Path(raw)


def load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot load verification helper: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def exact_file(source: Path, target: Path) -> str | None:
    if target.is_symlink() or not target.is_file():
        return "target is missing, non-file, or symlink"
    if source.read_bytes() != target.read_bytes():
        return "target bytes differ from the planned source"
    return None


def verify_targets(root: Path, plan: dict[str, Any]) -> dict[str, list[str]]:
    failures: dict[str, list[str]] = {}
    for row in plan["targets"]:
        surface = row["surface"]
        if row["classification"] in {"unowned-collision", "unsafe"}:
            failures.setdefault(surface, []).append(
                f'{row["target"]}: preserved {row["classification"]}'
            )
            continue
        reason = exact_file(root / row["source"], root / row["target"])
        if reason:
            failures.setdefault(surface, []).append(f'{row["target"]}: {reason}')
    return failures


def verify_overlays(root: Path, plan: dict[str, Any], failures: dict[str, list[str]]) -> None:
    helper = load_module(
        root / "hooks/local/fusebase-flow-overlays/overlay-block-replace.py",
        "flow_overlay_verify",
    )
    specs = {
        "AGENTS.md": (
            "agents_overlay", "## FuseBase Flow — workflow lifecycle overlay",
            ("## Fusebase Flow — workflow lifecycle overlay",), True,
        ),
        "CLAUDE.md": (
            "claude_overlay", "## FuseBase Flow — Claude Code adapter",
            ("## FuseBase Flow — additional rules (overlay)",
             "## Fusebase Flow — additional rules (overlay)"), False,
        ),
    }
    planned = {row["surface"]: row for row in plan["overlays"]}
    for name, (surface, heading, legacy, _required) in specs.items():
        target = root / name
        backup = planned.get(name, {}).get("backup", "")
        if backup:
            reason = exact_file(root / backup, target)
            if reason:
                failures.setdefault(surface, []).append(
                    f"{name}: restored provider bytes do not match {backup}: {reason}"
                )
        try:
            data = target.read_bytes()
            headings = tuple(item.encode() for item in (heading, *legacy))
            helper._owned_span(data, headings, allow_legacy=False)
        except (OSError, ValueError) as exc:
            failures.setdefault(surface, []).append(f"{name}: {exc}")


def validate_intent(root: Path, surface: str) -> str | None:
    path = root / "state/audit/flow-hook-wiring-intent.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return f"intent is unavailable or invalid: {exc}"
    schema = value.get("schema_version")
    if schema not in (1, 2) or value.get("enabled") is not True:
        return "intent is not an enabled supported record"
    recorded = value.get("repo_root", "")
    normalized_recorded = str(recorded).replace("\\", "/").rstrip("/").lower()
    normalized_root = str(root).replace("\\", "/").rstrip("/").lower()
    if len(normalized_recorded) > 3 and normalized_recorded[0] == "/" \
            and normalized_recorded[2] == "/":
        normalized_recorded = f"{normalized_recorded[1]}:{normalized_recorded[2:]}"
    if normalized_recorded != normalized_root:
        return "intent project identity does not match"
    surfaces = ["claude_settings"] if schema == 1 else value.get("surfaces")
    if not isinstance(surfaces, list) or surface not in surfaces:
        return f"intent does not authorize {surface}"
    return None


def verify_settings(root: Path, plan: dict[str, Any], failures: dict[str, list[str]]) -> None:
    if not plan["options"]["wire_hooks"]:
        return
    helper = load_module(
        root / "hooks/local/fusebase-flow-overlays/settings-json-merge.py",
        "flow_settings_verify",
    )
    path = root / ".claude/settings.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        helper.validate_settings_shape(value)
        hooks = value["hooks"]
        for event in helper.DEFAULT_FLOW_HOOKS:
            if not helper._flow_handler_present(hooks.get(event), event):
                raise ValueError(f"exact {event} Flow handler is absent")
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as exc:
        failures.setdefault("claude_settings", []).append(str(exc))
    intent_error = validate_intent(root, "claude_settings")
    if intent_error:
        failures.setdefault("claude_settings", []).append(intent_error)


def verify_git(root: Path, plan: dict[str, Any], failures: dict[str, list[str]]) -> None:
    if not plan["options"]["restore_git_hooks"]:
        return
    intent_error = validate_intent(root, "git_hooks")
    if intent_error:
        failures.setdefault("git_hooks", []).append(intent_error)
    for name in ("pre-commit", "commit-msg"):
        target = root / ".git/hooks" / name
        reason = exact_file(root / "hooks/git" / name, target)
        if reason:
            failures.setdefault("git_hooks", []).append(f"{name}: {reason}")
        elif not os.access(target, os.X_OK):
            failures.setdefault("git_hooks", []).append(f"{name}: target is not executable")


def verify(root: Path, plan: dict[str, Any]) -> dict[str, Any]:
    failures = verify_targets(root, plan)
    verify_overlays(root, plan, failures)
    verify_settings(root, plan, failures)
    verify_git(root, plan, failures)
    planned = plan["surfaces"]
    verified = [surface for surface in planned if surface not in failures]
    return {
        "schema_version": 1,
        "plan_id": plan["plan_id"],
        "verified_surfaces": verified,
        "uncertain_surfaces": [surface for surface in planned if surface in failures],
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--result", required=True)
    args = parser.parse_args()
    try:
        root = native_path(args.root).resolve()
        plan = json.loads(native_path(args.plan).read_text(encoding="utf-8"))
        result = verify(root, plan)
        native_path(args.result).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"[recovery-verify] verification failed: {exc}", file=os.sys.stderr)
        return 2
    for surface, reasons in result["failures"].items():
        for reason in reasons:
            print(f"[recovery-verify] {surface}: {reason}", file=os.sys.stderr)
    return 1 if result["uncertain_surfaces"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
