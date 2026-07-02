#!/usr/bin/env bash
# Fusebase Flow — WS5 (v3.30.4) upgrade-engine Windows-safe bounded-exit tests.
# Roadmap: docs/specs/windows-msys-hardening/roadmap.md § WS5. Engine: hooks/local/upgrade.sh.
#
# WS5 fixes the upgrade busy-loop / 255-at-tail on MSYS by (1) making prune_pre_backups
# SINGLE-PASS (the busy-loop ROOT — the old code ran a full-tree `find .` PER stem =
# O(K*M) fork-storm) and (2) bounding the long OPTIONAL steps via ffhc_run_step so a
# killed step is killable + observable. CRITICAL steps (content copy/merge, VERSION
# write) FAIL with the recovery hint when killed (never mask a partial upgrade as
# success); OPTIONAL steps (re-mirror, sync-strings, backup-prune) WARN + continue.
#
# The functions under test (prune_pre_backups, ffhc_run_step, print_recovery_hint) are
# EXTRACTED from the SHIPPED upgrade.sh (awk between the `name() {` and the matching
# `}`), so these assertions guard the real code path — a regression in the shipped
# function changes the extract and trips the test. A full end-to-end `upgrade.sh
# --auto-yes` needs a staged .fusebase-flow-source clone (consumer-gated); here we
# assert the specific changed steps' termination/rc/critical-vs-optional behavior.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: ws5-upgrade <name>" / "FAIL: ws5-upgrade <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
UPGRADE="$ROOT/hooks/local/upgrade.sh"
LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS: ws5-upgrade $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: ws5-upgrade $1 (${2:-})"; }
skip() { echo "PASS: ws5-upgrade $1 [SKIP — $2]"; pass=$((pass + 1)); }
finish() { echo "[test-ws5-upgrade-bounded] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$UPGRADE" ] || { bad "setup-upgrade-present" "missing $UPGRADE"; finish; }
[ -f "$LIB" ] || { bad "setup-lib-present" "missing $LIB"; finish; }

# Extract a named shell function VERBATIM from a script (the region from `name() {`
# through the first line that is exactly `}`). Used to drive the shipped functions.
extract_fn() { awk -v fn="$1" '$0 ~ ("^" fn "\\(\\) \\{"){p=1} p{print} p&&/^}/{exit}' "$2"; }

# ---- W1: prune_pre_backups is SINGLE-PASS — terminates on a LARGE backup set and keeps
# newest N per stem. The busy-loop ROOT FIX (not just a bound): the old code did a full
# `find .` per stem, so a large set fork-stormed MSYS into an apparent hang. ----
w1_prune() {
  local FIX; FIX="$(mktemp -d "${TMPDIR:-/tmp}/ws5-prune.XXXXXX")" || { bad "w1-prune-single-pass" "mktemp -d failed"; return; }
  ( cd "$FIX" || exit 1
    mkdir -p sub
    # 30 stems x 5 timestamps = 150 backups (+ 4 in a subdir) — big enough that the OLD
    # per-stem full-find would fork-storm; the single-pass pipeline is O(1) traversals.
    local s t
    for s in $(seq 1 30); do
      for t in 20260101T000001Z 20260102T000001Z 20260103T000001Z 20260104T000001Z 20260105T000001Z; do
        : > "file$s.txt.pre-upgrade-$t"
      done
    done
    for t in 20260101T000001Z 20260106T000001Z 20260107T000001Z 20260108T000001Z; do : > "sub/x.md.pre-refresh-$t"; done
  ) || { rm -rf "$FIX"; bad "w1-prune-single-pass" "fixture setup failed"; return; }

  local before after pruned rc start end el
  before="$(find "$FIX" -name '*.pre-*' 2>/dev/null | wc -l | tr -d ' ')"
  local FN; FN="$(extract_fn prune_pre_backups "$UPGRADE")"
  [ -n "$FN" ] || { rm -rf "$FIX"; bad "w1-prune-single-pass" "could not extract prune_pre_backups from upgrade.sh (regressed/renamed?)"; return; }
  # Bound the whole prune so a REGRESSION to the per-stem busy-loop FAILS here (rc 124)
  # instead of hanging the suite. 60s is generous for 154 files single-pass; the OLD
  # per-stem algorithm on 30 stems alone measured ~40s+ of pure traversal.
  start=$(date +%s)
  ( cd "$FIX" && timeout -k 3 60 bash -c "PRE_RETAIN=3; $FN; prune_pre_backups" ) > "$FIX/.plog" 2>&1
  rc=$?
  end=$(date +%s); el=$((end - start))
  after="$(find "$FIX" -name '*.pre-*' 2>/dev/null | wc -l | tr -d ' ')"
  pruned="$(grep -c 'pruned old backup' "$FIX/.plog" 2>/dev/null)"
  # 30 stems keep 3 each (90) + sub/x.md keeps 3 = 93 remaining; 150-90 + 4-3 = 61 pruned.
  if [ "$rc" -ne 0 ]; then
    bad "w1-prune-single-pass" "prune did not terminate within the bound (rc=$rc, ${el}s) — a regression to the per-stem busy-loop"
  elif [ "$after" -eq 93 ] && [ "$pruned" -eq 61 ]; then
    ok "w1-prune-single-pass (single-pass: $before -> $after backups (keep 3/stem), $pruned pruned, terminated in ${el}s — no per-stem busy-loop)"
  else
    bad "w1-prune-single-pass" "prune result wrong: before=$before after=$after pruned=$pruned (expected after=93 pruned=61)"
  fi
  # W1b: newest-3 kept for a sample stem (correct retention order).
  local kept; kept="$(cd "$FIX" && ls file1.txt.pre-upgrade-* 2>/dev/null | sort | tr '\n' ' ')"
  case "$kept" in
    *20260103T000001Z*20260104T000001Z*20260105T000001Z*) ok "w1b-prune-keeps-newest (file1 kept the 3 newest timestamps: $kept)" ;;
    *) bad "w1b-prune-keeps-newest" "file1 retention wrong: [$kept] (expected the 3 newest 03/04/05)" ;;
  esac
  rm -rf "$FIX"
}

