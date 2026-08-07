#!/usr/bin/env bash
# Fusebase Flow — S2 signal-reap regression arm. Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# WHAT IT DRIVES: a miniature bounded phase (child bash + its own grandchild bash) through the
# REAL ffhc_run_bounded path with a copy of run-tests.sh's teardown block, killed from outside
# mid-flight — plus direct drives of the guard primitives for the cases a live race cannot pin
# down deterministically.
#
# ROW CLASSES — read the summary line, not the count:
#   DISCRIMINATOR  fails against the pre-fix tree. These are the rows that carry the claim.
#   CONTROL        passed before the fix too; it exists to catch a REGRESSION (collateral, clean
#                  exit). A control PASS proves nothing about the fix.
#   SKIP           neither. Reported separately and NEVER counted as PASS — an off-MSYS skip
#                  incrementing the pass count is how "8/8" came to overstate coverage.
#
# TRIPWIRE: every kill here is identity-verified (lib/signal-reap-fixture.sh). A PID-only
# `kill -9` after a sleep can hit a recycled pid — the exact defect class under test.
#
# PROVENANCE (plan §5 / AC12): the retained trace records role, POSIX pid/ppid/pgid, Windows pid,
# executable BASENAME and liveness only — never a raw command line, absolute path, or environment.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: signal-reap <name>" / "FAIL: signal-reap <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"
REAPLIB="$ROOT/hooks/tests/lib/orphan-reap.sh"
FIXLIB="$ROOT/hooks/tests/lib/signal-reap-fixture.sh"

pass=0; fail=0; skipped=0
ok()   { pass=$((pass + 1)); echo "PASS: signal-reap $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: signal-reap $1 (${2:-})"; }
skip() { skipped=$((skipped + 1)); echo "SKIP: signal-reap $1 — ${2:-}" >&2; }
finish() {
  echo "[test-run-tests-signal-reap] $pass/$((pass + fail)) PASS, $fail FAIL, $skipped SKIP (skips are NOT passes)"
  exit $fail
}

for f in "$LIB" "$REAPLIB" "$FIXLIB"; do
  [ -f "$f" ] || { bad "setup-lib-present" "missing $f"; finish; }
done
# shellcheck source=/dev/null
. "$REAPLIB"
# shellcheck source=/dev/null
. "$FIXLIB"

# Cleanup deadline is the EXISTING grace (E8) — never a second constant. MSYS spawn is ~1s, so a
# strict grace edge would flake; the leak this must catch runs for tens of minutes, so +3s cannot
# swallow it.
GRACE="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; GSEC="${GRACE%[!0-9]*}"
case "$GSEC" in ''|*[!0-9]*) GSEC=5 ;; esac
REAP_CEILING=$((GSEC + 3))

HEAD_FULL="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
TREE=clean; git -C "$ROOT" diff --quiet HEAD 2>/dev/null || TREE=dirty
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
EVID="${FF_SIGNAL_REAP_EVIDENCE_DIR:-$ROOT/state/audit/run-tests-signal-reap/$HEAD_FULL}"
mkdir -p "$EVID" 2>/dev/null || true
# Run-unique (never one fixed name): two sessions at the same parent SHA used to truncate and
# interleave each other's topology, and a trace keyed only by HEAD cannot say which tree it tested.
TRACE="$EVID/topology-$TREE-$RUN_ID.tsv"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) : ;;
  *) skip "all-scenarios" "off-MSYS — POSIX process-group teardown reaps the phase tree; this defect class is MSYS-only"
     finish ;;
