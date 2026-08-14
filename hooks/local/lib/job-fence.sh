#!/usr/bin/env bash
# Fusebase Flow — Windows Job Object OUTER FENCE (opt-in; DEFAULT OFF).
#
# PROVENANCE:
#   Extracted from lib/run-with-timeout.sh per FR-25 (module-size ratchet): that file had
#   reached the 800-line ceiling. The seam is a responsibility seam, not a mechanical split —
#   run-with-timeout.sh owns the PLATFORM-NEUTRAL bounded run (watchdog rc, tempfile capture,
#   MSYS reap) and this file owns the opt-in Windows-only hard-kill fence plus its capability
#   probe. Nothing here runs unless FFHC_USE_JOB_OBJECT=1.
#
# CONTRACT (consumed by run-with-timeout.sh: _ffhc_tempfile_capture):
#   ffhc_job_available            => 0 iff the fence is enabled AND provably usable here
#   _ffhc_job_fence WINPID SECS   => sets FFHC_JOB_FENCE_TRIG / FFHC_JOB_FENCE_HPID (call
#                                    DIRECTLY, never in $( … ) — see its tripwire)
#   Probe internals (_ffhc_job_probe_*) are tested directly by hooks/tests/test-job-probe-honesty.sh.
#
# SOURCED, not executed. It relies on run_with_timeout / ffhc_is_msys / ffhc_timed_out from
# run-with-timeout.sh, which sources this file after defining them.
# ============================================================================
# WS2-hard (v3.30.4) — Windows Job Object OUTER FENCE (DEFAULT OFF / opt-in).
# ADDITIVE hard-kill fence around the EXISTING bounded run — NOT a PowerShell reimplementation of
# `timeout`. Launch, rc (124/137), tempfile capture and stdin semantics all stay in
# _ffhc_tempfile_capture / ffhc_msys_wait_reap; the fence only ASSIGNS the already-launched child's
# winpid to a KILL_ON_JOB_CLOSE Job Object so the deadline reap can add a TerminateJobObject —
# atomic, strictly scoped to the assigned Win32 tree (a sibling survives). rc: `wait "$_bpid"`.
# TRIPWIRE — DEFAULT OFF is the safety basis: FFHC_USE_JOB_OBJECT default 0 => the branch
# is INERT, so the default path is byte-behavior-unchanged WS2-core. There is no `auto`.
# stdin_mode=inherit DISABLES the branch (fenced-child stdin passthrough is unproven).
# TRIPWIRE — NO-RERUN CONTRACT: the probe runs BEFORE any child launches, so a probe
# failure just skips the branch; the ASSIGN runs AFTER launch and, if it fails, we fall
# back to the plain taskkill reap for the already-launched _bpid — never a re-execute.
# HONEST LIMITS: (1) a descendant that detaches out of the winpid's Win32 tree before
# assignment escapes the job; (2) the launch->assign window is shrunk, not eliminated;
# (3) GNU `timeout -k` alone already reaches rc 137 here, so the 137 smoke exercises the
# mechanism without proving the Job Object performed the kill (consumer-gated); (4) the
# tempfile capture, NOT the kill, remains the anti-hang guarantee.

