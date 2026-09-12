#!/usr/bin/env bash
# Fusebase Flow — fixture + identity-safe teardown for hooks/tests/test-run-tests-signal-reap.sh.
# Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# TRIPWIRE: every kill in this file and in its caller is identity-verified. A PID-only `kill -9`
# in a REGRESSION TEST is the same defect class the test exists to catch — after a sleep, a
# recorded numeric pid can belong to somebody else's process.
#
# Requires: hooks/tests/lib/orphan-reap.sh already sourced (ffor_identity / ffor_alive).

FFSR_TOKEN=""
declare -A FFSR_TOK=()

# ff_token PID -> FFSR_TOKEN ("<start>|<ppid>|<comm>"), the reuse-proof identity of a LIVE pid.
# The ppid is part of the identity because of the MSYS start-token hazard documented on
# ff_kill_verified; comm goes LAST because it can contain spaces.
ff_token() {
  FFSR_TOKEN=""
  ffor_identity "${1:-}" || return 1
  FFSR_TOKEN="$FFOR_START|$FFOR_PPID|$FFOR_COMM"
  return 0
}

# ff_track PID: remember PID together with the identity it has RIGHT NOW.
ff_track() { local p="${1:-}"; ffor_numeric "$p" || return 0; ff_token "$p" && FFSR_TOK[$p]="$FFSR_TOKEN"; return 0; }

# ff_kill_verified PID TOKEN [SIG]: signal ONLY when the live identity still PROVES this is the
# same process. Two independent proofs, either sufficient:
#   (a) the recorded start token still matches, or
#   (b) it is still THIS shell's own child and the comm matches.
#
# TRIPWIRE (measured on MSYS, 2026-09-12): (a) ALONE IS NOT ENOUGH and silently disarmed this
# whole teardown. `/proc/<pid>/stat` field 20 is a PRE-EXEC value when a pid first appears and
# changes exactly once — 0.7s later on an idle host, 4.1s later under gate load (recorded
# 239157481 -> 239161590). A token captured at spawn time therefore never matched again,
# ff_reap_tracked declined EVERY kill, and each run leaked its fixture siblings: six
# `while :; do sleep 1; done` loops were still burning CPU three days after the run that made
# them. (b) is NOT a loosening of the reuse guard: this shell never `wait`s these jobs, and an
# unreaped child's pid cannot be recycled, so "still our child with this comm" is exact.
ff_kill_verified() {
  local pid="${1:-}" tok="${2:-}" sig="${3:-9}" rs rp rc rest
  [ -n "$pid" ] && [ -n "$tok" ] || return 0
  ffor_identity "$pid" || return 0
  rs="${tok%%|*}"; rest="${tok#*|}"; rp="${rest%%|*}"; rc="${rest#*|}"
  if [ "$FFOR_START" = "$rs" ]      || { [ "$rp" = "$$" ] && [ "$FFOR_PPID" = "$$" ] && [ "$FFOR_COMM" = "$rc" ]; }; then
    kill "-$sig" "$pid" 2>/dev/null
  fi
  return 0
}

# ff_reap_tracked: verified-kill everything ff_track recorded, then forget it.
ff_reap_tracked() {
  local p
  for p in "${!FFSR_TOK[@]}"; do ff_kill_verified "$p" "${FFSR_TOK[$p]}"; done
  FFSR_TOK=()
  return 0
}

# ff_read_pid_file FIX NAME -> FFSR_FILE_PID (tracked). TRIPWIRE: sets a global instead of
# echoing — a `$( … )` wrapper would run ff_track in a SUBSHELL and silently lose the identity
# token, leaving the teardown with a bare pid again.
FFSR_FILE_PID=""
ff_read_pid_file() {
  FFSR_FILE_PID=""
  local p=""
  [ -s "$1/$2.pid" ] && IFS= read -r p 2>/dev/null < "$1/$2.pid"
  ffor_numeric "$p" || return 0
  FFSR_FILE_PID="$p"; ff_track "$p"
  return 0
}