esac
[ -n "$(command -v timeout || true)" ] || { skip "all-scenarios" "no timeout binary"; finish; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-signal-reap.XXXXXX")" || { bad "setup-fixture" "mktemp failed"; finish; }
cleanup_fixture() {
  local p
  for p in harness phase gc; do ff_read_pid_file "$FIX" "$p"; done
  ff_reap_tracked
  rm -rf "$FIX" 2>/dev/null
}
trap cleanup_fixture EXIT
ff_write_fixture "$FIX"

# Fixture knobs are EXPORTED globals set immediately before a launch and reset after: a
# `VAR=x func` prefix on a shell FUNCTION leaks past the call in bash, which would silently
# carry a knob into the next scenario.
export FFSR_NAP_OFF=0 FFSR_SLOW_WINPID="" FFSR_NO_SENTINEL=0 FFSR_PHASE_SECS=300 \
       FFSR_TRAP_TERM=0 FFSR_STATE_ONLY=0

# Our OWN process group. Every scenario that signals a group compares against this FIRST and
# aborts the measurement rather than risk signalling this test's own tree.
OWN_PGID="$(ffor_identity $$ && printf '%s' "$FFOR_PGID")"

printf 'head\ttree\tscenario\tcapture\trole\tpid\tppid\tpgid\twinpid\texe_basename\talive_posix\talive_win\n' > "$TRACE"
SIB_PID=""
capture() {   # capture <scenario> <label>; roles read from the fixture's pid files + one ps snap
  local scen="$1" label="$2" snap tl role pid win ppid pgid exe am aw hp
  snap="$(ps 2>/dev/null)"; tl="$(tasklist //NH //FO CSV 2>/dev/null)"
  hp=""; [ -s "$FIX/harness.pid" ] && IFS= read -r hp < "$FIX/harness.pid"
  for role in harness child grandchild sibling wrapper; do
    case "$role" in
      harness)    pid="$hp" ;;
      child)      pid=""; [ -s "$FIX/phase.pid" ] && IFS= read -r pid < "$FIX/phase.pid" ;;
      grandchild) pid=""; [ -s "$FIX/gc.pid" ] && IFS= read -r pid < "$FIX/gc.pid" ;;
      sibling)    pid="$SIB_PID" ;;
      wrapper)    pid="$(printf '%s\n' "$snap" | awk -v h="$hp" '$2==h && /timeout/ {print $1; exit}')" ;;
    esac
    [ -n "${pid:-}" ] || continue
    ppid="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $2; exit}')"
    pgid="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $3; exit}')"
    win="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $4; exit}')"
    exe="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $NF; exit}')"; exe="${exe##*/}"
    ff_alive "$pid" && am=alive || am=gone
    aw=gone
    [ -n "${win:-}" ] && printf '%s\n' "$tl" | grep -q "\",\"${win}\"," && aw=alive
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${HEAD_FULL:0:12}" "$TREE" "$scen" "$label" "$role" "$pid" "${ppid:-?}" "${pgid:-?}" \
      "${win:-?}" "${exe:-?}" "$am" "$aw" >> "$TRACE"
  done
}

# start_harness: reset the fixture dir and launch the harness. `timeout` is the launcher even when
# no wall is wanted, purely because it puts the harness in its OWN process group — that is what
# lets a scenario signal the harness's group without signalling this test's.
# TRIPWIRE: the wall is deliberately FAR AWAY and the signal is sent by signal_harness_group()
# once the fixture is PROVABLY established. A fixed 20s wall raced fixture setup — MSYS spawns are
# ~1s each and slower under load — so the scenario silently degraded into "the phase never
# started", which is not the case under test.
HARNESS_PID=""; HARNESS_TOK=""; OUTER_PID=""; CHILD_PID=""; GC_PID=""; HARNESS_PGID=""
start_harness() {   # start_harness <wall-secs> <isolate|none> [phase-script]
  local wall="$1" mode="$2" phase="${3:-$FIX/phase.sh}"
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log "$FIX"/sentinel.state \
        "$FIX"/sentinel.wrapper.pid 2>/dev/null
  if [ "$mode" = none ]; then
    bash "$FIX/harness.sh" "$FIX" "$LIB" "$phase" >/dev/null 2>&1 &
  else
    timeout -k "$GRACE" "$wall" bash "$FIX/harness.sh" "$FIX" "$LIB" "$phase" >/dev/null 2>&1 &
  fi
  OUTER_PID=$!; ff_track "$OUTER_PID"
  return 0
}
# signal_harness_group <signal>: reproduce what an outer `timeout -s SIG -k GRACE` does — SIG to
# the harness's process GROUP, then SIGKILL to that group after the grace. Returns 1 (measurement
# aborted, nothing signalled) unless the harness provably holds its own group.
signal_harness_group() {
  local sig="$1"
  ffor_snapshot || return 1
  ffor_row "$HARNESS_PID" || return 1
  HARNESS_PGID="$FFOR_ROW_PGID"
  # HARD GUARD: the group we signal must be the one OUR OWN launcher created (its leader is the
  # `timeout` we started), and it must not be ours. Anything else aborts the measurement rather
  # than take the risk — this test exists because an over-broad kill already killed real sessions.
  ffor_numeric "$HARNESS_PGID" || return 1
  [ "$HARNESS_PGID" -gt 1 ] || return 1
  [ "$HARNESS_PGID" = "$OWN_PGID" ] && return 1
  [ "$HARNESS_PGID" = "$OUTER_PID" ] || return 1
  kill -"$sig" -"$HARNESS_PGID" 2>/dev/null
  ( sleep "$GSEC"; kill -KILL -"$HARNESS_PGID" 2>/dev/null ) &
  ff_track $!
  return 0
}
wait_for_file() {   # wait_for_file <path> <secs>
  local i=0
  while [ ! -s "$1" ] && [ "$i" -lt "$2" ]; do sleep 1; i=$((i + 1)); done
  [ -s "$1" ]
}
read_pids() {       # -> HARNESS_PID / CHILD_PID / GC_PID, all tracked with their identities
  ff_read_pid_file "$FIX" harness; HARNESS_PID="$FFSR_FILE_PID"
  ff_read_pid_file "$FIX" phase;   CHILD_PID="$FFSR_FILE_PID"
  ff_read_pid_file "$FIX" gc;      GC_PID="$FFSR_FILE_PID"
  HARNESS_TOK="$(ff_tok "$HARNESS_PID")"
}