# _ffhc_job_helper_path: materialise the PowerShell fence helper at a stable per-user temp
# path (create-once) and echo it. TRIPWIRE: params go via -File args (winpid, trigger file,
# deadline), NEVER an inline -Command built from input. Status lines (ASSIGN-OK /
# ASSIGN-FAIL <code> / PROBE-DONE / TERMINATED) go to stdout, captured to a tempfile.
# TRIPWIRE (TOCTOU): NEVER write directly to $p. A `cat > $p` behind an existence test publishes
# the path the instant it opens, so a concurrent probe passes the test and executes a half-written
# script — a load-dependent parse failure that reads exactly like capability absence. Write the
# COMPLETE content to a unique SAME-DIRECTORY temp (rename is atomic only within a filesystem),
# verify the FENCE-EOF sentinel, then rename: a reader sees the old state or the whole file. A
# losing racer DISCARDS its temp rather than replacing a valid $p (on Windows a replacing rename
# can degrade to unlink+rename — pointless churn); a failed rename falls back to an existing $p.
_ffhc_job_helper_path() {
  local dir="${TMPDIR:-/tmp}" p tmp
  p="$dir/ffhc-job-fence-v2.ps1"   # TRIPWIRE: bump on ANY helper edit — write is create-once
  if [ ! -s "$p" ]; then
    tmp="$(mktemp "$dir/ffhc-job-fence.XXXXXX" 2>/dev/null)" || return 1
    cat > "$tmp" <<'FENCE_PS1' 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
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
  # WinPid 0 is the capability PROBE: create+setinfo have already answered and there is nothing
  # fenced, so exit NOW — entering the trigger wait only added probe latency (backlog 3).
  if ($WinPid -le 0) { [FfhcJob]::TerminateJobObject($job, 0) | Out-Null; [FfhcJob]::CloseHandle($job) | Out-Null; Write-Output "PROBE-DONE"; exit 0 }
  # Bounded wait for the trigger (deadline cap => never hang), then hard-kill the tree.
  $ticks = [int]([math]::Ceiling($DeadlineSecs / 0.1))
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
# FENCE-EOF
FENCE_PS1
    if [ "$(tail -1 "$tmp" 2>/dev/null)" != "# FENCE-EOF" ]; then rm -f "$tmp" 2>/dev/null; return 1; fi
    if [ -s "$p" ]; then rm -f "$tmp" 2>/dev/null; else mv -f "$tmp" "$p" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; [ -s "$p" ] || return 1; }; fi
  fi
  [ -s "$p" ] || sleep 0.2   # contended: another racer is mid-publish; never report "no helper"
  [ -s "$p" ] && echo "$p"
}

# ffhc_job_available: 0 (true) iff the Job Object fence is ENABLED and USABLE here. Gates in
# order: FFHC_USE_JOB_OBJECT=1 (default 0; FIRST so the default path forks nothing), ffhc_is_msys,
# powershell.exe, FFHC_TIMEOUT_BIN, then one live create+setinfo+terminate probe — bounded, and
# with NO winpid, so it can never hang before the fallback exists.
# FFHC_JOB_PROBE_FORCE_FAIL=1 => forced definite negative (test hook).
# TRIPWIRE (backlog release-gate-flaky-job-probe): a probe that got NO ANSWER (watchdog 124/137,
# unwritable helper, no/partial markers) must NEVER be cached as capability absence — that turns
# a timing flake into a permanent "unavailable" and silently deletes the fence — and must never
# be cached as SUCCESS either (rc 0 is required for ok; see _ffhc_job_probe_classify). Only an
# explicit ASSIGN-FAIL and the pre-flight gates are definite negatives. A no-answer is left
# uncached, so a LATER call in this process DOES probe again — a deferred cross-call retry,
# bounded by FFHC_JOB_PROBE_MAX_ATTEMPTS, after which it parks "err" = unavailable here, still
# not absence. One call still performs at most ONE live probe, so a single transient no-answer
# fails its caller exactly as before. Every non-ok probe prints one stderr diagnosis line.
FFHC_JOB_PROBE_RESULT=""   # "" unknown | "ok" | "no" definite-negative | "err" no-answer, budget spent
FFHC_JOB_PROBE_CLASS=""    # last probe: ok | definite-negative | timeout-or-error
FFHC_JOB_PROBE_TRIES=0
_ffhc_now_ms() { if [ -n "${EPOCHREALTIME:-}" ]; then echo $(( 10#${EPOCHREALTIME/./} / 1000 )); else echo $(( ${SECONDS:-0} * 1000 )); fi; }
# _ffhc_job_probe_classify RC OUT (probe-only — the fence's own ASSIGN check is separate).
# TRIPWIRE: the verdict needs the rc, not just the markers. `ok` requires ALL THREE — rc 0 AND
# ASSIGN-OK AND the PROBE-DONE end sentinel — so ASSIGN-OK followed by a watchdog kill is a
# no-answer, not a capability proof; caching "answered, then killed" as success is the same
# false-green one level down. ASSIGN-FAIL OUTRANKS ASSIGN-OK: mixed output is an answered failure.
_ffhc_job_probe_classify() {
  local rc="${1:-1}" out="${2:-}"
  case "$out" in
    *ASSIGN-FAIL*) echo "definite-negative" ;;
    *ASSIGN-OK*)
      case "$out" in
        *PROBE-DONE*) if [ "$rc" = "0" ]; then echo "ok"; else echo "timeout-or-error"; fi ;;
        *) echo "timeout-or-error" ;;
      esac ;;
    *) echo "timeout-or-error" ;;
  esac
}
# ONE stderr line (run-tests replays a FAILING phase's unparsed output to the log + audit artifact).
_ffhc_job_probe_diag() {
  local d="${6:-}"; d="${d//$'\r'/ }"; d="${d//$'\n'/ }"
  printf '[ffhc-job-probe] result=%s rc=%s elapsed_ms=%s helper=%s marker=%s attempt=%s/%s cache=%s detail=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$FFHC_JOB_PROBE_TRIES" "${FFHC_JOB_PROBE_MAX_ATTEMPTS:-2}" \
    "${FFHC_JOB_PROBE_RESULT:-unknown}" "${d:0:160}" >&2
}

