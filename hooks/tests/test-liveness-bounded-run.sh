#!/usr/bin/env bash
# Fusebase Flow — liveness-discipline bounded-run tests (FR-27).
# Spec: docs/specs/liveness-discipline/spec.md (AC3 a-e, AC4, AC6). Skill:
# flow-skills/liveness-discipline. Tooling: hooks/local/lib/bounded-run.sh.
#
# The load-bearing check (spec § Risks "attestation theatre / inert lever"): the
# bounded-run tooling must GENUINELY terminate a hang. AC3a/d run a real hanging /
# SIGTERM-ignoring child against a short deadline and assert the terminal timeout
# line + rc 124/137 — not a presence-of-a-signal check. Genuine, loud asserts.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: liveness <name>" / "FAIL: liveness <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
LIB="$ROOT/hooks/local/lib/bounded-run.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: liveness $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: liveness $1 (${2:-})"; }
finish() { echo "[test-liveness-bounded-run] $pass/$((pass + fail)) PASS"; exit $fail; }

# Loud precondition: a missing lib must FAIL, never false-green.
[ -f "$LIB" ] || { bad "setup-lib-present" "missing $LIB"; finish; }
ok "setup-lib-present"

# bash -n on the lib (syntax gate; a broken lib must not silently pass downstream).
if bash -n "$LIB" 2>/dev/null; then ok "lib-syntax-clean"; else bad "lib-syntax-clean" "bash -n failed"; fi

# Run a bounded_run call in a clean subshell; echo "RC=<rc>" + stderr (the wrapper
# logs heartbeats + the terminal line to stderr).
run_bounded() { # run_bounded <env-assignments> <deadline> <label> -- <cmd...> ; prints stderr then RC=<rc>
  local env_assign="$1"; shift
  local out rc
  out="$(env $env_assign bash -c '
    source "'"$LIB"'"
    bounded_run "$@"
  ' _ "$@" 2>&1 >/dev/null)"
  # Re-run capturing rc separately (stderr already captured above for assertions).
  env $env_assign bash -c 'source "'"$LIB"'"; bounded_run "$@" >/dev/null 2>&1' _ "$@"; rc=$?
  printf '%s\nRC=%s\n' "$out" "$rc"
}

###############################################################################
# AC3a — a deliberately-hanging command terminates with a timeout line within the
# deadline (rc 124 or 137). The silent-unbounded-wait is structurally bounded.
###############################################################################
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  start=$(date +%s)
  a_out="$(run_bounded "BOUNDED_RUN_HEARTBEAT_SECS=1" 2 "hang probe" -- sleep 30)"
  end=$(date +%s); span=$((end - start))
  a_rc="$(echo "$a_out" | sed -n 's/^RC=//p' | tail -1)"
  # rc must be timeout-induced (124 deadline, or 137 SIGKILL after -k grace).
  if [ "$a_rc" = "124" ] || [ "$a_rc" = "137" ]; then ok "ac3a-hang-rc-124-or-137"; else bad "ac3a-hang-rc-124-or-137" "rc=$a_rc (sleep 30 not bounded!)"; fi
  # Terminal timeout line present (the job reached death, not a silent idle).
  echo "$a_out" | grep -q "bounded-run: TIMEOUT" && ok "ac3a-terminal-timeout-line" || bad "ac3a-terminal-timeout-line" "no terminal TIMEOUT line: $a_out"
  # Bounded within a sane window (deadline 2s + the -k grace 5s + heartbeat-cap slack).
  if [ "$span" -le 20 ]; then ok "ac3a-bounded-within-deadline"; else bad "ac3a-bounded-within-deadline" "took ${span}s (deadline was 2s)"; fi
  ###############################################################################
  # AC3b — incremental progress is emitted (heartbeat line) while CMD runs.
  ###############################################################################
  echo "$a_out" | grep -q "bounded-run: still running" && ok "ac3b-incremental-progress" || bad "ac3b-incremental-progress" "no heartbeat line in: $a_out"
  ###############################################################################
  # AC3d — an ignored-SIGTERM child is still killed by run_with_timeout's -k
  # SIGKILL grace => rc 137. The child traps TERM and keeps sleeping.
  ###############################################################################
  d_out="$(run_bounded "FFHC_TIMEOUT_KILL_GRACE=1s BOUNDED_RUN_HEARTBEAT_SECS=10" 1 "stubborn child" -- bash -c 'trap "" TERM; sleep 30')"
  d_rc="$(echo "$d_out" | sed -n 's/^RC=//p' | tail -1)"
  if [ "$d_rc" = "137" ]; then ok "ac3d-ignored-sigterm-sigkilled"; else bad "ac3d-ignored-sigterm-sigkilled" "rc=$d_rc (expected 137 — the -k SIGKILL grace did not fire)"; fi
else
  # No timeout binary on this host: AC3a/b/d cannot run the bounded path. Record a
  # visible SKIP (not a silent pass) — but AC3c below STILL asserts the degrade
  # policy, which is exactly the no-binary case.
  echo "PASS: liveness ac3a-skipped-no-timeout-binary (host lacks timeout/gtimeout; AC3c covers degrade)"; pass=$((pass + 1))
fi

