#!/usr/bin/env bash
# Fusebase Flow — S2 signal-reap regression arm. Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# TIER: CI / FF_FULL only — never the fast local default. This is fault injection (it kills live
# process trees), not ordinary regression coverage, and the orphan sentinel it exercises runs only
# around the Windows/MSYS deep runner. Reach it with FF_ONLY=signal-reap or FF_FULL=1.
# Rationale: docs/specs/backlog-triage-execution/architecture-review.md Q3/Q4.
#
# WHAT IT DRIVES: the field case — a harness SIGKILLed mid-phase must leave zero surviving
# descendants — plus direct drives of the guard primitives for the fail-closed cases a live race
# cannot pin down deterministically.
#
# ROW CLASSES — read the summary line, not the count:
#   DISCRIMINATOR  fails against the pre-fix tree (91f8748^). These are the rows that carry the claim.
#   CONTROL        passed before the fix too; it exists to catch a REGRESSION (collateral, clean
#                  exit). A control PASS proves nothing about the fix.
#
# RESULT STATES (B4 / final-architecture-review finding 4). Three of four discriminators used to
# call skip(), and finish() excluded skips from the exit status — so a loaded Windows run could
# lose most of the defect coverage and still exit 0. The states are now:
#   PASS   the mechanism ran and produced the expected result.
#   FAIL   the mechanism ran and produced the wrong result.
#   ERROR  a DISCRIMINATOR's required topology could not be established. NON-GREEN: it is counted
#          into the exit status. "I could not test it" is not "it works" — that equivalence is
#          exactly what a loaded MSYS host used to buy.
#   SKIP   permitted for CONTROLS only, reported separately, never counted as a PASS. A control
#          that did not run reports nothing about the fix, but it also carries no claim.
#   N/A    declared STATICALLY, before any row is constructed, for a platform where the defect
#          class cannot exist. Off-MSYS this whole phase is N/A: POSIX process-group teardown
#          reaps the phase tree, so there is no MSYS orphan to leak. That is "absent by
#          construction" (zero rows exist, nothing attempted-then-escaped), and the coverage is
#          owned by the REQUIRED verify-windows-msys leg. It is not a runtime escape: no row can
#          reach N/A, only the platform gate above them can.
#
# ROW MANIFEST (DECLARED_ROWS below) — every declared row must report exactly one terminal state.
# A row that vanishes entirely (an early `return`, a refactor that drops a block) is reported as a
# missing row, not as a smaller-but-green suite. The old counter could not see that at all.
#
# SCOPE — deliberately 4 discriminators + 4 collateral controls. re-review-c97f8d2.md § "Coverage
# honesty" measured the previous 19-row suite at 4 real discriminators; the other 15 rows were
# controls or pre-existing behavior re-proved under a different signal, and cost ~1075s to say so.
# Removed as same-property repeats: the TERM and INT kill scenarios (the launch-window SIGKILL below
# proves the same property strictly harder), the sentinel-wrapper-death rows, the TERM=143 default
# exit status, and the with/without-sentinel byte comparison.
# NOT removed and NOT closed: SIGINT exit status 130 is an open DESIGN decision (bash defers a
# trapped signal through the FIFO nap's blocking read), tracked in
# docs/specs/backlog-triage-execution/execution-plan.md — it is not a row here because an
# undecidable row is not coverage.
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

# Every row this phase promises to report. Order is cosmetic; membership is the contract.
DECLARED_ROWS=(
  launch-window-signal-still-reaps            # DISCRIMINATOR
  launch-window-sibling-survives              # CONTROL
  failed-pgid-lookup-kills-nothing            # DISCRIMINATOR
  group-identity-mismatch-kills-nothing       # DISCRIMINATOR
  never-signals-own-group                     # CONTROL
  dead-leader-descendants-reaped              # DISCRIMINATOR
  normal-exit-performs-no-kill                # CONTROL
  pid-reuse-mismatch-kills-nothing            # CONTROL
)