_ffhc_job_probe_park() { FFHC_JOB_PROBE_CLASS="timeout-or-error"   # no-answer: never absence
  if [ "$FFHC_JOB_PROBE_TRIES" -ge "${FFHC_JOB_PROBE_MAX_ATTEMPTS:-2}" ]; then FFHC_JOB_PROBE_RESULT="err"; else FFHC_JOB_PROBE_RESULT=""; fi; }
# Records the watchdog rc, elapsed ms, the _ffhc_job_helper_path outcome and marker-seen, then
# classifies from those facts. Returns 0 only on a proven ok.
_ffhc_job_probe_run() {
  local helper out rc ms marker t0
  FFHC_JOB_PROBE_TRIES=$(( FFHC_JOB_PROBE_TRIES + 1 ))
  t0="$(_ffhc_now_ms)"
  helper="$(_ffhc_job_helper_path 2>/dev/null)" || helper=""
  if [ -z "$helper" ]; then
    _ffhc_job_probe_park
    _ffhc_job_probe_diag timeout-or-error - "$(( $(_ffhc_now_ms) - t0 ))" fail absent "helper path unavailable"
    return 1
  fi
  # TRIPWIRE: stderr is MERGED on purpose — a powershell that fails to start or parse says so ONLY
  # on stderr, and dropping it is why a hosted failure could not be diagnosed.
  out="$(run_with_timeout 15 powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$helper" 2>/dev/null || echo "$helper")" -WinPid 0 -TriggerFile "" -DeadlineSecs 1 2>&1)"; rc=$?
  ms=$(( $(_ffhc_now_ms) - t0 ))
  case "$out" in *ASSIGN-OK*PROBE-DONE*) marker="complete" ;; *ASSIGN-OK*) marker="partial" ;; *) marker="absent" ;; esac
  FFHC_JOB_PROBE_CLASS="$(_ffhc_job_probe_classify "$rc" "$out")"
  case "$FFHC_JOB_PROBE_CLASS" in
    ok) FFHC_JOB_PROBE_RESULT="ok" ;; definite-negative) FFHC_JOB_PROBE_RESULT="no" ;; *) _ffhc_job_probe_park ;;
  esac
  if [ "$FFHC_JOB_PROBE_CLASS" != "ok" ]; then _ffhc_job_probe_diag "$FFHC_JOB_PROBE_CLASS" "$rc" "$ms" ok "$marker" "$out"; fi
  [ "$FFHC_JOB_PROBE_CLASS" = "ok" ]
}

ffhc_job_available() {
  [ "${FFHC_USE_JOB_OBJECT:-0}" = "1" ] || return 1
  case "$FFHC_JOB_PROBE_RESULT" in ok) return 0 ;; no|err) return 1 ;; esac
  if [ "${FFHC_JOB_PROBE_FORCE_FAIL:-0}" = "1" ] || ! ffhc_is_msys \
       || ! command -v powershell.exe >/dev/null 2>&1 || [ -z "${FFHC_TIMEOUT_BIN:-}" ]; then
    FFHC_JOB_PROBE_RESULT="no"; FFHC_JOB_PROBE_CLASS="definite-negative"; return 1
  fi
  _ffhc_job_probe_run
}

