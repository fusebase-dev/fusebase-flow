#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

SKILL = "fusebase-flow-health-check"
AGENT = "t39-fixture-agent"
COMMAND = "fusebase-health.md"
STATUS = "state/audit/flow-recovery-status.json"
CONVERGENCE_TIMEOUT = 80
EXCLUSIONS = [STATUS, "T39 evidence directory (outside fixture root)"]
COPY_MARKERS = {
    "skill": "Fusebase Flow skill mirrors already current",
    "agent": "Fusebase Flow agent mirrors already current",
}

def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()

def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, path)

def append_event(path: Path, stage: str, event: str, **values: Any) -> None:
    row = {"stage": stage, "event": event, "utc": utc_now(), **values}
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def digest_rows(rows: dict[str, Any]) -> str:
    data = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def file_rows(root: Path, paths: list[Path]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for path in sorted(set(paths)):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            rows[rel] = {"type": "symlink", "target": os.readlink(path)}
        elif path.is_file():
            stat = path.stat()
            rows[rel] = {
                "type": "file", "sha256": sha(path), "mtime_ns": stat.st_mtime_ns,
            }
        elif path.exists():
            rows[rel] = {"type": "other"}
        else:
            rows[rel] = {"type": "missing"}
    return rows


def inventory(root: Path) -> dict[str, Any]:
    fixed = [
        "AGENTS.md", "CLAUDE.md", ".claude/settings.json",
        ".claude/settings.json.pre-flow-merge", ".codex/config.toml",
        ".claude/hooks/cli-user-sentinel.sh", "user-owned.txt",
        "audit/skill-mirror-manifest.txt", "audit/agent-mirror-manifest.txt",
        "state/audit/cli-stop-baseline.json", "state/audit/flow-hook-wiring-intent.json",
        "state/audit/recovery-owned-targets.json", ".git/hooks/pre-commit",
        ".git/hooks/commit-msg",
    ]
    paths = [root / rel for rel in fixed]
    for rel in (
        ".claude/skills", ".agents/skills", ".claude/agents",
        ".codex/agents", ".claude/commands",
    ):
        directory = root / rel
        if directory.is_dir():
            paths.extend(path for path in directory.rglob("*") if not path.is_dir())
    rows = file_rows(root, paths)
    return {"digest": digest_rows(rows), "targets": rows}


def changed(before: dict[str, Any], after: dict[str, Any]) -> list[str]:
    left, right = before["targets"], after["targets"]
    return sorted(key for key in set(left) | set(right) if left.get(key) != right.get(key))


def copy_source(source: Path, root: Path, rel: str, copied: list[str]) -> None:
    target = root / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / rel, target)
    copied.append(rel)