pass=0; fail=0; skipped=0; errors=0
PHASE_APPLICABLE=1
declare -A ROW_SEEN=()
# TRIPWIRE: the row NAME is the first word of $1 (the rest is the class tag + detail), so every
# reporter records ${1%% *}. A reporter that forgets this silently drops its row from the
# completeness check, which is the one thing that check exists to catch.
ok()   { ROW_SEEN[${1%% *}]=PASS;  pass=$((pass + 1)); echo "PASS: signal-reap $1"; }
bad()  { ROW_SEEN[${1%% *}]=FAIL;  fail=$((fail + 1)); echo "FAIL: signal-reap $1 (${2:-})"; }
# err: a DISCRIMINATOR could not establish the mechanism it tests. Emitted on the FAIL channel
# on purpose — run_shell_phase counts ^FAIL: rows, so this reaches the exit status the same way
# a wrong answer does, while the [ERROR] label keeps "could not run" distinguishable from
# "ran and was wrong" for whoever reads the log.
err()  { ROW_SEEN[${1%% *}]=ERROR; fail=$((fail + 1)); errors=$((errors + 1))
         echo "FAIL: signal-reap $1 ([ERROR] required topology not established: ${2:-}) — a discriminator that could not run is NOT a pass"; }
# skip: CONTROLS only. Never counted as a pass, never counted into the exit status.
skip() { ROW_SEEN[${1%% *}]=SKIP;  skipped=$((skipped + 1)); echo "SKIP: signal-reap $1 — ${2:-}" >&2; }
finish() {
  if [ "$PHASE_APPLICABLE" -eq 1 ]; then
    local n missing=""
    for n in "${DECLARED_ROWS[@]}"; do [ -n "${ROW_SEEN[$n]:-}" ] || missing="$missing $n"; done
    if [ -n "$missing" ]; then
      fail=$((fail + 1))
      echo "FAIL: signal-reap rows-complete ([ERROR] declared row(s) never reported:$missing — the suite got smaller, not greener)"
    fi
  fi
  echo "[test-run-tests-signal-reap] $pass/$((pass + fail)) PASS, $fail FAIL (of which $errors are ERROR: mechanism not established), $skipped SKIP (skips are CONTROLS only and are NOT passes)"
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

# STATIC PLATFORM GATE (see § RESULT STATES). Off-MSYS this phase is N/A by construction: the
# gate fires here, before a single row is constructed, so no discriminator is ever present-and-
# escaping. The coverage is owned by the REQUIRED verify-windows-msys leg.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) : ;;
  *) PHASE_APPLICABLE=0
     echo "N/A: signal-reap all-scenarios — off-MSYS. POSIX process-group teardown reaps the phase tree, so this defect class cannot exist here. Declared statically; owned by the required verify-windows-msys job."
     finish ;;
esac
# On MSYS the timeout binary is a REQUIRED mechanism, not a platform property — every
# discriminator below is driven through it. Missing it is an ERROR, never a green skip.
if [ -z "$(command -v timeout || true)" ]; then
  for _r in "${DECLARED_ROWS[@]}"; do err "$_r" "no timeout binary on PATH; the bounded runner every scenario drives cannot start"; done
  finish
fi

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
export FFSR_SLOW_WINPID="" FFSR_PHASE_SECS=300

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

