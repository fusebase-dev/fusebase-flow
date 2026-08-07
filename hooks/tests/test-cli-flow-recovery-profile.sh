#!/usr/bin/env bash
# Fusebase Flow — S3A/T2: the cli-flow-recovery observability seam.
# WHY-home: docs/specs/backlog-triage-execution/execution-plan.md § S3A (+ § 5 provenance).
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT:
#   It drives hooks/tests/lib/cli-flow-recovery-profile.sh directly with synthetic milestones
#   and asserts the trace contract: file created, rows parseable, durations non-negative and the
#   milestone sequence monotonic, provenance present, redaction allowlist honoured, and pass()/
#   fail() stdout/stderr bytes unchanged from the pre-seam harness. It does NOT run
#   test-cli-flow-recovery.sh (minutes) and therefore says NOTHING about that test's own result;
#   the seam's presence in that file is checked as residency only.
#
# P1: this is instrumentation. No assertion here may be read as selecting an optimization.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-flow-profile <name>" / "FAIL: cli-flow-profile <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$ROOT/hooks/tests/lib/cli-flow-recovery-profile.sh"
HARNESS="$ROOT/hooks/tests/test-cli-flow-recovery.sh"

# S3A: the shipped assertion-group count, recorded from the implementation-base SHA. T2 must not
# change it. TRIPWIRE: this number is the plan's "baseline count is UNKNOWN; T2 records it" - a
# later ticket that adds or drops a scenario updates it DELIBERATELY, never silently.
EXPECTED_SCENARIOS=31

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-cli-profile.$$"
# TRIPWIRE: the seam now REFUSES any trace destination outside $ROOT/state/audit (an ambient
# FFCP_TRACE_FILE naming an arbitrary existing path was truncated by ffcp_init). A scratch trace
# root therefore lives INSIDE the audit root and is removed on exit — there is deliberately no
# env escape hatch, because a containment guard with a bypass is not a containment guard.
AUDIT_SCRATCH="$ROOT/state/audit/.cli-flow-profile-test.$$"
cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-cli-profile.*|*/tmp/fusebase-flow-cli-profile.*|*/Temp/fusebase-flow-cli-profile.*)
      rm -rf "$TMP_BASE" ;;
  esac
  case "$AUDIT_SCRATCH" in
    */state/audit/.cli-flow-profile-test.*) rm -rf "$AUDIT_SCRATCH" ;;
  esac
}
trap cleanup EXIT
mkdir -p "$TMP_BASE" "$AUDIT_SCRATCH"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: cli-flow-profile $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: cli-flow-profile $1 (${2:-})"; }
finish() { echo "[test-cli-flow-recovery-profile] $pass/$((pass + fail)) PASS"; exit $fail; }

# ---- 1. The seam exists and the baselined harness actually uses it -----------------------
f=""
[ -f "$HELPER" ]  || f="$f [helper missing: hooks/tests/lib/cli-flow-recovery-profile.sh]"
[ -f "$HARNESS" ] || f="$f [harness missing: hooks/tests/test-cli-flow-recovery.sh]"
if [ -f "$HARNESS" ]; then
  grep -q 'hooks/tests/lib/cli-flow-recovery-profile.sh' "$HARNESS" \
    || f="$f [harness does not source the profile seam]"
  grep -q '^ffcp_init ' "$HARNESS" || f="$f [harness never calls ffcp_init]"
  # Anti-duplication: if the harness re-defines pass()/fail() inline, the seam is bypassed and
  # every trace row silently disappears while the suite stays green.
  grep -qE '^(pass|fail)\(\) \{' "$HARNESS" \
    && f="$f [harness still defines pass()/fail() inline - it would shadow the seam]"
fi
[ -z "$f" ] && ok "seam-sourced-by-harness (helper present; harness sources it, calls ffcp_init, and defines no shadowing reporter)" \
  || bad "seam-sourced-by-harness" "$f"

if [ ! -f "$HELPER" ]; then
  bad "trace-file-created" "helper absent - the remaining trace assertions cannot run"
  finish
