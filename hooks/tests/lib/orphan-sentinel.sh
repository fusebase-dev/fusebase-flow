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
cur_pid=""; cur_win=""; cur_pgid=""; cur_lead=""
while :; do
  ffor_state_read "$STATE"
  if [ -n "$FFOR_S_PID" ]; then
    if [ "$FFOR_S_PID" != "$cur_pid" ]; then
      cur_pid="$FFOR_S_PID"; cur_win=""; cur_pgid=""; cur_lead=""
    fi
    [ -n "$FFOR_S_WIN" ] && cur_win="$FFOR_S_WIN"
    if [ -z "$cur_pgid" ] && ffor_resolve "$cur_pid" "$FFOR_S_PGID"; then
      # A pgid still equal to the harness's group means `timeout` has not called setpgid yet —
      # caching that would poison the whole phase, so retry on the next tick instead.
      if [ "$FFOR_R_PGID" != "$HARNESS_PGID" ]; then
        cur_pgid="$FFOR_R_PGID"; cur_lead="$FFOR_R_LEADSTART"
      fi
    fi
  else
    cur_pid=""; cur_win=""; cur_pgid=""; cur_lead=""
  fi
  if ! ffor_alive "$HARNESS_PID"; then
    # The harness is gone. Anything it recorded as in-flight is an orphan by definition.
    [ -n "$cur_pid" ] && ffor_reap "$cur_pid" "$cur_win" "$cur_pgid" "$cur_lead" "$HARNESS_PGID" "$GRACE"
    exit 0
  fi
  sleep 1
done
