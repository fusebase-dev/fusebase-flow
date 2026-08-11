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

# ff_token PID -> FFSR_TOKEN ("<start> <comm>"), the reuse-proof identity of a LIVE pid.
ff_token() {
  FFSR_TOKEN=""
  ffor_identity "${1:-}" || return 1
  FFSR_TOKEN="$FFOR_START $FFOR_COMM"
  return 0
}

# ff_track PID: remember PID together with the identity it has RIGHT NOW.
ff_track() { local p="${1:-}"; ffor_numeric "$p" || return 0; ff_token "$p" && FFSR_TOK[$p]="$FFSR_TOKEN"; return 0; }

# ff_kill_verified PID TOKEN [SIG]: signal ONLY when the live identity still equals TOKEN.
# A recycled or vanished pid is skipped silently — never signalled.
ff_kill_verified() {
  local pid="${1:-}" tok="${2:-}" sig="${3:-9}"
  [ -n "$pid" ] && [ -n "$tok" ] || return 0
  ffor_identity "$pid" || return 0
  [ "$FFOR_START $FFOR_COMM" = "$tok" ] || return 0
  kill "-$sig" "$pid" 2>/dev/null
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
    ffor_resolve "$FFOR_S_PID" "$FFOR_S_PGID" || return 0
    ffor_pgid_of $$ || return 0
    ffor_reap "$FFOR_S_PID" "$FFOR_S_WIN" "$FFOR_R_PGID" "$FFOR_R_LEADSTART" \
        "$FFOR_PGID_OUT" "$FF_SENTINEL_GRACE"
    return 0
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
    _ff_reap_in_flight
    echo "reap-returned" >> "$D/trap.log"
    if ffhc_is_msys && [ -n "$FFHC_LAST_WINPID" ]; then
        ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID" "$FFHC_LAST_CHILD_PID"
    fi
    _ff_sentinel_stop
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
      FFSR_V_PGID="$FFOR_PGID"; FFSR_V_LEADSTART="$FFOR_START"; break
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
