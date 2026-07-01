#!/usr/bin/env bash
# Fusebase Flow — bounded-execution helper (sourced by the health-check engine).
#
# PROVENANCE:
#   Extracted from fusebase-flow-health-check.sh per FR-25 (module-size ratchet)
#   so the engine stays under the 800-line ceiling. Lives at hooks/local/lib/ —
#   outside the FuseBase CLI refresh manifest, so it survives `fusebase update`.
#
# PURPOSE:
#   Bound the engine's slow, verdict-affecting operations (preflight, run-tests,
#   conflict reporter, upstream git fetch) so a network-impaired or large-repo
#   host can't make the read-only diagnostic appear to hang.
#
# CONTRACT (relied on by the engine's verdict logic — do not change silently):
#   FFHC_TIMEOUT_BIN     — set by ffhc_detect_timeout: "timeout" | "gtimeout" | "" (none)
#   run_with_timeout SECS CMD...
#     rc 124  => the wrapped command timed out (the timeout binary's own signal rc)
#     rc 137  => the wrapped command ignored TERM and was SIGKILLed after the -k
#                grace (128+9) — also a timeout-induced kill
#     other   => the wrapped command's OWN rc, preserved (NOT squashed to 0/1)
#   ffhc_timed_out RC    => returns 0 (true) iff RC is timeout-induced (124 or 137)
#   ffhc_run_tests_pass_ok LINE  => 0 iff LINE is a strict clean "N/N PASS" summary
#                                   (counts [1-9][0-9]*, passed==total; rejects
#                                   leading-zero counts like 01/01 — Codex r3 A1)
#   ffhc_count_pass_lines OUT    => count of strict "N/N PASS" summary lines in OUT
#   ffhc_select_pass_line OUT    => echoes the SINGLE strict PASS summary line or ""
#                                   (empty unless EXACTLY one — NO tail -1; >=2 PASS
#                                   summaries are the ambiguous/duplicate spoof, r3 A2)
#   ffhc_pass_line_broken_msg RC OUT => LOCAL_BROKEN message for the empty-PASS case
#                                   (re-derives duplicate-vs-none from OUT; subshell-safe)

# Detect a usable timeout binary. GNU coreutils ships `timeout` (Linux, Git-Bash);
# macOS commonly ships only `gtimeout` (from coreutils via Homebrew). Sets the
# module-global FFHC_TIMEOUT_BIN to the binary name, or "" when neither exists.
# FFHC_FORCE_NO_TIMEOUT=1 forces the no-binary path (testability + an operator
# escape to exercise the degraded behavior on a host that does have timeout).
ffhc_detect_timeout() {
  if [ "${FFHC_FORCE_NO_TIMEOUT:-0}" = "1" ]; then
    FFHC_TIMEOUT_BIN=""
  elif command -v timeout >/dev/null 2>&1; then
    FFHC_TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    FFHC_TIMEOUT_BIN="gtimeout"
  else
    FFHC_TIMEOUT_BIN=""
  fi
}

# Timeout-induced rc: 124 = GNU-timeout's "duration elapsed"; 137 = 128+SIGKILL, the
# rc when `-k <grace>` SIGKILLs a child that ignored the initial TERM. Both must read
# as a timeout so a hung-then-SIGKILLed critical is UNVERIFIED, not a spurious other
# state. Accepted limitation: a wrapped command's OWN legit exit 124/137 (e.g. it
# self-SIGKILLs) is also treated as a timeout — acceptable for these read-only criticals.
ffhc_timed_out() {
  [ "${1:-}" = "124" ] || [ "${1:-}" = "137" ]
}

# run_with_timeout SECS CMD [ARGS...]
#   Runs CMD bounded to SECS via the detected timeout binary with a -k grace
#   window (a follow-up KILL if the command ignores the initial TERM). Returns
#   124 on timeout; otherwise the wrapped command's own exit code is preserved.
#   Caller MUST have run ffhc_detect_timeout and confirmed FFHC_TIMEOUT_BIN is
#   non-empty (no-binary handling is a verdict decision the engine owns, not this
#   helper — H5).
run_with_timeout() {
  local secs="$1"; shift
  local grace="${FFHC_TIMEOUT_KILL_GRACE:-5s}"
  "$FFHC_TIMEOUT_BIN" -k "$grace" "$secs" "$@"
}

