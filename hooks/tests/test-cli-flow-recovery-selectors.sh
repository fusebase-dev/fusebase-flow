#!/usr/bin/env bash
# Fusebase Flow — bounded public selector contract for test-cli-flow-recovery.sh.
# TRIPWIRE: scoped diagnostics must never emit the registered phase's ^PASS: shape; otherwise a
# partial group can be misread as complete recovery evidence by run-tests.sh.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WRAPPER="$ROOT/hooks/tests/test-cli-flow-recovery.sh"
SELECTED=""
case "$#" in
  0) ;;
  2)
    if [ "$1" = "--only" ] && [ "$2" = "t34" ]; then
      SELECTED="t34"
    else
      echo "[test-cli-flow-recovery-selectors] usage: $0 [--only t34]" >&2
      exit 2
    fi
    ;;
  *) echo "[test-cli-flow-recovery-selectors] usage: $0 [--only t34]" >&2; exit 2 ;;
esac
WORK="$(mktemp -d)"
# EVIDENCE LIVES OUTSIDE THE CLEANUP (the t15/t20 lesson, finally applied to the wrapper's own
# case output). Every case used to write into $WORK, which `trap rm -rf $WORK EXIT` deletes - so
# when the 1800s phase wall killed this phase in the v4.17.0 release run, every diagnostic it had
# produced was destroyed on the way out and the hang was undiagnosable from the job log. $EVID is
# removed ONLY on a clean finish; a failure or a kill leaves it, and each failing case also DUMPS
# an excerpt to stdout, because on a hosted runner the job log is the only durable artifact.
EVID="${TMPDIR:-/tmp}/fusebase-flow-selectors-evidence-$$"
mkdir -p "$EVID"
trap 'rm -rf "$WORK"' EXIT
echo "[test-cli-flow-recovery-selectors] case evidence: $EVID (retained unless every row passes)"

# TRIPWIRE: TMPDIR stays $WORK on purpose - the fixture-cleanup row asserts on that directory,
# and the wrapper's own `SCOPED diagnostic=` files live there. Those still vanish with $WORK, but
# their PATHS are printed into the retained .err, so a reader still learns what existed.

passed=0
failed=0
ok() { passed=$((passed + 1)); echo "PASS: cli-flow-recovery-selectors $1"; }
bad() { failed=$((failed + 1)); echo "FAIL: cli-flow-recovery-selectors $1 (${2:-})"; }
finish() {
  [ "$failed" -eq 0 ] && rm -rf "$EVID"
  echo "[test-cli-flow-recovery-selectors] $passed/$((passed + failed)) PASS"
  exit "$failed"
}

# Make a failing case legible in the job log itself, not just on the dead runner's disk.
evidence() {
  local n="$1"
  echo "---- evidence: case '$n' (retained at $EVID/$n.out, $EVID/$n.err) ----"
  tail -n 20 "$EVID/$n.out" 2>/dev/null | sed 's/^/    out| /'
  tail -n 20 "$EVID/$n.err" 2>/dev/null | sed 's/^/    err| /'
  echo "---- end evidence: case '$n' ----"
}

# FIX 2 - the operation is bounded by ITS OWNER. The wrapper's inner FFCF_SELECTOR_TIMEOUT_SECS
# goes through ffhc_msys_wait_reap, which POLLS for a `_done` sentinel and can outlive its own
# `secs` when that sentinel never arrives; in the v4.17.0 release run the 180s inner bound never
# fired and only the 1800s phase wall stopped it. This deadline is a plain `timeout` owned by
# THIS phase: it cannot be defeated by the sentinel, and it is deliberately LARGER than the inner
# bound so the rows that assert the inner contract still observe it.
. "$ROOT/hooks/local/lib/run-with-timeout.sh"
ffhc_detect_timeout                       # detection only - not the polled wait path
if [ -z "${FFHC_TIMEOUT_BIN:-}" ]; then
  echo "FAIL: cli-flow-recovery-selectors case-deadlines-available (no timeout binary; every case would run UNBOUNDED, which is this phase's own defect)"
  echo "[test-cli-flow-recovery-selectors] 0/1 PASS"
  exit 1