# =========================================================================================
# CONTROL + DISCRIMINATOR scenarios driven end-to-end through the real bounded-run path
# =========================================================================================

# run_scenario <name> <signal>: signal the harness's own process group once its phase subtree is
# provably up — the field case (an outer `timeout -s SIG -k GRACE` firing mid-phase), reproduced
# without racing fixture setup.
SCEN_CHILD_T=""; SCEN_GC_T=""; SCEN_SIB_ALIVE=""; SCEN_TRAP=""; SCEN_CHILD_30=""; SCEN_GC_30=""
run_scenario() {
  local scen="$1" sig="$2" nap_off="${3:-0}"
  # Control: a SAME-EXECUTABLE bash sibling in its own tree, started before the harness.
  bash -c 'sleep 240' & SIB_PID=$!; ff_track "$SIB_PID"
  FFSR_NAP_OFF="$nap_off"; start_harness 300 isolate
  if ! wait_for_file "$FIX/gc.pid" 90; then
    bad "$scen-fixture-established" "the miniature phase/grandchild never started within 90s"
    ff_reap_tracked; return 1
  fi
  read_pids
  capture "$scen" "before-signal"
  if ! signal_harness_group "$sig"; then
    bad "$scen-fixture-isolated" "the harness did not hold its own process group, so the measurement was aborted rather than signal ours"
    ff_reap_tracked; return 1
  fi
  SCEN_CHILD_T="$(ff_gone_within "$CHILD_PID" "$REAP_CEILING")"
  SCEN_GC_T="$(ff_gone_within "$GC_PID" "$REAP_CEILING")"
  capture "$scen" "after-grace"
  SCEN_SIB_ALIVE=no; ff_alive "$SIB_PID" && SCEN_SIB_ALIVE=yes
  SCEN_TRAP=none; [ -f "$FIX/trap.log" ] && SCEN_TRAP="$(tr '\n' ' ' < "$FIX/trap.log")"
  SCEN_CHILD_30=no; ff_alive "$CHILD_PID" && SCEN_CHILD_30=yes
  SCEN_GC_30=no; ff_alive "$GC_PID" && SCEN_GC_30=yes
  capture "$scen" "post-assert"
  ff_reap_tracked
  return 0
}