# ffhc_is_msys: 0 (true) on Git-Bash/MSYS/Cygwin, where a NATIVE descendant of a
# bounded command survives POSIX `timeout` cleanup (D-B1). POSIX hosts reap fine.
ffhc_is_msys() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# ffhc_default_timeout KIND: echo the platform-appropriate default budget (seconds)
# for KIND in {preflight,tests} (WS4). Git-Bash/MSYS spawns each process in ~0.8-1.4s
# (vs ~1-3ms POSIX), so the flat 30/60 budgets time out a HEALTHY MSYS install under
# load => spurious PARTIAL_UNVERIFIED; MSYS gets 60/120, POSIX keeps 30/60. An
# explicit FFHC_*_TIMEOUT env value still wins (the engine applies it via ${VAR:-…}).
# fetch/conflict are platform-agnostic (network/git) — not gated here.
ffhc_default_timeout() {
  case "$1" in
    preflight) ffhc_is_msys && echo 60  || echo 30 ;;
    tests)     ffhc_is_msys && echo 120 || echo 60 ;;
    *) echo 30 ;;
  esac
}

# ffhc_msys_winpid PID: echo the Windows pid for a bash PID via /proc/<pid>/winpid,
# or "" if unresolved. TRIPWIRE: call this IMMEDIATELY after launch, while the proc
# is still ALIVE — /proc/<pid>/winpid vanishes the instant the proc exits, so a
# post-deadline read races the wrapper's own exit and usually reads empty (the T7
# defect). Capturing it early is the whole point.
ffhc_msys_winpid() {
  local pid="${1:-}"
  [ -n "$pid" ] || return 0
  cat "/proc/$pid/winpid" 2>/dev/null || true
}

# ffhc_msys_taskkill_winpid WINPID [CHILD_PID]: `taskkill //F //T` the recorded
# child's Windows pid tree (output suppressed). Graceful no-op: empty winpid or no
# taskkill => return 0, never error, never hang the bounded contract.
# TRIPWIRE (WS2-core strict scoping): //T reaps the WHOLE tree rooted at WINPID, so
# an ancestor/reused winpid would collateral-kill the caller/harness/other sessions
# (the observed 255-collateral). When CHILD_PID is given, re-verify at kill-time that
# /proc/<CHILD_PID>/winpid STILL equals the recorded WINPID (guards Windows PID reuse
# under churn) — if the child already exited (winpid unresolvable) or the mapping
# changed, SKIP the taskkill rather than risk collateral. NEVER kill an ancestor and
# NEVER a broad/lazy fallback on an unverifiable winpid.
ffhc_msys_taskkill_winpid() {
  local winpid="${1:-}" child_pid="${2:-}"
  [ -n "$winpid" ] || return 0
  command -v taskkill >/dev/null 2>&1 || return 0
  if [ -n "$child_pid" ]; then
    local now_winpid; now_winpid="$(ffhc_msys_winpid "$child_pid")"
    [ "$now_winpid" = "$winpid" ] || return 0   # PID reuse / child gone => skip, no collateral
  fi
  taskkill //F //T //PID "$winpid" >/dev/null 2>&1 || true
}

# ffhc_msys_tree_kill PID: MSYS-only Windows-native tree reap (lazy lookup). Resolves
# the bash PID's Windows pid via /proc/<pid>/winpid and `taskkill //F //T` its tree.
# TRIPWIRE: this lazy lookup is BEST-EFFORT only — if PID has already exited the
# winpid read returns empty and this no-ops; the early-captured winpid path
# (ffhc_msys_winpid at launch + ffhc_msys_taskkill_winpid on timeout) is the
# reliable reap. Kept for API/back-compat. Graceful fallback: absent winpid or
# taskkill => no-op (never errors, never hangs).
ffhc_msys_tree_kill() {
  ffhc_msys_taskkill_winpid "$(ffhc_msys_winpid "${1:-}")"
}