###############################################################################
# AC3c — no-timeout-binary path degrades per the skip policy (NOT a false
# "bounded"): the wrapper SKIPs (sentinel rc 125), the command does NOT run, and
# a marker file proves non-execution. Forced via FFHC_FORCE_NO_TIMEOUT=1.
###############################################################################
MARK="${TMPDIR:-/tmp}/fusebase-flow-liveness-mark.$$"
rm -f "$MARK"
c_out="$(run_bounded "FFHC_FORCE_NO_TIMEOUT=1" 2 "degrade" -- touch "$MARK")"
c_rc="$(echo "$c_out" | sed -n 's/^RC=//p' | tail -1)"
if [ "$c_rc" = "125" ]; then ok "ac3c-no-binary-skip-rc-125"; else bad "ac3c-no-binary-skip-rc-125" "rc=$c_rc (expected 125 sentinel)"; fi
# The command MUST NOT have run (no false "bounded" that silently executes unbounded).
if [ ! -e "$MARK" ]; then ok "ac3c-no-binary-command-not-run"; else bad "ac3c-no-binary-command-not-run" "command ran despite no-binary skip (false bounded!)"; rm -f "$MARK"; fi
echo "$c_out" | grep -q "bounded-run: SKIPPED" && ok "ac3c-skip-marker-line" || bad "ac3c-skip-marker-line" "no SKIPPED line: $c_out"

###############################################################################
# AC3e / AC6 — FFHC API intact + no regression: the existing health-check timeout
# suite (which sources run-with-timeout.sh and exercises the ffhc_* API) still
# passes. bounded-run.sh reuses that core; if it broke the API the suite fails.
###############################################################################
if [ -f "$ROOT/hooks/tests/test-health-check-timeout.sh" ]; then
  ht_out="$(bash "$ROOT/hooks/tests/test-health-check-timeout.sh" 2>&1)"; ht_rc=$?
  ht_failed="$(echo "$ht_out" | grep -c '^FAIL: health-check-timeout')"
  if [ "$ht_rc" -eq 0 ] && [ "$ht_failed" -eq 0 ]; then
    ok "ac6-health-check-timeout-no-regression"
  else
    bad "ac6-health-check-timeout-no-regression" "health-check timeout suite failed ($ht_failed FAIL, rc $ht_rc) — ffhc_* API regressed?"
  fi
else
  bad "ac6-health-check-timeout-no-regression" "test-health-check-timeout.sh missing (cannot prove AC6)"
fi
# Direct FFHC API surface check: sourcing run-with-timeout.sh still defines the
# functions the health-check engine calls directly (the API contract, FR-07).
api_check="$(bash -c '
  source "'"$ROOT"'/hooks/local/lib/run-with-timeout.sh"
  for fn in ffhc_detect_timeout ffhc_timed_out run_with_timeout ffhc_run_bounded \
            ffhc_run_tests_pass_ok ffhc_count_pass_lines ffhc_select_pass_line \
            ffhc_pass_line_broken_msg; do
    type "$fn" >/dev/null 2>&1 || { echo "MISSING:$fn"; exit 1; }
  done
  echo OK
' 2>&1)"
[ "$api_check" = "OK" ] && ok "ac6-ffhc-api-functions-present" || bad "ac6-ffhc-api-functions-present" "$api_check"

###############################################################################
# AC4 — the implement-handoff template carries the liveness clause in the
# Role-bootstrap HARD-INVARIANTS, not only the Tracks section. Assert the FR-27
# clause appears in the "Hard invariants" paragraph (the prose between that bold
# label and the next "## " or "**Refusal" boundary), and ALSO guard against a
# false-pass where it ONLY lives in the Tracks section.
###############################################################################
IMPL="$ROOT/templates/handoff-implement.md"
if [ -f "$IMPL" ]; then
  # Extract the Hard-invariants region: the paragraph starting at "**Hard invariants**"
  # up to the next blank-line-delimited "---" separator (the role-bootstrap block).
  hard_region="$(awk '/\*\*Hard invariants\*\*/{f=1} f{print} /^## Mandatory pre-execution reads/{f=0}' "$IMPL")"
  if echo "$hard_region" | grep -qi "FR-27" && echo "$hard_region" | grep -qi "liveness"; then
    ok "ac4-liveness-in-hard-invariants"
  else
    bad "ac4-liveness-in-hard-invariants" "FR-27/liveness clause absent from the Role-bootstrap Hard-invariants region"
  fi
  # Bite-check: the assertion is meaningful only if the Hard-invariants region was
  # actually extracted (non-empty) and is NOT the whole file (which would let a
  # Tracks-only mention pass). The region must be smaller than the full file.
  full_lines="$(wc -l < "$IMPL")"; region_lines="$(echo "$hard_region" | wc -l)"
  if [ -n "$hard_region" ] && [ "$region_lines" -lt "$full_lines" ]; then
    ok "ac4-hard-region-bounded"
  else
    bad "ac4-hard-region-bounded" "Hard-invariants region empty or unbounded (extraction wrong; assertion would not bite)"
  fi
else
  bad "ac4-liveness-in-hard-invariants" "templates/handoff-implement.md missing"
fi

finish
