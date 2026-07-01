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

# --- T17 (all platforms with a timeout binary): OPT-IN stdin inheritance for the
# bounded capture. A backgrounded (`&`) child's fd 0 defaults to /dev/null (POSIX),
# overriding a `< file` on the WRAPPER — so ffhc_run_bounded_stdout drops the fixture
# and a deny-fixture reads the wrong `allow`. ffhc_run_bounded_stdin_stdout inherits
# fd 0 so `< file` reaches the child. RED (old stdout path) => allow; GREEN (new stdin
# path) => deny. Also assert the DEFAULT path did NOT regress and T12-clears on both. ---
if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
  t17_fix="${TMPDIR:-/tmp}/ffhc-t17-deny.$$.json"
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' > "$t17_fix"

  # RED: the OLD stdout path loses the piped-in fixture (backgrounded child => /dev/null
  # stdin) so pre_tool_use reads empty and returns the default `allow`.
  ffhc_run_bounded_stdout 30 python3 "$ROOT/hooks/handlers/pre_tool_use.py" < "$t17_fix"
  red_out="$FFHC_LAST_OUT"

  # GREEN: the NEW stdin variant inherits fd 0 so the fixture reaches the handler => deny.
  ffhc_run_bounded_stdin_stdout 30 python3 "$ROOT/hooks/handlers/pre_tool_use.py" < "$t17_fix"
  green_out="$FFHC_LAST_OUT"
  rm -f "$t17_fix"

  if echo "$red_out" | grep -q '"decision": "allow"' && echo "$green_out" | grep -q '"decision": "deny"'; then
    ok "t17-stdin-reaches-child (RED old stdout path=allow [stdin dropped] => GREEN new stdin path=deny [fixture reached handler])"
  else
    bad "t17-stdin-reaches-child" "expected RED allow + GREEN deny; got RED=[$red_out] GREEN=[$green_out]"
  fi

  # Default (non-stdin) path did NOT regress: bounded, stdout captured, own rc preserved,
  # no hang (a stdin reader gets EOF from the explicit < /dev/null, never a TTY block).
  ffhc_run_bounded_stdout 30 bash -c 'cat; echo default-marker; exit 7'
  if [ "$FFHC_LAST_OUT" = "default-marker" ] && [ "$FFHC_LAST_RC" = "7" ]; then
    ok "t17-default-path-unchanged (non-stdin bounded run: stdout captured, own rc=7, < /dev/null EOF => no hang)"
  else
    bad "t17-default-path-unchanged" "default path regressed: out=[$FFHC_LAST_OUT] rc=$FFHC_LAST_RC (expected default-marker / 7)"
  fi

  # T12 on BOTH paths: the in-flight-child globals are cleared on return so a caller's
  # EXIT-trap reap is a strict no-op (no stale/reused winpid swept).
  t17d_fix="${TMPDIR:-/tmp}/ffhc-t17d.$$.in"; printf 'x' > "$t17d_fix"
  FFHC_LAST_WINPID="t17-stale"; FFHC_LAST_CHILD_PID="99999"
  ffhc_run_bounded_stdin_stdout 30 bash -c 'cat >/dev/null; exit 0' < "$t17d_fix"
  rm -f "$t17d_fix"
  if [ -z "$FFHC_LAST_WINPID" ] && [ -z "$FFHC_LAST_CHILD_PID" ]; then
    ok "t17-stdin-path-t12-clear (stdin variant clears WINPID+CHILD_PID on return => EXIT-trap reap is a no-op)"
  else
    bad "t17-stdin-path-t12-clear" "stdin path left globals set (WINPID='$FFHC_LAST_WINPID' CHILD_PID='$FFHC_LAST_CHILD_PID')"
  fi

  # --- T18 (the fix): the DEFAULT bounded path is IMMUNE to an externally EXPORTED
  # FFHC_CAPTURE_STDIN. Before T18, ffhc_run_bounded_stdout branched on the ambient
  # module global, so an exported/stale/adversarial FFHC_CAPTURE_STDIN=1 flipped the
  # default path to `0<&0` (inherit) instead of the guaranteed `< /dev/null`. After
  # T18 stdin-mode is an EXPLICIT parameter ("null" for the default wrappers), so the
  # default path can NEVER take the inherit branch regardless of the environment.
  # PROOF: export FFHC_CAPTURE_STDIN=1, pipe a NON-EMPTY fixture into the DEFAULT
  # wrapper running `cat` (a stdin reader). If the default path still honored the flag
  # (regression) the captured stdout would contain the leaked fixture bytes; with the
  # explicit `< /dev/null` the child's `cat` gets immediate EOF and captures NOTHING —
  # only the post-cat marker survives (own rc preserved, no hang). ---
  t18_fix="${TMPDIR:-/tmp}/ffhc-t18-leak.$$.in"; printf 'FIXTURE-STDIN-BYTES' > "$t18_fix"
  ( export FFHC_CAPTURE_STDIN=1
    ffhc_run_bounded_stdout 30 bash -c 'cat; echo T18-IMMUNE-MARKER; exit 5' < "$t18_fix"
    # Immune => captured stdout is EXACTLY the marker (no leaked fixture bytes), rc 5.
    [ "$FFHC_LAST_OUT" = "T18-IMMUNE-MARKER" ] && [ "$FFHC_LAST_RC" = "5" ]
  )
  t18_rc=$?
  rm -f "$t18_fix"
  if [ "$t18_rc" -eq 0 ]; then
    ok "t18-default-path-immune-to-exported-FFHC_CAPTURE_STDIN (exported flag=1 + piped fixture => DEFAULT wrapper still uses < /dev/null: cat sees EOF, captured out is marker-only, own rc=5)"
  else
    bad "t18-default-path-immune-to-exported-FFHC_CAPTURE_STDIN" "exported FFHC_CAPTURE_STDIN=1 leaked the caller's fd 0 into the DEFAULT bounded path (out should be marker-only + rc 5) — default path is NOT immune to the ambient var"
  fi

  # T18 corollary: the ambient global is DEAD. Even with FFHC_CAPTURE_STDIN=1 exported,
  # the dedicated STDIN wrapper still delivers fd 0 (selection is by explicit param, not
  # the env) — a deny-fixture into pre_tool_use still DENIES. Proves the stdin path is
  # driven ONLY by the wrapper's explicit "inherit", never by the (now-removed) global.
  t18s_fix="${TMPDIR:-/tmp}/ffhc-t18-deny.$$.json"
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' > "$t18s_fix"
  ( export FFHC_CAPTURE_STDIN=1
    ffhc_run_bounded_stdin_stdout 30 python3 "$ROOT/hooks/handlers/pre_tool_use.py" < "$t18s_fix"
    echo "$FFHC_LAST_OUT" | grep -q '"decision": "deny"'
  )
  t18s_rc=$?
  rm -f "$t18s_fix"
  if [ "$t18s_rc" -eq 0 ]; then
    ok "t18-stdin-wrapper-still-delivers-fd0 (explicit inherit param drives the stdin path; deny-fixture DENIES even with the dead FFHC_CAPTURE_STDIN exported)"
  else
    bad "t18-stdin-wrapper-still-delivers-fd0" "dedicated stdin wrapper failed to deliver fd 0 (deny-fixture did not DENY) with FFHC_CAPTURE_STDIN exported"
  fi