# ffhc_msys_wait_reap BPID SECS [WINPID]: MSYS-only wait that returns BPID's own rc
# (so 124/137 are preserved) while reaping its native descendant tree once the
# deadline passes. Polls at 1s; after SECS elapses it taskkill-tree-kills the bounded
# proc so a native runaway is reaped, then collects the rc. Capped at SECS+grace+eps
# so a stuck wait can never outlive the contract.
# WINPID (T7): the Windows pid captured at LAUNCH (while alive). When provided, the
# reap uses it directly AND re-verifies it still maps to BPID before killing (strict
# scoping — no ancestor/reused-pid collateral). BEST-EFFORT anti-runaway: it reaps the
# bounded wrapper's attributable tree even after the wrapper has exited. HONEST LIMIT:
# a descendant reparented/detached after its ancestor exited (Windows does NOT reparent
# to init) may still survive — the tempfile capture, NOT this kill, is the guaranteed
# anti-hang. Falls back to the lazy ffhc_msys_tree_kill when WINPID is empty.
# Returns a true 124 on a deadline-reap whose rc would otherwise mask the timeout.
# TRIGGER_FILE (WS2-hard, additive 4th param — empty for every WS2-core caller, so the
# default path is byte-behavior-unchanged): when set, the deadline reap ALSO touches it,
# signaling the Job Object fence helper to TerminateJobObject the assigned Win32 tree
# (an atomic strictly-scoped hard-kill that AUGMENTS the taskkill). The rc still comes
# from wait "$bpid" below (true 124/137), so the fence never changes the rc contract.
ffhc_msys_wait_reap() {
  local bpid="$1" secs="$2" winpid="${3:-}" trigger="${4:-}"
  local grace="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; local gsec="${grace%[!0-9]*}"
  case "$gsec" in ''|*[!0-9]*) gsec=5 ;; esac
  local cap=$(( secs + gsec + 2 )) waited=0 reaped=0
  # Strict scoping: pass bpid so the taskkill re-verifies the recorded winpid still
  # maps to OUR child before killing (no ancestor/reused-pid collateral). When a job
  # trigger is set, touch it first so the fence hard-kills the assigned tree atomically.
  _ffhc_reap() {
    [ -n "$trigger" ] && : > "$trigger" 2>/dev/null
    if [ -n "$winpid" ]; then ffhc_msys_taskkill_winpid "$winpid" "$bpid"; else ffhc_msys_tree_kill "$bpid"; fi
  }
  while kill -0 "$bpid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [ "$waited" -ge "$secs" ] && [ "$reaped" -eq 0 ]; then
      _ffhc_reap; reaped=1
    fi
    [ "$waited" -ge "$cap" ] && { _ffhc_reap; break; }
  done
  wait "$bpid"; local rc=$?
  # TRIPWIRE (WS2-core true-124-on-kill): when WE reaped at the deadline, an MSYS
  # taskkill can make `wait` return a non-timeout rc (0/other) instead of 124/137 —
  # that masks the timeout and routes the health-check to a false BROKEN (the
  # rc0-on-kill defect). Normalize a deadline-reap to a true 124 unless the child
  # already surfaced a genuine timeout-induced rc (124/137). Only fires when we
  # actually killed at the deadline (reaped=1), so a fast, self-completing command
  # keeps its own rc.
  if [ "$reaped" -eq 1 ] && ! ffhc_timed_out "$rc"; then rc=124; fi
  return "$rc"
}

# ============================================================================
# WS2-hard (v3.30.4) — Windows Job Object OUTER FENCE (DEFAULT OFF / opt-in).
#
# WHAT: an ADDITIVE hard-kill fence around the EXISTING bounded run. It does NOT
# reimplement `timeout` in PowerShell — the launch + rc (124/137) + tempfile
# capture + stdin semantics ALL stay in _ffhc_tempfile_capture / ffhc_msys_wait_reap
# below. The fence only ASSIGNS the already-launched child's winpid to a Windows
# Job Object (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE) so the deadline reap can add a
# TerminateJobObject — an ATOMIC, strictly-scoped kill of the assigned Win32 tree
# that can never reach the harness/caller/other session (a sibling survives). The
# rc still comes from `wait "$_bpid"`; the job kill AUGMENTS taskkill, never replaces
# the reap.
#
# DEFAULT OFF (load-bearing safety basis): FFHC_USE_JOB_OBJECT default 0 => the
# branch is INERT on every host, so the default path is byte-behavior-unchanged
# WS2-core (zero regression by construction). =1 opts in; then it ALSO requires
# ffhc_is_msys + powershell.exe + a one-time BOUNDED capability probe. There is NO
# `auto` default. stdin_mode=inherit DISABLES the branch (stdin passthrough to the
# fenced child is unproven — fall to WS2-core).
#
# HONEST LIMIT (same as taskkill's, run-with-timeout.sh:143): a native descendant
# that MSYS-fork/`start //b`-DETACHES out of the assigned winpid's Win32 tree before
# assignment is not in the job — best-effort, exactly like the existing reap. What
# the fence GUARANTEES: the assigned tree dies atomically (proven: a stubborn
# TERM-ignoring child under run_with_timeout => rc 137 on TerminateJobObject) and
# the kill is strictly scoped (an unrelated sibling survives). The tempfile capture,
# not the kill, remains the anti-hang guarantee.
#
# NO-RERUN CONTRACT: the probe runs BEFORE any child launches (a probe failure just
# skips the branch — WS2-core re-run is safe, nothing launched). The helper ASSIGN
# runs AFTER launch; if it fails, we DO NOT re-execute — we fall back to the plain
# taskkill reap for the already-launched _bpid and return its bounded rc.

