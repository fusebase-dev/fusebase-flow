#!/usr/bin/env bash
# Fusebase Flow — hook test runner
# Pipes each fixture into its target handler and checks the response.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TESTS_DIR="$ROOT/hooks/tests/fixtures"
HANDLERS_DIR="$ROOT/hooks/handlers"
RESULTS_FILE="$ROOT/state/audit/hook-test-results.md"

python_bin="${PYTHON:-python3}"

if ! command -v "$python_bin" >/dev/null 2>&1; then
    echo "[run-tests] $python_bin not found; install Python 3.10+." >&2
    exit 1
fi

pass=0
fail=0
total=0
report_rows=""

mkdir -p "$(dirname "$RESULTS_FILE")"

for fixture in "$TESTS_DIR"/*.json; do
    [ -f "$fixture" ] || continue
    total=$((total + 1))
    name="$(basename "$fixture")"

    # Extract metadata via python (simpler than jq for portability).
    meta="$("$python_bin" - "$fixture" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get("_test", ""))
print(data.get("_handler", ""))
print(data.get("_expected_decision", ""))
print(data.get("_expected_rule_id", ""))
print(data.get("_expected_rule_id_contains", ""))
PY
)"
    test_name="$(echo "$meta" | sed -n '1p')"
    handler="$(echo "$meta" | sed -n '2p')"
    expected_decision="$(echo "$meta" | sed -n '3p')"
    expected_rule_id="$(echo "$meta" | sed -n '4p')"
    expected_rule_contains="$(echo "$meta" | sed -n '5p')"

    if [ -z "$handler" ]; then
        echo "[run-tests] $name SKIP — no _handler set"
        continue
    fi

    # Run handler with the fixture as stdin; capture stdout + exit code.
    output="$("$python_bin" "$HANDLERS_DIR/$handler" < "$fixture" 2>/dev/null)"
    exit_code=$?

    # Parse decision and rule_id from JSON stdout.
    actual="$("$python_bin" - <<PY
import json, sys
out = json.loads('''$output''') if '''$output'''.strip().startswith("{") else {}
print(out.get("decision", ""))
print(out.get("rule_id", "") or "")
PY
)"
    actual_decision="$(echo "$actual" | sed -n '1p')"
    actual_rule_id="$(echo "$actual" | sed -n '2p')"

    ok=1
    detail=""
    if [ -n "$expected_decision" ] && [ "$expected_decision" != "$actual_decision" ]; then
        ok=0
        detail="$detail expected=$expected_decision got=$actual_decision"
    fi
    if [ -n "$expected_rule_id" ] && [ "$expected_rule_id" != "$actual_rule_id" ]; then
        ok=0
        detail="$detail expected_rule=$expected_rule_id got=$actual_rule_id"
    fi
    if [ -n "$expected_rule_contains" ]; then
        if [[ "$actual_rule_id" != *"$expected_rule_contains"* ]]; then
            ok=0
            detail="$detail expected_rule_contains=$expected_rule_contains got=$actual_rule_id"
        fi
    fi

    if [ $ok -eq 1 ]; then
        pass=$((pass + 1))
        echo "PASS: $name  ($test_name) -> decision=$actual_decision"
        report_rows="$report_rows| $name | $test_name | PASS | decision=$actual_decision rule=$actual_rule_id |"$'\n'
    else
        fail=$((fail + 1))
        echo "FAIL: $name  ($test_name) ->$detail"
        report_rows="$report_rows| $name | $test_name | FAIL |$detail (raw=$output) |"$'\n'
    fi
done

# Write report
{
    echo "# Hook test results"
    echo
    echo "Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Total: $total — PASS: $pass — FAIL: $fail"
    echo
    echo "| Fixture | Test | Result | Detail |"
    echo "|---|---|---|---|"
    echo -n "$report_rows"
} > "$RESULTS_FILE"

echo
echo "[run-tests] $pass/$total PASS"
echo "[run-tests] report written: $RESULTS_FILE"

exit $fail