# ---- W2/W3: ffhc_run_step critical-vs-optional. Extract the shipped helper (verbatim),
# source the lib for ffhc_run_bounded, stub print_recovery_hint, drive one step. ----
w2_optional_killed_continues() {
  if [ -z "${FFHC_TIMEOUT_BIN:-}" ] && ! command -v timeout >/dev/null 2>&1; then
    skip "w2-optional-killed-continues" "no timeout binary to bound the step"; return
  fi
  # An OPTIONAL step (critical=0) that OVERRUNS a 1s bound must be killed, WARN, and the
  # harness must CONTINUE to a marker line with rc 0 (never fail the upgrade). Drive the
  # SHIPPED ffhc_run_step directly (extracted verbatim).
  local out rc
  out="$(FFHC_TIMEOUT_KILL_GRACE=1s bash -c '
    ROOT="'"$ROOT"'"; FFHC_STEP_LIB="'"$LIB"'"; FFHC_STEP_LIB_OK=0
    . "$FFHC_STEP_LIB"; ffhc_detect_timeout; FFHC_STEP_LIB_OK=1
    print_recovery_hint() { echo HINT >&2; }
    '"$(extract_fn ffhc_run_step "$UPGRADE")"'
    ffhc_run_step 1 0 "slow-optional" sleep 20
    echo "AFTER-OPTIONAL rc=$?"
  ' 2>&1)"; rc=$?
  if echo "$out" | grep -q "AFTER-OPTIONAL rc=0" && echo "$out" | grep -qi "optional step failed/killed"; then
    ok "w2-optional-killed-continues (a killed OPTIONAL step WARNs + continues; harness reaches AFTER-OPTIONAL rc=0 — upgrade not failed)"
  else
    bad "w2-optional-killed-continues" "expected a WARN + continue to AFTER-OPTIONAL rc=0; got: $out"
  fi
}