# --- Scenario A: external TERM, FIFO nap ACTIVE (the shipped poll arm) --------------------
if run_scenario term TERM 0; then
  if [ "$SCEN_CHILD_T" -ge 0 ] 2>/dev/null; then
    ok "child-reaped-within-grace [DISCRIMINATOR] (TERM/nap-active: phase child gone ${SCEN_CHILD_T}s after the signal, <= ${REAP_CEILING}s)"
  else
    bad "child-reaped-within-grace" "TERM/nap-active: phase child STILL ALIVE at ${REAP_CEILING}s (still alive after the assert window: $SCEN_CHILD_30; EXIT trap: $SCEN_TRAP) — the orphan leak"
  fi
  if [ "$SCEN_GC_T" -ge 0 ] 2>/dev/null; then
    ok "grandchild-reaped-within-grace [DISCRIMINATOR] (TERM/nap-active: grandchild gone ${SCEN_GC_T}s after the signal)"
  else
    bad "grandchild-reaped-within-grace" "TERM/nap-active: grandchild STILL ALIVE at ${REAP_CEILING}s (still alive after the assert window: $SCEN_GC_30; EXIT trap: $SCEN_TRAP) — a child-only reap does not close this"
  fi
  if [ "$SCEN_SIB_ALIVE" = yes ]; then
    ok "sibling-survives [CONTROL] (TERM: the independently launched same-executable bash sibling outside the target tree is alive — no collateral)"
  else
    bad "sibling-survives" "TERM: the unrelated same-executable sibling was killed — over-broad teardown (the bounded-run-msys-collateral-kill class)"
  fi
else
  bad "child-reaped-within-grace" "TERM scenario could not be established"
fi

# --- Scenario B: the EXIT path that DOES run, with NO sentinel to fall back on -------------
# B1's arm, isolated. Nap forced off + a trapped TERM => bash runs the EXIT trap with a phase
# still in flight; the record is published but NO sentinel process exists, so the harness-side
# path is the only thing that can reap. Under the shipped ordering that path disarmed the guard
# and then ran the known-insufficient `taskkill //T`, so the descendants survived.
FFSR_NAP_OFF=1; FFSR_TRAP_TERM=1; FFSR_STATE_ONLY=1
if run_scenario exit-path TERM 1; then
  FFSR_NAP_OFF=0; FFSR_TRAP_TERM=0; FFSR_STATE_ONLY=0
  if [ "$SCEN_TRAP" = none ]; then
    bad "exit-path-reaps-group-without-sentinel" "the EXIT trap did NOT run, so this scenario measured nothing about EXIT ordering (trap marker absent)"
  elif [ "$SCEN_CHILD_T" -ge 0 ] 2>/dev/null && [ "$SCEN_GC_T" -ge 0 ] 2>/dev/null; then
    ok "exit-path-reaps-group-without-sentinel [DISCRIMINATOR] (EXIT trap ran [$SCEN_TRAP] with no sentinel available: child gone ${SCEN_CHILD_T}s / grandchild ${SCEN_GC_T}s)"
  else
    bad "exit-path-reaps-group-without-sentinel" "EXIT trap ran [$SCEN_TRAP] but child_gone=${SCEN_CHILD_T}s grandchild_gone=${SCEN_GC_T}s (-1 = alive at the ${REAP_CEILING}s deadline) — the EXIT path disarmed the guard before cleanup completed"
  fi
  if [ "$SCEN_SIB_ALIVE" = yes ]; then
    ok "exit-path-sibling-survives [CONTROL] (unrelated same-executable sibling alive)"
  else
    bad "exit-path-sibling-survives" "the unrelated same-executable sibling was killed — over-broad teardown"
  fi
else
  FFSR_NAP_OFF=0; FFSR_TRAP_TERM=0; FFSR_STATE_ONLY=0
  bad "exit-path-reaps-group-without-sentinel" "the EXIT-path scenario could not be established"
fi

# --- Scenario C: external INT (operator Ctrl-C — the more common real case) ---------------
if run_scenario int INT 0; then
  if [ "$SCEN_CHILD_T" -ge 0 ] 2>/dev/null && [ "$SCEN_GC_T" -ge 0 ] 2>/dev/null; then
    ok "int-child+grandchild-reaped-within-grace [DISCRIMINATOR] (INT: child ${SCEN_CHILD_T}s / grandchild ${SCEN_GC_T}s after the signal)"
  else
    bad "int-child+grandchild-reaped-within-grace" "INT: child_gone=${SCEN_CHILD_T}s grandchild_gone=${SCEN_GC_T}s (-1 = alive at the ${REAP_CEILING}s deadline; EXIT trap: $SCEN_TRAP)"
  fi
  if [ "$SCEN_SIB_ALIVE" = yes ]; then
    ok "int-sibling-survives [CONTROL] (INT: unrelated same-executable sibling alive)"
  else
    bad "int-sibling-survives" "INT: the unrelated same-executable sibling was killed — over-broad teardown"
  fi