# ff_tok PID: the tracked token for PID ("" when untracked or PID is empty).
ff_tok() { ffor_numeric "${1:-}" || { printf ''; return 0; }; printf '%s' "${FFSR_TOK[$1]:-}"; }

# ff_alive PID: liveness only (no identity claim). Callers that KILL must use ff_kill_verified.
ff_alive() { kill -0 "${1:-0}" 2>/dev/null; }

# ff_spawn_sibling -> FFSR_SIB_PID: an unrelated, SAME-EXECUTABLE (bash) process outside every
# target tree — the collateral target the "kills nothing" controls are measured on.
# TRIPWIRE: the body must stay a LOOP. `bash -c 'sleep 240'` is a single simple command, so bash
# execs sleep in place: ff_track then records comm=bash while the live comm becomes sleep, the
# identity-verified reap declines to signal it, and a 240s process outlives every run. Measured —
# two survived a completed run and would have loaded the next one's timings.
ff_spawn_sibling() {
  bash -c 'while :; do sleep 1; done' & FFSR_SIB_PID=$!
  ff_track "$FFSR_SIB_PID"
  return 0
}

# ff_gone_within PID CEIL: seconds until the pid disappears, or -1 if it never did.
ff_gone_within() {
  local pid="$1" ceil="$2" i=0
  while [ "$i" -le "$ceil" ]; do
    ff_alive "$pid" || { echo "$i"; return 0; }
    sleep 1; i=$((i + 1))
  done
  echo "-1"; return 1
}

# ff_ps_gone_within PID CEIL: seconds until PID leaves the PROCESS TABLE, or -1 if it never did.
# TRIPWIRE: use THIS, not ff_gone_within, for a pid that is this shell's own background job.
# `kill -0` succeeds on an unwaited zombie, so a correctly reaped child reads as still alive and
# the assertion reports a leak that is not there.
ff_ps_gone_within() {
  local pid="$1" ceil="$2" i=0
  while [ "$i" -le "$ceil" ]; do
    ffor_snapshot || { echo "-1"; return 1; }
    ffor_row "$pid" || { echo "$i"; return 0; }
    sleep 1; i=$((i + 1))
  done
  echo "-1"; return 1
}