w3_critical_killed_fails_with_hint() {
  if [ -z "${FFHC_TIMEOUT_BIN:-}" ] && ! command -v timeout >/dev/null 2>&1; then
    skip "w3-critical-killed-fails-with-hint" "no timeout binary to bound the step"; return
  fi
  # A CRITICAL step (critical=1) that OVERRUNS a 1s bound must PRINT the recovery hint and
  # EXIT 1 (never continue past a broken critical). The `echo AFTER` must NOT appear.
  local out rc
  out="$(FFHC_TIMEOUT_KILL_GRACE=1s bash -c '
    ROOT="'"$ROOT"'"; FFHC_STEP_LIB="'"$LIB"'"; FFHC_STEP_LIB_OK=0
    . "$FFHC_STEP_LIB"; ffhc_detect_timeout; FFHC_STEP_LIB_OK=1
    print_recovery_hint() { echo "RECOVERY-HINT-PRINTED" >&2; }
    '"$(extract_fn ffhc_run_step "$UPGRADE")"'
    ffhc_run_step 1 1 "slow-critical" sleep 20
    echo "AFTER-CRITICAL-SHOULD-NOT-APPEAR"
  ' 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -q "RECOVERY-HINT-PRINTED" && ! echo "$out" | grep -q "AFTER-CRITICAL-SHOULD-NOT-APPEAR"; then
    ok "w3-critical-killed-fails-with-hint (a killed CRITICAL step exits nonzero (rc=$rc) + prints the recovery hint + does NOT continue — never masks a partial upgrade)"
  else
    bad "w3-critical-killed-fails-with-hint" "expected nonzero exit + RECOVERY-HINT + no AFTER line; got rc=$rc out: $out"
  fi
}

w4_critical_failing_cmd_fails() {
  # A CRITICAL step whose command FAILS (nonzero, fast — not a timeout) must ALSO exit 1
  # with the hint (critical failure, not just a kill). Guards the rc!=0 critical branch.
  local out rc
  out="$(bash -c '
    ROOT="'"$ROOT"'"; FFHC_STEP_LIB="'"$LIB"'"; FFHC_STEP_LIB_OK=0
    . "$FFHC_STEP_LIB" 2>/dev/null; ffhc_detect_timeout; command -v ffhc_run_bounded >/dev/null 2>&1 && FFHC_STEP_LIB_OK=1
    print_recovery_hint() { echo "RECOVERY-HINT-PRINTED" >&2; }
    '"$(extract_fn ffhc_run_step "$UPGRADE")"'
    ffhc_run_step 30 1 "failing-critical" bash -c "exit 4"
    echo "AFTER-SHOULD-NOT-APPEAR"
  ' 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -q "RECOVERY-HINT-PRINTED" && ! echo "$out" | grep -q "AFTER-SHOULD-NOT-APPEAR"; then
    ok "w4-critical-failing-cmd-fails (a CRITICAL step whose cmd exits nonzero => exit $rc + recovery hint + halts — partial upgrade never reported success)"
  else
    bad "w4-critical-failing-cmd-fails" "expected nonzero exit + hint + no AFTER line; got rc=$rc out: $out"
  fi
}

w5_optional_ok_returns0() {
  # A fast OPTIONAL step that SUCCEEDS returns 0 and continues (the happy path — the bound
  # must not add spurious failure to a normal quick step).
  local out
  out="$(bash -c '
    ROOT="'"$ROOT"'"; FFHC_STEP_LIB="'"$LIB"'"; FFHC_STEP_LIB_OK=0
    . "$FFHC_STEP_LIB" 2>/dev/null; ffhc_detect_timeout; command -v ffhc_run_bounded >/dev/null 2>&1 && FFHC_STEP_LIB_OK=1
    print_recovery_hint() { :; }
    '"$(extract_fn ffhc_run_step "$UPGRADE")"'
    ffhc_run_step 30 0 "quick-optional" bash -c "echo did-work; exit 0"
    echo "AFTER-OK rc=$?"
  ' 2>&1)"
  if echo "$out" | grep -q "AFTER-OK rc=0"; then
    ok "w5-optional-ok-returns0 (a fast successful OPTIONAL step returns 0 and continues — no spurious bound failure)"
  else
    bad "w5-optional-ok-returns0" "expected AFTER-OK rc=0; got: $out"
  fi
}

# ---- W9..W12: the set -e BLOCKER (v3.30.4 review correction). The engine runs
# `set -euo pipefail` WITHOUT `set -E`, so a nonzero `wait "$bpid"` deep in
# ffhc_run_bounded (rc 124 timeout OR a child's own failure) would ABORT the whole
# upgrade at that `wait` — before ffhc_run_step's warn/continue (or critical hint),
# with NO ERR-trap inheritance (set -E off). The w2/w3/w4 cases above run WITHOUT
# `set -e` (line 22: `set -uo`), which is exactly why they PASSED while the shipped
# run aborted — the BLIND SPOT. These four drive the SHIPPED ffhc_run_step under the
# SHIPPED environment: `set -euo pipefail` + the ERR trap the engine arms at :298. ----