# _ffhc_job_helper_path: write the PowerShell fence helper to a stable per-user temp
# path once (idempotent) and echo it. The helper is passed params via -File args
# (winpid, trigger-file, deadline), NEVER an inline -Command built from user input.
# It creates a KILL_ON_JOB_CLOSE job, OpenProcess+AssignProcessToJobObject the winpid,
# then waits (bounded by its own deadline cap) for the trigger file — TerminateJobObject
# on trigger OR on its own cap, so it can never hang. Status ("ASSIGN-OK"/"ASSIGN-FAIL
# <code>") goes to stdout (the caller captures it to a tempfile, never a pipe).
_ffhc_job_helper_path() {
  local dir="${TMPDIR:-/tmp}"
  local p="$dir/ffhc-job-fence.ps1"
  if [ ! -f "$p" ]; then
    cat > "$p" <<'FENCE_PS1' 2>/dev/null || return 1
param([int]$WinPid, [string]$TriggerFile, [int]$DeadlineSecs = 60)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FfhcJob {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr CreateJobObjectW(IntPtr a, string name);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool TerminateJobObject(IntPtr job, uint code);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
}
'@
try {
  $job = [FfhcJob]::CreateJobObjectW([IntPtr]::Zero, $null)
  if ($job -eq [IntPtr]::Zero) { Write-Output "ASSIGN-FAIL create"; exit 2 }
  # JobObjectExtendedLimitInformation=9; JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE=0x2000 at
  # BasicLimitInformation.LimitFlags (offset 16). The struct size MUST be exact for the
  # class (ERROR_BAD_LENGTH otherwise): JOBOBJECT_EXTENDED_LIMIT_INFORMATION is 144 bytes
  # on 64-bit (112 basic + IO_COUNTERS + 4 SIZE_T), 112 on 32-bit — pick by IntPtr size.
  $sz = if ([IntPtr]::Size -eq 8) { 144 } else { 112 }
  $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal($sz)
  for ($z=0; $z -lt $sz; $z+=4) { [Runtime.InteropServices.Marshal]::WriteInt32($buf, $z, 0) }
  [Runtime.InteropServices.Marshal]::WriteInt32($buf, 16, 0x2000)
  if (-not [FfhcJob]::SetInformationJobObject($job, 9, $buf, $sz)) { Write-Output ("ASSIGN-FAIL setinfo " + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); exit 3 }
  if ($WinPid -gt 0) {
    # PROCESS_SET_QUOTA(0x100)|PROCESS_TERMINATE(0x1) is the minimum for Assign; ALL_ACCESS is fine.
    $h = [FfhcJob]::OpenProcess(0x1F0FFF, $false, [uint32]$WinPid)
    if ($h -eq [IntPtr]::Zero) { Write-Output ("ASSIGN-FAIL openprocess " + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); exit 4 }
    if (-not [FfhcJob]::AssignProcessToJobObject($job, $h)) { Write-Output ("ASSIGN-FAIL assign " + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); exit 5 }
  }
  Write-Output "ASSIGN-OK"
  # Bounded wait for the trigger (deadline cap => never hang), then hard-kill the tree.
  $ticks = [int]([math]::Ceiling($DeadlineSecs / 0.1)) + 20
  for ($i = 0; $i -lt $ticks; $i++) {
    if ($TriggerFile -and (Test-Path $TriggerFile)) { break }
    Start-Sleep -Milliseconds 100
  }
  [FfhcJob]::TerminateJobObject($job, 137) | Out-Null
  [FfhcJob]::CloseHandle($job) | Out-Null
  Write-Output "TERMINATED"
  exit 0
} catch {
  Write-Output ("ASSIGN-FAIL exception " + $_.Exception.Message)
  exit 9
}
FENCE_PS1
  fi
  [ -f "$p" ] && echo "$p"
}

# ffhc_job_available: 0 (true) iff the Job Object fence is ENABLED and USABLE on this
# host. One-time, CACHED, and BOUNDED (the probe runs the helper with no winpid under
# run_with_timeout so it can never hang before the fallback exists). Gates: opt-in knob
# FFHC_USE_JOB_OBJECT=1 (default 0 => always unavailable), ffhc_is_msys, powershell.exe
# present, and a live create+setinfo+terminate probe. FFHC_JOB_PROBE_FORCE_FAIL=1 forces
# the probe to fail (test hook) => clean pre-launch fallback to WS2-core.
FFHC_JOB_PROBE_RESULT=""   # "" unknown | "ok" | "no"
ffhc_job_available() {
  [ "${FFHC_USE_JOB_OBJECT:-0}" = "1" ] || return 1
  case "$FFHC_JOB_PROBE_RESULT" in ok) return 0 ;; no) return 1 ;; esac
  if [ "${FFHC_JOB_PROBE_FORCE_FAIL:-0}" = "1" ]; then FFHC_JOB_PROBE_RESULT="no"; return 1; fi
  ffhc_is_msys || { FFHC_JOB_PROBE_RESULT="no"; return 1; }
  command -v powershell.exe >/dev/null 2>&1 || { FFHC_JOB_PROBE_RESULT="no"; return 1; }
  [ -n "${FFHC_TIMEOUT_BIN:-}" ] || { FFHC_JOB_PROBE_RESULT="no"; return 1; }
  local helper; helper="$(_ffhc_job_helper_path)" || { FFHC_JOB_PROBE_RESULT="no"; return 1; }
  [ -n "$helper" ] || { FFHC_JOB_PROBE_RESULT="no"; return 1; }
  # Bounded no-assign probe (winpid 0 => create+setinfo+terminate only). Trigger absent
  # => the helper hits its short cap and terminates; run_with_timeout bounds it hard.
  local out; out="$(run_with_timeout 15 powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$helper" 2>/dev/null || echo "$helper")" -WinPid 0 -TriggerFile "" -DeadlineSecs 1 2>/dev/null)"
  case "$out" in *ASSIGN-OK*) FFHC_JOB_PROBE_RESULT="ok"; return 0 ;; *) FFHC_JOB_PROBE_RESULT="no"; return 1 ;; esac
}

