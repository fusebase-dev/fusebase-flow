#!/usr/bin/env python3
"""Record consumer workflow, validation, recovery, and isolated CLI measurements."""

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def bash_executable():
    configured = os.environ.get("FUSEBASE_FLOW_BASH")
    git = shutil.which("git")
    candidates = [configured]
    if git and os.name == "nt":
        candidates.append(str(Path(git).resolve().parents[1] / "bin/bash.exe"))
    candidates.append(shutil.which("bash"))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    return "bash"


def measured(value, unit=None):
    row = {"status": "MEASURED", "value": value}
    if unit:
        row["unit"] = unit
    return row


def unavailable(reason):
    return {"status": "UNAVAILABLE", "reason": reason}


def run(command, cwd, env=None, timeout=60):
    start = time.perf_counter()
    try:
        result = subprocess.run(
            command, cwd=str(cwd), env=env, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        return result.returncode, time.perf_counter() - start, None
    except subprocess.TimeoutExpired:
        return None, time.perf_counter() - start, "bounded timeout after %ss" % timeout
    except OSError as exc:
        return None, time.perf_counter() - start, str(exc)


def load_lane_fixture():
    path = ROOT / "hooks/tests/lane-workflow-fixture.py"
    spec = importlib.util.spec_from_file_location("lane_workflow_benchmark", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.BASH_EXE = bash_executable()
    return module


def workflow_measurements():
    fixture = load_lane_fixture()
    rows = []
    scenarios = [
        ("ordinary-diagnosed-fix", ["src/widgets.py"], []),
        ("sensitive-auth-change", ["src/ordinary_logic.py"], [{
            "trigger_id": "auth", "evidence_path": "src/ordinary_logic.py:12",
            "reason": "diagnosed behavior changes authentication",
        }]),
    ]
    for name, paths, triggers in scenarios:
        start = time.perf_counter()
        result = fixture.run_scenario(name, paths, True, triggers)
        elapsed = time.perf_counter() - start
        rows.append({
            "scenario": name,
            "lane": result["final_lane"],
            "wall_time": measured(round(elapsed, 6), "seconds"),
            "actual_tokens": unavailable("host did not expose model token telemetry"),
            "tool_calls": unavailable("deterministic fixture records subprocesses, not agent tool telemetry"),
            "subprocess_calls": measured(2, "calls"),
            "operator_decisions": measured(result["product_decisions"], "decisions"),
            "role_relays": measured(result["relays"], "relays"),
            "artifacts": measured(len(result["created_artifacts"]), "artifacts"),
        })
    return rows


def validation_measurement():
    with tempfile.TemporaryDirectory(prefix="flow-validator-benchmark-") as raw:
        repo = Path(raw) / "repo"
        outside = Path(raw) / "count"
        (repo / "hooks/local/lib").mkdir(parents=True)
        outside.mkdir()
        shutil.copy2(ROOT / "hooks/local/lib/validator-evidence.py", repo / "hooks/local/lib/")
        shutil.copy2(ROOT / "hooks/local/run-validators.sh", repo / "hooks/local/")
        (repo / "validator.py").write_text(
            "import os,pathlib,sys\np=pathlib.Path(os.environ['FFBENCH_COUNT'])/sys.argv[1]\np.write_text((p.read_text() if p.exists() else '')+'x')\n",
            encoding="utf-8",
        )
        (repo / "evidence.sh").write_text(
            "#!/usr/bin/env bash\npython3 -S hooks/local/lib/validator-evidence.py \"$1\" --root \"$PWD\" --lint \"$FUSEBASE_FLOW_LINT\" --typecheck \"$FUSEBASE_FLOW_TYPECHECK\"\n",
            encoding="utf-8",
        )
        (repo / "source.txt").write_text("source\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "fixture@example.test"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Fixture"], cwd=repo, check=True)
        subprocess.run(
            ["git", "add", "--", "hooks", "validator.py", "evidence.sh", "source.txt"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=repo, check=True)
        (repo / "source.txt").write_text("changed\n", encoding="utf-8")
        subprocess.run(["git", "add", "--", "source.txt"], cwd=repo, check=True)
        lint = "python3 validator.py lint"
        typecheck = "python3 validator.py typecheck"
        env = os.environ.copy()
        env.update({
            "FUSEBASE_FLOW_LINT": lint,
            "FUSEBASE_FLOW_TYPECHECK": typecheck,
            "FFBENCH_COUNT": str(outside),
        })
        rc, elapsed, error = run([bash_executable(), "hooks/local/run-validators.sh"], repo, env)
        verify_rc, verify_elapsed, verify_error = run(
            [bash_executable(), "evidence.sh", "verify"], repo, env)
        run([bash_executable(), "evidence.sh", "invalidate"], repo, env)
        counts = {
            name: len((outside / name).read_text()) if (outside / name).exists() else 0
            for name in ("lint", "typecheck")
        }
        return {
            "command_identity": measured({"lint": lint, "typecheck": typecheck}),
            "validator_runs": measured(sum(counts.values()), "runs"),
            "validator_duration": measured(round(elapsed, 6), "seconds"),
            "receipt_verify_duration": measured(round(verify_elapsed, 6), "seconds"),
            "exact_state_reuse": measured(rc == 0 and verify_rc == 0 and counts == {"lint": 1, "typecheck": 1}),
            "error": unavailable(error or verify_error) if error or verify_error else None,
        }


def tree_fingerprint(paths):
    digest = hashlib.sha256()
    files = []
    for path in paths:
        files.extend([path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file()))
    for path in sorted(set(files)):
        digest.update(str(path.relative_to(ROOT)).replace("\\", "/").encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def recovery_measurement():
    targets = [ROOT / "flow-skills", ROOT / ".agents/skills", ROOT / ".claude/skills",
               ROOT / "audit/skill-mirror-manifest.txt"]
    before = tree_fingerprint(targets)
    rc, elapsed, error = run(
        [bash_executable(), "hooks/local/mirror-skills.sh", "--check"], ROOT)
    after = tree_fingerprint(targets)
    return {
        "command": "bash hooks/local/mirror-skills.sh --check",
        "wall_time": measured(round(elapsed, 6), "seconds"),
        "no_op_writes": measured(0 if rc == 0 and before == after else None, "writes")
        if rc == 0 and before == after else unavailable(error or "hash check failed or target bytes changed"),
        "result": "PASS" if rc == 0 and before == after else "UNVERIFIED",
    }


def workspace_state():
    status = subprocess.run(
        ["git", "status", "--porcelain=v1", "-uall"], cwd=ROOT,
        capture_output=True, check=True,
    ).stdout
    diff = subprocess.run(
        ["git", "diff", "--binary", "HEAD"], cwd=ROOT,
        capture_output=True, check=True,
    ).stdout
    owned = tree_fingerprint([
        ROOT / ".git/hooks", ROOT / ".agents", ROOT / ".claude", ROOT / "flow-skills",
        ROOT / "hooks", ROOT / "policies", ROOT / "audit", ROOT / "AGENTS.md", ROOT / "CLAUDE.md",
    ])
    return hashlib.sha256(status + b"\0" + diff + b"\0" + owned.encode()).hexdigest()


def directory_state(root):
    return {
        str(path.relative_to(root)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*")) if path.is_file()
    }


def cli_refresh_measurement(mode):
    if mode == "skip":
        return {"result": "UNVERIFIED", "reason": "isolated current-CLI refresh was not requested"}
    cli = shutil.which("fusebase")
    if not cli:
        return {"result": "UNVERIFIED", "reason": "current FuseBase CLI executable unavailable"}
    version = subprocess.run(
        [cli, "--version"], capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=15,
    )
    shared_before = workspace_state()
    with tempfile.TemporaryDirectory(prefix="flow-current-cli-refresh-") as raw:
        project = Path(raw).resolve()
        if project == ROOT or ROOT in project.parents or not project.is_dir():
            return {"result": "UNVERIFIED", "reason": "disposable directory validation failed"}
        (project / "fusebase.json").write_text(
            json.dumps({"orgId": "isolated-fixture", "productId": "isolated-fixture", "apps": []}) + "\n",
            encoding="utf-8",
        )
        project_before = directory_state(project)
        command = [
            cli, "update", "--skip-cli-update", "--skip-mcp",
            "--skip-deps", "--skip-install", "--skip-commit",
            "--skip-gate-permissions-sync",
        ]
        rc, elapsed, error = run(command, project, timeout=60)
        project_after = directory_state(project)
        changed = sorted(
            path for path in set(project_before) | set(project_after)
            if project_before.get(path) != project_after.get(path)
        )
    shared_unchanged = shared_before == workspace_state()
    success = rc == 0 and shared_unchanged and bool(changed)
    return {
        "result": "PASS" if success else "UNVERIFIED",
        "command": "fusebase update " + " ".join(command[2:]),
        "cli_identity": measured({"path": cli, "version": version.stdout.strip()}),
        "wall_time": measured(round(elapsed, 6), "seconds"),
        "exit_code": measured(rc) if rc is not None else unavailable(error or "no exit code"),
        "changed_files": measured(len(changed), "files"),
        "disposable_directory_validated": measured(True),
        "shared_workspace_unchanged": measured(shared_unchanged),
        "reason": None if success else error or "current CLI returned nonzero, produced no isolated writes, or shared workspace changed",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cli-refresh", choices=("attempt", "skip"), default="skip")
    args = parser.parse_args()
    report = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "hard_performance_gate": False,
        "workflow": workflow_measurements(),
        "validation": validation_measurement(),
        "recovery": recovery_measurement(),
        "current_cli_refresh": cli_refresh_measurement(args.cli_refresh),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