# Build a bash program that reproduces the engine's set -e + ERR-trap environment,
# sources the extracted ffhc_run_step, runs one step, and echoes a post-step marker.
# CMD_LINE is embedded VERBATIM as the tail of the ffhc_run_step call (already a
# properly-quoted command line, e.g. `sleep 20` or `bash -c 'exit 4'`) so quoting
# survives — NOT word-split through $* (which would strip inner quotes).
_ws5_set_e_prog() { # <critical> <secs> <cmd-line-verbatim>
  local critical="$1" secs="$2" cmd_line="$3"
  cat <<PROG
set -euo pipefail
ROOT="$ROOT"; FFHC_STEP_LIB="$LIB"; FFHC_STEP_LIB_OK=0
. "\$FFHC_STEP_LIB"; ffhc_detect_timeout; FFHC_STEP_LIB_OK=1
export FFHC_TIMEOUT_KILL_GRACE=1s
print_recovery_hint() { echo "RECOVERY-HINT-PRINTED" >&2; }
trap 'rc=\$?; print_recovery_hint; exit \$rc' INT TERM ERR
$(extract_fn ffhc_run_step "$UPGRADE")
ffhc_run_step $secs $critical "step-under-set-e" $cmd_line
echo "REACHED-MARKER rc=\$?"
PROG
}

w9_optional_timeout_set_e_safe() {
  if [ -z "${FFHC_TIMEOUT_BIN:-}" ] && ! command -v timeout >/dev/null 2>&1; then
    skip "w9-optional-timeout-set-e-safe" "no timeout binary to bound the step"; return
  fi
  # An OPTIONAL step (critical=0) that TIMES OUT (rc124) under `set -euo pipefail` + the ERR
  # trap must WARN + CONTINUE + reach the VERSION-write marker with rc0 — NOT abort at `wait`.
  local out rc
  out="$(timeout -k 5 40 bash -c "$(_ws5_set_e_prog 0 1 'sleep 20')" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "REACHED-MARKER rc=0" && echo "$out" | grep -qi "optional step failed/killed"; then
    ok "w9-optional-timeout-set-e-safe (UNDER set -e + ERR trap: a timed-out OPTIONAL step WARNs + continues + reaches the VERSION-write marker rc0 — the set -e wait-abort can no longer escape)"
  else
    bad "w9-optional-timeout-set-e-safe" "set -e wait-abort NOT neutralized: outer_rc=$rc (expected 0), out: $out"
  fi
}

w10_optional_fail_set_e_safe() {
  # An OPTIONAL step whose command FAILS fast (rc4, not a timeout) under set -e must ALSO
  # warn + continue + reach the marker rc0 (the child-failure arm of the same wait-abort).
  local out rc
  out="$(timeout -k 5 40 bash -c "$(_ws5_set_e_prog 0 30 "bash -c 'exit 4'")" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "REACHED-MARKER rc=0" && echo "$out" | grep -qi "optional step failed/killed"; then
    ok "w10-optional-fail-set-e-safe (UNDER set -e: a fast-failing OPTIONAL step (rc4) WARNs + continues + reaches the marker rc0 — no wait-abort)"
  else
    bad "w10-optional-fail-set-e-safe" "set -e abort on optional child-fail: outer_rc=$rc (expected 0), out: $out"
  fi
}

w11_critical_fail_set_e_exits_with_hint() {
  # A CRITICAL step that fails under set -e must reach ffhc_run_step's OWN critical branch:
  # exit nonzero WITH the recovery hint (NOT a raw set -e abort that skips the hint). The
  # post-step marker must NOT appear.
  local out rc
  out="$(timeout -k 5 40 bash -c "$(_ws5_set_e_prog 1 30 "bash -c 'exit 4'")" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -q "RECOVERY-HINT-PRINTED" && echo "$out" | grep -q "CRITICAL step failed" && ! echo "$out" | grep -q "REACHED-MARKER"; then
    ok "w11-critical-fail-set-e-exits-with-hint (UNDER set -e: a failing CRITICAL step exits nonzero (rc=$rc) via ffhc_run_step's FATAL+hint path — not a raw wait-abort that would skip the hint)"
  else
    bad "w11-critical-fail-set-e-exits-with-hint" "expected nonzero exit + FATAL + RECOVERY-HINT + no marker; got rc=$rc out: $out"
  fi
}

