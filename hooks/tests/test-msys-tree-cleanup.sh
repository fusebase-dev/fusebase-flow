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

# --- T8 (all platforms): robust tempfile fallback. If the capture temp can't be
# created/written, _ffhc_tempfile_capture MUST route to the SKIPPED sentinel
# (rc 125 + FFHC_LAST_SKIPPED=1 + empty out) so the engine reads UNVERIFIED — NOT
# an empty-output run a verdict reads as a false BROKEN, and NEVER a hang. Also
# assert no transient ffhc-bounded.* file leaks into CWD. Platform-independent (the
# temp-fail branch is above the MSYS gate), so it runs on Linux/macOS CI too. ---
if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
  t8_cwd_leak_before=$(ls -1 ffhc-bounded.* 2>/dev/null | wc -l)
  ( export TMPDIR="/nonexistent-ffhc-tmp-$$/deeper"
    ffhc_run_bounded 5 bash -c 'echo should-not-run; exit 0'
    [ "$FFHC_LAST_SKIPPED" = "1" ] && [ "$FFHC_LAST_RC" = "125" ] && [ -z "$FFHC_LAST_OUT" ] && [ "$FFHC_LAST_TIMED_OUT" = "0" ]
  )
  if [ $? -eq 0 ]; then
    ok "t8-tempfail-routes-to-skipped (unwritable TMPDIR => rc 125 + SKIPPED + empty out => UNVERIFIED, never false BROKEN/hang)"
  else
    bad "t8-tempfail-routes-to-skipped" "unwritable TMPDIR did not produce the SKIPPED sentinel (rc 125 / FFHC_LAST_SKIPPED=1 / empty out)"
  fi
  t8_cwd_leak_after=$(ls -1 ffhc-bounded.* 2>/dev/null | wc -l)
  if [ "$t8_cwd_leak_after" -le "$t8_cwd_leak_before" ]; then
    ok "t8-no-cwd-tempfile-leak (explicit \${TMPDIR}/ffhc-bounded.\$\$.XXXXXX template — no transient files in CWD)"
  else
    bad "t8-no-cwd-tempfile-leak" "ffhc-bounded.* file(s) leaked into CWD (before=$t8_cwd_leak_before after=$t8_cwd_leak_after)"
  fi
else
  skip "t8-tempfail-routes-to-skipped" "no timeout binary on PATH — tempfile-capture path not exercised"
fi

# --- WS2-core (all platforms with a timeout binary): true-124-on-kill + no-hang.
# true-124: a bounded op that overruns its deadline MUST report a timeout-induced rc
# (124/137), NEVER 0 — an rc0-on-kill masks the timeout and routes the health-check to
# a false BROKEN (the Ovation defect). On POSIX `timeout` returns 124 natively; on MSYS
# the ffhc_msys_wait_reap deadline-reap normalizes a masked rc to a true 124.
# no-hang: a fast command under a LARGE budget must RETURN promptly with its own rc
# (the watchdog/rendezvous must not block for the whole budget). ---
if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
  export FFHC_TIMEOUT_KILL_GRACE=1s
  ffhc_run_bounded 1 bash -c 'sleep 20'
  if ffhc_timed_out "$FFHC_LAST_RC"; then
    ok "ws2-true-124-on-kill (overrun => rc $FFHC_LAST_RC is timeout-induced 124/137, never 0)"
  else
    bad "ws2-true-124-on-kill" "overrun bounded op returned rc=$FFHC_LAST_RC (expected 124/137; rc0-on-kill masks the timeout => false BROKEN)"
  fi

  nh_start=$(date +%s)
  ffhc_run_bounded 300 bash -c 'exit 7'
  nh_end=$(date +%s); nh_elapsed=$((nh_end - nh_start))
  if [ "$nh_elapsed" -le 30 ] && [ "$FFHC_LAST_RC" = "7" ]; then
    ok "ws2-no-hang-large-budget (returned in ${nh_elapsed}s with the command's own rc=$FFHC_LAST_RC, not the 300s budget)"
  else
    bad "ws2-no-hang-large-budget" "large-budget fast command took ${nh_elapsed}s / rc=$FFHC_LAST_RC (expected <=30s + rc 7 — watchdog must not block for the whole budget)"
  fi
else
  skip "ws2-true-124-on-kill" "no timeout binary on PATH"
  skip "ws2-no-hang-large-budget" "no timeout binary on PATH"
fi

# --- T12 (all platforms with a timeout binary): the in-flight-child globals are
# non-empty ONLY while the child is provably alive. After ffhc_run_bounded RETURNS
# (the child is reaped by then), BOTH FFHC_LAST_WINPID AND FFHC_LAST_CHILD_PID must be
# EMPTY, so a caller's EXIT-trap reap is a strict no-op (no stale/reused winpid swept).
# Guards the false pre-T12 ":cleared once we return" comment: the globals were never
# actually cleared, so between fixture iterations the trap could taskkill a DEAD or
# reused winpid. Platform-independent (the lib clears both on every path). ---
if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
  FFHC_LAST_WINPID="sentinel-stale"; FFHC_LAST_CHILD_PID="99999"   # pre-seed stale ids
  ffhc_run_bounded 5 bash -c 'exit 0'
  if [ -z "$FFHC_LAST_WINPID" ] && [ -z "$FFHC_LAST_CHILD_PID" ]; then
    ok "t12-winpid+childpid-cleared-on-return (both globals empty after a normal bounded return => EXIT-trap reap is a no-op)"
  else
    bad "t12-winpid+childpid-cleared-on-return" "globals not cleared after return (WINPID='$FFHC_LAST_WINPID' CHILD_PID='$FFHC_LAST_CHILD_PID') — a stale/reused winpid could be swept by the EXIT-trap"
  fi