# _ffhc_job_fence WINPID SECS: launch the fence helper for an ALREADY-LAUNCHED child's
# WINPID, bounded to SECS+grace. Echoes the trigger-file path on ASSIGN-OK (touch it to
# hard-kill the assigned tree; the reap does this at the deadline). Echoes "" on any
# ASSIGN failure (NO-RERUN: the caller falls back to the plain taskkill reap for the
# already-launched _bpid — never re-executes). Helper stdout => a tempfile, never a pipe.
FFHC_JOB_FENCE_HPID=""
_ffhc_job_fence() {
  local winpid="$1" secs="$2"
  FFHC_JOB_FENCE_HPID=""
  [ -n "$winpid" ] || { echo ""; return 0; }
  local helper; helper="$(_ffhc_job_helper_path)"; [ -n "$helper" ] || { echo ""; return 0; }
  local grace="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; local gsec="${grace%[!0-9]*}"
  case "$gsec" in ''|*[!0-9]*) gsec=5 ;; esac
  local dl=$(( secs + gsec + 3 ))
  local trig; trig="$(mktemp "${TMPDIR:-/tmp}/ffhc-jobtrig.$$.XXXXXX" 2>/dev/null)"; rm -f "$trig" 2>/dev/null
  local hstat; hstat="$(mktemp "${TMPDIR:-/tmp}/ffhc-jobstat.$$.XXXXXX" 2>/dev/null)" || { echo ""; return 0; }
  powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$helper" 2>/dev/null || echo "$helper")" \
    -WinPid "$winpid" -TriggerFile "$(cygpath -w "$trig" 2>/dev/null || echo "$trig")" -DeadlineSecs "$dl" \
    >"$hstat" 2>/dev/null &
  FFHC_JOB_FENCE_HPID=$!
  # Confirm ASSIGN-OK within a short bound (the helper prints it right after assign). If it
  # never confirms, NO-RERUN: signal-close the helper, drop the trigger, return "" (fallback).
  local waited=0
  while [ "$waited" -lt 30 ]; do
    grep -q "ASSIGN-OK" "$hstat" 2>/dev/null && { rm -f "$hstat" 2>/dev/null; echo "$trig"; return 0; }
    grep -q "ASSIGN-FAIL" "$hstat" 2>/dev/null && break
    kill -0 "$FFHC_JOB_FENCE_HPID" 2>/dev/null || break
    sleep 0.1; waited=$((waited + 1))
  done
  # NO-RERUN fallback: signal-close the helper, reap it, then clean BOTH temp files (no
  # leak) and return "" so the caller uses the plain taskkill reap for the already-launched
  # child — never a re-run.
  : > "$trig" 2>/dev/null
  [ -n "$FFHC_JOB_FENCE_HPID" ] && wait "$FFHC_JOB_FENCE_HPID" 2>/dev/null
  FFHC_JOB_FENCE_HPID=""
  rm -f "$trig" "$hstat" 2>/dev/null
  echo ""
}