fi

# ---- Drive the seam with synthetic milestones -------------------------------------------
TRACE_ROOT="$AUDIT_SCRATCH/traces"
DRIVER="$TMP_BASE/driver.sh"
cat > "$DRIVER" <<'DRIVER_EOF'
set -euo pipefail
. "$HELPER_PATH"
ffcp_init test-cli-flow-recovery.sh
ffcp_substep fixture-base "(none)" "synthetic fixture interval"
pass "F3: synthetic milestone one"
ffcp_substep recovery-default post-fusebase-update.sh "synthetic invocation interval"
pass "U20: synthetic	milestone two"
DRIVER_EOF

# Decoys: values that MUST NOT reach the trace. The name families come from the plan's
# redaction contract (TOKEN/SECRET/KEY/PASSWORD/AUTH/COOKIE) plus a non-allowlisted FF_* name -
# an allowlist that leaks a sibling FF_* is the failure this catches.
DECOY="ffcp-decoy-must-not-appear-8f2a1c"
DRIVER_OUT="$TMP_BASE/driver.out"; DRIVER_ERR="$TMP_BASE/driver.err"
# TRIPWIRE: `-u FF_ONLY` is load-bearing. This suite is routinely invoked AS
# `FF_ONLY=cli-flow-profile bash run-tests.sh`, and the child inherits that value - so without the
# explicit unset, the set-vs-(default) assertion below passes or fails depending on how the
# operator started the run. One allowlisted name must be deterministically SET and one
# deterministically UNSET for that distinction to be testable at all.
env -u FF_ONLY HELPER_PATH="$HELPER" FFCP_TRACE_ROOT="$TRACE_ROOT" \
    FF_CLI_RECOVERY_TIMEOUT=900 \
    FF_INTERNAL_DECOY="$DECOY" AWS_SECRET_ACCESS_KEY="$DECOY" SESSION_COOKIE="$DECOY" \
    bash "$DRIVER" > "$DRIVER_OUT" 2> "$DRIVER_ERR"
DRIVER_RC=$?

TRACE="$(ls -1 "$TRACE_ROOT"/*/run-*.tsv 2>/dev/null | head -n1)"

f=""
[ "$DRIVER_RC" -eq 0 ] || f="$f [driver exited $DRIVER_RC; stderr: $(head -3 "$DRIVER_ERR" | tr '\n' ' ')]"
[ -n "$TRACE" ] || f="$f [no trace file under $TRACE_ROOT/<head>/run-*.tsv]"
if [ -n "$TRACE" ]; then
  [ -s "$TRACE" ] || f="$f [trace file is empty]"
  # The <full-head> directory level is part of the plan's retention contract (T6 groups repeated
  # runs by exact SHA); a flat file would silently merge runs from different commits.
  head_dir="$(basename "$(dirname "$TRACE")")"
  printf '%s' "$head_dir" | grep -qE '^[0-9a-f]{40}$' \
    || f="$f [trace parent dir is not a full 40-hex HEAD: $head_dir]"
fi
[ -z "$f" ] && ok "trace-file-created (one run-*.tsv under state/audit/cli-flow-recovery-profiles/<full-head>/; driver exit 0)" \
  || bad "trace-file-created" "$f"

if [ -z "$TRACE" ] || [ ! -s "$TRACE" ]; then
  bad "trace-rows-parseable" "no trace to parse"
  finish
fi

# ---- 3. Every row is parseable ------------------------------------------------------------
f=""
bad_rows="$(awk -F'\t' '
  $1 == "meta"  { if (NF != 3) print "meta row NF=" NF " line " NR; next }
  $1 == "event" { if (NF != 10) print "event row NF=" NF " line " NR; next }
  { print "unknown row kind \"" $1 "\" line " NR }
