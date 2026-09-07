#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path
from typing import Callable


SOURCE_ROOT = Path(__file__).resolve().parents[2]


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def append(path: Path, value: str) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(value)
        handle.flush()
        os.fsync(handle.fileno())


def stage(path: Path, name: str, action: Callable[[], tuple[str, str]]) -> None:
    started = time.monotonic()
    append(path, f"stage={name} event=START elapsed=0 rc=pending\n")
    rc = 0
    stdout = ""
    stderr = ""
    try:
        stdout, stderr = action()
    except Exception:
        rc = 1
        stderr = traceback.format_exc()
    append(path, f"stage={name} stream=stdout BEGIN\n{stdout}\nstage={name} stream=stdout END\n")
    append(path, f"stage={name} stream=stderr BEGIN\n{stderr}\nstage={name} stream=stderr END\n")
    append(path, f"stage={name} event=END elapsed={time.monotonic() - started:.3f} rc={rc}\n")
    if rc:
        print(stderr, file=sys.stderr, end="")
        raise RuntimeError(f"{name} failed")
    print(f"T15 DIRECT PASS: {name}", flush=True)


def provider_fixture(content: bytes) -> tuple[tempfile.TemporaryDirectory, Path, Path]:
    holder = tempfile.TemporaryDirectory(prefix="flow-t15-provider-")
    root = Path(holder.name)
    backup = root / "CLAUDE.md.pre-refresh-20260906T000000Z"
    backup.write_bytes(content)
    status = root / "state/audit/flow-recovery-status.json"
    status.parent.mkdir(parents=True)
    relative = backup.relative_to(root).as_posix()
    status.write_text(json.dumps({
        "schema_version": 2,
        "backup_artifacts": [{
            "path": relative,
            "sha256": hashlib.sha256(content).hexdigest(),
        }],
    }), encoding="utf-8")
    return holder, root, backup


def provider_check(project: Path, content: bytes, mode: str) -> tuple[str, str]:
    preflight = load(project / "hooks/local/lib/recovery-preflight.py", f"preflight_{mode}")
    overlay = load(
        project / "hooks/local/fusebase-flow-overlays/overlay-block-replace.py",
        f"overlay_{mode}",
    )
    holder, root, backup = provider_fixture(content)
    try:
        headings = tuple(item.encode() for item in (
            "## FuseBase Flow — Claude Code adapter",
            "## FuseBase Flow — additional rules (overlay)",
            "## Fusebase Flow — additional rules (overlay)",
        ))
        relative = backup.relative_to(root).as_posix()
        found, error = preflight.verified_provider_backup(root, "CLAUDE.md", overlay, headings)
        if found != relative or error:
            raise AssertionError(f"positive provider control failed: found={found!r} error={error!r}")
        if mode == "tampered-backup":
            backup.write_bytes(content + b"\nTAMPERED\n")
            expected = "hash mismatch"
        else:
            backup.unlink()
            expected = "no ownership-verified provider backup"
        found, error = preflight.verified_provider_backup(root, "CLAUDE.md", overlay, headings)
        if found or expected not in error or (root / "CLAUDE.md").exists():
            raise AssertionError(f"provider refusal failed: found={found!r} error={error!r}")
        return f"positive control accepted {relative}; {mode} refused; target remained absent", ""
    finally:
        holder.cleanup()


def validate_bash(raw: str) -> Path:
    path = Path(raw)
    if not path.is_absolute() or not path.is_file():
        raise ValueError("Bash executable must be an absolute existing file")
    return path


def selection(raw: str) -> str:
    if raw not in {"settings-wiring", "status-writer"}:
        raise argparse.ArgumentTypeError(f"unknown selection: {raw}")
    return raw


def shell_path(path: Path) -> str:
    value = str(path)
    return value.replace("\\", "/") if os.name == "nt" else value


def write_status(
    project: Path, plan: dict, verified: list[str], uncertain: list[str], bash: Path,
) -> subprocess.CompletedProcess[str]:
    script = r'''
set -euo pipefail
. "$1/hooks/local/lib/flow-recovery-plan.sh"
FFRP_ROOT="$1"
FFRP_PLANNED="$2"
FFRP_PLAN_ID="$3"
FFRP_APPLIED="$2"
ffrp_verified "$4" "$5"
ffrp_finish partial 1 "post-apply verification found incomplete surfaces"
'''
    return subprocess.run(
        [str(bash), "-c", script, "t37-status", shell_path(project),
         ",".join(plan["surfaces"]), plan["plan_id"],
         ",".join(verified), ",".join(uncertain)],
        text=True, capture_output=True, timeout=20, shell=False,
    )