# _ffhc_job_fence WINPID SECS: launch the fence helper for an ALREADY-LAUNCHED child's
# WINPID, bounded to SECS+grace. SETS TWO MODULE GLOBALS in the CURRENT shell (never a
# command substitution — see the tripwire): FFHC_JOB_FENCE_TRIG = the trigger-file path
# on ASSIGN-OK (touch it to hard-kill the assigned tree; the reap does this at the
# deadline), or "" on any ASSIGN failure; FFHC_JOB_FENCE_HPID = the helper's bash pid so
# the caller reaps it. TRIPWIRE: this MUST be called DIRECTLY (`_ffhc_job_fence …`), NOT
# in `$( … )` — a subshell would (a) lose FFHC_JOB_FENCE_HPID so the caller's helper reap
# never runs (leak) and (b) block the parent on the backgrounded helper's stdout until its
# deadline cap (the fast-opt-in HANG). The helper's stdout goes to a tempfile ($hstat),
# never a pipe the parent reads. NO-RERUN: on ASSIGN failure the caller falls back to the
# plain taskkill reap for the already-launched _bpid — never re-executes.
FFHC_JOB_FENCE_HPID=""
FFHC_JOB_FENCE_TRIG=""
_ffhc_job_fence() {
  local winpid="$1" secs="$2"
  FFHC_JOB_FENCE_HPID=""; FFHC_JOB_FENCE_TRIG=""
  [ -n "$winpid" ] || return 0
  local helper; helper="$(_ffhc_job_helper_path)"; [ -n "$helper" ] || return 0
  local grace="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; local gsec="${grace%[!0-9]*}"
  case "$gsec" in ''|*[!0-9]*) gsec=5 ;; esac
  # TRIPWIRE: dl must stay ABOVE ffhc_msys_wait_reap's cap (secs+gsec+2) — the reap owns the kill; since the helper's tick loop lost its +20 padding, dl IS the wall and the margin is 1s, not 3s.
  local dl=$(( secs + gsec + 3 ))
  local trig; trig="$(mktemp "${TMPDIR:-/tmp}/ffhc-jobtrig.$$.XXXXXX" 2>/dev/null)"; rm -f "$trig" 2>/dev/null
  local hstat; hstat="$(mktemp "${TMPDIR:-/tmp}/ffhc-jobstat.$$.XXXXXX" 2>/dev/null)" || return 0
  # stdout -> $hstat (a tempfile), NEVER a pipe the parent reads: the parent must not block
  # on the backgrounded helper's fd 1 (that is the fast-opt-in HANG when called under $(…)).
  powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$helper" 2>/dev/null || echo "$helper")" \
    -WinPid "$winpid" -TriggerFile "$(cygpath -w "$trig" 2>/dev/null || echo "$trig")" -DeadlineSecs "$dl" \
    >"$hstat" 2>/dev/null &
  FFHC_JOB_FENCE_HPID=$!
  # Confirm ASSIGN-OK within a short bound (the helper prints it right after assign). If it
  # never confirms, NO-RERUN: signal-close the helper, drop the trigger, leave TRIG="" (fallback).
  local waited=0
  while [ "$waited" -lt 30 ]; do
    grep -q "ASSIGN-OK" "$hstat" 2>/dev/null && { rm -f "$hstat" 2>/dev/null; FFHC_JOB_FENCE_TRIG="$trig"; return 0; }
    grep -q "ASSIGN-FAIL" "$hstat" 2>/dev/null && break
    kill -0 "$FFHC_JOB_FENCE_HPID" 2>/dev/null || break
    sleep 0.1; waited=$((waited + 1))
  done
  # NO-RERUN fallback: signal-close the helper, reap it, then clean BOTH temp files (no
  # leak) and leave FFHC_JOB_FENCE_TRIG="" so the caller uses the plain taskkill reap for
  # the already-launched child — never a re-run.
  : > "$trig" 2>/dev/null
  [ -n "$FFHC_JOB_FENCE_HPID" ] && wait "$FFHC_JOB_FENCE_HPID" 2>/dev/null
  FFHC_JOB_FENCE_HPID=""
  rm -f "$trig" "$hstat" 2>/dev/null
}