' "$TRACE")"
[ -z "$bad_rows" ] || f="$f [$(printf '%s' "$bad_rows" | tr '\n' ';')]"
n_events="$(awk -F'\t' '$1=="event"' "$TRACE" | grep -c .)"
[ "$n_events" -eq 4 ] || f="$f [expected 4 synthetic events (2 substeps + 2 scenarios), got $n_events]"
awk -F'\t' '$1=="event" && $4 !~ /^(F3|U20|fixture-base|recovery-default)$/ {print}' "$TRACE" | grep -q . \
  && f="$f [an event carries an unexpected scenario id; ids must derive from the milestone label]"
# Driver milestone order: seq 1 = fixture-base substep, 2 = F3 scenario, 3 = recovery-default
# substep, 4 = U20 scenario.
awk -F'\t' '$1=="event" && $2=="1" && ($3 != "substep" || $9 != "(none)")' "$TRACE" | grep -q . \
  && f="$f [first substep row lost its event name or invoked-script column]"
awk -F'\t' '$1=="event" && $2=="3" && $9 != "post-fusebase-update.sh"' "$TRACE" | grep -q . \
  && f="$f [substep row lost its invoked-script basename]"
awk -F'\t' '$1=="event" && $2=="4" && ($3 != "scenario" || $8 != "PASS")' "$TRACE" | grep -q . \
  && f="$f [scenario row lost its event name or result]"
[ -z "$f" ] && ok "trace-rows-parseable (every row is meta/3 or event/10 fields; 4 events; scenario ids and invoked-script column populated)" \
  || bad "trace-rows-parseable" "$f"

# ---- 4. Durations non-negative; milestone sequence monotonic -------------------------------
# The sequence is a PARTITION of the run: each event's start is the previous event's end.
f=""
seq_err="$(awk -F'\t' '
  $1 != "event" { next }
  { seq=$2+0; start=$5+0; end=$6+0; dur=$7+0
    if (seq != prev_seq + 1) print "seq jumped: " prev_seq " -> " seq
    if (dur < 0)             print "negative duration at seq " seq ": " dur
    if (end < start)         print "end < start at seq " seq
    if (dur != end - start)  print "duration != end-start at seq " seq
    if (seq > 1 && start != prev_end) print "sequence not contiguous at seq " seq " (start " start " != previous end " prev_end ")"
    if (end < prev_end)      print "clock went backwards at seq " seq
    prev_seq=seq; prev_end=end }
  END { if (prev_seq == 0) print "no event rows examined" }
' "$TRACE")"
[ -z "$seq_err" ] || f="$f [$(printf '%s' "$seq_err" | tr '\n' ';')]"
awk -F'\t' '$1=="event" && $2=="1" && $5 != "0"' "$TRACE" | grep -q . \
  && f="$f [first event does not start at 0ms - the trace is not relative to ffcp_init]"
[ -z "$f" ] && ok "durations-non-negative-and-monotonic (dur == end-start >= 0; seq +1 each row; each start == previous end; no backward clock step)" \
  || bad "durations-non-negative-and-monotonic" "$f"

# ---- 5. Provenance ------------------------------------------------------------------------
f=""
for key in schema head head_dirty platform shell script clock started_utc; do
  awk -F'\t' -v k="$key" '$1=="meta" && $2==k {found=1} END{exit !found}' "$TRACE" \
    || f="$f [missing provenance field: $key]"
done
awk -F'\t' '$1=="meta" && $2=="head" {print $3}' "$TRACE" | grep -qE '^[0-9a-f]{40}$' \
  || f="$f [provenance head is not a full 40-hex SHA]"
for name in FF_ONLY FF_SKIP_CLI_RECOVERY FF_CLI_RECOVERY_TIMEOUT FF_PHASE_TIMEOUT \
            FFHC_TIMEOUT_KILL_GRACE FFHC_USE_JOB_OBJECT FFHC_HEARTBEAT_SECS; do
  awk -F'\t' -v k="env.$name" '$1=="meta" && $2==k {found=1} END{exit !found}' "$TRACE" \
    || f="$f [allowlisted FF_* name not recorded (absence must be explicit): $name]"
