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

# Bounded-run engine (WS2-core strict-scoped reap): each heavy phase runs under
# ffhc_run_bounded (tempfile capture + the recorded-child taskkill), so an MSYS
# native grandchild can't hold a $(...) pipe open past the deadline and freeze the
# harness. Reads FFHC_LAST_OUT / FFHC_LAST_RC after each call.
. "$ROOT/hooks/local/lib/run-with-timeout.sh"
ffhc_detect_timeout

# Per-phase heavy-run bound. Generous default (the recovery phase copies a skill tree
# + drives the health engine — minutes on MSYS); operator-overridable.
FF_PHASE_TIMEOUT="${FF_PHASE_TIMEOUT:-600}"

# EXIT-trap reaper (WS3): if the harness is signaled while a bounded phase is still in
# flight, taskkill ONLY that phase's own recorded child winpid — FFHC_LAST_WINPID, set
# live at launch by the T1 capture — strict-scoped, never a broad taskkill (depends on
# WS2-core). run_bounded_phase CLEARS FFHC_LAST_WINPID the instant a phase returns (its
# child is already reaped by then), so a normal exit reaps nothing and a stale/reused
# winpid is never swept. The reap is a no-op off-MSYS.
FFHC_LAST_WINPID=""
_ff_exit_reap() {
    ffhc_is_msys || return 0
    [ -n "$FFHC_LAST_WINPID" ] && ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID"
}
trap _ff_exit_reap EXIT

# progress <phase>: flush a starting marker to stderr BEFORE the (possibly multi-min)
# phase runs, so a slow phase is visibly progressing, never mistakable for a freeze.
progress() { printf '[run-tests] starting %s\n' "$1" >&2; }

# run_bounded_phase <label> CMD...: flush progress, run CMD under ffhc_run_bounded
# (tempfile capture + T1 strict-scoped reap; FFHC_LAST_WINPID tracks the in-flight
# child for the EXIT-trap), exposing FFHC_LAST_OUT / FFHC_LAST_RC to the caller. Clears
# FFHC_LAST_WINPID on return so the EXIT-trap never reaps a completed phase's dead winpid.
run_bounded_phase() {
    local label="$1"; shift
    progress "$label"
    ffhc_run_bounded "$FF_PHASE_TIMEOUT" "$@"
    FFHC_LAST_WINPID=""   # phase returned => child reaped; no stale sweep on exit
}

pass=0
fail=0
total=0
report_rows=""

mkdir -p "$(dirname "$RESULTS_FILE")"

progress "fixture handler tests"
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

    # Run handler with the fixture as stdin; capture stdout + exit code. Bounded via
    # ffhc_run_bounded_stdout (tempfile capture + T1 strict-scoped reap; stderr dropped
    # to preserve the ORIGINAL 2>/dev/null stdout-only capture the JSON parse relies on)
    # so a hung handler (or an MSYS native grandchild holding a $(...) pipe) can't freeze
    # the loop past the deadline. FFHC_LAST_OUT holds stdout only; the '{' parse below
    # is unchanged.
    ffhc_run_bounded_stdout "$FF_PHASE_TIMEOUT" "$python_bin" "$HANDLERS_DIR/$handler" < "$fixture"
    output="$FFHC_LAST_OUT"
    exit_code=$FFHC_LAST_RC

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
FFHC_LAST_WINPID=""   # fixture loop done — clear the last handler's winpid before the trap window

