#!/usr/bin/env bash

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PYTHON_BIN="${PYTHON:-python3}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
RECORD="$TMP_DIR/lane-workflow-record.json"
BASH_EXE="$(cygpath -w "$(command -v bash)")"

if ! "$PYTHON_BIN" "$ROOT/hooks/tests/lane-workflow-fixture.py" --bash "$BASH_EXE" --output "$RECORD" >/dev/null; then
  echo "FAIL: lane-workflow fixture-runner"
  echo "[test-lane-workflow] 0/1 PASS"
  exit 1
fi
echo "PASS: lane-workflow fixture-runner"

"$PYTHON_BIN" - "$RECORD" <<'PY'
import json
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
scenarios = {item["scenario_id"]: item for item in record["scenarios"]}
failures = []

ordinary = scenarios["ordinary-diagnosed-fix"]
if not (
    ordinary["diagnosis"] == {
        "performed": True,
        "read_only": True,
        "bounded": True,
        "evidence_paths": ["src/widgets.py"],
    }
    and ordinary["router_result"]["mechanical_result"] == "NO_MECHANICAL_MATCH"
    and ordinary["assessor_declarations"] == []
    and ordinary["final_lane"] == "lightweight"
    and ordinary["product_decisions"] == 1
    and ordinary["relays"] == 0
    and ordinary["agent_passes"] == 1
    and ordinary["created_artifacts"] == ["change-note"]
):
    failures.append("ordinary diagnosis did not persist the one-pass Lightweight inventory")
else:
    print("PASS: lane-workflow ordinary-diagnosis-to-lightweight")

trigger_ids = {
    "auth",
    "permissions",
    "secrets",
    "data-schema",
    "public-contract",
    "production-release",
    "protected-path",
    "cross-cutting-architecture",
    "unresolved-product-decision",
}

mechanical = scenarios["mechanical-protected-path"]
if (
    mechanical["router_result"]["mechanical_result"] == "FULL_REQUIRED"
    and mechanical["router_result"]["matches"][0]["trigger_id"] == "AUTH_SECRET_POLICY"
    and mechanical["assessor_declarations"] == []
    and mechanical["final_lane"] == "full"
    and mechanical["created_artifacts"]
    == ["spec.md", "decisions.md", "tasks.md", "verification-gate.md", "implement-handoff.md"]
):
    print("PASS: lane-workflow mechanical-match-routes-full")
else:
    failures.append("mechanical match did not persist the Full inventory")

observed = set()
for trigger_id in trigger_ids:
    scenario = scenarios[f"semantic-{trigger_id}"]
    observed.add(scenario["assessor_declarations"][0]["trigger_id"])
    if not (
        scenario["router_result"]["mechanical_result"] == "NO_MECHANICAL_MATCH"
        and scenario["final_lane"] == "full"
        and scenario["product_decisions"] == 1
        and scenario["relays"] == 1
        and scenario["agent_passes"] == 2
        and scenario["created_artifacts"]
        == ["spec.md", "decisions.md", "tasks.md", "verification-gate.md", "implement-handoff.md"]
    ):
        failures.append(f"semantic trigger {trigger_id} did not persist the Full inventory")
if observed == trigger_ids:
    print("PASS: lane-workflow every-semantic-trigger-routes-full")
else:
    failures.append("semantic trigger inventory is incomplete")

if all(
    scenarios[f"semantic-{trigger_id}"]["diagnosis"]["evidence_paths"]
    == ["src/ordinary_logic.py"]
    for trigger_id in ("auth", "public-contract")
):
    print("PASS: lane-workflow ordinary-filenames-cannot-hide-sensitive-logic")
else:
    failures.append("auth or public-contract scenario did not use an ordinary filename")

unresolved = scenarios["unresolved-assessment"]
if (
    unresolved["final_lane"] is None
    and unresolved["assessment_result"]["status"] == "blocked"
    and unresolved["assessment_result"]["blocked_at"] == "BLOCKED-AT-lane-assessment"
    and unresolved["created_artifacts"] == []
):
    print("PASS: lane-workflow unresolved-assessment-never-infers-safe")
else:
    failures.append("unresolved assessment did not block without artifacts")

if failures:
    for failure in failures:
        print(f"FAIL: lane-workflow {failure}")
    raise SystemExit(1)

print("PASS: lane-workflow persisted-decision-relay-artifact-inventory")
PY
fixture_rc=$?

carriers=(
  FLOW_RULES.md
  templates/change-note.md
  flow-skills/lightweight-lane/SKILL.md
  flow-skills/documentation-budget/SKILL.md
  flow-skills/requirements-specification/SKILL.md
  workflows/eight-phase-flow.md
  workflows/lightweight-lane.md
  agents/ai-developer/AGENT.md
  agents/product-owner/AGENT.md
  flow-skills/role-discipline/references/ai-developer.md
  flow-skills/role-discipline/references/product-owner.md
)
carrier_rc=0
required=(
  "FLOW_RULES.md|BLOCKED-AT-lane-assessment"
  "templates/change-note.md|Semantic:"
  "flow-skills/lightweight-lane/SKILL.md|NO_MECHANICAL_MATCH"
  "flow-skills/documentation-budget/SKILL.md|bounded read-only diagnosis"
  "flow-skills/requirements-specification/SKILL.md|hooks/local/lane-assessment.py"
  "workflows/eight-phase-flow.md|initially unknown cause"
  "workflows/lightweight-lane.md|semantic declarations"
  "agents/ai-developer/AGENT.md|objective trigger"
  "agents/product-owner/AGENT.md|path-router result"
  "flow-skills/role-discipline/references/ai-developer.md|File count"
  "flow-skills/role-discipline/references/product-owner.md|objective trigger"
)
for entry in "${required[@]}"; do
  path="${entry%%|*}"
  needle="${entry#*|}"
  if ! grep -Fq "$needle" "$ROOT/$path"; then
    echo "FAIL: lane-workflow carrier-missing $path: $needle"
    carrier_rc=1
  fi
done
if [ "$carrier_rc" -eq 0 ]; then
  echo "PASS: lane-workflow required-carriers-aligned"
fi

if rg -n "In doubt|root cause understood|root cause known|unknown-cause|unknown root cause|couple files|>2 files|deeper bug|turns non-trivial|if it grows|grows mid-flight" "${carriers[@]/#/$ROOT/}"; then
  echo "FAIL: lane-workflow stale-lane-carrier"
  carrier_rc=1
else
  echo "PASS: lane-workflow stale-lane-carriers-absent"
fi

if [ "$fixture_rc" -eq 0 ] && [ "$carrier_rc" -eq 0 ]; then
  echo "[test-lane-workflow] 9/9 PASS"
  exit 0
fi
exit 1