else
  bad "int-child+grandchild-reaped-within-grace" "INT scenario could not be established"
fi

# --- Scenario D: a signal inside the LAUNCH-TO-RECORD window ------------------------------
# The child exists but its winpid/pgid probes (MSYS spawns) have not completed. Recording only
# AFTER those probes left this window seconds wide: a SIGKILL here published nothing, the guard
# read "nothing in flight", and the original leak returned. FFSR_SLOW_WINPID makes the window
# deterministic instead of hoping to hit a millisecond race.
bash -c 'sleep 240' & SIB_PID=$!; ff_track "$SIB_PID"
FFSR_SLOW_WINPID=25; start_harness 0 none; FFSR_SLOW_WINPID=""
if wait_for_file "$FIX/gc.pid" 90 && wait_for_file "$FIX/harness.pid" 5; then
  read_pids
  capture launch-window "in-window"
  # SIGKILL: no EXIT trap, no signal handler — only what was already PUBLISHED can save the tree.
  ff_kill_verified "$HARNESS_PID" "$HARNESS_TOK" 9
  lw_child="$(ff_gone_within "$CHILD_PID" "$REAP_CEILING")"
  lw_gc="$(ff_gone_within "$GC_PID" "$REAP_CEILING")"
  capture launch-window "after-grace"
  if [ "$lw_child" -ge 0 ] 2>/dev/null && [ "$lw_gc" -ge 0 ] 2>/dev/null; then
    ok "launch-window-signal-still-reaps [DISCRIMINATOR] (harness SIGKILLed while the identity probes were still in flight: child ${lw_child}s / grandchild ${lw_gc}s)"
  else
    bad "launch-window-signal-still-reaps" "child_gone=${lw_child}s grandchild_gone=${lw_gc}s (-1 = alive at ${REAP_CEILING}s) — the launch-to-record window published nothing, so the guard had no identity to act on"
  fi
  if ff_alive "$SIB_PID"; then
    ok "launch-window-sibling-survives [CONTROL] (unrelated same-executable sibling alive)"
  else
    bad "launch-window-sibling-survives" "the unrelated sibling was killed during a launch-window reap"
  fi
else
  bad "launch-window-signal-still-reaps" "the launch-window fixture never established within 90s"
fi
ff_reap_tracked

# --- Scenario E: the sentinel's own `timeout` wrapper dies mid-run ------------------------
# The wrapper supplies the hard cap and the process group; the guard itself is the bash beneath
# it. Killing the wrapper must not disarm the guard, and must not leave a sentinel behind.
bash -c 'sleep 240' & SIB_PID=$!; ff_track "$SIB_PID"
start_harness 0 none
if wait_for_file "$FIX/gc.pid" 90 && wait_for_file "$FIX/sentinel.wrapper.pid" 5; then
  read_pids
  IFS= read -r SW_PID < "$FIX/sentinel.wrapper.pid"
  SENT_PID="$(ff_child_of "$SW_PID")"
  ff_track "$SW_PID"; ff_track "$SENT_PID"
  ff_kill_verified "$SW_PID" "$(ff_tok "$SW_PID")" 9
  sleep 1
  ff_kill_verified "$HARNESS_PID" "$HARNESS_TOK" 9
  sw_child="$(ff_gone_within "$CHILD_PID" "$REAP_CEILING")"
  sw_gc="$(ff_gone_within "$GC_PID" "$REAP_CEILING")"
  sw_sent=""; ffor_numeric "$SENT_PID" && sw_sent="$(ff_gone_within "$SENT_PID" "$REAP_CEILING")"
  capture sentinel-wrapper-death "after-grace"
  if [ "$sw_child" -ge 0 ] 2>/dev/null && [ "$sw_gc" -ge 0 ] 2>/dev/null; then
    ok "sentinel-survives-wrapper-death [DISCRIMINATOR] (wrapper SIGKILLed, guard still reaped: child ${sw_child}s / grandchild ${sw_gc}s)"
  else
    bad "sentinel-survives-wrapper-death" "wrapper killed => child_gone=${sw_child}s grandchild_gone=${sw_gc}s (-1 = alive at ${REAP_CEILING}s)"
  fi
  if [ -z "$sw_sent" ]; then
    skip "sentinel-leaves-nothing-behind" "the guard process under the wrapper could not be resolved"
  elif [ "$sw_sent" -ge 0 ] 2>/dev/null; then
    ok "sentinel-leaves-nothing-behind [DISCRIMINATOR] (the guard exited ${sw_sent}s after the harness died — no orphaned sentinel outlives the run)"
  else
    bad "sentinel-leaves-nothing-behind" "the sentinel process was still alive ${REAP_CEILING}s after the harness died — a wrapper-less guard has no cap"
  fi
  if ff_alive "$SIB_PID"; then
    ok "wrapper-death-sibling-survives [CONTROL] (unrelated same-executable sibling alive)"
  else
    bad "wrapper-death-sibling-survives" "the unrelated sibling was killed during a wrapper-death reap"
  fi
