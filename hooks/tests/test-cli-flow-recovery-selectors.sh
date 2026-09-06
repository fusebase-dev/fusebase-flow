#!/usr/bin/env bash
# Fusebase Flow — bounded public selector contract for test-cli-flow-recovery.sh.
# TRIPWIRE: scoped diagnostics must never emit the registered phase's ^PASS: shape; otherwise a
# partial group can be misread as complete recovery evidence by run-tests.sh.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WRAPPER="$ROOT/hooks/tests/test-cli-flow-recovery.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
ok() { passed=$((passed + 1)); echo "PASS: cli-flow-recovery-selectors $1"; }
bad() { failed=$((failed + 1)); echo "FAIL: cli-flow-recovery-selectors $1 (${2:-})"; }
finish() { echo "[test-cli-flow-recovery-selectors] $passed/$((passed + failed)) PASS"; exit "$failed"; }

run_case() {
  local name="$1"; shift
  "$@" > "$WORK/$name.out" 2> "$WORK/$name.err"
  CASE_RC=$?
}

expected_groups=$'u14\nlegacy\nengine\nt1\nt14\nt15\nt20'
run_case list env TMPDIR="$WORK" bash "$WRAPPER" --list
if [ "$CASE_RC" -eq 0 ] && [ "$(<"$WORK/list.out")" = "$expected_groups" ]; then
  ok "list-and-default-group-parity"
else
  bad "list-and-default-group-parity" "rc=$CASE_RC output=[$(<"$WORK/list.out")]"
fi

parse_ok=1
run_case unknown env TMPDIR="$WORK" bash "$WRAPPER" --only unknown; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case missing env TMPDIR="$WORK" bash "$WRAPPER" --only; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case empty env TMPDIR="$WORK" bash "$WRAPPER" --only ""; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case conflict env TMPDIR="$WORK" FFCF_T1_ONLY=1 bash "$WRAPPER" --only u14; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case legacy_conflict env TMPDIR="$WORK" FFCF_T1_ONLY=1 FFCF_T14_ONLY=1 bash "$WRAPPER"; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case list_conflict env TMPDIR="$WORK" FFCF_T1_ONLY=1 bash "$WRAPPER" --list; [ "$CASE_RC" -eq 2 ] || parse_ok=0
if [ "$parse_ok" -eq 1 ] && ! find "$WORK" -maxdepth 1 -type d -name 'fusebase-flow-cli-sim.*' | grep -q .; then
  ok "invalid-selection-exit-2-before-fixture-mutation"
else
  bad "invalid-selection-exit-2-before-fixture-mutation" "one parser case returned the wrong rc or created a fixture"
fi

run_case selected env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 bash "$WRAPPER" --only u14
if [ "$CASE_RC" -eq 0 ] \
  && grep -q '^SCOPED PASS: cli-flow-recovery U14:' "$WORK/selected.out" \
  && ! grep -q 'U7:' "$WORK/selected.out"; then
  ok "selected-u14-runs-real-group-only"
else
  bad "selected-u14-runs-real-group-only" "rc=$CASE_RC"
fi
if ! grep -q '^PASS: cli-flow-recovery ' "$WORK/selected.out" \
  && grep -q '^SCOPED: cli-flow-recovery group=u14; not full-suite evidence$' "$WORK/selected.out"; then
  ok "scoped-output-cannot-attest-full-pass"
else
  bad "scoped-output-cannot-attest-full-pass" "registered PASS shape leaked or scope banner missing"
fi
if grep -qE '^\[cli-flow-recovery\] SCOPED group=u14 START elapsed=0s timeout=180s$' "$WORK/selected.err" \
  && grep -qE '^\[cli-flow-recovery\] SCOPED group=u14 END elapsed=[0-9]+s rc=0$' "$WORK/selected.err"; then
  ok "selected-group-start-end-observable"
else
  bad "selected-group-start-end-observable" "START/END identity missing"
fi

run_case legacy_env env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 FFCF_T1_ONLY=1 bash "$WRAPPER"
if [ "$CASE_RC" -eq 0 ] && grep -q '^SCOPED: cli-flow-recovery group=t1;' "$WORK/legacy_env.out" \
  && grep -q '^SCOPED PASS: cli-flow-recovery T17:' "$WORK/legacy_env.out" \
  && ! grep -q 'U14:' "$WORK/legacy_env.out"; then
  ok "legacy-environment-selector-compatible"
else
  bad "legacy-environment-selector-compatible" "rc=$CASE_RC or wrong dispatch"
fi

run_case failure env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 PYTHON=false bash "$WRAPPER" --only u14
failure_log="$(sed -n 's/^\[cli-flow-recovery\] SCOPED diagnostic=//p' "$WORK/failure.err" | tail -n 1)"
if [ "$CASE_RC" -eq 1 ] && [ -n "$failure_log" ] && [ -f "$failure_log" ] \
  && grep -q '^group=u14 rc=1 ' "$failure_log"; then
  ok "selected-failure-propagates-and-retains-log"
else
  bad "selected-failure-propagates-and-retains-log" "rc=$CASE_RC log=[$failure_log]"
fi

run_case timeout env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=1 bash "$WRAPPER" --only u14
timeout_log="$(sed -n 's/^\[cli-flow-recovery\] SCOPED diagnostic=//p' "$WORK/timeout.err" | tail -n 1)"
if { [ "$CASE_RC" -eq 124 ] || [ "$CASE_RC" -eq 137 ]; } \
  && [ -n "$timeout_log" ] && [ -f "$timeout_log" ] \
  && grep -q "^group=u14 rc=$CASE_RC " "$timeout_log"; then
  ok "selected-timeout-propagates-and-retains-log"
else
  bad "selected-timeout-propagates-and-retains-log" "rc=$CASE_RC log=[$timeout_log]"
fi

if ! find "$WORK" -maxdepth 1 -type d -name 'fusebase-flow-cli-sim.*' | grep -q .; then
  ok "selected-fixtures-cleaned-after-success-failure-timeout"
else
  bad "selected-fixtures-cleaned-after-success-failure-timeout" "fixture directory remains under $WORK"
fi

finish
