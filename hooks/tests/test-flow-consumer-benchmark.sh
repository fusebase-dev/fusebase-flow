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
if validation.get("validator_runs", {}).get("value") != 2:
    failures.append("validator run count is not 2")
if validation.get("validator_runner_rc", {}).get("value") != 0:
    failures.append("validator runner did not complete successfully")
if validation.get("receipt_verify_rc", {}).get("value") != 3:
    failures.append("disabled receipt verifier did not return the exact refusal code")
if validation.get("receipt_path_resolved", {}).get("value") is not True:
    failures.append("receipt path query failed or returned an empty path")
if validation.get("receipt_present", {}).get("value") is not False:
    failures.append("disabled reuse unexpectedly minted a receipt")
reuse = validation.get("exact_state_reuse", {})
if reuse.get("status") != "UNAVAILABLE" or "verifier refused" not in reuse.get("reason", ""):
    failures.append("disabled exact-state reuse label is missing")
if validation.get("error") is not None:
    failures.append("validation measurement reported an unexpected error")
if validation.get("validator_duration", {}).get("status") != "MEASURED":
    failures.append("validator duration missing")
recovery = doc.get("recovery", {})
if recovery.get("result") != "PASS" or recovery.get("mode") != "read-only integrity":
    failures.append("mirror check is not labeled read-only integrity")
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
print("PASS: consumer-benchmark mirror-check-read-only-integrity")
print("PASS: consumer-benchmark skipped-cli-is-unverified")
print("[test-flow-consumer-benchmark] 5/5 PASS")
PY