# ffhc_run_bounded SECS CMD [ARGS...]
#   Runs CMD per the no-binary policy and records the result in module-globals
#   the engine reads. Captures combined stdout+stderr so callers can parse it.
#     FFHC_LAST_OUT       — captured combined output ("" when skipped)
#     FFHC_LAST_RC        — wrapped command's own rc (124 on timeout; 125 sentinel when skipped)
#     FFHC_LAST_TIMED_OUT — 1 iff the run hit the timeout (rc 124), else 0
#     FFHC_LAST_SKIPPED   — 1 iff the run was skipped because no timeout binary exists, else 0
#   Policy (H5): if no timeout binary AND FFHC_ALLOW_UNBOUNDED!=1 => SKIP (no run,
#   sentinel rc 125, FFHC_LAST_SKIPPED=1) so a slow op can never hang the engine;
#   FFHC_ALLOW_UNBOUNDED=1 opts into an unbounded run instead.
# _ffhc_tempfile_capture STDERR_MODE STDIN_MODE SECS CMD...: shared belt-#2 capture
# core (D-B1). Backgrounds the bounded run with output to a TEMP FILE (never a pipe a
# descendant could hold open), holds its pid + MSYS-reaps the native tree, waits, reads.
# Sets FFHC_LAST_OUT/FFHC_LAST_RC/FFHC_LAST_TIMED_OUT. STDERR_MODE: "merge" (2>&1,
# combined) or "drop" (2>/dev/null, stdout only). STDIN_MODE: "null" (explicit
# `< /dev/null`, the DEFAULT) or "inherit" (`0<&0`, the caller's fd 0). One core =>
# the conflict reporter and ffhc_run_bounded share the exact same liveness guarantee
# (FR-25 seam).
# T8: explicit "${TMPDIR:-/tmp}/ffhc-bounded.$$.XXXXXX" template (no CWD files), and
# if the temp can't be created/written, route to the SKIPPED sentinel (rc 125,
# FFHC_LAST_SKIPPED=1) so the engine reads UNVERIFIED — NOT an empty-output run that
# would read as a false BROKEN, and NEVER a launch into a broken redirect.
_ffhc_tempfile_capture() {
  local stderr_mode="$1" stdin_mode="$2" secs="$3"; shift 3
  local _tf
  _tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-bounded.$$.XXXXXX" 2>/dev/null || true)"
  # TRIPWIRE: a missing/unwritable temp must SKIP (UNVERIFIED), never launch the
  # bounded run into a dead redirect (that returns empty => false BROKEN) or hang.
  if [ -z "$_tf" ] || ! { : >"$_tf"; } 2>/dev/null; then
    [ -n "$_tf" ] && rm -f "$_tf" 2>/dev/null
    FFHC_LAST_OUT=""; FFHC_LAST_RC=125; FFHC_LAST_SKIPPED=1; FFHC_LAST_TIMED_OUT=0
    return 0
  fi
  # TRIPWIRE (T17/T18): a backgrounded (`&`) command's stdin defaults to /dev/null and that
  # default OVERRIDES a `< file` redirect applied to the CALLER — so the child never sees
  # the caller's fd 0 unless we redirect it explicitly here. STDIN_MODE is an EXPLICIT
  # PARAMETER (never an ambient global — T18): "null" => explicit `< /dev/null` (the DEFAULT,
  # identical to today's guarantee — a bounded op can never block on an inherited TTY);
  # "inherit" => `0<&0` (the caller's fd 0), selected ONLY by the dedicated stdin wrapper so
  # a `< file` on that wrapper reaches the bounded child (the MSYS fixture-phase fix). The
  # DEFAULT path can NEVER take the inherit branch regardless of the environment. Both paths
  # keep the tempfile capture + winpid/childpid reap IDENTICAL below.
  if [ "$stdin_mode" = "inherit" ]; then
    if [ "$stderr_mode" = "drop" ]; then
      run_with_timeout "$secs" "$@" >"$_tf" 2>/dev/null 0<&0 &
    else
      run_with_timeout "$secs" "$@" >"$_tf" 2>&1 0<&0 &
    fi
  else
    if [ "$stderr_mode" = "drop" ]; then
      run_with_timeout "$secs" "$@" >"$_tf" 2>/dev/null </dev/null &
    else
      run_with_timeout "$secs" "$@" >"$_tf" 2>&1 </dev/null &
    fi
  fi
  local _bpid=$!
  # T7: capture the Windows pid NOW, while _bpid is still alive (the /proc/<pid>/winpid
  # node vanishes on exit; a post-deadline read races the wrapper's exit and reads empty).
  local _winpid=""; if ffhc_is_msys; then _winpid="$(ffhc_msys_winpid "$_bpid")"; fi
  # FFHC_LAST_WINPID/FFHC_LAST_CHILD_PID (additive): the recorded in-flight child's
  # winpid AND its bash pid, exposed so a caller's EXIT-trap can strict-scoped-reap a
  # phase still running if the caller is signaled mid-run — the child pid lets the trap
  # re-verify the winpid still maps to OUR child (PID-reuse guard), same as the deadline
  # path. Both are cleared the instant we return below (the child is reaped by then), so
  # they are non-empty ONLY while the child is provably alive.
  FFHC_LAST_WINPID="$_winpid"; FFHC_LAST_CHILD_PID="$_bpid"
  # WS2-hard OUTER FENCE (opt-in, guarded by ffhc_is_msys AND ffhc_job_available AND the
  # non-inherit default path). Purely additive: when off/unavailable/inherit, _trig="" and
  # the wait_reap call below is IDENTICAL to WS2-core (byte-behavior-unchanged default).
  # NO-RERUN: the fence assigns the ALREADY-LAUNCHED _winpid; an ASSIGN failure returns
  # _trig="" and we fall straight through to the plain taskkill reap — never a re-run.
  local _trig=""
  if ffhc_is_msys && [ "$stdin_mode" != "inherit" ] && [ -n "$_winpid" ] && ffhc_job_available; then
    _trig="$(_ffhc_job_fence "$_winpid" "$secs")"
  fi
  if ffhc_is_msys; then ffhc_msys_wait_reap "$_bpid" "$secs" "$_winpid" "$_trig"; else wait "$_bpid"; fi
  FFHC_LAST_RC=$?
  # Release + reap the fence helper (ours): touch the trigger so a still-waiting helper
  # TerminateJobObjects the (now-exited, harmless no-op) tree and exits, then reap it so
  # it never lingers. Bounded by the helper's own deadline cap regardless.
  if [ -n "$_trig" ]; then
    : > "$_trig" 2>/dev/null
    [ -n "$FFHC_JOB_FENCE_HPID" ] && { wait "$FFHC_JOB_FENCE_HPID" 2>/dev/null; }
    rm -f "$_trig" 2>/dev/null; FFHC_JOB_FENCE_HPID=""
  fi
  FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""   # child reaped => a later EXIT-trap reap is a no-op
  FFHC_LAST_OUT="$(cat "$_tf" 2>/dev/null)"
  rm -f "$_tf" 2>/dev/null
  ffhc_timed_out "$FFHC_LAST_RC" && FFHC_LAST_TIMED_OUT=1 || FFHC_LAST_TIMED_OUT=0
}