def verify_status(
    project: Path, plan: dict, verifier, bash: Path,
) -> tuple[str, str]:
    positive = verifier.verify(project, plan)
    if positive["failures"] or positive["uncertain_surfaces"]:
        raise AssertionError(f"positive verification control failed: {positive}")
    command = next(row for row in plan["targets"] if row["surface"] == "commands")
    target = project / command["target"]
    target.write_bytes(target.read_bytes() + b"\nT15 POST-APPLY TAMPER\n")
    result = verifier.verify(project, plan)
    if "commands" not in result["uncertain_surfaces"] or "commands" in result["verified_surfaces"]:
        raise AssertionError(f"command mutation was not isolated: {result}")
    written = write_status(
        project, plan, result["verified_surfaces"], result["uncertain_surfaces"], bash,
    )
    if written.returncode:
        raise AssertionError(f"status writer failed: {written.stderr}")
    status = json.loads((project / "state/audit/flow-recovery-status.json").read_text(encoding="utf-8"))
    if status["status"] != "partial" or status["exit_code"] != 1:
        raise AssertionError(f"status is not partial: {status}")
    if "commands" not in status["uncertain_surfaces"] or "commands" in status["verified_surfaces"]:
        raise AssertionError(f"status misstated command uncertainty: {status}")
    return "positive verifier control passed; command mutation uncertain; actual status writer recorded partial", written.stderr


def post_apply_check(project: Path, bash: Path) -> tuple[str, str]:
    preflight = load(project / "hooks/local/lib/recovery-preflight.py", "preflight_post_apply")
    verifier = load(project / "hooks/local/lib/recovery-verify.py", "verify_post_apply")
    plan = preflight.build_plan(project, False, False, False)
    return verify_status(project, plan, verifier, bash)


def status_writer_check(bash: Path) -> tuple[str, str]:
    for invalid in ("bash", str(SOURCE_ROOT / "missing-bash")):
        try:
            validate_bash(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid executable accepted: {invalid}")
    try:
        selection("unknown")
    except argparse.ArgumentTypeError:
        pass
    else:
        raise AssertionError("unknown selection was accepted")
    with tempfile.TemporaryDirectory(prefix="flow-t15-status-") as raw:
        root = Path(raw)
        source = root / "command-source.md"
        target = root / ".claude/commands/fusebase-health.md"
        source.write_bytes(b"command\n")
        target.parent.mkdir(parents=True)
        target.write_bytes(source.read_bytes())
        overlay_dir = root / "hooks/local/fusebase-flow-overlays"
        overlay_dir.mkdir(parents=True)
        shutil.copyfile(
            SOURCE_ROOT / "hooks/local/fusebase-flow-overlays/overlay-block-replace.py",
            overlay_dir / "overlay-block-replace.py",
        )
        for target_name, template_name in (
            ("AGENTS.md", "agents-md-overlay.md"),
            ("CLAUDE.md", "claude-md-overlay.md"),
        ):
            content = (SOURCE_ROOT / "hooks/local/fusebase-flow-overlays" / template_name).read_bytes()
            (root / target_name).write_bytes(b"external provider bytes\n" + content)
        plan_lib = root / "hooks/local/lib/flow-recovery-plan.sh"
        plan_lib.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE_ROOT / "hooks/local/lib/flow-recovery-plan.sh", plan_lib)
        plan = {
            "schema_version": 1,
            "plan_id": "t38-status-writer",
            "surfaces": ["commands"],
            "options": {"wire_hooks": False, "restore_git_hooks": False},
            "overlays": [],
            "targets": [{
                "surface": "commands", "source": "command-source.md",
                "target": ".claude/commands/fusebase-health.md",
                "classification": "current", "detail": "fixture",
            }],
        }
        verifier = load(SOURCE_ROOT / "hooks/local/lib/recovery-verify.py", "verify_status_only")
        stdout, stderr = verify_status(root, plan, verifier, bash)
    return (
        "invalid executable and selection refused without fixture writes; " + stdout,
        stderr,
    )


def invoke_merge(module, path: Path) -> int:
    original = module.sys.argv
    try:
        module.sys.argv = [str(module.__file__), str(path)]
        return module.main()
    finally:
        module.sys.argv = original