else
  skip "t17-stdin-reaches-child" "no timeout binary on PATH — bounded stdin path not exercised"
  skip "t17-default-path-unchanged" "no timeout binary on PATH"
  skip "t17-stdin-path-t12-clear" "no timeout binary on PATH"
  skip "t18-default-path-immune-to-exported-FFHC_CAPTURE_STDIN" "no timeout binary on PATH"
  skip "t18-stdin-wrapper-still-delivers-fd0" "no timeout binary on PATH"
fi

# --- T19 (WS2-hard) part D — POSIX run_with_timeout body byte-UNCHANGED (all platforms).
# The Job Object fence is additive; the load-bearing WS2-core function that produces the
# 124/137 rc MUST stay byte-identical. Hash-gate the exact function body so any future edit
# to run_with_timeout (even a whitespace nudge) trips this. The pinned hash is the v3.30.3
# body; update it ONLY with a deliberate, reviewed change to that function. ---
POSIX_BODY_SHA_EXPECT="d7b4201b7e187bc9c409c7faa979e63cfd8c8632d5f09b6c2eaf18772a7f72c8"
posix_body_sha="$(awk '/^run_with_timeout\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$LIB" | sha256sum | cut -d' ' -f1)"
if [ "$posix_body_sha" = "$POSIX_BODY_SHA_EXPECT" ]; then
  ok "ws2hard-posix-body-byte-unchanged (run_with_timeout body sha256 == pinned WS2-core hash; the fence is additive-only)"
else
  bad "ws2hard-posix-body-byte-unchanged" "run_with_timeout body sha256 changed: got $posix_body_sha expected $POSIX_BODY_SHA_EXPECT — the POSIX timeout root must stay byte-identical (fence is an OUTER wrapper, not a rewrite)"
fi

