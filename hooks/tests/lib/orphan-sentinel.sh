#!/usr/bin/env bash
# Fusebase Flow — S2 orphan sentinel. Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# WHY OUT-OF-BAND, not a trap: T3 measured the harness deaf to TERM/INT while ffhc_msys_wait_reap
# naps on the F3 FIFO, so an outer `timeout -k` SIGKILLs it before any harness-side handler runs.
# Full R1-R3 evidence lives in the ticket README — not here.
#
# CONTRACT: poll the harness; when it dies with a phase still in flight, revalidate the recorded
# identity and terminate THAT PROCESS GROUP only. Every guard is in ./orphan-reap.sh, which
# run-tests.sh's EXIT trap sources too — one guard set, two teardown paths.
#
# Usage: orphan-sentinel.sh <harness-pid> <harness-pgid> <state-file> <grace-secs>

set -uo pipefail
# shellcheck source=/dev/null
. "${BASH_SOURCE[0]%/*}/orphan-reap.sh"

HARNESS_PID="${1:-}"
HARNESS_PGID="${2:-}"
STATE="${3:-}"
GRACE="${4:-5}"
ffor_numeric "$GRACE" || GRACE=5

[ -n "$HARNESS_PID" ] && [ -n "$STATE" ] || exit 0

# Cached identity of the CURRENT in-flight child. TRIPWIRE: the harness publishes the pid the
# instant it exists — BEFORE its own winpid/pgid probes — and this loop completes the tuple
# out-of-band while the child is provably alive. That is what makes a signal inside the
# launch-to-record window still leave a reapable record.
cur_pid=""; cur_pgid=""; cur_lead=""; settle=0
while :; do
  ffor_state_read "$STATE"
  if [ -n "$FFOR_S_PID" ]; then
    if [ "$FFOR_S_PID" != "$cur_pid" ]; then
      cur_pid="$FFOR_S_PID"; cur_pgid=""; cur_lead=""; settle=0
    fi
    # The recorded pid is the harness's own capture subshell, so its group IS the harness's;
    # ffor_resolve_phase descends to the group `timeout` created. Until that group exists it
    # returns 1 and we simply retry on the next tick rather than cache a poisoned handle.
    if [ -z "$cur_pgid" ] && ffor_resolve_phase "$cur_pid" "$HARNESS_PGID"; then
      cur_pgid="$FFOR_R_PGID"; cur_lead="$FFOR_R_LEADSTART"; settle=12
    fi
    # REFRESH the leader token across the SETTLE WINDOW only, then stop.
    # TRIPWIRE (measured): MSYS reports a PRE-EXEC start token that changes EXACTLY ONCE, within
    # 0.45s idle and 4.1s under gate load. A token cached at resolve time can therefore be the
    # stale one, and ffor_reap would refuse its own target and reap NOTHING. Refreshing is SOUND,
    # not a loosening: while the leader is alive and still leads this pgid it is by definition the
    # same process. 12 ticks is ~3x the worst measured settle; the value never moves again, so
    # refreshing FOREVER buys nothing and costs a lot — one /proc read is ~185ms here, which made
    # this loop 202ms/tick against 4ms, i.e. ~330s of background CPU across one 1659s phase
    # (docs/backlog/gate-bounds-lack-headroom/). Do not restore the unbounded refresh.
    if [ "$settle" -gt 0 ]; then
      settle=$((settle - 1))
      if ffor_identity "$cur_pgid" && [ "$FFOR_PGID" = "$cur_pgid" ]; then cur_lead="$FFOR_START"; fi
    fi
  else
    cur_pid=""; cur_pgid=""; cur_lead=""; settle=0
  fi
  if ! ffor_alive "$HARNESS_PID"; then
    # The harness is gone. Anything it recorded as in-flight is an orphan by definition.
    # Reap the phase GROUP by its own leader: the recorded winpid/pid belong to the harness-group
    # subshell above it, and ffor_reap's recorded-child guards would reject that pairing.
    [ -n "$cur_pgid" ] && ffor_reap "$cur_pgid" "" "$cur_pgid" "$cur_lead" "$HARNESS_PGID" "$GRACE"
    # The harness's own _ff_sentinel_stop never ran, so this file is ours to remove: a SIGKILLed
    # gate otherwise leaves one state file per run in TMPDIR forever.
    rm -f "$STATE" 2>/dev/null
    exit 0
  fi
  sleep 1
done