# ff_write_fixture DIR: the miniature bounded phase + a byte-faithful copy of run-tests.sh's
# teardown block. TRIPWIRE: harness.sh mirrors hooks/tests/run-tests.sh's reaper + sentinel
# block. If that block changes and this does not, the control set stops describing the shipped
# harness. Knobs (test-only, never read by shipped code):
#   FFSR_SLOW_WINPID=<s>  widen the launch-to-record window deterministically
#   FFSR_PHASE_SECS=<s>   the miniature phase's bound
ff_write_fixture() {
  local d="$1"
  cat > "$d/gc.sh" <<'GC'
#!/usr/bin/env bash
D="$1"
echo $$ > "$D/gc.pid"; cat "/proc/$$/winpid" > "$D/gc.winpid" 2>/dev/null
while :; do sleep 1; done
GC
  cat > "$d/phase.sh" <<'PH'
#!/usr/bin/env bash
D="$1"
echo $$ > "$D/phase.pid"; cat "/proc/$$/winpid" > "$D/phase.winpid" 2>/dev/null
bash "$D/gc.sh" "$D" &
while :; do sleep 1; done
PH
  cat > "$d/fast.sh" <<'FA'
#!/usr/bin/env bash
D="$1"
echo $$ > "$D/phase.pid"; cat "/proc/$$/winpid" > "$D/phase.winpid" 2>/dev/null
bash -c 'echo $$ > "'"$1"'/gc.pid"; exit 0'
echo fast-marker
FA
  cat > "$d/harness.sh" <<'HN'
#!/usr/bin/env bash
set -uo pipefail
D="$1"; LIB="$2"; PHASE="${3:-$D/phase.sh}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
. "$LIB"
ffhc_detect_timeout
[ -f "$ROOT/hooks/tests/lib/orphan-reap.sh" ] && . "$ROOT/hooks/tests/lib/orphan-reap.sh"
FFHC_HEARTBEAT_SECS="${FFHC_HEARTBEAT_SECS:-30}"
if [ -n "${FFSR_SLOW_WINPID:-}" ]; then
    ffhc_msys_winpid() { sleep "$FFSR_SLOW_WINPID"; local w=""
        IFS= read -r w 2>/dev/null < "/proc/${1:-0}/winpid" || w=""; printf '%s\n' "$w"; }
fi
FFHC_LAST_WINPID=""
FFHC_LAST_CHILD_PID=""
FF_SENTINEL_PID=""
FF_SENTINEL_PGID=""
FF_SENTINEL_GRACE=5
FFHC_SENTINEL_STATE=""
_ff_reap_in_flight() {
    [ -n "${FFHC_SENTINEL_STATE:-}" ] || return 0
    command -v ffor_state_read >/dev/null 2>&1 || return 0
    ffor_state_read "$FFHC_SENTINEL_STATE"
    [ -n "$FFOR_S_PID" ] || return 0
    local hp
    ffor_pgid_of $$ || return 1
    hp="$FFOR_PGID_OUT"
    ffor_resolve_phase "$FFOR_S_PID" "$hp" || return 1
    ffor_reap "$FFOR_R_PGID" "" "$FFOR_R_PGID" "$FFOR_R_LEADSTART" "$hp" 0
    ffor_group_gone "$FFOR_R_PGID"
}
_ff_sentinel_stop() {
    [ -n "$FF_SENTINEL_PID" ] || { [ -n "$FFHC_SENTINEL_STATE" ] && rm -f "$FFHC_SENTINEL_STATE" 2>/dev/null; return 0; }
    ffhc_sentinel_note
    kill "$FF_SENTINEL_PID" 2>/dev/null
    wait "$FF_SENTINEL_PID" 2>/dev/null
    local own; own="$(ffhc_pgid_of $$)"
    if [ -n "$FF_SENTINEL_PGID" ] && [ -n "$own" ] && [ "$FF_SENTINEL_PGID" != "$own" ]; then
        case "$FF_SENTINEL_PGID" in
            *[!0-9]*) : ;;
            *) [ "$FF_SENTINEL_PGID" -gt 1 ] && kill -TERM -"$FF_SENTINEL_PGID" 2>/dev/null ;;
        esac
    fi
    FF_SENTINEL_PGID=""; FF_SENTINEL_PID=""
    [ -n "$FFHC_SENTINEL_STATE" ] && rm -f "$FFHC_SENTINEL_STATE" 2>/dev/null
    return 0
}
_ff_exit_reap() {
    # trap.log is a post-mortem breadcrumb: "trap-ran" without "reap-returned" means the EXIT path
    # was SIGKILLed part-way (grace budget), not that it ran and reaped nothing (ordering defect).
    echo "trap-ran winpid=$FFHC_LAST_WINPID child=$FFHC_LAST_CHILD_PID" >> "$D/trap.log"
    _ff_reap_in_flight; local gone=$?
    echo "reap-returned gone=$gone" >> "$D/trap.log"
    if ffhc_is_msys && [ -n "$FFHC_LAST_WINPID" ]; then
        ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID" "$FFHC_LAST_CHILD_PID"
    fi
    [ "$gone" -eq 0 ] && _ff_sentinel_stop
    return 0
}
trap _ff_exit_reap EXIT
if ffhc_is_msys && [ -n "${FFHC_TIMEOUT_BIN:-}" ] \
     && [ -f "$ROOT/hooks/tests/lib/orphan-sentinel.sh" ]; then
    FFHC_SENTINEL_STATE="$(mktemp "${TMPDIR:-/tmp}/ffhc-sentinel.$$.XXXXXX" 2>/dev/null)" || FFHC_SENTINEL_STATE=""
    if [ -n "$FFHC_SENTINEL_STATE" ]; then
        echo "$FFHC_SENTINEL_STATE" > "$D/sentinel.state"
        _g="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; _g="${_g%[!0-9]*}"
        case "$_g" in ''|*[!0-9]*) _g=5 ;; esac
        FF_SENTINEL_GRACE="$_g"
        "$FFHC_TIMEOUT_BIN" "${FF_SENTINEL_CAP:-600}" bash "$ROOT/hooks/tests/lib/orphan-sentinel.sh" \
            "$$" "$(ffhc_pgid_of $$)" "$FFHC_SENTINEL_STATE" "$_g" >/dev/null 2>&1 &
        FF_SENTINEL_PID=$!
        FF_SENTINEL_PGID="$(ffhc_pgid_of "$FF_SENTINEL_PID")"
        echo "$FF_SENTINEL_PID" > "$D/sentinel.wrapper.pid"
    fi