# ffhc_run_bounded SECS CMD [ARGS...]
#   Runs CMD per the no-binary policy and records the result in module-globals
#   the engine reads. Captures combined stdout+stderr so callers can parse it.
#     FFHC_LAST_OUT       — captured combined output ("" when skipped)
#     FFHC_LAST_RC        — wrapped command's own rc (124 on timeout; 125 sentinel when skipped)
#     FFHC_LAST_TIMED_OUT — 1 iff the run hit the timeout (rc 124), else 0
#     FFHC_LAST_SKIPPED   — 1 iff the run was skipped because no timeout binary exists, else 0
#   Policy (H5): if no timeout binary AND FFHC_ALLOW_UNBOUNDED!=1 => SKIP (no run,
#   sentinel rc 125, FFHC_LAST_SKIPPED=1) so a slow op can never hang the engine;
#   FFHC_ALLOW_UNBOUNDED=1 opts into an unbounded run instead.
ffhc_run_bounded() {
  local secs="$1"; shift
  FFHC_LAST_OUT=""; FFHC_LAST_RC=0; FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    _ffhc_tempfile_capture merge null "$secs" "$@"  # combined stdout+stderr (belt #2, D-B1)
  elif [ "${FFHC_ALLOW_UNBOUNDED:-0}" = "1" ]; then
    FFHC_LAST_OUT="$("$@" 2>&1)"; FFHC_LAST_RC=$?
  else
    FFHC_LAST_RC=125; FFHC_LAST_SKIPPED=1
  fi
}

# ffhc_run_bounded_stdout SECS CMD [ARGS...]: like ffhc_run_bounded but stdout-only
# (stderr discarded) — for callers that parse clean JSON/text (the conflict reporter).
# Same module-globals + no-binary SKIP policy. Belt-#2 capture via the shared core.
ffhc_run_bounded_stdout() {
  local secs="$1"; shift
  FFHC_LAST_OUT=""; FFHC_LAST_RC=0; FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    _ffhc_tempfile_capture drop null "$secs" "$@"
  elif [ "${FFHC_ALLOW_UNBOUNDED:-0}" = "1" ]; then
    FFHC_LAST_OUT="$("$@" 2>/dev/null)"; FFHC_LAST_RC=$?
  else
    FFHC_LAST_RC=125; FFHC_LAST_SKIPPED=1
  fi
}

# ffhc_run_bounded_stdin_stdout SECS CMD [ARGS...]: like ffhc_run_bounded_stdout
# (stdout-only capture, same no-binary SKIP + belt-#2 liveness) BUT the bounded child
# INHERITS the caller's fd 0, so a `< file` redirect on the wrapper call reaches the
# child. For stdin-fed handlers under the bound (the run-tests fixture loop): a
# backgrounded child's stdin otherwise defaults to /dev/null and drops the fixture.
# The unbounded fallback already inherits fd 0 (no `< /dev/null`), so it needs no arg.
# T18: stdin inheritance is selected by passing the EXPLICIT "inherit" stdin-mode PARAM
# to _ffhc_tempfile_capture (no ambient module global, no set/reset dance) — so ONLY this
# dedicated wrapper ever takes the inherit branch; the default wrappers pass "null" and
# are immune to any environment value.
ffhc_run_bounded_stdin_stdout() {
  local secs="$1"; shift
  FFHC_LAST_OUT=""; FFHC_LAST_RC=0; FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    _ffhc_tempfile_capture drop inherit "$secs" "$@"
  elif [ "${FFHC_ALLOW_UNBOUNDED:-0}" = "1" ]; then
    FFHC_LAST_OUT="$("$@" 2>/dev/null)"; FFHC_LAST_RC=$?
  else
    FFHC_LAST_RC=125; FFHC_LAST_SKIPPED=1
  fi
}