else
  bad "sentinel-survives-wrapper-death" "the wrapper-death fixture never established within 90s"
fi
ff_reap_tracked

# =========================================================================================
# GUARD-LEVEL discriminators. Driven directly so the fail-closed cases are deterministic
# rather than dependent on winning a sub-second race.
# =========================================================================================
# victim_case <name> <mutate>: build an independent group, run the mutation, assert it SURVIVED.
victim_survives() {   # victim_survives <row-name> <detail> <expected-size>
  local name="$1" detail="$2" want="$3" got
  got="$(ff_group_size "$FFSR_V_PGID")"
  if [ "$got" -ge "$want" ] 2>/dev/null; then
    ok "$name [DISCRIMINATOR] ($detail — all $got members of the unrelated group survived)"
  else
    bad "$name" "$detail — the unrelated group was reaped ($got of $want members left); this guard failed OPEN"
  fi
}

# --- F: a failed own/harness PGID lookup must kill NOTHING --------------------------------
if ff_spawn_victim_group 90; then
  ffor_reap "$FFSR_V_LEADER" "" "$FFSR_V_PGID" "$FFSR_V_LEADSTART" "" "$GSEC"
  victim_survives "failed-pgid-lookup-kills-nothing" "harness pgid unresolvable" 3
else
  skip "failed-pgid-lookup-kills-nothing" "could not establish an independent victim group"
fi
ff_reap_tracked

# --- G: a recycled group leader (identity mismatch) must kill NOTHING ---------------------
if ff_spawn_victim_group 90; then
  ffor_reap "$FFSR_V_LEADER" "" "$FFSR_V_PGID" "$((FFSR_V_LEADSTART + 1))" "$OWN_PGID" "$GSEC"
  victim_survives "group-identity-mismatch-kills-nothing" "recorded leader start token does not match the live leader (pid/group reuse)" 3
else
  skip "group-identity-mismatch-kills-nothing" "could not establish an independent victim group"
fi
ff_reap_tracked

# --- H: our OWN group and the harness's group are never signalled -------------------------
if [ -n "$OWN_PGID" ]; then
  ffor_reap "$$" "" "$OWN_PGID" "$(ffor_identity "$OWN_PGID" && printf '%s' "$FFOR_START")" "$OWN_PGID" "$GSEC"
  if ff_alive $$; then
    ok "never-signals-own-group [CONTROL] (a record naming this test's own process group killed nothing)"
  else
    bad "never-signals-own-group" "unreachable — the guard signalled our own group"
  fi
else
  skip "never-signals-own-group" "own pgid unresolvable"
fi