# start_harness: reset the fixture dir and launch the harness in its OWN process group.
HARNESS_PID=""; HARNESS_TOK=""; OUTER_PID=""; CHILD_PID=""; GC_PID=""
start_harness() {   # start_harness <phase-script>
  local phase="${1:-$FIX/phase.sh}"
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log "$FIX"/sentinel.state \
        "$FIX"/sentinel.wrapper.pid 2>/dev/null
  bash "$FIX/harness.sh" "$FIX" "$LIB" "$phase" >/dev/null 2>&1 &
  OUTER_PID=$!; ff_track "$OUTER_PID"
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
# THE FIELD DISCRIMINATOR — killed harness => zero surviving descendants
# =========================================================================================
# A signal inside the LAUNCH-TO-RECORD window: the child exists but its winpid/pgid probes (MSYS
# spawns) have not completed. Recording only AFTER those probes left this window seconds wide — a
# SIGKILL here published nothing, the guard read "nothing in flight", and the leak returned.
# FFSR_SLOW_WINPID makes the window deterministic instead of hoping to hit a millisecond race.
# SIGKILL is used on purpose: no EXIT trap, no signal handler, so ONLY what was already PUBLISHED
# can save the tree. That makes this strictly harder than the TERM/INT arms it replaces.
#
# TRIPWIRE (measured): the widened window must outlast THIS TEST's own pre-kill overhead — the
# `capture` below spawns `ps` + `tasklist`, tens of seconds on a loaded MSYS host. At the former
# 25s the probe finished first, the full tuple was already published, and the row went green
# against a deliberately re-broken publication order (mutation: publish AFTER the winpid probe).
# So the window is 120s AND `lw_window` below PROVES it was open at kill time; a raced window is
# reported red ("could not discriminate"), never as a pass.
ff_spawn_sibling; SIB_PID="$FFSR_SIB_PID"
FFSR_SLOW_WINPID=120; start_harness; FFSR_SLOW_WINPID=""
if wait_for_file "$FIX/gc.pid" 90 && wait_for_file "$FIX/harness.pid" 5; then
  read_pids
  capture launch-window "in-window"
  # Window state at the moment of the kill, read from the record the sentinel actually consumes:
  #   open   = pid published, winpid/pgid still "-" (probes in flight)  -> the case under test
  #   empty  = nothing published at all                                 -> the B6 defect itself
  #   closed = full tuple already published                             -> we lost the race
  lw_window=empty; lw_state=""
  [ -s "$FIX/sentinel.state" ] && IFS= read -r lw_state < "$FIX/sentinel.state"
  if [ -n "$lw_state" ] && [ -s "$lw_state" ]; then
    case "$(tail -n 1 "$lw_state" 2>/dev/null)" in
      *" - - END") lw_window=open ;;
      *)           lw_window=closed ;;
    esac
  fi
  ff_kill_verified "$HARNESS_PID" "$HARNESS_TOK" 9
  lw_child="$(ff_gone_within "$CHILD_PID" "$REAP_CEILING")"
  lw_gc="$(ff_gone_within "$GC_PID" "$REAP_CEILING")"
  capture launch-window "after-grace"
  if [ "$lw_window" = closed ]; then
    bad "launch-window-signal-still-reaps" "the launch-to-record window had already CLOSED at kill time (full tuple published) — this row could not discriminate on this host; raise FFSR_SLOW_WINPID above the pre-kill \`ps\`/\`tasklist\` cost. Reported red, never as a pass."
  elif [ "$lw_child" -ge 0 ] 2>/dev/null && [ "$lw_gc" -ge 0 ] 2>/dev/null; then
    ok "launch-window-signal-still-reaps [DISCRIMINATOR] (window provably $lw_window at kill time; harness SIGKILLed while the identity probes were still in flight: child ${lw_child}s / grandchild ${lw_gc}s)"
  else
    bad "launch-window-signal-still-reaps" "window=$lw_window child_gone=${lw_child}s grandchild_gone=${lw_gc}s (-1 = alive at ${REAP_CEILING}s) — the launch-to-record window published nothing, so the guard had no identity to act on"
  fi
  if ff_alive "$SIB_PID"; then
    ok "launch-window-sibling-survives [CONTROL] (the independently launched same-executable bash sibling outside the target tree is alive — no collateral)"
  else
    bad "launch-window-sibling-survives" "the unrelated same-executable sibling was killed — over-broad teardown (the bounded-run-msys-collateral-kill class)"
  fi
else
  bad "launch-window-signal-still-reaps" "the launch-window fixture never established within 90s"
fi
ff_reap_tracked

# =========================================================================================
# GUARD-LEVEL discriminators. Driven directly so the fail-closed cases are deterministic
# rather than dependent on winning a sub-second race.
# =========================================================================================
victim_survives() {   # victim_survives <row-name> <detail> <expected-size>
  local name="$1" detail="$2" want="$3" got
  got="$(ff_group_size "$FFSR_V_PGID")"
  if [ "$got" -ge "$want" ] 2>/dev/null; then
    ok "$name [DISCRIMINATOR] ($detail — all $got members of the unrelated group survived)"
  else
    bad "$name" "$detail — the unrelated group was reaped ($got of $want members left); this guard failed OPEN"
  fi
}

