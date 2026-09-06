#!/usr/bin/env python3

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROUTER = ROOT / "hooks/local/lane-router.sh"
ASSESSOR = ROOT / "hooks/local/lane-assessment.py"
BASH_EXE = "bash"
FULL_ARTIFACTS = ["spec.md", "decisions.md", "tasks.md", "verification-gate.md", "implement-handoff.md"]


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def diagnose(work: Path, paths: list[str], skip: bool) -> dict[str, object]:
    evidence: dict[str, str] = {}
    for relative in paths:
        target = work / "inputs" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f"fixture evidence for {relative}\n", encoding="utf-8")
        evidence[relative] = hashlib.sha256(target.read_bytes()).hexdigest()
    if not skip:
        write_json(work / "records/diagnosis.json", {"read_only": True, "files": evidence})
    return {"performed": (work / "records/diagnosis.json").is_file(),
            "read_only": True, "bounded": len(evidence) == len(paths),
            "evidence_paths": list(evidence)}


def execute_lane(work: Path, lane: str | None, mutation: str) -> None:
    if lane is None:
        return
    write_json(work / "records/product-decisions/decision.json", {"lane": lane})
    write_json(work / "records/agent-passes/product-owner.json", {"status": "complete"})
    artifacts = ["change-note.md"] if lane == "lightweight" else FULL_ARTIFACTS
    if lane == "full":
        write_json(work / "records/agent-passes/ai-developer.json", {"status": "complete"})
        write_json(work / "records/relays/implement.json", {"from": "product-owner", "to": "ai-developer"})
    for name in artifacts:
        target = work / "artifacts" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f"# Executed {name}\n", encoding="utf-8")
    write_json(work / "records/actions/applied.json", {"allowed_fixture_action": True})
    if mutation == "extra-relay":
        write_json(work / "records/relays/extra.json", {"unexpected": True})
    if mutation == "extra-artifact":
        (work / "artifacts/unexpected.md").write_text("unexpected\n", encoding="utf-8")


def run_scenario(scenario_id: str, paths: list[str], complete: bool,
                 triggers: list[dict[str, str]], *, mutation: str = "none",
                 workspace_root: Path | None = None) -> dict[str, object]:
    base = workspace_root or Path(tempfile.mkdtemp(prefix="flow-lane-fixture-"))
    work = base / scenario_id
    work.mkdir(parents=True, exist_ok=True)
    diagnosis = diagnose(work, paths, mutation == "skip-diagnosis")
    routed = subprocess.run([BASH_EXE, str(ROUTER), "--json", *paths], cwd=ROOT,
                            text=True, capture_output=True, check=False)
    if routed.returncode not in {0, 10}:
        raise RuntimeError(f"router failed for {scenario_id}: {routed.stderr}")
    router_result = json.loads(routed.stdout)
    assessed = subprocess.run(
        [sys.executable, str(ASSESSOR)], cwd=ROOT,
        input=json.dumps({"router": router_result,
                          "assessment": {"complete": complete, "triggers": triggers}}),
        text=True, capture_output=True, check=False)
    expected_rc = 20 if not complete else 10 if triggers or routed.returncode == 10 else 0
    if assessed.returncode != expected_rc:
        raise RuntimeError(f"assessor failed for {scenario_id}: {assessed.stdout}{assessed.stderr}")
    assessment_result = json.loads(assessed.stdout)
    final_lane = assessment_result.get("final_lane")
    execute_lane(work, final_lane, mutation)
    found_artifacts = {path.name for path in (work / "artifacts").glob("*") if path.is_file()}
    artifact_order = ["change-note.md"] if final_lane == "lightweight" else FULL_ARTIFACTS
    artifacts = ([name for name in artifact_order if name in found_artifacts]
                 + sorted(found_artifacts - set(artifact_order)))
    relays = list((work / "records/relays").glob("*.json"))
    passes = list((work / "records/agent-passes").glob("*.json"))
    decisions = list((work / "records/product-decisions").glob("*.json"))
    actions = list((work / "records/actions").glob("*.json"))
    return {
        "scenario_id": scenario_id, "diagnosis": diagnosis, "router_result": router_result,
        "assessor_declarations": triggers, "assessment_result": assessment_result,
        "final_lane": final_lane, "product_decisions": len(decisions), "relays": len(relays),
        "agent_passes": len(passes), "created_artifacts": artifacts,
        "allowed_actions": len(actions), "boundary": "scripted fixture simulation",
    }


def scenarios(mutation: str, workspace: Path) -> list[dict[str, object]]:
    rows = [
        run_scenario("ordinary-diagnosed-fix", ["src/widgets.py"], True, [], mutation=mutation, workspace_root=workspace),
        run_scenario("mechanical-protected-path", ["policies/command-policy.yml"], True, [], mutation=mutation, workspace_root=workspace),
    ]
    for trigger_id in ["auth", "permissions", "secrets", "data-schema", "public-contract",
                       "production-release", "protected-path", "cross-cutting-architecture",
                       "unresolved-product-decision"]:
        rows.append(run_scenario(
            f"semantic-{trigger_id}", ["src/ordinary_logic.py"], True,
            [{"trigger_id": trigger_id, "evidence_path": "src/ordinary_logic.py:12",
              "reason": f"diagnosed behavior activates {trigger_id}"}],
            mutation=mutation, workspace_root=workspace))
    rows.append(run_scenario("unresolved-assessment", ["src/unknown.py"], False, [],
                             mutation=mutation, workspace_root=workspace))
    return rows


def valid(rows: list[dict[str, object]]) -> bool:
    for row in rows:
        lane = row["final_lane"]
        if not row["diagnosis"]["performed"]:
            return False
        expected = ((1, 0, 1, ["change-note.md"]) if lane == "lightweight" else
                    (1, 1, 2, sorted(FULL_ARTIFACTS)) if lane == "full" else (0, 0, 0, []))
        actual = (row["product_decisions"], row["relays"], row["agent_passes"],
                  sorted(row["created_artifacts"]))
        if actual != expected or (lane is not None and row["allowed_actions"] != 1):
            return False
    return True


def main() -> int:
    global BASH_EXE
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--bash", default="bash")
    parser.add_argument("--mutation", choices=("none", "extra-relay", "extra-artifact", "skip-diagnosis"), default="none")
    args = parser.parse_args()
    BASH_EXE = args.bash
    rows = scenarios(args.mutation, args.output.parent / f"fixture-{args.mutation}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"schema_version": 2, "scenarios": rows}, indent=2) + "\n", encoding="utf-8")
    print(args.output)
    return 0 if valid(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