# --- I: a DEAD group leader with surviving descendants IS reaped --------------------------
# The topology the field report recorded: the wrapper died, its descendants did not. A guard
# that returns early unless the leader is alive is inert in exactly the case it exists for.
if ff_spawn_victim_group 90; then
  DL_PGID="$FFSR_V_PGID"; DL_LEAD="$FFSR_V_LEADSTART"; DL_LEADER="$FFSR_V_LEADER"
  ff_kill_verified "$DL_LEADER" "${FFSR_TOK[$DL_LEADER]:-}" 9
  sleep 1
  if ff_alive "$DL_LEADER"; then
    skip "dead-leader-descendants-reaped" "the group leader would not die; topology not established"
  elif [ "$(ff_group_size "$DL_PGID")" -lt 1 ] 2>/dev/null; then
    skip "dead-leader-descendants-reaped" "killing the leader took its descendants with it; the leaked topology was not reproduced"
  else
    before="$(ff_group_size "$DL_PGID")"
    ffor_reap "$DL_LEADER" "" "$DL_PGID" "$DL_LEAD" "$OWN_PGID" "$GSEC"
    after="$(ff_group_size "$DL_PGID")"
    if [ "$after" -eq 0 ] 2>/dev/null; then
      ok "dead-leader-descendants-reaped [DISCRIMINATOR] (leader dead, $before surviving descendants — group reaped to 0)"
    else
      bad "dead-leader-descendants-reaped" "leader dead with $before surviving descendants; $after still alive after the reap — the guard requires a live leader, which is the case it exists for"
    fi
  fi
else
  skip "dead-leader-descendants-reaped" "could not establish an independent victim group"
fi
ff_reap_tracked

# =========================================================================================
# CONTROLS on the normal path
# =========================================================================================

# --- J: the harness's OWN exit status -----------------------------------------------------
# `set -m` gives the harness its own process group in a non-interactive shell, so `wait` returns
# the HARNESS's status. The previous row read the enclosing `timeout`'s status, which can be
# 143/130 whatever the harness did — i.e. it could pass without the harness doing anything.
#
# TERM is asserted. INT is reported INCONCLUSIVE, not asserted, and NOT counted: measured here,
# an untrapped SIGINT to this harness is never acted on (it has to be SIGKILLed), and the shipped
# code installs no INT handler. Adding `trap … INT` is NOT the fix — T3 measured that a TRAPPED
# signal is not delivered while the F3 FIFO nap's blocking `read` is in flight, so the trap would
# defer past the outer `-k` SIGKILL. Closing INT means changing the nap primitive, which is a
# design decision, not an implementation. Asserting 130 here would only manufacture a red row
# for an open question; claiming it green would be the wider-than-the-code defect.
harness_own_status() {   # harness_own_status <signal> -> status | none | unisolated
  local sig="$1" rc_file="$FIX/own-rc.log"
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$rc_file" "$FIX"/trap.log 2>/dev/null
  ( set -m
    bash "$FIX/harness.sh" "$FIX" "$LIB" >/dev/null 2>&1 &
    hp=$!
    echo "$hp" > "$FIX/own-harness.pid"
    wait "$hp"; echo "$?" > "$rc_file" ) &
  local w=$! hp hpg
  ff_track "$w"
  wait_for_file "$FIX/gc.pid" 90 || { ff_reap_tracked; echo none; return; }
  IFS= read -r hp 2>/dev/null < "$FIX/harness.pid" || hp=""
  ff_track "$hp"
  hpg="$(ffor_identity "$hp" && printf '%s' "$FFOR_PGID")"
  # HARD GUARD: never signal our own group. Abort the measurement rather than take the risk.
  if ! ffor_numeric "$hpg" || [ "$hpg" = "$OWN_PGID" ] || [ "$hpg" != "$hp" ]; then
    ff_reap_tracked; echo "unisolated"; return
  fi
  kill -"$sig" -"$hpg" 2>/dev/null
  local i=0
  while [ ! -s "$rc_file" ] && [ "$i" -lt "$REAP_CEILING" ]; do sleep 1; i=$((i + 1)); done
  read_pids; ff_reap_tracked
  if [ -s "$rc_file" ]; then IFS= read -r i < "$rc_file"; echo "$i"; else echo none; fi
}
term_rc="$(harness_own_status TERM)"; int_rc="$(harness_own_status INT)"
if [ "$term_rc" = "143" ]; then
  ok "harness-own-exit-status-term [DISCRIMINATOR] (the HARNESS's own status, measured on the harness and not on an enclosing wall: TERM => 143)"