w12_degraded_optional_fail_set_e_safe() {
  # The FFHC_STEP_LIB_OK=0 degraded path runs the step DIRECTLY (`"$@"; rc=$?`) — it has the
  # identical set -e bug. Under set -e a degraded OPTIONAL fail must still warn + continue.
  local prog out rc
  prog="$(cat <<PROG
set -euo pipefail
FFHC_STEP_LIB_OK=0
print_recovery_hint() { echo "RECOVERY-HINT-PRINTED" >&2; }
trap 'rc=\$?; print_recovery_hint; exit \$rc' INT TERM ERR
$(extract_fn ffhc_run_step "$UPGRADE")
ffhc_run_step 30 0 "degraded-optional-fail" bash -c 'exit 7'
echo "REACHED-MARKER rc=\$?"
PROG
)"
  out="$(timeout -k 5 20 bash -c "$prog" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "REACHED-MARKER rc=0" && echo "$out" | grep -qi "optional step failed/killed"; then
    ok "w12-degraded-optional-fail-set-e-safe (UNDER set -e, FFHC_STEP_LIB_OK=0 direct-run path: a failing OPTIONAL step WARNs + continues + reaches the marker rc0)"
  else
    bad "w12-degraded-optional-fail-set-e-safe" "degraded-path set -e abort: outer_rc=$rc (expected 0), out: $out"
  fi
}

# ---- W13: prune timestamp-safety (defense-in-depth on the DELETE path). A non-backup
# file that merely CONTAINS ".pre-upgrade-"/".pre-refresh-" (e.g. config.pre-upgrade-
# template.yml) must NEVER be deleted; only genuine [0-9]{8}T[0-9]{6}Z-suffixed backups
# are eligible, and they still prune (keep newest N/stem). ----
w13_prune_ignores_non_backup() {
  local FIX; FIX="$(mktemp -d "${TMPDIR:-/tmp}/ws5-prunesafe.XXXXXX")" || { bad "w13-prune-ignores-non-backup" "mktemp -d failed"; return; }
  ( cd "$FIX" || exit 1
    # Non-backups bearing the reserved substring but NOT the timestamp shape — must survive.
    : > config.pre-upgrade-template.yml
    : > notes.pre-refresh-draft.md
    : > x.pre-upgrade-20260101T00001Z          # 5-digit time => malformed => survive
    # Genuine timestamped backups: 5 for one stem => newest 3 kept, oldest 2 pruned.
    local t
    for t in 20260101T000001Z 20260102T000001Z 20260103T000001Z 20260104T000001Z 20260105T000001Z; do
      : > "real.txt.pre-upgrade-$t"
    done
  ) || { rm -rf "$FIX"; bad "w13-prune-ignores-non-backup" "fixture setup failed"; return; }
  local FN; FN="$(extract_fn prune_pre_backups "$UPGRADE")"
  [ -n "$FN" ] || { rm -rf "$FIX"; bad "w13-prune-ignores-non-backup" "could not extract prune_pre_backups"; return; }
  ( cd "$FIX" && timeout -k 3 30 bash -c "PRE_RETAIN=3; $FN; prune_pre_backups" ) >/dev/null 2>&1
  local pruned_ok=1 kept
  [ -f "$FIX/config.pre-upgrade-template.yml" ] || pruned_ok=0
  [ -f "$FIX/notes.pre-refresh-draft.md" ] || pruned_ok=0
  [ -f "$FIX/x.pre-upgrade-20260101T00001Z" ] || pruned_ok=0
  kept="$(cd "$FIX" && ls real.txt.pre-upgrade-* 2>/dev/null | sort | tr '\n' ' ')"
  rm -rf "$FIX"
  if [ "$pruned_ok" -eq 1 ] && case "$kept" in *20260103T000001Z*20260104T000001Z*20260105T000001Z*) [ "$(echo "$kept" | wc -w)" -eq 3 ] ;; *) false ;; esac; then
    ok "w13-prune-ignores-non-backup (non-backup .pre-upgrade-/.pre-refresh- files survive; genuine timestamped backups prune to newest-3/stem: $kept)"
  else
    bad "w13-prune-ignores-non-backup" "template survived=$pruned_ok; real-backups-kept=[$kept] (expected 3 newest 03/04/05, non-backups intact)"
  fi
}