# --- a failed own/harness PGID lookup must kill NOTHING -----------------------------------
if ff_spawn_victim_group 90; then
  ffor_reap "$FFSR_V_LEADER" "" "$FFSR_V_PGID" "$FFSR_V_LEADSTART" "" "$GSEC"
  victim_survives "failed-pgid-lookup-kills-nothing" "harness pgid unresolvable" 3
else
  err "failed-pgid-lookup-kills-nothing" "could not establish an independent victim group"
fi
ff_reap_tracked

# --- a recycled group leader (identity mismatch) must kill NOTHING ------------------------
if ff_spawn_victim_group 90; then
  ffor_reap "$FFSR_V_LEADER" "" "$FFSR_V_PGID" "$((FFSR_V_LEADSTART + 1))" "$OWN_PGID" "$GSEC"
  victim_survives "group-identity-mismatch-kills-nothing" "recorded leader start token does not match the live leader (pid/group reuse)" 3
else
  err "group-identity-mismatch-kills-nothing" "could not establish an independent victim group"
fi
ff_reap_tracked

# --- our OWN group and the harness's group are never signalled ----------------------------
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

# --- a DEAD group leader with surviving descendants IS reaped -----------------------------
# The topology the field report recorded: the wrapper died, its descendants did not. A guard
# that returns early unless the leader is alive is inert in exactly the case it exists for.
if ff_spawn_victim_group 90; then
  DL_PGID="$FFSR_V_PGID"; DL_LEAD="$FFSR_V_LEADSTART"; DL_LEADER="$FFSR_V_LEADER"
  ff_kill_verified "$DL_LEADER" "${FFSR_TOK[$DL_LEADER]:-}" 9
  sleep 1
  if ff_alive "$DL_LEADER"; then
    err "dead-leader-descendants-reaped" "the group leader would not die; the dead-leader topology was not established"
  elif [ "$(ff_group_size "$DL_PGID")" -lt 1 ] 2>/dev/null; then
    err "dead-leader-descendants-reaped" "killing the leader took its descendants with it; the leaked topology was not reproduced"
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
  err "dead-leader-descendants-reaped" "could not establish an independent victim group"
fi
ff_reap_tracked

# =========================================================================================
# CONTROLS on the normal path — a clean run must kill nothing
# =========================================================================================
rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log 2>/dev/null
ff_spawn_sibling; SIB_PID="$FFSR_SIB_PID"
bash "$FIX/harness.sh" "$FIX" "$LIB" "$FIX/fast.sh" >/dev/null 2>&1
norm_rc=$?
norm_log="$(cat "$FIX/harness.log" 2>/dev/null)"
if [ "$norm_rc" -eq 0 ] && ff_alive "$SIB_PID" && printf '%s' "$norm_log" | grep -q "phase-returned rc=0"; then
  ok "normal-exit-performs-no-kill [CONTROL] (fast phase: harness rc 0, phase rc 0, unrelated sibling untouched)"
else
  bad "normal-exit-performs-no-kill" "harness rc=$norm_rc sibling_alive=$(ff_alive "$SIB_PID" && echo yes || echo no) harness.log=[$norm_log]"
fi
ff_reap_tracked

# --- a recorded winpid whose child pid no longer matches kills NOTHING ---------------------
# The OTHER kill primitive: the guards above bind a POSIX group, this one binds a Windows pid.
# shellcheck source=/dev/null
. "$LIB"
ff_spawn_sibling; VICTIM="$FFSR_SIB_PID"
sleep 1
VWIN=""; IFS= read -r VWIN 2>/dev/null < "/proc/$VICTIM/winpid" || VWIN=""
# Test-only knob (never read by shipped code): force a CONTROL's skip branch, so the other half
# of the B4 claim — a control may still skip and the phase still passes — is demonstrable too.
[ "${FFSR_FORCE_NO_WINPID:-0}" = "1" ] && VWIN=""
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