fi
echo $$ > "$D/harness.pid"; cat "/proc/$$/winpid" > "$D/harness.winpid" 2>/dev/null
ffhc_run_bounded "${FFSR_PHASE_SECS:-300}" bash "$PHASE" "$D"
echo "phase-returned rc=$FFHC_LAST_RC" >> "$D/harness.log"
exit 0
HN
  return 0
}

# ff_spawn_victim_group: an independent process group (leader + child + grandchild) that NOTHING
# in this repository owns — the collateral target every "kills nothing" assertion is measured on.
# Sets FFSR_V_LEADER / FFSR_V_PGID / FFSR_V_LEADSTART; tracks all three pids for teardown.
ff_spawn_victim_group() {
  FFSR_V_LEADER=""; FFSR_V_PGID=""; FFSR_V_LEADSTART=""
  # Test-only knob (never read by shipped code): force the "topology not established" branch so
  # B4's own claim — a discriminator that cannot run must make the phase non-zero — is itself
  # mechanically demonstrable instead of waiting for a loaded host to produce it by accident.
  [ "${FFSR_FORCE_NO_VICTIM_GROUP:-0}" = "1" ] && return 1
  local secs="${1:-120}" i=0
  timeout "$secs" bash -c 'bash -c "while :; do sleep 1; done" & while :; do sleep 1; done' \
    >/dev/null 2>&1 &
  FFSR_V_LEADER=$!
  while [ "$i" -lt 15 ]; do
    if ffor_identity "$FFSR_V_LEADER" && [ "$FFOR_PGID" = "$FFSR_V_LEADER" ]; then
      FFSR_V_PGID="$FFOR_PGID"; break
    fi
    sleep 1; i=$((i + 1))
  done
  [ -n "$FFSR_V_PGID" ] || return 1
  ff_track "$FFSR_V_LEADER"
  i=0
  while [ "$i" -lt 15 ]; do
    [ "$(ff_group_size "$FFSR_V_PGID")" -ge 3 ] 2>/dev/null && break
    sleep 1; i=$((i + 1))
  done
  # TRIPWIRE: read the leader's start token HERE, after the group is populated — not in the poll
  # loop above. That token is handed to the SHIPPED ffor_reap, which compares it to the live value
  # at kill time, and a pre-exec value (see ff_kill_verified) would make the guard refuse.
  ffor_identity "$FFSR_V_LEADER" || return 1
  FFSR_V_LEADSTART="$FFOR_START"
  local mp mw
  ffor_snapshot || return 0
  ffor_group_members "$FFSR_V_PGID" || return 0
  while read -r mp mw; do ffor_numeric "$mp" && ff_track "$mp"; done <<< "$FFOR_MEMBERS"
  return 0
}

# ff_group_size PGID: number of CURRENT members, or -1 when `ps` is unavailable.
# TRIPWIRE: snapshot FIRST. This is a MEASUREMENT, so it must never report a cached table — and a
# stale/absent snapshot reporting an empty group would turn "the guard killed nothing" into a
# false PASS on exactly the assertions that exist to catch collateral.
ff_group_size() {
  ffor_snapshot || { echo "-1"; return 0; }
  ffor_group_members "${1:-0}" || { echo "-1"; return 0; }
  printf '%s\n' "$FFOR_MEMBERS" | grep -c . || true
}