def build_fixture(source: Path, root: Path, git: Path) -> tuple[str, str]:
    copied: list[str] = []
    for rel in (
        "hooks/local/post-fusebase-update.sh", "hooks/local/mirror-skills.sh",
        "hooks/local/mirror-agents.sh", "hooks/local/install-git-hooks.sh",
        "hooks/git/pre-commit", "hooks/git/commit-msg",
        "hooks/local/fusebase-flow-overlays/agent-surface-ownership.json",
        "hooks/local/fusebase-flow-overlays/agents-md-overlay.md",
        "hooks/local/fusebase-flow-overlays/claude-md-overlay.md",
        "hooks/local/fusebase-flow-overlays/overlay-block-replace.py",
        "hooks/local/fusebase-flow-overlays/settings-json-merge.py",
        f"hooks/local/fusebase-flow-overlays/commands/{COMMAND}",
        f"hooks/local/fusebase-flow-overlays/skills/{SKILL}/SKILL.md",
    ):
        copy_source(source, root, rel, copied)
    shutil.copytree(
        source / "hooks/local/lib", root / "hooks/local/lib",
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
    )
    copied.extend(
        path.relative_to(source).as_posix()
        for path in (source / "hooks/local/lib").rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
    )
    canonical = root / f"flow-skills/{SKILL}"
    (canonical / "references").mkdir(parents=True)
    shutil.copy2(
        source / f"hooks/local/fusebase-flow-overlays/skills/{SKILL}/SKILL.md",
        canonical / "SKILL.md",
    )
    (canonical / "references/direct.md").write_text("T39 direct reference\n", encoding="utf-8")
    agent = root / f"agents/{AGENT}/AGENT.md"
    agent.parent.mkdir(parents=True)
    agent.write_text("# T39 fixture agent\n", encoding="utf-8")
    (root / "FLOW_RULES.md").write_text("# T39 fixture rules\n", encoding="utf-8")
    (root / "AGENTS.md").write_text(
        "# CLI project\n\nT39 CLI AGENTS SENTINEL\n\n## Fusebase Flow V2 - stale overlay\n",
        encoding="utf-8",
    )
    (root / "CLAUDE.md").write_text(
        "# CLI project\n\nT39 CLI CLAUDE SENTINEL\n\n## Fusebase Flow V2 - stale overlay\n",
        encoding="utf-8",
    )
    settings = root / ".claude/settings.json"
    settings.parent.mkdir(parents=True)
    settings.write_text(json.dumps({
        "enabledMcpjsonServers": ["fusebase-dashboards"],
        "hooks": {"Stop": [{"hooks": [{
            "type": "command",
            "command": 'bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/cli-user-sentinel.sh',
            "timeout": 30,
        }]}]},
    }, indent=2) + "\n", encoding="utf-8")
    sentinels = {
        ".claude/hooks/cli-user-sentinel.sh": "#!/usr/bin/env bash\necho T39_CLI_HOOK_SENTINEL\n",
        ".codex/config.toml": "T39_CLI_CONFIG_SENTINEL = true\n",
        ".claude/skills/fusebase-cli/SKILL.md": "T39_CLI_SKILL_SENTINEL\n",
        ".agents/skills/fusebase-cli/SKILL.md": "T39_CLI_SKILL_SENTINEL\n",
        "user-owned.txt": "T39_USER_SENTINEL\n",
    }
    for rel, content in sentinels.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    subprocess.run([str(git), "init", "--quiet", str(root)], check=True)
    subprocess.run([str(git), "-C", str(root), "config", "user.name", "T39 fixture"], check=True)
    subprocess.run(
        [str(git), "-C", str(root), "config", "user.email", "t39@example.invalid"],
        check=True,
    )
    source_rows = file_rows(source, [source / rel for rel in copied])
    input_paths = [
        path for path in root.rglob("*")
        if path.is_file() and ".git" not in path.relative_to(root).parts
    ]
    return digest_rows(source_rows), digest_rows(file_rows(root, input_paths))


def read_status(root: Path) -> dict[str, Any]:
    value = json.loads((root / STATUS).read_text(encoding="utf-8"))
    if (value.get("status"), value.get("exit_code")) != ("complete", 0):
        raise AssertionError(f"recovery status is not complete: {value}")
    if value.get("pending_surfaces") or value.get("uncertain_surfaces"):
        raise AssertionError(f"recovery status retains incomplete surfaces: {value}")
    return value