done
# Set vs unset must be distinguishable, or "no override was in effect" is unprovable.
awk -F'\t' '$1=="meta" && $2=="env.FF_CLI_RECOVERY_TIMEOUT" && $3=="900" {found=1} END{exit !found}' "$TRACE" \
  || f="$f [a SET allowlisted value was not recorded verbatim]"
awk -F'\t' '$1=="meta" && $2=="env.FF_ONLY" && $3=="(default)" {found=1} END{exit !found}' "$TRACE" \
  || f="$f [an UNSET allowlisted value was not recorded as (default)]"
[ -z "$f" ] && ok "provenance-fields-present (schema/head(40-hex)/head_dirty/platform/shell/script/clock/started_utc + all 7 allowlisted FF_* names, set-vs-default distinguishable)" \
  || bad "provenance-fields-present" "$f"

# ---- 6. Redaction: allowlist only, no environment dump -------------------------------------
f=""
grep -qF "$DECOY" "$TRACE" && f="$f [a decoy secret value reached the trace - the environment is being dumped]"
stray="$(awk -F'\t' '$1=="meta" && $2 ~ /^env\./ {print $2}' "$TRACE" \
  | grep -vxE 'env\.(FF_ONLY|FF_SKIP_CLI_RECOVERY|FF_CLI_RECOVERY_TIMEOUT|FF_PHASE_TIMEOUT|FFHC_TIMEOUT_KILL_GRACE|FFHC_USE_JOB_OBJECT|FFHC_HEARTBEAT_SECS|FFCP_TRACE_FILE|FFCP_TRACE_ROOT)')"
[ -z "$stray" ] || f="$f [non-allowlisted env name recorded: $(printf '%s' "$stray" | tr '\n' ' ')]"
grep -qiE 'TOKEN|SECRET|PASSWORD|COOKIE' "$TRACE" && f="$f [trace carries a redaction-family name]"
# A behaviour-changing override with no provenance row is the same blind spot as a missing timeout.
for name in FFCP_TRACE_FILE FFCP_TRACE_ROOT; do
  awk -F'\t' -v k="env.$name" '$1=="meta" && $2==k {found=1} END{exit !found}' "$TRACE" \
    || f="$f [behaviour-changing override not recorded: $name]"
done
# The accepted trace ROOT must be recorded as a disposition, never as the path itself (§5 excludes
# absolute paths from the trace outright).
awk -F'\t' '$1=="meta" && $2=="env.FFCP_TRACE_ROOT" {print $3}' "$TRACE" | grep -qx 'set (accepted)' \
  || f="$f [FFCP_TRACE_ROOT disposition not recorded as 'set (accepted)': $(awk -F'\t' '$1=="meta" && $2=="env.FFCP_TRACE_ROOT" {print $3}' "$TRACE")]"
grep -qF "$AUDIT_SCRATCH" "$TRACE" && f="$f [the raw override PATH was written into the trace]"
[ -z "$f" ] && ok "provenance-redaction-allowlist-only (three decoy values absent; env.* rows are exactly the 9 allowlisted names; both FFCP_TRACE_* overrides recorded as dispositions, not paths; no TOKEN/SECRET/PASSWORD/COOKIE family text)" \
  || bad "provenance-redaction-allowlist-only" "$f"

# ---- 6b. An allowlisted NAME does not make its VALUE recordable ----------------------------
# FF_ONLY is free text an operator types on a command line; it was written to the trace verbatim,
# so a secret pasted there was persisted. Only self-evidently non-secret shapes (numbers) stay
# verbatim; the shipped set/unset distinction (assertion 5) must survive the change.
f=""
RED_ROOT="$AUDIT_SCRATCH/traces-redact"
env HELPER_PATH="$HELPER" FFCP_TRACE_ROOT="$RED_ROOT" FF_ONLY="cli-flow-profile,$DECOY" \
    bash "$DRIVER" >/dev/null 2>&1
RED_TRACE="$(ls -1 "$RED_ROOT"/*/run-*.tsv 2>/dev/null | head -n1)"
if [ -z "$RED_TRACE" ]; then
  bad "allowlisted-values-are-redacted" "no trace produced for the redaction probe"
