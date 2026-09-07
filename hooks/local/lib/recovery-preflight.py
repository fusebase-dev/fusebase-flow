#!/usr/bin/env python3
"""Construct and validate a complete, read-only Flow recovery plan."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


SURFACES = [
    "skill_mirrors", "agent_mirrors", "agents_overlay", "claude_overlay",
    "claude_settings", "git_hooks", "health_skill", "commands",
]


def native_path(raw: str) -> Path:
    if os.name == "nt" and raw.startswith("/"):
        raw = subprocess.run(
            ["cygpath", "-m", raw], check=True, text=True, capture_output=True
        ).stdout.strip()
    return Path(raw)


def load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot load helper: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def regular_source(path: Path, label: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"{label} is missing, non-file, or symlink: {path}")


def read_json(path: Path, label: str) -> Any:
    regular_source(path, label)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is invalid JSON: {exc}") from exc


def validate_intent(root: Path) -> str:
    path = root / "state/audit/flow-hook-wiring-intent.json"
    if not path.exists():
        return "absent"
    value = read_json(path, "hook-wiring intent")
    if not isinstance(value, dict) or value.get("schema_version") not in (1, 2):
        raise ValueError("hook-wiring intent has an unsupported schema")
    if not isinstance(value.get("enabled"), bool):
        raise ValueError("hook-wiring intent enabled is not boolean")
    recorded_root = value.get("repo_root")
    if not isinstance(recorded_root, str) or not recorded_root.strip():
        raise ValueError("hook-wiring intent has no project identity")
    if value["schema_version"] == 2:
        allowed = {"claude_settings", "git_hooks"}
        surfaces = value.get("surfaces")
        if not isinstance(surfaces, list) or any(x not in allowed for x in surfaces):
            raise ValueError("hook-wiring intent has invalid surfaces")
        if value["enabled"] and not surfaces:
            raise ValueError("enabled hook-wiring intent has no surfaces")
    return "enabled" if value["enabled"] else "revoked"


def validate_ownership_map(root: Path) -> dict[str, Any]:
    path = root / "hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
    value = read_json(path, "provider ownership map")
    if value.get("schema_version") != 1 or not isinstance(value.get("paths"), list):
        raise ValueError("provider ownership map has invalid schema")
    required = {"cli-owned", "flow-owned", "shared-merge"}
    owners = value.get("owners")
    if not isinstance(owners, dict) or not required.issubset(owners):
        raise ValueError("provider ownership map is incomplete")
    for index, row in enumerate(value["paths"]):
        if not isinstance(row, dict) or row.get("owner") not in required:
            raise ValueError(f"provider ownership row {index} is invalid")
    return value


def target_rows(root: Path, ownership: Any) -> list[dict[str, str]]:
    receipt_path = root / "state/audit/recovery-owned-targets.json"
    receipt = {"schema": 1, "targets": {}}
    if receipt_path.exists():
        receipt = read_json(receipt_path, "owned-target receipt")
        if receipt.get("schema") != 1 or not isinstance(receipt.get("targets"), dict):
            raise ValueError("owned-target receipt has invalid schema")
    candidates = []
    metadata: dict[str, tuple[str, str]] = {}

    def add(source: Path, target: str, surface: str, owner_surface: str) -> None:
        source_raw = str(source)
        row = ownership.make_plan_row(root, source_raw, target, owner_surface)
        candidates.append(row)
        metadata.setdefault(target, (surface, source.relative_to(root).as_posix()))

    skill_count = 0
    for source in sorted((root / "flow-skills").glob("*/SKILL.md")):
        if not (source.is_file() or source.is_symlink()):
            continue
        skill_count += 1
        skill = source.parent.name
        for provider in (".claude", ".agents"):
            add(source, f"{provider}/skills/{skill}/SKILL.md", "skill_mirrors", "skill")
        references = source.parent / "references"
        if references.is_dir():
            for reference in sorted(references.glob("*")):
                if reference.is_file() or reference.is_symlink():
                    for provider in (".claude", ".agents"):
                        add(
                            reference, f"{provider}/skills/{skill}/references/{reference.name}",
                            "skill_mirrors", "skill",
                        )
    if not skill_count:
        raise ValueError("canonical flow-skills has no source files")
    agent_count = 0
    for source in sorted((root / "agents").glob("*/AGENT.md")):
        if not (source.is_file() or source.is_symlink()):
            continue
        agent_count += 1
        name = source.parent.name
        add(source, f".claude/agents/{name}.md", "agent_mirrors", "agent")
        add(source, f".codex/agents/{name}.md", "agent_mirrors", "agent")
    if not agent_count:
        raise ValueError("canonical agents has no source files")
    health = root / "flow-skills/fusebase-flow-health-check/SKILL.md"
    if not (health.exists() or health.is_symlink()):
        health = root / "hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md"
    for provider in (".claude", ".agents"):
        add(
            health, f"{provider}/skills/fusebase-flow-health-check/SKILL.md",
            "health_skill", "health-skill",
        )
    command_dir = root / "hooks/local/fusebase-flow-overlays/commands"
    commands = sorted(command_dir.glob("*.md")) if command_dir.is_dir() else []
    if not commands:
        raise ValueError("no recovery command sources are available")
    for source in commands:
        add(source, f".claude/commands/{source.name}", "commands", "command")
    baseline, prepared = ownership.prepare_rows(root, candidates, receipt["targets"])
    proofs = [item for item in prepared if item.proof]
    if proofs:
        baseline.revalidate_head()
        for item in proofs:
            baseline.revalidate(item.proof, item.source, item.target)
    rows: list[dict[str, str]] = []
    for item in prepared:
        if item.source is None or item.target is None or item.status == "unsafe":
            raise ValueError(f"invalid recovery target {item.row.target_rel}: {item.detail}")
        surface, source_rel = metadata[item.row.target_rel]
        rows.append({
            "surface": surface, "source": source_rel, "target": item.row.target_rel,
            "classification": item.status, "detail": item.detail,
        })
    return rows


def verified_provider_backup(root: Path, name: str, overlay: Any, headings: tuple[bytes, ...]) -> tuple[str, str]:
    status_path = root / "state/audit/flow-recovery-status.json"
    if not status_path.is_file():
        return "", "no retained provider receipt"
    try:
        status = json.loads(status_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "", "retained provider receipt is invalid"
    rows = status.get("backup_artifacts", [])
    candidates = [row for row in rows if isinstance(row, dict)
                  and str(row.get("path", "")).startswith(f"{name}.pre-refresh-")]
    for row in reversed(candidates):
        relative = row.get("path")
        expected = row.get("sha256")
        path = root / relative
        if not isinstance(expected, str) or not path.is_file() or path.is_symlink():
            continue
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            return "", f"retained provider backup hash mismatch: {relative}"
        try:
            content = path.read_bytes()
            start, end, _legacy = overlay._owned_span(content, headings, allow_legacy=False)
            if not (content[:start].strip() or content[end:].strip()):
                raise ValueError("backup contains no external provider bytes")
        except (OSError, ValueError) as exc:
            return "", f"retained provider backup is structurally invalid: {exc}"
        return relative, ""
    return "", "no ownership-verified provider backup"


def expected_overlay_bytes(
    original: bytes, template_bytes: bytes, overlay: Any,
    headings: tuple[bytes, ...], canonical: bytes,
) -> tuple[bytes, str]:
    template_pairs = overlay._marker_pairs(template_bytes)
    if len(template_pairs) != 1:
        raise ValueError("canonical overlay template must contain exactly one marker span")
    template_start, template_end, _ = overlay._owned_span(
        template_bytes, (canonical,), allow_legacy=False
    )
    overlay._preserve_span(template_bytes)
    marker_pairs = overlay._marker_pairs(original)
    preserve_span = overlay._preserve_span(original)
    matches = [match for heading in headings for match in overlay._line_matches(original, (heading,))]
    if not matches:
        if marker_pairs or preserve_span is not None:
            raise ValueError("marker-bearing provider content has no recognized Flow heading")
        return original + template_bytes, "append"
    start, end, legacy = overlay._owned_span(original, headings, allow_legacy=True)
    effective = overlay._effective_template(
        original[start:end], template_bytes[template_start:template_end],
        overlay._newline_style(original),
    )
    expected = original[:start] + effective + original[end:]
    return expected, "refresh-needed" if legacy or expected != original else "current"


def validate_overlays(root: Path, refresh: bool) -> list[dict[str, str]]:
    helper_path = root / "hooks/local/fusebase-flow-overlays/overlay-block-replace.py"
    overlay = load_module(helper_path, "flow_overlay_preflight")
    specs = [
        ("AGENTS.md", "agents-md-overlay.md", "## FuseBase Flow — workflow lifecycle overlay",
         ("## Fusebase Flow — workflow lifecycle overlay",)),
        ("CLAUDE.md", "claude-md-overlay.md", "## FuseBase Flow — Claude Code adapter",
         ("## FuseBase Flow — additional rules (overlay)", "## Fusebase Flow — additional rules (overlay)")),
    ]
    rows = []
    for target_name, template_name, heading, legacy in specs:
        target = root / target_name
        template = root / "hooks/local/fusebase-flow-overlays" / template_name
        regular_source(template, f"{target_name} overlay template")
        if target.exists() and (target.is_symlink() or not target.is_file()):
            raise ValueError(f"{target_name} is not a regular file")
        state = "missing"
        backup = ""
        backup_error = ""
        headings = tuple(x.encode() for x in (heading, *legacy))
        canonical = heading.encode()
        template_bytes = template.read_bytes()
        expected: bytes | None = None
        if target.is_file():
            data = target.read_bytes()
            expected, canonical_state = expected_overlay_bytes(
                data, template_bytes, overlay, headings, canonical
            )
            state = canonical_state if refresh else (
                "present" if canonical_state != "append" else "append"
            )
        elif not target.exists():
            backup, backup_error = verified_provider_backup(root, target_name, overlay, headings)
            if backup:
                state = "restore-backup"
                original = (root / backup).read_bytes()
                expected, _ = expected_overlay_bytes(
                    original, template_bytes, overlay, headings, canonical
                )
        rows.append({
            "surface": target_name, "state": state, "backup": backup,
            "backup_error": backup_error,
            "expected_sha256": hashlib.sha256(expected).hexdigest() if expected is not None else "",
        })
    return rows


def build_plan(root: Path, wire: bool, restore_git: bool, refresh: bool) -> dict[str, Any]:
    required = [
        root / "hooks/local/mirror-skills.sh", root / "hooks/local/mirror-agents.sh",
        root / "hooks/local/lib/recovery-owned-write.py",
        root / "hooks/local/fusebase-flow-overlays/settings-json-merge.py",
        root / "hooks/local/lib/recovery-verify.py",
    ]
    for path in required:
        regular_source(path, "recovery helper")
    ownership_map = validate_ownership_map(root)
    ownership = load_module(required[2], "flow_recovery_ownership")
    settings_helper = load_module(required[3], "flow_settings_preflight")
    intent = validate_intent(root)
    settings_path = root / ".claude/settings.json"
    if wire and settings_path.exists():
        settings_helper.validate_settings_shape(read_json(settings_path, "Claude settings"))
    operations = [
        {"surface": "agents_overlay", "source": "hooks/local/fusebase-flow-overlays/agents-md-overlay.md", "target": "AGENTS.md"},
        {"surface": "claude_overlay", "source": "hooks/local/fusebase-flow-overlays/claude-md-overlay.md", "target": "CLAUDE.md"},
    ]
    if wire:
        operations.append({"surface": "claude_settings", "source": str(required[3].relative_to(root)).replace("\\", "/"), "target": ".claude/settings.json"})
    if restore_git:
        installer = root / "hooks/local/install-git-hooks.sh"
        regular_source(installer, "Git hook installer")
        if not os.access(installer, os.X_OK) or not (root / ".git/hooks").is_dir():
            raise ValueError("Git hook restoration prerequisites are unavailable")
        for name in ("pre-commit", "commit-msg"):
            source = root / "hooks/git" / name
            regular_source(source, "Git hook source")
            operations.append({"surface": "git_hooks", "source": f"hooks/git/{name}", "target": f".git/hooks/{name}"})
    plan = {
        "schema_version": 1, "repo_root": str(root), "surfaces": SURFACES,
        "options": {"wire_hooks": wire, "restore_git_hooks": restore_git,
                    "refresh_overlays": refresh},
        "intent_state": intent, "provider_path_count": len(ownership_map["paths"]),
        "overlays": validate_overlays(root, refresh),
        "targets": target_rows(root, ownership),
        "operations": operations,
    }
    identity_input = {
        "schema_version": plan["schema_version"], "repo_root": plan["repo_root"],
        "surfaces": plan["surfaces"], "options": plan["options"],
        "sources": [
            (row["surface"], row["source"], row["target"],
             hashlib.sha256((root / row["source"]).read_bytes()).hexdigest())
            for row in plan["targets"]
        ],
        "operations": plan["operations"],
        "overlays": plan["overlays"],
    }
    identity = hashlib.sha256(json.dumps(identity_input, sort_keys=True).encode()).hexdigest()
    return {**plan, "plan_id": identity}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--wire-hooks", action="store_true")
    parser.add_argument("--restore-git-hooks", action="store_true")
    parser.add_argument("--refresh-overlays", action="store_true")
    args = parser.parse_args()
    try:
        root = native_path(args.root).resolve()
        plan = build_plan(root, args.wire_hooks, args.restore_git_hooks, args.refresh_overlays)
        native_path(args.output).write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"[recovery-preflight] invalid plan: {exc}", file=sys.stderr)
        return 2
    print(plan["plan_id"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