def parse_copy_counts(stdout: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for family, marker in COPY_MARKERS.items():
        if stdout.count(marker) != 1:
            raise AssertionError(f"missing or ambiguous {family} zero-copy marker")
        counts[family] = 0
    return counts


def run_recovery(
    bash: Path, root: Path, evidence: Path, name: str, timeout: int, args: list[str],
) -> dict[str, Any]:
    command = [str(bash), "hooks/local/post-fusebase-update.sh", *args]
    start_utc, start_tick = utc_now(), time.monotonic()
    process = subprocess.Popen(
        command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace", shell=False,
    )
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        rc = process.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        stdout, stderr = process.communicate()
        rc = 124
    elapsed = time.monotonic() - start_tick
    (evidence / f"{name}.stdout.log").write_text(stdout, encoding="utf-8")
    (evidence / f"{name}.stderr.log").write_text(stderr, encoding="utf-8")
    return {
        "command": command, "pid": process.pid, "started_utc": start_utc,
        "ended_utc": utc_now(), "monotonic_started": start_tick,
        "elapsed_seconds": round(elapsed, 3), "exit_code": rc,
        "timed_out": timed_out, "stdout": stdout, "stderr": stderr,
    }


def require_expected(root: Path) -> None:
    pairs = [
        (f"flow-skills/{SKILL}/SKILL.md", f".claude/skills/{SKILL}/SKILL.md"),
        (f"flow-skills/{SKILL}/SKILL.md", f".agents/skills/{SKILL}/SKILL.md"),
        (f"flow-skills/{SKILL}/references/direct.md", f".claude/skills/{SKILL}/references/direct.md"),
        (f"flow-skills/{SKILL}/references/direct.md", f".agents/skills/{SKILL}/references/direct.md"),
        (f"agents/{AGENT}/AGENT.md", f".claude/agents/{AGENT}.md"),
        (f"agents/{AGENT}/AGENT.md", f".codex/agents/{AGENT}.md"),
        (f"hooks/local/fusebase-flow-overlays/commands/{COMMAND}", f".claude/commands/{COMMAND}"),
        ("hooks/git/pre-commit", ".git/hooks/pre-commit"),
        ("hooks/git/commit-msg", ".git/hooks/commit-msg"),
    ]
    for source, target in pairs:
        if (root / source).read_bytes() != (root / target).read_bytes():
            raise AssertionError(f"converged bytes differ: {target}")
    required = [
        ".claude/settings.json.pre-flow-merge", "state/audit/cli-stop-baseline.json",
        "state/audit/flow-hook-wiring-intent.json", "state/audit/recovery-owned-targets.json",
        "audit/skill-mirror-manifest.txt", "audit/agent-mirror-manifest.txt",
    ]
    if any(not (root / rel).is_file() for rel in required):
        raise AssertionError("convergence omitted required receipt or manifest")
    sentinel_pairs = {
        "AGENTS.md": "T39 CLI AGENTS SENTINEL",
        "CLAUDE.md": "T39 CLI CLAUDE SENTINEL",
        ".claude/settings.json": "cli-user-sentinel.sh",
        ".claude/hooks/cli-user-sentinel.sh": "T39_CLI_HOOK_SENTINEL",
        ".codex/config.toml": "T39_CLI_CONFIG_SENTINEL",
        ".claude/skills/fusebase-cli/SKILL.md": "T39_CLI_SKILL_SENTINEL",
        "user-owned.txt": "T39_USER_SENTINEL",
    }
    for rel, value in sentinel_pairs.items():
        if value not in (root / rel).read_text(encoding="utf-8"):
            raise AssertionError(f"sentinel lost: {rel}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--bash-executable", required=True)
    args = parser.parse_args()
    source, root = Path(args.source_root).resolve(), Path(args.project).resolve()
    evidence, bash = Path(args.evidence_dir).resolve(), Path(args.bash_executable)
    if not bash.is_absolute() or not bash.is_file():
        print("T39: Bash executable must be an absolute existing file", file=sys.stderr)
        return 1
    git_value = shutil.which("git")
    if not git_value or not Path(git_value).is_absolute():
        print("T39: Git executable identity unavailable", file=sys.stderr)
        return 1
    evidence.mkdir(parents=True, exist_ok=True)
    progress = evidence / "stages.jsonl"
    active_stage = ""
    try:
        active_stage = "fixture"
        append_event(progress, "fixture", "START", exclusions=EXCLUSIONS)
        source_digest, input_digest = build_fixture(source, root, Path(git_value))
        atomic_json(evidence / "identity.json", {
            "source_root": str(source), "source_digest": source_digest,
            "input_digest": input_digest, "bash_executable": str(bash),
            "git_executable": git_value, "diagnostic_exclusions": EXCLUSIONS,
        })
        append_event(progress, "fixture", "END", rc=0)
        active_stage = "convergence"
        append_event(progress, "convergence", "START", timeout_seconds=CONVERGENCE_TIMEOUT)
        convergence = run_recovery(
            bash, root, evidence, "convergence", CONVERGENCE_TIMEOUT, ["--wire-hooks"],
        )
        convergence_record = {
            key: value for key, value in convergence.items() if key not in ("stdout", "stderr")
        } | {"source_digest": source_digest, "input_digest": input_digest}
        atomic_json(evidence / "convergence.json", convergence_record)
        if convergence["exit_code"]:
            raise AssertionError(f"convergence exited {convergence['exit_code']}")
        convergence_record["status"] = read_status(root)
        require_expected(root)
        convergence_record["target_inventory"] = inventory(root)
        atomic_json(evidence / "convergence.json", convergence_record)
        append_event(
            progress, "convergence", "END", rc=0,
            elapsed_seconds=convergence["elapsed_seconds"], pid=convergence["pid"],
        )
        active_stage = ""
        pids: set[int] = set()
        for number in (1, 2, 3):
            name = f"attempt{number}"
            active_stage = name
            append_event(progress, name, "START", timeout_seconds=45)
            before = inventory(root)
            status_mtime_before = (root / STATUS).stat().st_mtime_ns
            result = run_recovery(bash, root, evidence, name, 45, [])
            after = inventory(root)
            status_mtime_after = (root / STATUS).stat().st_mtime_ns
            changed_targets = changed(before, after)
            record = {
                key: value for key, value in result.items() if key not in ("stdout", "stderr")
            } | {
                "attempt_id": f"write-mode-{number}", "source_digest": source_digest,
                "input_digest": input_digest, "before": before, "after": after,
                "changed_targets": changed_targets,
                "changed_target_count": len(changed_targets),
                "status_mtime_before_ns": status_mtime_before,
                "status_mtime_after_ns": status_mtime_after,
                "diagnostic_exclusions": EXCLUSIONS,
            }
            error = ""
            try:
                if result["exit_code"]:
                    raise AssertionError(f"attempt exited {result['exit_code']}")
                record["reported_copy_count"] = parse_copy_counts(result["stdout"])
                record["status"] = read_status(root)
                if status_mtime_after <= status_mtime_before:
                    raise AssertionError("complete status was not freshly rewritten")
                if changed_targets:
                    raise AssertionError(f"attempt changed targets: {changed_targets}")
                if result["pid"] in pids:
                    raise AssertionError("recovery process PID was reused")
                pids.add(result["pid"])
            except Exception as exc:
                error = str(exc)
                record["error"] = error
            atomic_json(evidence / f"{name}.json", record)
            append_event(
                progress, name, "END", rc=1 if error else 0,
                elapsed_seconds=result["elapsed_seconds"], pid=result["pid"],
            )
            active_stage = ""
            if error:
                raise AssertionError(error)
            print(
                f"T20 ATTEMPT PASS: {number}/3 pid={result['pid']} "
                f"elapsed={result['elapsed_seconds']:.3f}s changed=0 skill_copied=0 agent_copied=0",
                flush=True,
            )
        active_stage = "mutation"
        append_event(progress, "mutation", "START")
        mutation_before = inventory(root)
        command_target = root / f".claude/commands/{COMMAND}"
        command_target.write_bytes(command_target.read_bytes() + b"\nT39 MUTATION\n")
        mutation_after = inventory(root)
        mutation_changed = changed(mutation_before, mutation_after)
        parser_refusals = 0
        for sample in ("", "re-mirrored Fusebase Flow skills; copied 1"):
            try:
                parse_copy_counts(sample)
            except AssertionError:
                parser_refusals += 1
        if command_target.relative_to(root).as_posix() not in mutation_changed or parser_refusals != 2:
            raise AssertionError("mutation or copy-count parser red control failed")
        atomic_json(evidence / "mutation.json", {
            "changed_targets": mutation_changed,
            "changed_target_count": len(mutation_changed),
            "copy_parser_refusals": parser_refusals,
        })
        append_event(
            progress, "mutation", "END", rc=0,
            changed_target_count=len(mutation_changed), copy_parser_refusals=parser_refusals,
        )
        active_stage = ""
        print("T20 MUTATION PASS: target drift and missing/nonzero copy evidence rejected", flush=True)
        return 0
    except Exception as exc:
        if active_stage:
            append_event(progress, active_stage, "END", rc=1, error=str(exc))
        append_event(progress, "run", "FAIL", rc=1, error=str(exc))
        print(f"T39: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