# Phase 2 — FR-25 module-size ratchet scenarios (shell-level; not handler fixtures).
MS_TEST="$ROOT/hooks/tests/test-module-size.sh"
if [ -f "$MS_TEST" ]; then
    run_bounded_phase "module-size ratchet" bash "$MS_TEST"
    ms_out="$FFHC_LAST_OUT"; ms_fail=$FFHC_LAST_RC
    echo "$ms_out" | grep -E '^(PASS|FAIL): module-size' || true
    ms_pass="$(echo "$ms_out" | grep -c '^PASS: module-size')"
    ms_failed="$(echo "$ms_out" | grep -c '^FAIL: module-size')"
    total=$((total + ms_pass + ms_failed))
    pass=$((pass + ms_pass))
    fail=$((fail + ms_failed))
    while IFS= read -r line; do
        name="${line#*: module-size }"
        result="${line%%:*}"
        report_rows="$report_rows| test-module-size.sh | $name | $result | exit-code scenario |"$'\n'
    done < <(echo "$ms_out" | grep -E '^(PASS|FAIL): module-size')
    # Crash guard: a non-zero exit with zero parsed FAIL lines means the scenario
    # script died before running (mktemp/cp/syntax) — count it, don't go green.
    if [ "$ms_fail" -ne 0 ] && [ "$ms_failed" -eq 0 ]; then
        total=$((total + 1))
        fail=$((fail + 1))
        echo "FAIL: test-module-size.sh crashed (exit $ms_fail) before reporting scenarios"
        report_rows="$report_rows| test-module-size.sh | (harness) | FAIL | crashed with exit $ms_fail, no scenario output |"$'\n'
    fi
fi

# Phase 3 — health-check bounded-execution + verdict/exit contract scenarios
# (shell-level; spec docs/specs/health-check-fast-timeout). Same parse contract
# as Phase 2: count "PASS:/FAIL: health-check-timeout <name>" lines; a non-zero
# exit with zero parsed FAIL lines means the script crashed before reporting.
HT_TEST="$ROOT/hooks/tests/test-health-check-timeout.sh"
if [ -f "$HT_TEST" ]; then
    run_bounded_phase "health-check-timeout scenarios" bash "$HT_TEST"
    ht_out="$FFHC_LAST_OUT"; ht_rc=$FFHC_LAST_RC
    echo "$ht_out" | grep -E '^(PASS|FAIL): health-check-timeout' || true
    ht_pass="$(echo "$ht_out" | grep -c '^PASS: health-check-timeout')"
    ht_failed="$(echo "$ht_out" | grep -c '^FAIL: health-check-timeout')"
    total=$((total + ht_pass + ht_failed))
    pass=$((pass + ht_pass))
    fail=$((fail + ht_failed))
    while IFS= read -r line; do
        name="${line#*: health-check-timeout }"
        result="${line%%:*}"
        report_rows="$report_rows| test-health-check-timeout.sh | $name | $result | timeout/verdict scenario |"$'\n'
    done < <(echo "$ht_out" | grep -E '^(PASS|FAIL): health-check-timeout')
    if [ "$ht_rc" -ne 0 ] && [ "$ht_failed" -eq 0 ]; then
        total=$((total + 1))
        fail=$((fail + 1))
        echo "FAIL: test-health-check-timeout.sh crashed (exit $ht_rc) before reporting scenarios"
        report_rows="$report_rows| test-health-check-timeout.sh | (harness) | FAIL | crashed with exit $ht_rc, no scenario output |"$'\n'
    fi
fi

# Phases 4-7 — upgrade-tooling-hardening shell scenarios (v3.24.x). Same parse
# contract as Phase 2/3: count "PASS:/FAIL: <tag> <name>" lines; a non-zero exit
# with zero parsed FAIL lines means the script crashed before reporting. One loop
# over (script, tag) pairs keeps run-tests under the FR-25 ceiling.
run_shell_phase() { # run_shell_phase <test-script> <tag>
    local script="$ROOT/hooks/tests/$1" tag="$2"
    [ -f "$script" ] || return 0
    local out rc p f
    run_bounded_phase "$tag" bash "$script"
    out="$FFHC_LAST_OUT"; rc=$FFHC_LAST_RC
    echo "$out" | grep -E "^(PASS|FAIL): $tag " || true
    p="$(echo "$out" | grep -c "^PASS: $tag ")"
    f="$(echo "$out" | grep -c "^FAIL: $tag ")"
    total=$((total + p + f)); pass=$((pass + p)); fail=$((fail + f))
    while IFS= read -r line; do
        name="${line#*: $tag }"; result="${line%%:*}"
        report_rows="$report_rows| $1 | $name | $result | shell scenario |"$'\n'
    done < <(echo "$out" | grep -E "^(PASS|FAIL): $tag ")
    if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then
        total=$((total + 1)); fail=$((fail + 1))
        echo "FAIL: $1 crashed (exit $rc) before reporting scenarios"
        report_rows="$report_rows| $1 | (harness) | FAIL | crashed with exit $rc, no scenario output |"$'\n'
    fi
}
run_shell_phase test-newline-preserve.sh     "newline-preserve"
run_shell_phase test-baseline-merge.sh       "baseline-merge"
run_shell_phase test-sync-allowlist.sh       "sync-allowlist"
run_shell_phase test-policy-state-preserve.sh "policy-state"
run_shell_phase test-bootstrap-baseline-hop.sh "bootstrap-baseline-hop"
run_shell_phase test-fr22-delivery-guarantee.sh "fr22-delivery"
run_shell_phase test-po-verifiable-boot.sh     "po-verifiable-boot"
run_shell_phase test-liveness-bounded-run.sh   "liveness"
run_shell_phase test-codex-prompt-parity.sh    "codex-parity"
run_shell_phase test-cli-0259-compat.sh        "cli-0259"
run_shell_phase test-secret-scan-staged.sh     "secret-scan-staged"
run_shell_phase test-msys-tree-cleanup.sh      "msys-tree-cleanup"