else
  grep -qF "$DECOY" "$RED_TRACE" && f="$f [a secret placed in the ALLOWLISTED FF_ONLY was recorded verbatim]"
  awk -F'\t' '$1=="meta" && $2=="env.FF_ONLY" {print $3}' "$RED_TRACE" | grep -q '^set (redacted' \
    || f="$f [a set, non-numeric allowlisted value was not reduced to a shape description: $(awk -F'\t' '$1=="meta" && $2=="env.FF_ONLY" {print $3}' "$RED_TRACE")]"
  [ -z "$f" ] && ok "allowlisted-values-are-redacted (a secret in the allowlisted FF_ONLY is absent from the trace and recorded only as a shape; numeric knobs stay verbatim per assertion 5)" \
    || bad "allowlisted-values-are-redacted" "$f"
fi

# ---- 6c. A trace destination outside the audit root is REJECTED, not truncated --------------
# ffcp_init opens its target with `> `, so an ambient FFCP_TRACE_FILE naming any existing path
# destroyed that file. The victim here is a real file with real bytes.
f=""
VICTIM="$TMP_BASE/precious.txt"
printf 'do-not-truncate-me\n' > "$VICTIM"
env HELPER_PATH="$HELPER" FFCP_TRACE_FILE="$VICTIM" bash "$DRIVER" >/dev/null 2>&1
esc_rc=$?
[ "$esc_rc" -eq 0 ] || f="$f [the driver failed ($esc_rc) instead of ignoring the rejected override]"
grep -qx 'do-not-truncate-me' "$VICTIM" \
  || f="$f [the out-of-root trace target was TRUNCATED — instrumentation destroyed an unrelated file]"
# The `..` form must be rejected too, or the prefix test is trivially bypassable.
VICTIM2="$TMP_BASE/precious2.txt"
printf 'also-do-not-truncate\n' > "$VICTIM2"
env HELPER_PATH="$HELPER" FFCP_TRACE_FILE="$ROOT/state/audit/../../$(basename "$TMP_BASE")/precious2.txt" \
    bash "$DRIVER" >/dev/null 2>&1
grep -qx 'also-do-not-truncate' "$VICTIM2" \
  || f="$f [a '..' traversal through the audit root truncated a file outside it]"
[ -z "$f" ] && ok "trace-destination-contained (an out-of-root FFCP_TRACE_FILE, and a '..' traversal through the audit root, are both rejected; both victim files keep their bytes and the run still exits 0)" \
  || bad "trace-destination-contained" "$f"

# ---- 6d. A trace-write failure is INERT ------------------------------------------------------
# The harness runs under `set -e`. An unguarded append meant a full disk aborted the run BEFORE
# its PASS/FAIL bytes, so instrumentation could decide a verdict. Simulated by replacing the trace
# file with a DIRECTORY after ffcp_init, which makes every later append fail.
f=""
INERT_DRIVER="$TMP_BASE/inert-driver.sh"
cat > "$INERT_DRIVER" <<'INERT_EOF'
set -euo pipefail
. "$HELPER_PATH"
ffcp_init test-cli-flow-recovery.sh
rm -f "$FFCP_TRACE_FILE"; mkdir -p "$FFCP_TRACE_FILE"
pass "F3: milestone after the trace destination broke"
pass "U20: second milestone after the trace destination broke"
INERT_EOF
IOUT="$TMP_BASE/inert.out"
env HELPER_PATH="$HELPER" FFCP_TRACE_ROOT="$AUDIT_SCRATCH/traces-inert" \
    bash "$INERT_DRIVER" > "$IOUT" 2>/dev/null
inert_rc=$?
[ "$inert_rc" -eq 0 ] || f="$f [a failing trace write changed the run's exit status to $inert_rc]"
grep -qx '\[test-cli-flow-recovery\] PASS: F3: milestone after the trace destination broke' "$IOUT" \
  || f="$f [the first PASS byte after the write failure was lost]"
grep -qx '\[test-cli-flow-recovery\] PASS: U20: second milestone after the trace destination broke' "$IOUT" \
  || f="$f [the run stopped after the write failure — instrumentation aborted the verdict]"