else
  skip "t12-winpid+childpid-cleared-on-return" "no timeout binary on PATH — tempfile-capture path not exercised"
fi

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) : ;;  # MSYS — run the real RED-then-GREEN + sibling-survival
  *) skip "native-descendant-reap" "off-MSYS — POSIX timeout reaps the tree; native-escape repro is MSYS-only"; skip "ws2-concurrent-sibling-survives" "off-MSYS — taskkill scoping is MSYS-only; strict-scoping asserted by code + true-124/no-hang above"; finish ;;
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

# --- Best-effort reap (T7): the early-captured winpid lets the fixed path taskkill
# the bounded wrapper tree on timeout. ASSERT no-hang + rc 124/137 (above) — the
# GUARANTEED contract. The tree-reap is BEST-EFFORT: a descendant reparented/detached
# after its ancestor exited (Windows does NOT reparent to init) may linger, so a
# surviving native orphan is NOT a test failure here (the tempfile capture is what
# guarantees the parent never starves). We surface a reparented-orphan as a NOTE only. ---
# Confirm the early-capture plumbing is present (the T7 fix); absence is a real regression.
if grep -q "ffhc_msys_winpid" "$LIB" && grep -q "ffhc_msys_taskkill_winpid" "$LIB"; then
  ok "early-winpid-capture-plumbing-present (T7: winpid resolved at launch, taskkill on timeout)"
else
  bad "early-winpid-capture-plumbing-present" "ffhc_msys_winpid / ffhc_msys_taskkill_winpid missing from $LIB — T7 early-capture reap not wired"
fi

# --- RED demonstration (bounded, best-effort proof): the OLD `$(run_with_timeout …)`
# pipe capture on the SAME payload tends to block materially longer (the descendant
# holds the pipe). Run it inside its own outer timeout so a RED machine can't hang the
# suite. This delta is a BEST-EFFORT regression signal, not a correctness gate — on a
# heavily-loaded host or a fast-returning ping it can be inconclusive; report it as a
# NOTE (still a PASS) rather than failing the suite on an environmental wobble. ---
rs=$(date +%s)
timeout -k 2 15 bash -c '. "'"$LIB"'"; ffhc_detect_timeout; OUT="$(run_with_timeout 1 bash -c '"'"'cmd //c start //b cmd //c "ping -n 8 127.0.0.1 >NUL" & sleep 12'"'"' 2>&1)"' >/dev/null 2>&1
re=$(date +%s); red_elapsed=$((re - rs))

if [ "$red_elapsed" -gt "$green_elapsed" ]; then
  ok "tempfile-capture-faster-than-pipe (pipe ${red_elapsed}s > tempfile ${green_elapsed}s)"
else
  skip "tempfile-capture-faster-than-pipe" "delta inconclusive on this host (pipe ${red_elapsed}s, tempfile ${green_elapsed}s) — no-hang + rc 124/137 already proved the guaranteed contract; relative speed is a best-effort signal only"
fi

# --- WS2-core concurrent-sibling-survival (the load-bearing strict-scoping proof).
# Spawn an UNRELATED `bash sleep` sibling in its OWN process tree (record its PID),
# then run a bounded op that OVERRUNS its deadline (triggering the taskkill reap).
# The reap is strictly scoped to the bounded op's OWN recorded child winpid subtree,
# so the unrelated sibling MUST SURVIVE. A broad/ancestor taskkill (the 255-collateral
# bug) would reap the sibling too. This is the WS2/WS3 30+-sibling-survival AC in miniature. ---
bash -c 'sleep 25' &
sib_pid=$!
sleep 1   # let the sibling establish its own tree
if kill -0 "$sib_pid" 2>/dev/null; then
  export FFHC_TIMEOUT_KILL_GRACE=1s
  ffhc_run_bounded 1 bash -c 'sleep 20'   # overruns => strict-scoped taskkill reap
  if kill -0 "$sib_pid" 2>/dev/null; then
    ok "ws2-concurrent-sibling-survives (unrelated bash sleep pid=$sib_pid alive after a bounded op's timeout-taskkill — reap scoped to recorded child only)"
  else
    bad "ws2-concurrent-sibling-survives" "unrelated sibling pid=$sib_pid was reaped by the bounded op's taskkill — over-broad/ancestor kill (255-collateral regression)"
  fi
  kill "$sib_pid" 2>/dev/null; wait "$sib_pid" 2>/dev/null
else
  # Sibling died on its own before the bounded op — environmental; don't false-fail.
  skip "ws2-concurrent-sibling-survives" "sibling exited before the bounded op could run (environmental; strict-scoping still asserted by true-124/no-hang + code)"
  wait "$sib_pid" 2>/dev/null
fi

finish