fi

CASE_EXPECT_DEADLINE=0        # set to 1 ONLY by the fault-injection row, reset by run_case
run_case() {
  local name="$1" secs="$2"; shift 2
  local expect="$CASE_EXPECT_DEADLINE"; CASE_EXPECT_DEADLINE=0
  echo "[test-cli-flow-recovery-selectors] case=$name deadline=${secs}s"
  local started; started="$(date +%s)"
  "$FFHC_TIMEOUT_BIN" -k 10 "$secs" "$@" > "$EVID/$name.out" 2> "$EVID/$name.err"
  CASE_RC=$?
  CASE_ELAPSED=$(( $(date +%s) - started ))
  # TRIPWIRE: OUR deadline is a DISTINCT outcome - never a pass, never an ordinary nonzero. The
  # inner bound also reports 124, so elapsed is what separates them: an inner timeout returns
  # long before the case deadline, ours only at it.
  CASE_DEADLINE_HIT=0
  if { [ "$CASE_RC" -eq 124 ] || [ "$CASE_RC" -eq 137 ]; } && [ "$CASE_ELAPSED" -ge "$secs" ]; then
    CASE_DEADLINE_HIT=1
    if [ "$expect" -eq 1 ]; then
      # The injected stall. Its row scores the verdict; emitting the counted shape here would
      # redden the phase that is proving the bound works.
      echo "[test-cli-flow-recovery-selectors] injected CASE DEADLINE ${secs}s on '$name' (rc=$CASE_RC, elapsed=${CASE_ELAPSED}s)"
    else
      bad "case-$name-produced-a-verdict" \
          "CASE DEADLINE ${secs}s: '$name' produced no verdict at its own bound (rc=$CASE_RC, elapsed=${CASE_ELAPSED}s)"
    fi
    evidence "$name"
  fi
}

expected_groups=$'u14\nlegacy\nengine\nt1\nt14\nt15\nt20\nt34\neol'
run_case list 60 env TMPDIR="$WORK" bash "$WRAPPER" --list
if [ "$CASE_RC" -eq 0 ] && [ "$(<"$EVID/list.out")" = "$expected_groups" ]; then
  ok "list-and-default-group-parity"
else
  bad "list-and-default-group-parity" "rc=$CASE_RC output=[$(<"$EVID/list.out")]"
  evidence "list"
fi

parse_ok=1
run_case unknown 60 env TMPDIR="$WORK" bash "$WRAPPER" --only unknown; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case missing 60 env TMPDIR="$WORK" bash "$WRAPPER" --only; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case empty 60 env TMPDIR="$WORK" bash "$WRAPPER" --only ""; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case conflict 60 env TMPDIR="$WORK" FFCF_T1_ONLY=1 bash "$WRAPPER" --only u14; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case legacy_conflict 60 env TMPDIR="$WORK" FFCF_T1_ONLY=1 FFCF_T14_ONLY=1 bash "$WRAPPER"; [ "$CASE_RC" -eq 2 ] || parse_ok=0
run_case list_conflict 60 env TMPDIR="$WORK" FFCF_T1_ONLY=1 bash "$WRAPPER" --list; [ "$CASE_RC" -eq 2 ] || parse_ok=0
if [ "$parse_ok" -eq 1 ] && ! find "$WORK" -maxdepth 1 -type d -name 'fusebase-flow-cli-sim.*' | grep -q .; then
  ok "invalid-selection-exit-2-before-fixture-mutation"
else
  bad "invalid-selection-exit-2-before-fixture-mutation" "one parser case returned the wrong rc or created a fixture"
fi

run_case t34 300 env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 bash "$WRAPPER" --only t34
if [ "$CASE_RC" -eq 0 ] \
  && grep -q '^SCOPED PASS: cli-flow-recovery T34:' "$EVID/t34.out" \
  && ! grep -q 'U14:' "$EVID/t34.out"; then
  ok "selected-t34-runs-real-group-only"
