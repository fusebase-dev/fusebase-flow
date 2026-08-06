#!/usr/bin/env bash
# Fusebase Flow — S2 orphan sentinel (T4). Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# WHY OUT-OF-BAND, not a trap (T3 evidence, state/audit/run-tests-signal-reap/<head>/summary.md):
#   R2 — the harness is deaf to TERM/INT while `ffhc_msys_wait_reap` polls on the F3 FIFO nap.
#        Measured: an EXPLICIT `trap … TERM INT` never fired in 12s; with the nap forced off it
#        fired in 1s. An outer `timeout -k 5s` therefore SIGKILLs the harness first, so NO
#        harness-side cleanup — trap, EXIT trap or otherwise — can be relied on.
#   R3 — `taskkill //F //T` on the recorded child winpid returns SUCCESS but kills only the inner
#        `timeout`; MSYS exec/fork emulation breaks the Win32 parent link //T walks.
#   R1 — GNU `timeout` puts the bounded child in its OWN process group, which is both why the
#        subtree survives the harness's group signal AND the exact handle this reaps.
#
# CONTRACT: poll the harness; when it dies with a phase still in flight, revalidate the recorded
# identity tuple and terminate THAT PROCESS GROUP only. It never signals its own group, the
# harness's group, an ancestor, a name-wide set, or an unverified pid.
#
# LIFECYCLE: started once per harness run under `timeout` (a new process group => immune to the
# group signal that kills the harness, plus a hard cap so it can never outlive the run). The
# harness kills it on the normal path; it self-exits the moment it has nothing left to guard.
#
# Usage: orphan-sentinel.sh <harness-pid> <harness-pgid> <state-file> <grace-secs>
# State file (written by hooks/local/lib/run-with-timeout.sh): "<child_pid> <winpid> <pgid>",
# truncated the instant a phase returns — an empty file means nothing is in flight.

set -uo pipefail

HARNESS_PID="${1:-}"
HARNESS_PGID="${2:-}"
STATE="${3:-}"
GRACE="${4:-5}"
case "$GRACE" in ''|*[!0-9]*) GRACE=5 ;; esac

[ -n "$HARNESS_PID" ] && [ -n "$STATE" ] || exit 0

# Spawn-free pgid read (/proc/<pid>/stat field 5) — a `ps` per poll would cost more than the
# leak it guards.
pgid_of() {
  local s
  s="$(cat "/proc/${1:-0}/stat" 2>/dev/null)" || return 1
  printf '%s\n' "$s" | awk '{print $5}'
}
alive() { kill -0 "${1:-0}" 2>/dev/null; }

# reap <child_pid> <winpid> <pgid> : identity-revalidate, then group-terminate. Any mismatch
# returns WITHOUT killing — a PID-reuse or stale record must never cost an unrelated process.
reap() {
  local cpid="$1" cwin="$2" cpgid="$3" now_win now_pgid i

  case "$cpgid" in ''|*[!0-9]*) return 0 ;; esac
  [ "$cpgid" -gt 1 ] || return 0
  # Never our own group, never the harness's group, never an ancestor.
  [ "$cpgid" = "$(pgid_of $$)" ] && return 0
  [ -n "$HARNESS_PGID" ] && [ "$cpgid" = "$HARNESS_PGID" ] && return 0

  alive "$cpid" || return 0
  now_pgid="$(pgid_of "$cpid")"
  [ "$now_pgid" = "$cpgid" ] || return 0          # child moved groups / pid reuse => no kill
  if [ -n "$cwin" ]; then
    now_win="$(cat "/proc/$cpid/winpid" 2>/dev/null)"
    [ "$now_win" = "$cwin" ] || return 0          # winpid no longer maps to OUR child => no kill
  fi

  kill -TERM -"$cpgid" 2>/dev/null
  i=0
  while [ "$i" -lt "$GRACE" ]; do
    alive "$cpid" || break
    sleep 1; i=$((i + 1))
  done
  alive "$cpid" && kill -KILL -"$cpgid" 2>/dev/null

  # Native survivors: a non-MSYS descendant is not reachable by a POSIX group signal. Sweep ONLY
  # processes still carrying the recorded pgid, one winpid at a time — never `//T` (T3/R3 showed
  # the tree walk is unreliable here) and never a pid outside the group.
  command -v taskkill >/dev/null 2>&1 || return 0
  ps 2>/dev/null | awk -v g="$cpgid" '$3==g {print $4}' | while read -r w; do
    case "$w" in ''|*[!0-9]*) continue ;; esac
    taskkill //F //PID "$w" >/dev/null 2>&1 || true
  done
  return 0
}

# Guard loop. Reads the CURRENT in-flight record every tick, so a phase that starts after the
# sentinel does is covered too.
last_pid=""; last_win=""; last_pgid=""
while :; do
  if [ -r "$STATE" ]; then
    read -r s_pid s_win s_pgid < "$STATE" 2>/dev/null || true
    if [ -n "${s_pid:-}" ]; then
      last_pid="$s_pid"; last_win="${s_win:-}"; last_pgid="${s_pgid:-}"
    else
      last_pid=""; last_win=""; last_pgid=""
    fi
  fi
  if ! alive "$HARNESS_PID"; then
    # The harness is gone. Anything it recorded as in-flight is an orphan by definition.
    [ -n "$last_pid" ] && reap "$last_pid" "$last_win" "$last_pgid"
    exit 0
  fi
  sleep 1
done
