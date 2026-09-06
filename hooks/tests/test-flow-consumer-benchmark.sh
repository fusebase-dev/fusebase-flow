#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t flow-consumer-benchmark)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/report.json"

if ! python3 "$ROOT/hooks/tests/benchmark-flow-consumers.py" --output "$OUT" --cli-refresh skip >/dev/null; then
    echo "FAIL: consumer-benchmark runner"
    echo "[test-flow-consumer-benchmark] 0/1 PASS"
    exit 1
fi

python3 - "$OUT" <<'PY'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))
failures = []
if doc.get("hard_performance_gate") is not False:
    failures.append("hard performance gate enabled")
workflow = {row["scenario"]: row for row in doc.get("workflow", [])}
for scenario, lane in (("ordinary-diagnosed-fix", "lightweight"), ("sensitive-auth-change", "full")):
    row = workflow.get(scenario, {})
    if row.get("lane") != lane or row.get("wall_time", {}).get("status") != "MEASURED":
        failures.append(f"{scenario} lane/wall measurement missing")
    for metric in ("actual_tokens", "tool_calls"):
        value = row.get(metric, {})
        if value.get("status") != "UNAVAILABLE" or not value.get("reason"):
            failures.append(f"{scenario} {metric} missing-metric label absent")
    for metric in ("operator_decisions", "role_relays", "artifacts"):
        if row.get(metric, {}).get("status") != "MEASURED":
            failures.append(f"{scenario} {metric} not measured")
    if row.get("evidence_boundary") != "scripted fixture simulation":
        failures.append(f"{scenario} scripted boundary is not labeled")
validation = doc.get("validation", {})
if sys.platform == "win32":
    if validation.get("validator_runs", {}).get("value") != 0:
        failures.append("Windows fail-closed validator run count is not zero")
    reuse = validation.get("exact_state_reuse", {})
    if reuse.get("status") != "UNAVAILABLE" or "must rerun" not in reuse.get("reason", ""):
        failures.append("Windows authority-unavailable rerun label is missing")
else:
    if validation.get("validator_runs", {}).get("value") != 2:
        failures.append("validator run count is not 2")
    if validation.get("exact_state_reuse", {}).get("value") is not True:
        failures.append("exact-state validation evidence did not verify")
if validation.get("validator_duration", {}).get("status") != "MEASURED":
    failures.append("validator duration missing")
recovery = doc.get("recovery", {})
if recovery.get("result") != "PASS" or recovery.get("no_op_writes", {}).get("value") != 0:
    failures.append("recovery no-op writes not measured at zero")
refresh = doc.get("current_cli_refresh", {})
if refresh.get("result") != "UNVERIFIED" or not refresh.get("reason"):
    failures.append("skipped current-CLI attempt lacks explicit UNVERIFIED reason")
if failures:
    for failure in failures:
        print(f"FAIL: consumer-benchmark {failure}")
    raise SystemExit(1)
print("PASS: consumer-benchmark metrics-and-missing-labels")
print("PASS: consumer-benchmark workflow-ordinary-sensitive")
print("PASS: consumer-benchmark validation-runs-duration")
print("PASS: consumer-benchmark recovery-no-op-writes")
print("PASS: consumer-benchmark skipped-cli-is-unverified")
print("[test-flow-consumer-benchmark] 5/5 PASS")
PY