# ffhc_run_tests_pass_ok <pass-line>: classify a run-tests summary line. Returns 0
# (OK) ONLY when the line is STRICTLY "[run-tests] N/N PASS" (nothing but optional
# trailing whitespace after PASS) with passed==total AND total>0. Returns 1 for a
# trailing suffix (e.g. "1/1 PASS but not really"), zero tests ("0/0 PASS"), a
# real undercount ("1/2 PASS"), or leading-zero counts ("01/01 PASS"). A prefix
# match alone is NOT proof of a clean run (Codex round-2 A1): the engine must
# record OK only on a genuine all-pass summary.
#
# Counts are matched [1-9][0-9]* (NOT [0-9]+): a leading zero ("01/01", "0/0",
# "00") is a malformed/spoofed summary, never a clean run. [1-9][0-9]* already
# excludes total==0, so the prior numeric total>0 guard is redundant; passed==total
# is still checked numerically (Codex round-3 A1: "01/01 PASS" normalized 01==01
# and read HEALTHY — the regex must reject the leading zero before any numeric cmp).
ffhc_run_tests_pass_ok() {
  local cnt
  cnt=$(echo "$1" | sed -nE 's|^\[run-tests\] ([1-9][0-9]*)/([1-9][0-9]*) PASS[[:space:]]*$|\1 \2|p')
  [ -n "$cnt" ] && [ "${cnt% *}" -eq "${cnt#* }" ]
}

# ffhc_count_pass_lines <raw-run-tests-output>: echo the number of STRICT run-tests
# PASS summary lines in the output. "Strict" = the full anchored "[run-tests] N/N
# PASS" shape (only trailing whitespace) — the same shape ffhc_run_tests_pass_ok
# demands; a malformed line (suffix, mid-line, leading whitespace) is NOT a PASS
# summary. Used by both selection and the BROKEN-message classifier so the count
# rule lives in one place (no cross-subshell global — Codex round-3 A2).
ffhc_count_pass_lines() {
  echo "$1" | grep -cE "^\[run-tests\] [0-9]+/[0-9]+ PASS[[:space:]]*$"
}

# ffhc_select_pass_line <raw-run-tests-output>: echo the SINGLE strict run-tests
# PASS summary line, or "" when the output does not contain EXACTLY one (zero, or
# two+ which is the ambiguous/duplicate spoof). Replaces the engine's
# `grep ... | tail -1` (Codex round-3 A2): tail -1 hid a second PASS summary, so
# two summaries collapsed to the last clean line and read HEALTHY. The reason for
# an empty result is re-derived by ffhc_pass_line_broken_msg from the same raw
# output (NOT a shared global — this runs in a command-substitution subshell).
# THREAT MODEL: this classifier trusts the framework-owned run-tests.sh FAIL:/N/N
# PASS contract; a malicious harness emitting one clean summary while hiding
# failures is out of threat model (it requires harness control — repo already compromised).
ffhc_select_pass_line() {
  [ "$(ffhc_count_pass_lines "$1")" -eq 1 ] && echo "$1" | grep -E "^\[run-tests\] [0-9]+/[0-9]+ PASS[[:space:]]*$"
}

# ffhc_pass_line_broken_msg <rc> <raw-run-tests-output>: the LOCAL_BROKEN message
# for the no-single-PASS-line case. Re-derives the reason from the raw output
# (>=2 strict PASS summaries => the ambiguous/duplicate spoof, Codex round-3 A2;
# else unparseable/no summary) so it works inside the engine even though the
# selection ran in a subshell. Kept in the lib (not inlined) so the engine branch
# stays one line under the FR-25 800-line ceiling.
ffhc_pass_line_broken_msg() {
  if [ "$(ffhc_count_pass_lines "${2:-}")" -ge 2 ]; then
    echo "hook tests: ambiguous/duplicate hook-test summary — cannot confirm pass (>=2 'N/N PASS' summaries; run 'bash hooks/tests/run-tests.sh' to inspect)"
  else
    echo "hook tests: harness exited rc=${1:-?} but printed no parsable 'N/N PASS' line and no FAIL: — output is unparseable, cannot confirm pass (run 'bash hooks/tests/run-tests.sh' to inspect)"
  fi
}