# Exit-code phase — all-or-nothing shell tests that fail-fast (set -e + fail()→exit)
# and don't emit the run_shell_phase "PASS: <tag> <name>" contract. One row per test;
# PASS iff exit 0. test-cli-flow-recovery.sh is heavy (copies the skill tree + drives
# the health engine — minutes) and was UNBOUNDED, so it hung the whole harness on
# MSYS (the universal run-tests-never-completes defect). Now bounded via
# ffhc_run_bounded_stdout at FF_CLI_RECOVERY_TIMEOUT (default 240s) with an
# FF_SKIP_CLI_RECOVERY=1 opt-out; a timeout (rc 124/137) is reported INCONCLUSIVE —
# counted as a non-pass so the suite never goes silently green on a bound-hit.
run_exitcode_phase() { # run_exitcode_phase <test-script> <label>
    local script="$ROOT/hooks/tests/$1" label="$2"
    [ -f "$script" ] || return 0
    total=$((total + 1))
    if [ "${FF_SKIP_CLI_RECOVERY:-0}" = "1" ]; then
        # Operator opt-out of the heavy phase. Not a pass (keeps the count honest) —
        # a visible INCONCLUSIVE row, never a silent green.
        fail=$((fail + 1)); echo "INCONCLUSIVE: $label (skipped via FF_SKIP_CLI_RECOVERY=1)"
        report_rows="$report_rows| $1 | $label | INCONCLUSIVE | skipped (FF_SKIP_CLI_RECOVERY=1) |"$'\n'
        return 0
    fi
    progress "$label"
    ffhc_run_bounded_stdout "${FF_CLI_RECOVERY_TIMEOUT:-240}" bash "$script"
    local rc=$FFHC_LAST_RC
    FFHC_LAST_WINPID=""   # phase returned => child reaped; no stale sweep on exit
    if [ "$rc" -eq 0 ]; then
        pass=$((pass + 1)); echo "PASS: $label (exit 0)"
        report_rows="$report_rows| $1 | $label | PASS | exit 0 |"$'\n'
    elif ffhc_timed_out "$rc"; then
        # Bound-hit on a loaded/slow host: INCONCLUSIVE, not FAIL and NOT silent-green.
        fail=$((fail + 1)); echo "INCONCLUSIVE: $label (bounded timeout rc $rc at ${FF_CLI_RECOVERY_TIMEOUT:-240}s — re-run on a quiet host or FF_SKIP_CLI_RECOVERY=1)"
        report_rows="$report_rows| $1 | $label | INCONCLUSIVE | bounded timeout rc $rc |"$'\n'
    else
        fail=$((fail + 1)); echo "FAIL: $label (exit $rc)"
        report_rows="$report_rows| $1 | $label | FAIL | exit $rc |"$'\n'
    fi
}
run_exitcode_phase test-cli-flow-recovery.sh "cli-flow-recovery (0.25.9 model)"

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