def settings_wiring_check() -> tuple[str, str]:
    with tempfile.TemporaryDirectory(prefix="flow-t49-settings-") as raw:
        root = Path(raw).resolve()
        overlay_dir = root / "hooks/local/fusebase-flow-overlays"
        verifier_dir = root / "hooks/local/lib"
        overlay_dir.mkdir(parents=True)
        verifier_dir.mkdir(parents=True)
        merge_path = overlay_dir / "settings-json-merge.py"
        verifier_path = verifier_dir / "recovery-verify.py"
        shutil.copyfile(
            SOURCE_ROOT / "hooks/local/fusebase-flow-overlays/settings-json-merge.py",
            merge_path,
        )
        shutil.copyfile(SOURCE_ROOT / "hooks/local/lib/recovery-verify.py", verifier_path)
        merge = load(merge_path, "t49_settings_merge")
        verifier = load(verifier_path, "t49_recovery_verify")

        hooks = {
            event: [merge.make_event_block(event)] for event in merge.DEFAULT_FLOW_HOOKS
        }
        consumer_a = {
            "matcher": "Bash", "scope": "operator-a",
            "hooks": [{"type": "command", "command": "bash ./consumer-a.sh", "timeout": 41}],
        }
        consumer_b = {
            "matcher": "Write", "scope": "operator-b",
            "hooks": [{"type": "command", "command": "bash ./consumer-b.sh", "timeout": 42}],
        }
        restricted = merge.make_event_block("PreToolUse")
        restricted["matcher"] = "Bash"
        hooks["PreToolUse"] = [copy.deepcopy(consumer_a), restricted, copy.deepcopy(consumer_b)]
        settings_path = root / ".claude/settings.json"
        settings_path.parent.mkdir()
        settings_path.write_text(json.dumps({"hooks": hooks}, indent=2) + "\n", encoding="utf-8")
        intent = root / "state/audit/flow-hook-wiring-intent.json"
        intent.parent.mkdir(parents=True)
        intent.write_text(json.dumps({
            "schema_version": 2, "enabled": True, "repo_root": str(root),
            "surfaces": ["claude_settings"],
        }), encoding="utf-8")
        plan = {"options": {"wire_hooks": True}}

        initial_failures: dict[str, list[str]] = {}
        verifier.verify_settings(root, plan, initial_failures)
        assert "claude_settings" in initial_failures
        before = settings_path.read_bytes()
        assert invoke_merge(merge, settings_path) == 0
        after = settings_path.read_bytes()
        assert after != before
        repaired = json.loads(settings_path.read_text(encoding="utf-8"))
        blocks = repaired["hooks"]["PreToolUse"]
        assert blocks[:2] == [consumer_a, consumer_b]
        assert blocks[-1] == merge.make_event_block("PreToolUse")
        repaired_failures: dict[str, list[str]] = {}
        verifier.verify_settings(root, plan, repaired_failures)
        assert not repaired_failures

        assert invoke_merge(merge, settings_path) == 0
        assert settings_path.read_bytes() == after

        metadata_mutation = copy.deepcopy(repaired)
        metadata_handler = metadata_mutation["hooks"]["PostToolUse"][0]["hooks"][0]
        metadata_handler["type"] = "prompt"
        metadata_handler["timeout"] = 99
        metadata_handler["scope"] = "operator"
        settings_path.write_text(json.dumps(metadata_mutation), encoding="utf-8")
        mutated_bytes = settings_path.read_bytes()
        assert invoke_merge(merge, settings_path) == 0
        assert settings_path.read_bytes() != mutated_bytes
        metadata_repaired = json.loads(settings_path.read_text(encoding="utf-8"))
        assert metadata_repaired["hooks"]["PostToolUse"] == [
            merge.make_event_block("PostToolUse")
        ]

        duplicate = copy.deepcopy(repaired)
        duplicate["hooks"]["PreToolUse"].append(merge.make_event_block("PreToolUse"))
        settings_path.write_text(json.dumps(duplicate), encoding="utf-8")
        duplicate_failures: dict[str, list[str]] = {}
        verifier.verify_settings(root, plan, duplicate_failures)
        assert "claude_settings" in duplicate_failures

        wrong_type = copy.deepcopy(repaired)
        flow_handler = wrong_type["hooks"]["PreToolUse"][-1]["hooks"][0]
        flow_handler["type"] = "prompt"
        flow_handler["timeout"] = 99
        settings_path.write_text(json.dumps(wrong_type), encoding="utf-8")
        wrong_type_failures: dict[str, list[str]] = {}
        verifier.verify_settings(root, plan, wrong_type_failures)
        assert "claude_settings" in wrong_type_failures

    return (
        "PASS: T49 Bash-only matcher repair persisted\n"
        "PASS: T49 custom block order and scope preserved\n"
        "PASS: T49 second merge byte-identical\n"
        "PASS: T49 duplicate and wrong-type mutations rejected",
        "",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root")
    parser.add_argument("--backup")
    parser.add_argument("--stage-file", required=True)
    parser.add_argument("--bash-executable", required=True)
    parser.add_argument("--only", type=selection)
    args = parser.parse_args()
    stage_file = Path(args.stage_file).resolve()
    try:
        bash = validate_bash(args.bash_executable)
        if args.only == "settings-wiring":
            stage(stage_file, "settings-wiring", settings_wiring_check)
            print("PARTIAL/NON-ATTESTING: settings-wiring selection only")
            return 0
        if args.only == "status-writer":
            stage(stage_file, "status-writer", lambda: status_writer_check(bash))
            print("PARTIAL/NON-ATTESTING: status-writer selection only")
            return 0
        if not args.root or not args.backup:
            raise ValueError("--root and --backup are required without --only")
        project = Path(args.root).resolve()
        backup = Path(args.backup).resolve()
        content = backup.read_bytes()
        stage(stage_file, "tampered-backup", lambda: provider_check(project, content, "tampered-backup"))
        stage(stage_file, "missing-backup", lambda: provider_check(project, content, "missing-backup"))
        stage(stage_file, "post-apply-verification", lambda: post_apply_check(project, bash))
    except Exception as exc:
        print(f"[test-recovery-final-verification] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
