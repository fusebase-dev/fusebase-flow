#!/usr/bin/env bash
# Fusebase Flow — MSYS bounded-run tree-cleanup + tempfile-capture test (D-B1).
# Spec: docs/specs/secret-scan-and-msys-liveness-fix/spec.md (AC-B1).
#
# RED-then-GREEN (this is the load-bearing B-core proof). On MSYS/MINGW/CYGWIN a
# NATIVE descendant of a bounded command (spawned via `cmd //c start //b …`, a
# SHORT FINITE sleep) survives POSIX `timeout` cleanup and keeps the captured
# stdout pipe open, so the OLD `VAR=$(run_with_timeout …)` capture BLOCKS past the
# deadline (RED, ~native-sleep seconds). The fixed ffhc_run_bounded captures via a
# TEMP FILE and MSYS-reaps the tree, so it RETURNS at ~deadline+grace with rc 124
# (GREEN). Bounded by a SHORT finite native sleep so RED is late-but-finite, never
# an infinite suite hang. Off MSYS: visible SKIP (not false-green).
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: msys-tree-cleanup <name>" / "FAIL: msys-tree-cleanup <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS: msys-tree-cleanup $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: msys-tree-cleanup $1 (${2:-})"; }
skip() { echo "PASS: msys-tree-cleanup $1 [SKIP — $2]"; pass=$((pass + 1)); }
finish() { echo "[test-msys-tree-cleanup] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$LIB" ] || { bad "setup-lib-present" "missing $LIB"; finish; }
# shellcheck source=/dev/null
. "$LIB"
ffhc_detect_timeout

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) : ;;  # MSYS — run the real RED-then-GREEN
  *) skip "native-descendant-reap" "off-MSYS — POSIX timeout reaps the tree; native-escape repro is MSYS-only"; finish ;;
esac

if [ -z "${FFHC_TIMEOUT_BIN:-}" ]; then
  skip "native-descendant-reap" "no timeout binary on PATH"; finish
fi

# The native-descendant payload: a detached native process (`start //b`) holds a
# SHORT FINITE-sleep `ping`, plus a long bash `sleep` the bounded timeout must cut.
# Deadline 1s; grace 1s. If the capture honored only the direct child it would block
# on the native ping (~6-8s = the RED signal); the fix returns at ~deadline+grace.
PAYLOAD=(bash -c 'cmd //c start //b cmd //c "ping -n 8 127.0.0.1 >NUL" & sleep 12')
DEADLINE=1
export FFHC_TIMEOUT_KILL_GRACE=1s
GREEN_CEILING=6   # deadline + grace + epsilon (host-load slack); still under the ~8-10s native-ping RED block

# --- GREEN: the fixed ffhc_run_bounded (tempfile capture + MSYS tree-kill) ---
start=$(date +%s)
ffhc_run_bounded "$DEADLINE" "${PAYLOAD[@]}"
green_rc=$FFHC_LAST_RC
end=$(date +%s); green_elapsed=$((end - start))

if [ "$green_elapsed" -le "$GREEN_CEILING" ]; then
  ok "native-descendant-returns-at-deadline (${green_elapsed}s <= ${GREEN_CEILING}s)"
else
  bad "native-descendant-returns-at-deadline" "ffhc_run_bounded blocked ${green_elapsed}s past the ${DEADLINE}s deadline — the native descendant starved the capture (regression)"
fi

if ffhc_timed_out "$green_rc"; then
  ok "native-descendant-rc-preserved (rc=$green_rc is timeout-induced 124/137)"
else
  bad "native-descendant-rc-preserved" "expected timeout rc 124/137, got $green_rc"
fi

# --- RED demonstration (bounded): the OLD `$(run_with_timeout …)` pipe capture on
# the SAME payload blocks materially longer (the descendant holds the pipe). Run it
# inside its own outer timeout so a RED machine can't hang the suite, and assert the
# fixed path is strictly faster (the regression-proof delta). ---
rs=$(date +%s)
timeout -k 2 15 bash -c '. "'"$LIB"'"; ffhc_detect_timeout; OUT="$(run_with_timeout 1 bash -c '"'"'cmd //c start //b cmd //c "ping -n 8 127.0.0.1 >NUL" & sleep 12'"'"' 2>&1)"' >/dev/null 2>&1
re=$(date +%s); red_elapsed=$((re - rs))

if [ "$red_elapsed" -gt "$green_elapsed" ]; then
  ok "tempfile-capture-faster-than-pipe (pipe ${red_elapsed}s > tempfile ${green_elapsed}s)"
else
  # Non-fatal-to-correctness but the proof is weak; surface it loudly as a FAIL so a
  # silent environmental change (e.g. ping returning instantly) is investigated.
  bad "tempfile-capture-faster-than-pipe" "old pipe capture (${red_elapsed}s) was NOT slower than the fixed tempfile capture (${green_elapsed}s) — RED signal did not reproduce; check the native-descendant payload"
fi

finish
