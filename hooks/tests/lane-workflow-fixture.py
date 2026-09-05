#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROUTER = ROOT / "hooks" / "local" / "lane-router.sh"
ASSESSOR = ROOT / "hooks" / "local" / "lane-assessment.py"
BASH_EXE = "bash"
FULL_ARTIFACTS = [
    "spec.md",
    "decisions.md",
    "tasks.md",
    "verification-gate.md",
    "implement-handoff.md",
]


def run_scenario(
    scenario_id: str,
    paths: list[str],
    complete: bool,
    triggers: list[dict[str, str]],
) -> dict[str, object]:
    routed = subprocess.run(
        [BASH_EXE, str(ROUTER), "--json", *paths],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if routed.returncode not in {0, 10}:
        raise RuntimeError(f"router failed for {scenario_id}: {routed.stderr}")
    router_result = json.loads(routed.stdout)
    request = {
        "router": router_result,
        "assessment": {"complete": complete, "triggers": triggers},
    }
    assessed = subprocess.run(
        [sys.executable, str(ASSESSOR)],
        cwd=ROOT,
        input=json.dumps(request),
        text=True,
        capture_output=True,
        check=False,
    )
    expected_rc = 20 if not complete else 10 if triggers or routed.returncode == 10 else 0
    if assessed.returncode != expected_rc:
        raise RuntimeError(
            f"assessor failed for {scenario_id}: expected {expected_rc}, got {assessed.returncode}: {assessed.stdout}{assessed.stderr}"
        )
    assessment_result = json.loads(assessed.stdout)
    final_lane = assessment_result.get("final_lane")
    if final_lane == "lightweight":
        product_decisions = 1
        relays = 0
        agent_passes = 1
        artifacts = ["change-note"]
    elif final_lane == "full":
        product_decisions = 1
        relays = 1
        agent_passes = 2
        artifacts = FULL_ARTIFACTS
    else:
        product_decisions = 0
        relays = 0
        agent_passes = 0
        artifacts = []
    return {
        "scenario_id": scenario_id,
        "diagnosis": {
            "performed": True,
            "read_only": True,
            "bounded": True,
            "evidence_paths": paths,
        },
        "router_result": router_result,
        "assessor_declarations": triggers,
        "assessment_result": assessment_result,
        "final_lane": final_lane,
        "product_decisions": product_decisions,
        "relays": relays,
        "agent_passes": agent_passes,
        "created_artifacts": artifacts,
    }


def main() -> int:
    global BASH_EXE
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--bash", default="bash")
    args = parser.parse_args()
    BASH_EXE = args.bash

    scenarios = [
        run_scenario("ordinary-diagnosed-fix", ["src/widgets.py"], True, []),
        run_scenario(
            "mechanical-protected-path",
            ["policies/command-policy.yml"],
            True,
            [],
        ),
    ]
    for trigger_id in [
        "auth",
        "permissions",
        "secrets",
        "data-schema",
        "public-contract",
        "production-release",
        "protected-path",
        "cross-cutting-architecture",
        "unresolved-product-decision",
    ]:
        scenarios.append(
            run_scenario(
                f"semantic-{trigger_id}",
                ["src/ordinary_logic.py"],
                True,
                [
                    {
                        "trigger_id": trigger_id,
                        "evidence_path": "src/ordinary_logic.py:12",
                        "reason": f"diagnosed behavior activates {trigger_id}",
                    }
                ],
            )
        )
    scenarios.append(run_scenario("unresolved-assessment", ["src/unknown.py"], False, []))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps({"schema_version": 1, "scenarios": scenarios}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