else
  bad "selected-t34-runs-real-group-only" "rc=$CASE_RC"
  evidence "t34"
fi
if ! grep -q '^PASS: cli-flow-recovery ' "$EVID/t34.out" \
  && grep -q '^SCOPED: cli-flow-recovery group=t34; not full-suite evidence$' "$EVID/t34.out" \
  && grep -qE '^\[cli-flow-recovery\] SCOPED group=t34 START elapsed=0s timeout=180s$' "$EVID/t34.err" \
  && grep -qE '^\[cli-flow-recovery\] SCOPED group=t34 END elapsed=[0-9]+s rc=0$' "$EVID/t34.err"; then
  ok "selected-t34-scoped-and-observable"
else
  bad "selected-t34-scoped-and-observable" "registered PASS shape leaked or START/END identity missing"
  evidence "t34"
fi

[ "$SELECTED" = "t34" ] && finish

run_case selected 300 env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 bash "$WRAPPER" --only u14
if [ "$CASE_RC" -eq 0 ] \
  && grep -q '^SCOPED PASS: cli-flow-recovery U14:' "$EVID/selected.out" \
  && ! grep -q 'U7:' "$EVID/selected.out"; then
  ok "selected-u14-runs-real-group-only"
else
  bad "selected-u14-runs-real-group-only" "rc=$CASE_RC"
  evidence "selected"
fi
if ! grep -q '^PASS: cli-flow-recovery ' "$EVID/selected.out" \
  && grep -q '^SCOPED: cli-flow-recovery group=u14; not full-suite evidence$' "$EVID/selected.out"; then
  ok "scoped-output-cannot-attest-full-pass"
else
  bad "scoped-output-cannot-attest-full-pass" "registered PASS shape leaked or scope banner missing"
  evidence "selected"
fi
if grep -qE '^\[cli-flow-recovery\] SCOPED group=u14 START elapsed=0s timeout=180s$' "$EVID/selected.err" \
  && grep -qE '^\[cli-flow-recovery\] SCOPED group=u14 END elapsed=[0-9]+s rc=0$' "$EVID/selected.err"; then
  ok "selected-group-start-end-observable"
else
  bad "selected-group-start-end-observable" "START/END identity missing"
  evidence "selected"
fi

run_case legacy_env 300 env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 FFCF_T1_ONLY=1 bash "$WRAPPER"
if [ "$CASE_RC" -eq 0 ] && grep -q '^SCOPED: cli-flow-recovery group=t1;' "$EVID/legacy_env.out" \
  && grep -q '^SCOPED PASS: cli-flow-recovery T17:' "$EVID/legacy_env.out" \
  && ! grep -q 'U14:' "$EVID/legacy_env.out"; then
  ok "legacy-environment-selector-compatible"
else
  bad "legacy-environment-selector-compatible" "rc=$CASE_RC or wrong dispatch"
  evidence "legacy_env"
fi

run_case failure 300 env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=180 PYTHON=false bash "$WRAPPER" --only u14
failure_log="$(sed -n 's/^\[cli-flow-recovery\] SCOPED diagnostic=//p' "$EVID/failure.err" | tail -n 1)"
if [ "$CASE_RC" -eq 1 ] && [ -n "$failure_log" ] && [ -f "$failure_log" ] \
  && grep -q '^group=u14 rc=1 ' "$failure_log"; then
  ok "selected-failure-propagates-and-retains-log"
else
  bad "selected-failure-propagates-and-retains-log" "rc=$CASE_RC log=[$failure_log]"
  evidence "failure"
fi

run_case timeout 120 env TMPDIR="$WORK" FFCF_SELECTOR_TIMEOUT_SECS=1 \
  FFCF_SELECTOR_TEST_DELAY_SECS=3 bash "$WRAPPER" --only u14