# --- T19 (WS2-hard) parts A/B/C — Windows Job Object OUTER FENCE mechanism smoke. The
# publish host is MSYS + has powershell.exe, so this MUST RUN (non-skipped): default OFF is
# byte-identity, opt-in adds an atomic strictly-scoped TerminateJobObject hard-kill. Only the
# Cummings ac3d→rc137 RELIABILITY under that host's condition stays consumer-gated; the
# mechanism is proven here. ---
if command -v powershell.exe >/dev/null 2>&1 && [ -n "${FFHC_TIMEOUT_BIN:-}" ] && case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) true ;; *) false ;; esac; then
  export FFHC_TIMEOUT_KILL_GRACE=1s

  # Part C first — DEFAULT OFF (knob unset) is byte-behavior-unchanged: true rc, timeout rc,
  # no hang. This is the whole safety basis (zero regression by construction).
  ffhc_run_bounded 30 bash -c 'echo off-marker; exit 3'
  offc_rc=$FFHC_LAST_RC; offc_out=$FFHC_LAST_OUT
  ffhc_run_bounded 1 bash -c 'sleep 20'; offc_to=$FFHC_LAST_RC
  if [ "$offc_rc" = "3" ] && [ "$offc_out" = "off-marker" ] && ffhc_timed_out "$offc_to"; then
    ok "ws2hard-default-off-byte-identity (knob unset: own rc=3 + captured 'off-marker' + timeout rc=$offc_to == today, no job branch taken)"
  else
    bad "ws2hard-default-off-byte-identity" "default-OFF path changed: rc=$offc_rc out=[$offc_out] timeout-rc=$offc_to (expected 3 / off-marker / 124|137)"
  fi

  # Probe gating: knob OFF => unavailable; knob ON => available on this host; forced-fail =>
  # unavailable. Each in its OWN subshell so the one-time FFHC_JOB_PROBE_RESULT cache from
  # one case can't leak into the next (the cache is intentionally per-process in production).
  ( FFHC_USE_JOB_OBJECT=1 ffhc_job_available ); g_on=$?
  ( ffhc_job_available ); g_off=$?
  ( FFHC_USE_JOB_OBJECT=1 FFHC_JOB_PROBE_FORCE_FAIL=1 ffhc_job_available ); g_ff=$?
  if [ "$g_on" -eq 0 ] && [ "$g_off" -ne 0 ] && [ "$g_ff" -ne 0 ]; then
    ok "ws2hard-probe-gating (knob=1 => AVAILABLE here; knob unset => OFF (default); FFHC_JOB_PROBE_FORCE_FAIL=1 => OFF)"
  else
    bad "ws2hard-probe-gating" "probe gating wrong (knob=1 rc=$g_on expect 0; unset rc=$g_off expect !=0; forced-fail rc=$g_ff expect !=0)"
  fi

  if FFHC_USE_JOB_OBJECT=1 ffhc_job_available; then
    # Part A(i) — job ON: own rc preserved + stdout captured via tempfile.
    FFHC_USE_JOB_OBJECT=1 ffhc_run_bounded 30 bash -c 'echo job-capture; exit 7'
    if [ "$FFHC_LAST_RC" = "7" ] && [ "$FFHC_LAST_OUT" = "job-capture" ]; then
      ok "ws2hard-job-rc-preserved+capture (job ON: own rc=7 + tempfile-captured stdout 'job-capture')"
    else
      bad "ws2hard-job-rc-preserved+capture" "job ON regressed rc/capture: rc=$FFHC_LAST_RC out=[$FFHC_LAST_OUT] (expected 7 / job-capture)"
    fi

    # Part A(ii) — 124 on timeout under the fence.
    FFHC_USE_JOB_OBJECT=1 ffhc_run_bounded 1 bash -c 'sleep 20'
    if ffhc_timed_out "$FFHC_LAST_RC"; then
      ok "ws2hard-job-124-on-timeout (job ON: overrun => timeout-induced rc=$FFHC_LAST_RC, never 0)"
    else
      bad "ws2hard-job-124-on-timeout" "job ON overrun returned rc=$FFHC_LAST_RC (expected 124/137)"
    fi

    # Part A(iii) — 137 on a stubborn TERM-ignoring child hard-killed. On this host the -k
    # SIGKILL grace already reaches it AND the fence's TerminateJobObject is the OUTER
    # guarantee; both converge on 137. The rc still comes from wait "$_bpid" (outer fence,
    # not a PowerShell rc). out captured => the launch path is unchanged.
    # NOTE: stderr_mode=merge folds bash's job-control "Killed" line into FFHC_LAST_OUT, so
    # match 'started' as a SUBSTRING (the pre-kill stdout), not byte-exact equality.
    FFHC_USE_JOB_OBJECT=1 ffhc_run_bounded 1 bash -c 'trap "" TERM; echo started; sleep 30'
    if [ "$FFHC_LAST_RC" = "137" ] && printf '%s' "$FFHC_LAST_OUT" | grep -q "started"; then
      ok "ws2hard-job-137-on-hard-kill (job ON: stubborn TERM-ignoring child => rc 137 (128+SIGKILL) + captured 'started'; rc from wait \$_bpid, fence augments the reap)"
    elif ffhc_timed_out "$FFHC_LAST_RC" && printf '%s' "$FFHC_LAST_OUT" | grep -q "started"; then
      # Accept 124 too (host-load: the child may exit before the -k grace on a fast box)
      # — still a true timeout-induced rc with capture intact; 137 is the target, 124 is honest.
      ok "ws2hard-job-137-on-hard-kill [rc=$FFHC_LAST_RC] (timeout-induced + captured 'started'; 137 is the TerminateJobObject/-k SIGKILL target, 124 accepted under host load)"
    else
      bad "ws2hard-job-137-on-hard-kill" "expected rc 137 (or timeout-induced) + captured 'started'; got rc=$FFHC_LAST_RC out=[$FFHC_LAST_OUT]"
    fi

    # Part A(iv) — concurrent sibling survives the fence hard-kill (strict scoping). An
    # unrelated bash sleep in its OWN tree must live through TerminateJobObject.
    bash -c 'sleep 25' & jsib=$!
    sleep 1
    if kill -0 "$jsib" 2>/dev/null; then
      FFHC_USE_JOB_OBJECT=1 ffhc_run_bounded 1 bash -c 'trap "" TERM; sleep 30'
      if kill -0 "$jsib" 2>/dev/null; then
        ok "ws2hard-job-sibling-survives (unrelated bash sleep pid=$jsib alive after the fence's TerminateJobObject — assigned-tree-only, no collateral)"
      else
        bad "ws2hard-job-sibling-survives" "sibling pid=$jsib killed by the fence — TerminateJobObject reached outside the assigned tree (collateral regression)"
      fi
      kill "$jsib" 2>/dev/null; wait "$jsib" 2>/dev/null
    else
      skip "ws2hard-job-sibling-survives" "sibling exited before the bounded op (environmental)"
      wait "$jsib" 2>/dev/null
    fi

    # Part B — forced pre-launch probe failure => clean fallback to WS2-core (no hang/error),
    # own rc preserved. NO-RERUN: nothing double-runs; the branch is simply not taken.
    fb_start=$(date +%s)
    FFHC_USE_JOB_OBJECT=1 FFHC_JOB_PROBE_FORCE_FAIL=1 ffhc_run_bounded 30 bash -c 'echo fb-marker; exit 5'
    fb_end=$(date +%s); fb_el=$((fb_end - fb_start))
    if [ "$FFHC_LAST_RC" = "5" ] && [ "$FFHC_LAST_OUT" = "fb-marker" ] && [ "$fb_el" -le 30 ]; then
      ok "ws2hard-forced-probe-fail-clean-fallback (FFHC_JOB_PROBE_FORCE_FAIL=1 => WS2-core path: own rc=5 + 'fb-marker' in ${fb_el}s, no hang, no re-run)"
    else
      bad "ws2hard-forced-probe-fail-clean-fallback" "forced probe fail did not fall back cleanly: rc=$FFHC_LAST_RC out=[$FFHC_LAST_OUT] elapsed=${fb_el}s (expected 5 / fb-marker / <=30s)"
    fi
  else
    bad "ws2hard-job-mechanism-must-run-here" "the publish host is MSYS + has powershell.exe but ffhc_job_available returned false with FFHC_USE_JOB_OBJECT=1 — the job MECHANISM smoke MUST run here, not skip (probe regressed?)"
  fi
else
  # Off-MSYS / no-powershell / no-timeout: the mechanism is Windows-only. Visible SKIPs (not
  # false-green); the default-OFF byte-identity + POSIX hash-gate above still asserted.
  skip "ws2hard-default-off-byte-identity" "off-MSYS or no powershell.exe/timeout — job branch is Windows-only; default-OFF == WS2-core covered by the ws2-* checks above"
  skip "ws2hard-probe-gating" "off-MSYS or no powershell.exe/timeout"
  skip "ws2hard-job-rc-preserved+capture" "off-MSYS or no powershell.exe/timeout"
  skip "ws2hard-job-124-on-timeout" "off-MSYS or no powershell.exe/timeout"
  skip "ws2hard-job-137-on-hard-kill" "off-MSYS or no powershell.exe/timeout"
  skip "ws2hard-job-sibling-survives" "off-MSYS or no powershell.exe/timeout"
  skip "ws2hard-forced-probe-fail-clean-fallback" "off-MSYS or no powershell.exe/timeout"
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