[ -z "$f" ] && ok "trace-write-failure-is-inert (trace destination destroyed mid-run: both later PASS lines still printed and the run still exited 0)" \
  || bad "trace-write-failure-is-inert" "$f"

# ---- 7. stdout/stderr bytes are what the pre-seam harness produced --------------------------
# The gate parses stdout. A trace byte on stdout, or a changed PASS prefix, breaks it.
f=""
# The second label carries a literal TAB on purpose: pass() must print the operator's label
# VERBATIM (pre-seam bytes) while the trace row sanitizes the separator out - assertion 3's
# field-count check is what proves the trace half.
EXPECTED_OUT="$(printf '%s\n%s' \
  '[test-cli-flow-recovery] PASS: F3: synthetic milestone one' \
  "$(printf '[test-cli-flow-recovery] PASS: U20: synthetic\tmilestone two')")"
ACTUAL_OUT="$(cat "$DRIVER_OUT")"
[ "$ACTUAL_OUT" = "$EXPECTED_OUT" ] || f="$f [pass() stdout changed:
--- expected ---
$EXPECTED_OUT
--- actual ---
$ACTUAL_OUT]"
grep -qE '^(meta|event)	' "$DRIVER_OUT" && f="$f [trace rows leaked onto stdout]"
# fail(): same bytes, still stderr, still exit 1.
FAIL_DRIVER="$TMP_BASE/fail-driver.sh"
cat > "$FAIL_DRIVER" <<'FAIL_EOF'
set -uo pipefail
. "$HELPER_PATH"
ffcp_init test-cli-flow-recovery.sh
fail "U11: synthetic failure"
echo "UNREACHABLE"
FAIL_EOF
FOUT="$TMP_BASE/fail.out"; FERR="$TMP_BASE/fail.err"
env HELPER_PATH="$HELPER" FFCP_TRACE_ROOT="$AUDIT_SCRATCH/traces-fail" \
    bash "$FAIL_DRIVER" > "$FOUT" 2> "$FERR"
FAIL_RC=$?
[ "$FAIL_RC" -eq 1 ] || f="$f [fail() exited $FAIL_RC, expected 1]"
grep -qx '\[test-cli-flow-recovery\] FAIL: U11: synthetic failure' "$FERR" \
  || f="$f [fail() stderr line changed: $(grep -F 'FAIL:' "$FERR" | head -1)]"
grep -q 'UNREACHABLE' "$FOUT" && f="$f [fail() no longer terminates the script]"
[ -s "$FOUT" ] && f="$f [fail() wrote to stdout: $(head -1 "$FOUT")]"
FAIL_TRACE="$(ls -1 "$AUDIT_SCRATCH/traces-fail"/*/run-*.tsv 2>/dev/null | head -n1)"
[ -n "$FAIL_TRACE" ] && awk -F'\t' '$1=="event" && $8=="FAIL" {found=1} END{exit !found}' "$FAIL_TRACE" \
  || f="$f [the failing milestone was not recorded with result FAIL]"
[ -z "$f" ] && ok "stdout-byte-contract-preserved (pass() prints the pre-seam line and nothing else; fail() keeps stderr shape, exit 1, script termination, and records a FAIL milestone)" \
  || bad "stdout-byte-contract-preserved" "$f"

# ---- 8. CONTROL: the shipped assertion-group count is unchanged -----------------------------
# Declared a CONTROL: it passes on both sides of T2 by construction. It exists so a later
# instrumentation edit cannot quietly delete or duplicate a scenario.
n="$(grep -c '^pass "' "$HARNESS")"
[ "$n" -eq "$EXPECTED_SCENARIOS" ] \
  && ok "scenario-count-unchanged (CONTROL - $n top-level pass call sites, the recorded S3A baseline; passes on both sides of T2 and proves nothing about the seam)" \
  || bad "scenario-count-unchanged" "harness has $n top-level pass call sites, recorded baseline is $EXPECTED_SCENARIOS"

finish