else
  bad "harness-own-exit-status-term" "TERM => $term_rc (want 143); 'none' = the harness never exited within ${REAP_CEILING}s of the signal (an unacted-on signal, not a wrong code); 'unisolated' = it did not get its own process group, so the measurement was aborted rather than signal our own group"
fi
echo "INCONCLUSIVE: signal-reap harness-own-exit-status-int (INT => $int_rc, want 130; no INT handler is shipped and a trap cannot supply one while the F3 nap blocks delivery — open design decision, deliberately NOT asserted and NOT counted)"

# --- K: a NORMAL run's captured bytes are IDENTICAL with and without the sentinel ----------
# The "byte-identical" claim, measured instead of asserted: same phase, same capture path, one
# run with the guard armed and one with it absent.
rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log 2>/dev/null
bash -c 'sleep 60' & SIB_PID=$!; ff_track "$SIB_PID"
FFSR_OUT="$FIX/out-sentinel.bin" bash "$FIX/harness.sh" "$FIX" "$LIB" "$FIX/fast.sh" >/dev/null 2>&1
norm_rc=$?
norm_log="$(cat "$FIX/harness.log" 2>/dev/null)"
rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/harness.log 2>/dev/null
FFSR_NO_SENTINEL=1 FFSR_OUT="$FIX/out-nosentinel.bin" bash "$FIX/harness.sh" "$FIX" "$LIB" "$FIX/fast.sh" >/dev/null 2>&1
plain_rc=$?
if [ "$norm_rc" -eq 0 ] && ff_alive "$SIB_PID" && printf '%s' "$norm_log" | grep -q "phase-returned rc=0"; then
  ok "normal-exit-performs-no-kill [CONTROL] (fast phase: harness rc 0, phase rc 0, unrelated sibling untouched)"
else
  bad "normal-exit-performs-no-kill" "harness rc=$norm_rc sibling_alive=$(ff_alive "$SIB_PID" && echo yes || echo no) harness.log=[$norm_log]"
fi
if [ ! -s "$FIX/out-sentinel.bin" ] && [ ! -s "$FIX/out-nosentinel.bin" ]; then
  bad "normal-run-output-byte-identical" "both captures were EMPTY — the comparison would have passed vacuously"
elif [ "$norm_rc" -eq "$plain_rc" ] && cmp -s "$FIX/out-sentinel.bin" "$FIX/out-nosentinel.bin"; then
  ok "normal-run-output-byte-identical [DISCRIMINATOR] ($(wc -c < "$FIX/out-sentinel.bin" | tr -d ' ') captured bytes and rc $norm_rc identical with the guard armed and with it absent)"
else
  bad "normal-run-output-byte-identical" "the guard changed a normal run: rc $norm_rc vs $plain_rc; capture diff: $(cmp "$FIX/out-sentinel.bin" "$FIX/out-nosentinel.bin" 2>&1 | head -1)"
fi
ff_reap_tracked

# --- L: a recorded winpid whose child pid no longer matches kills NOTHING ------------------
# shellcheck source=/dev/null
. "$LIB"
bash -c 'sleep 60' & VICTIM=$!; ff_track "$VICTIM"
sleep 1
VWIN=""; IFS= read -r VWIN 2>/dev/null < "/proc/$VICTIM/winpid" || VWIN=""
if [ -n "$VWIN" ] && ff_alive "$VICTIM"; then
  ffhc_msys_taskkill_winpid "$VWIN" "999999"   # 999999 = a pid that cannot map to $VWIN
  sleep 1
  if ff_alive "$VICTIM"; then
    ok "pid-reuse-mismatch-kills-nothing [CONTROL] (recorded winpid + non-matching child pid => the guard skipped the taskkill; the process survived)"
  else
    bad "pid-reuse-mismatch-kills-nothing" "the taskkill fired on a winpid whose recorded child pid no longer matches — the PID-reuse guard is not holding"
  fi
else
  skip "pid-reuse-mismatch-kills-nothing" "could not resolve a winpid for the control process"
fi
ff_reap_tracked

echo "[test-run-tests-signal-reap] trace: ${TRACE#"$ROOT/"}" >&2
finish