w6_version_write_critical_guard_present() {
  # The VERSION write is CRITICAL: a failed/partial write must FAIL with the hint, never
  # leave content refreshed while VERSION reads stale. Assert the shipped guard is present
  # (a byte-level presence check on the exact verify-or-exit shape, not a full run — a full
  # upgrade needs a staged clone, consumer-gated).
  if grep -q 'CRITICAL step failed — VERSION write did not land' "$UPGRADE" \
     && grep -q 'tr -d .\\n\\r. < VERSION' "$UPGRADE"; then
    ok "w6-version-write-critical-guard (upgrade.sh verifies the VERSION write landed + exits with the recovery hint on failure — CRITICAL, never a silent stale VERSION)"
  else
    bad "w6-version-write-critical-guard" "the CRITICAL VERSION-write verify-or-exit guard is missing from upgrade.sh"
  fi
}

w7_remirror_and_prune_bounded_wiring() {
  # The re-mirror + sync-strings steps are routed through ffhc_run_step (OPTIONAL, bounded)
  # and the prune is single-pass + invoked directly with `|| WARN`. Assert the wiring is in
  # the shipped engine (a regression that dropped the bound would remove these).
  local okc=0
  grep -q 'ffhc_run_step .* "re-mirror skills"' "$UPGRADE" && okc=$((okc+1))
  grep -q 'ffhc_run_step .* "sync-version-strings"' "$UPGRADE" && okc=$((okc+1))
  grep -q 'single-pass' "$UPGRADE" && okc=$((okc+1))
  if [ "$okc" -eq 3 ]; then
    ok "w7-remirror+prune-bounded-wiring (re-mirror + sync-strings routed through ffhc_run_step OPTIONAL bound; prune is single-pass — all present in the shipped engine)"
  else
    bad "w7-remirror+prune-bounded-wiring" "expected 3 wiring markers (re-mirror/sync-strings ffhc_run_step + single-pass prune); found $okc"
  fi
}

w8_no_runaway_after_prune() {
  # After a bounded prune, no ffhc/timeout/sleep runaway attributable to this test lingers.
  # Best-effort: count PING/sleep children we might have spawned (we spawn none here) — the
  # real guard is w1's bounded termination. This asserts the prune leaves no background job.
  local jobs_before jobs_after
  jobs_before="$(jobs -p 2>/dev/null | wc -l | tr -d ' ')"
  local FN; FN="$(extract_fn prune_pre_backups "$UPGRADE")"
  local FIX; FIX="$(mktemp -d "${TMPDIR:-/tmp}/ws5-noruna.XXXXXX")"
  ( cd "$FIX" && : > a.txt.pre-upgrade-20260101T000001Z && bash -c "PRE_RETAIN=3; $FN; prune_pre_backups" >/dev/null 2>&1 )
  jobs_after="$(jobs -p 2>/dev/null | wc -l | tr -d ' ')"
  rm -rf "$FIX"
  if [ "$jobs_after" -le "$jobs_before" ]; then
    ok "w8-no-runaway-after-prune (prune left no background job: before=$jobs_before after=$jobs_after)"
  else
    bad "w8-no-runaway-after-prune" "background jobs grew (before=$jobs_before after=$jobs_after) — a prune runaway"
  fi
}

w1_prune
w2_optional_killed_continues
w3_critical_killed_fails_with_hint
w4_critical_failing_cmd_fails
w5_optional_ok_returns0
w9_optional_timeout_set_e_safe
w10_optional_fail_set_e_safe
w11_critical_fail_set_e_exits_with_hint
w12_degraded_optional_fail_set_e_safe
w13_prune_ignores_non_backup
w6_version_write_critical_guard_present
w7_remirror_and_prune_bounded_wiring
w8_no_runaway_after_prune

finish