timeout_log="$(sed -n 's/^\[cli-flow-recovery\] SCOPED diagnostic=//p' "$EVID/timeout.err" | tail -n 1)"
if { [ "$CASE_RC" -eq 124 ] || [ "$CASE_RC" -eq 137 ]; } \
  && [ -n "$timeout_log" ] && [ -f "$timeout_log" ] \
  && grep -q "^group=u14 rc=$CASE_RC " "$timeout_log"; then
  ok "selected-timeout-propagates-and-retains-log"
else
  bad "selected-timeout-propagates-and-retains-log" "rc=$CASE_RC log=[$timeout_log]"
  evidence "timeout"
fi

# FAULT INJECTION: the stall this phase actually suffered. The inner bound is pushed out of
# reach (3600s) and the child is made to hang, so the wrapper's own deadline CANNOT fire - which
# is what happened in the v4.17.0 release run, where the 180s bound never fired and only the
# 1800s phase wall stopped it, deleting every diagnostic on the way out. The phase-owned deadline
# must cut it in seconds, name it as a deadline, and LEAVE THE EVIDENCE.
#
# Discrimination limit, stated rather than implied: on b90b833 `run_case` takes no deadline
# argument at all, so this row cannot fail there "behaviourally" - there is no bound to observe.
# It fails there because the call shape does not exist. What it pins GOING FORWARD is the
# behaviour: a stalled case is cut at its own bound, with its evidence retained and printed.
stall_before="$failed"
CASE_EXPECT_DEADLINE=1
# Its own TMPDIR: a killed wrapper cannot run its own cleanup, and the fixture it leaves
# behind is a consequence of the INJECTION, not a cleanup defect - so it must not land in
# the directory the cleanup row judges.
mkdir -p "$WORK/stall-tmp"
run_case stall 8 env TMPDIR="$WORK/stall-tmp" FFCF_SELECTOR_TIMEOUT_SECS=3600 \
  FFCF_SELECTOR_TEST_DELAY_SECS=600 bash "$WRAPPER" --only u14
stall_problems=""
[ "$CASE_DEADLINE_HIT" -eq 1 ] || stall_problems="$stall_problems no-deadline-fired(rc=$CASE_RC,elapsed=${CASE_ELAPSED}s)"
[ "$CASE_ELAPSED" -lt 60 ] || stall_problems="$stall_problems waited-${CASE_ELAPSED}s-not-its-own-8s-bound"
[ "$failed" -eq "$stall_before" ] || stall_problems="$stall_problems injected-deadline-was-counted-against-the-phase"
[ -f "$EVID/stall.out" ] && [ -f "$EVID/stall.err" ] || stall_problems="$stall_problems evidence-missing"
rm -rf "$WORK/stall-tmp"
if [ -z "$stall_problems" ]; then
  ok "stalled-case-is-cut-at-its-own-deadline-with-evidence-retained"
else
  bad "stalled-case-is-cut-at-its-own-deadline-with-evidence-retained" "$stall_problems"
fi

# TRIPWIRE (source assertion, and named as one): an UNEXPECTED deadline must stay a counted,
# named failure. Exercising that branch for real would redden this phase by design, so what is
# checked is that the branch still calls `bad` with the CASE DEADLINE label - the thing a later
# edit would quietly drop while making the injected path quiet.
if grep -q 'bad "case-\$name-produced-a-verdict"' "$0" \
  && grep -q 'CASE DEADLINE \${secs}s' "$0"; then
  ok "an-unexpected-case-deadline-is-a-counted-named-failure"
else
  bad "an-unexpected-case-deadline-is-a-counted-named-failure" "the deadline branch no longer scores a named failure"
fi

if ! find "$WORK" -maxdepth 1 -type d -name 'fusebase-flow-cli-sim.*' | grep -q .; then
  ok "selected-fixtures-cleaned-after-success-failure-timeout"
else
  bad "selected-fixtures-cleaned-after-success-failure-timeout" "fixture directory remains under $WORK"
fi

finish
