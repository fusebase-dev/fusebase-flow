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
  observer-bound-heartbeat-units
  observer-bound-cap
  observer-done-empty-child-error
  observer-done-empty-grandchild-error
  observer-done-nonnumeric-child-error
  observer-done-nonnumeric-grandchild-error
  tracked-identity-survives-msys-exec         # DISCRIMINATOR
  non-reaping-parent-still-reaped
  launch-window-signal-still-reaps            # DISCRIMINATOR
  phase-group-is-not-the-harness-group        # DISCRIMINATOR
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
  : > "$FIX/winpid.release"
  for p in harness phase gc sentinel.wrapper; do ff_read_pid_file "$FIX" "$p"; done
  ff_reap_tracked
  rm -rf "$FIX" 2>/dev/null
}
trap cleanup_fixture EXIT
ff_write_fixture "$FIX" || { bad "setup-fixture" "fixture copy could not establish heartbeat/DEAD/TERM instrumentation"; finish; }
mkfifo "$FIX/observe.fifo" || { bad "setup-fixture" "observer FIFO unavailable"; finish; }
exec {OBS_FD}<>"$FIX/observe.fifo" || { bad "setup-fixture" "observer FIFO could not open"; finish; }

# Fixture knobs are EXPORTED globals set immediately before a launch and reset after: a
# `VAR=x func` prefix on a shell FUNCTION leaks past the call in bash, which would silently
# carry a knob into the next scenario.
export FFSR_WINPID_RELEASE="" FFSR_PHASE_SECS=300

# Our OWN process group. Every scenario that signals a group compares against this FIRST and
# aborts the measurement rather than risk signalling this test's own tree.
OWN_PGID="$(ffor_identity $$ && printf '%s' "$FFOR_PGID")"

printf 'head\ttree\tscenario\tcapture\trole\tpid\tppid\tpgid\twinpid\texe_basename\talive_posix\talive_win\tps_present\tproc_state\tsentinel_state\tsentinel_wrapper_pid\tsentinel_wrapper_alive\tdetect_ms\tterm_ms\treaped_ms\tharness_exit_ms\tchild_exit_ms\tgrandchild_exit_ms\n' > "$TRACE"
SIB_PID=""
capture() {   # capture <scenario> <label>; roles read from the fixture's pid files + one ps snap
  local scen="$1" label="$2" snap tl role pid win ppid pgid exe am aw hp
  snap="$(ps 2>/dev/null)"; tl="$(tasklist //NH //FO CSV 2>/dev/null)"
  hp=""; [ -s "$FIX/harness.pid" ] && IFS= read -r hp < "$FIX/harness.pid"
  for role in harness child grandchild sibling wrapper sentinel; do
    case "$role" in
      harness)    pid="$hp" ;;
      child)      pid=""; [ -s "$FIX/phase.pid" ] && IFS= read -r pid < "$FIX/phase.pid" ;;
      grandchild) pid=""; [ -s "$FIX/gc.pid" ] && IFS= read -r pid < "$FIX/gc.pid" ;;
      sibling)    pid="$SIB_PID" ;;
      wrapper)    pid="$(printf '%s\n' "$snap" | awk -v h="$hp" '$2==h && /timeout/ {print $1; exit}')" ;;
      sentinel)   pid=""; [ -s "$FIX/sentinel.wrapper.pid" ] && IFS= read -r pid < "$FIX/sentinel.wrapper.pid" ;;
    esac
    [ -n "${pid:-}" ] || continue
    ppid="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $2; exit}')"
    pgid="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $3; exit}')"
    win="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $4; exit}')"
    exe="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $NF; exit}')"; exe="${exe##*/}"
    ff_alive "$pid" && am=alive || am=gone
    aw=unknown
    if [ -n "${win:-}" ] && [ -n "$tl" ]; then
      aw=gone; printf '%s\n' "$tl" | grep -q "\",\"${win}\"," && aw=alive
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t?\t?\t?\t?\t?\t?\t?\t?\t?\t?\t?\n' \
      "${HEAD_FULL:0:12}" "$TREE" "$scen" "$label" "$role" "$pid" "${ppid:-?}" "${pgid:-?}" \
      "${win:-?}" "${exe:-?}" "$am" "$aw" >> "$TRACE"
  done
}

# start_harness: reset the fixture dir and launch the harness in its OWN process group.
HARNESS_PID=""; HARNESS_TOK=""; OUTER_PID=""; CHILD_PID=""; GC_PID=""
start_harness() {   # start_harness <phase-script>
  local phase="${1:-$FIX/phase.sh}"
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log "$FIX"/sentinel.state \
        "$FIX"/sentinel.wrapper.pid "$FIX"/winpid.waiting "$FIX"/winpid.release 2>/dev/null
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
  ff_read_pid_file "$FIX" sentinel.wrapper
  HARNESS_TOK="$(ff_tok "$HARNESS_PID")"
}

ff_ms() {
  local stamp="$1" frac="${1#*.}000000"
  frac="${frac:0:6}"
  FFSR_US=$(( ${stamp%%.*} * 1000000 + 10#$frac ))
  FFSR_MS=$((FFSR_US / 1000))
}

observation_trace() {
  local scenario="$1" elapsed="$2" state="$3" wrapper="$4" role pid exited present wrapper_alive
  ffor_snapshot || true
  wrapper_alive=no; [ -e "/proc/$wrapper/exe" ] && wrapper_alive=yes
  for role in harness child grandchild; do
    case "$role" in harness) pid="$HARNESS_PID" ;; child) pid="$CHILD_PID" ;; grandchild) pid="$GC_PID" ;; esac
    exited=alive; [ -e "/proc/$pid/exe" ] || exited=exited
    present=no; ffor_row "$pid" && present=yes
    printf '%s\t%s\t%s\ttick-%sms\t%s\t%s\t%s\t%s\t%s\t?\t%s\t?\t%s\t?\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${HEAD_FULL:0:12}" "$TREE" "$scenario" "$elapsed" "$role" "$pid" \
      "${FFOR_ROW_PPID:-?}" "${FFOR_ROW_PGID:-?}" "${FFOR_ROW_WIN:-?}" "$exited" "$present" "$state" "${wrapper:-?}" "$wrapper_alive" \
      "$FFSR_OBS_DETECT" "$FFSR_OBS_TERM" "$FFSR_OBS_REAPED" "$FFSR_OBS_EXIT" "$FFSR_OBS_CHILD" "$FFSR_OBS_GC" >> "$TRACE"
  done
}

observe_reap() {
  local scenario="$1" state="$2" killed="$3" killed_ms killed_us now elapsed stamp dead_us=-1
  local tick tick_ms last_tick=-1 max_interval=1000 interval beats=0 post_kill=0 between=0
  local cap="${FF_SENTINEL_CAP:-600}" bound last_trace=-3000 trace_pid="" role pid s rest stop
  local state_present wrapper="" done_ok=0
  ff_ms "$killed"; killed_ms="$FFSR_MS"; killed_us="$FFSR_US"
  case "$cap" in ''|*[!0-9]*) cap=600 ;; esac
  FFSR_OBS_STATUS=FAIL; FFSR_OBS_REASON="sentinel did not finish"
  FFSR_OBS_CHILD=-1; FFSR_OBS_GC=-1; FFSR_OBS_EXIT=-1
  FFSR_OBS_DETECT=-1; FFSR_OBS_TERM=-1; FFSR_OBS_REAPED=-1
  FFSR_OBS_PARENT=1; FFSR_OBS_ZOMBIE=0
  [ -s "$FIX/sentinel.wrapper.pid" ] && IFS= read -r wrapper < "$FIX/sentinel.wrapper.pid"
  while :; do
    stop=1
    ff_ms "$EPOCHREALTIME"; now="$FFSR_MS"; elapsed=$((now - killed_ms))
    state_present=yes
    if [ ! -e "$state" ]; then
      state_present=no; FFSR_OBS_REAPED="$elapsed"
      # Do not delay done-point probes behind diagnostics (audit-T134 F1/F2).
      if ! [[ "$CHILD_PID" =~ ^[1-9][0-9]*$ && "$GC_PID" =~ ^[1-9][0-9]*$ ]]; then
        done_ok=-1
      elif [ ! -e "/proc/$CHILD_PID/exe" ] && [ ! -e "/proc/$GC_PID/exe" ]; then
        done_ok=1
      fi
    fi
    for role in harness child grandchild; do
      case "$role" in harness) pid="$HARNESS_PID" ;; child) pid="$CHILD_PID" ;; grandchild) pid="$GC_PID" ;; esac
      ff_ms "$EPOCHREALTIME"; stamp=$((FFSR_MS - killed_ms))
      if [ ! -e "/proc/$pid/exe" ]; then
        case "$role" in
          harness) [ "$FFSR_OBS_EXIT" -lt 0 ] && FFSR_OBS_EXIT="$stamp" ;;
          child) [ "$FFSR_OBS_CHILD" -lt 0 ] && FFSR_OBS_CHILD="$stamp" ;;
          grandchild) [ "$FFSR_OBS_GC" -lt 0 ] && FFSR_OBS_GC="$stamp" ;;
        esac
      fi
    done
    if [ "$scenario" = non-reaping-parent ]; then
      [ -e "/proc/$OUTER_PID/exe" ] || FFSR_OBS_PARENT=0
      if [ "$FFSR_OBS_ZOMBIE" -eq 0 ] && [ "$FFSR_OBS_EXIT" -ge 0 ] && ff_alive "$HARNESS_PID" \
        && IFS= read -r s 2>/dev/null < "/proc/$HARNESS_PID/stat"; then
        case "$s" in *') '*) rest="${s##*) }"; [ "${rest%% *}" = Z ] && FFSR_OBS_ZOMBIE=1 ;; esac
      fi
    fi
    if [ "$dead_us" -lt 0 ] && [ -s "$state.dead" ]; then
      IFS= read -r stamp < "$state.dead"; ff_ms "$stamp"
      dead_us="$FFSR_US"; FFSR_OBS_DETECT=$((FFSR_MS - killed_ms))
    fi
    if [ "$FFSR_OBS_TERM" -lt 0 ] && [ -s "$state.term" ]; then
      IFS= read -r stamp < "$state.term"; ff_ms "$stamp"; FFSR_OBS_TERM=$((FFSR_MS - killed_ms))
    fi
    if [ -s "$state.ticks" ]; then
      while IFS= read -r tick; do
        ff_ms "$tick"; tick_ms="$FFSR_MS"
        [ "$tick_ms" -gt "$last_tick" ] || continue
        if [ "$last_tick" -ge 0 ]; then
          interval=$((tick_ms - last_tick)); [ "$interval" -le "$max_interval" ] || max_interval="$interval"
        fi
        last_tick="$tick_ms"; beats=$((beats + 1))
        [ "$FFSR_US" -le "$killed_us" ] || post_kill=$((post_kill + 1))
      done < "$state.ticks"
      between=0
      while IFS= read -r tick; do
        ff_ms "$tick"
        if [ "$FFSR_US" -gt "$killed_us" ] && { [ "$dead_us" -lt 0 ] || [ "$FFSR_US" -lt "$dead_us" ]; }; then
          between=$((between + 1))
        fi
      done < "$state.ticks"
    fi
    bound=$(((GSEC + 4) * max_interval))
    [ "$bound" -le "$((cap * 1000))" ] || bound=$((cap * 1000))
    if [ "$done_ok" -eq -1 ]; then
      FFSR_OBS_STATUS=ERROR; FFSR_OBS_REASON="child or grandchild PID missing or nonnumeric at sentinel done-point"
    elif [ "$between" -gt 2 ]; then
      FFSR_OBS_REASON="more than two heartbeats after kill before DEAD"
    elif [ "$state_present" = no ]; then
      if [ "$beats" -eq 0 ]; then
        FFSR_OBS_STATUS=ERROR; FFSR_OBS_REASON="sentinel starved: no heartbeat"
      elif [ "$dead_us" -lt 0 ]; then
        FFSR_OBS_REASON="sentinel finished without DEAD"
      elif [ "$done_ok" -ne 1 ]; then
        FFSR_OBS_REASON="child or grandchild still executing at sentinel done-point"
      elif [ "$FFSR_OBS_EXIT" -lt 0 ]; then
        FFSR_OBS_STATUS=ERROR; FFSR_OBS_REASON="harness exit not established"
      else
        FFSR_OBS_STATUS=PASS; FFSR_OBS_REASON="within two kill-anchored heartbeats; zero survivors at sentinel done-point"
      fi
    elif [ "$elapsed" -ge "$bound" ]; then
      if [ "$dead_us" -lt 0 ] && [ "$post_kill" -eq 0 ]; then
        FFSR_OBS_STATUS=ERROR; FFSR_OBS_REASON="sentinel starved: no post-kill heartbeat or DEAD"
      else
        FFSR_OBS_REASON="sentinel hang at (GSEC + 4) * max heartbeat interval (capped by FF_SENTINEL_CAP)"
      fi
    else
      stop=0
    fi
    [ "$stop" -eq 0 ] || break
    if [ "$((elapsed - last_trace))" -ge 3000 ] && { [ -z "$trace_pid" ] || ! ff_alive "$trace_pid"; }; then
      [ -z "$trace_pid" ] || wait "$trace_pid" 2>/dev/null
      last_trace="$elapsed"
      # Keep ps off the 4 Hz exit watcher (audit-T134 F2).
      observation_trace "$scenario" "$elapsed" "$state_present" "$wrapper" & trace_pid=$!
    fi
    read -r -t 0.25 -u "$OBS_FD" _ || true
  done
  [ -z "$trace_pid" ] || wait "$trace_pid" 2>/dev/null
  observation_trace "$scenario" "$elapsed" "$state_present" "$wrapper"
  FFSR_OBS_DETAIL="detect=${FFSR_OBS_DETECT}ms TERM=${FFSR_OBS_TERM}ms reaped=${FFSR_OBS_REAPED}ms exit(harness/child/grandchild)=${FFSR_OBS_EXIT}/${FFSR_OBS_CHILD}/${FFSR_OBS_GC}ms heartbeats=$between bound=${bound}ms (-1 = unobserved); trace=$TRACE"
}

observer_contract_probe() (
  local state="$FIX/observer-contract"
  GSEC=5; FF_SENTINEL_CAP="$1"
  HARNESS_PID=999999999; CHILD_PID="$2"; GC_PID="$3"
  printf '100.000000\n102.000000\n' > "$state.ticks"
  printf '100.500000\n' > "$state.dead"
  observation_trace() { :; }
  observe_reap observer-contract "$state" 100.000000
  printf '%s|%s\n' "$FFSR_OBS_STATUS" "$FFSR_OBS_DETAIL"
)

observer_result="$(observer_contract_probe 600 999999998 999999997)"
case "$observer_result" in
  'PASS|'*'bound=18000ms '*) ok "observer-bound-heartbeat-units [CONTROL]" ;;
  *) bad "observer-bound-heartbeat-units" "$observer_result" ;;
esac
observer_result="$(observer_contract_probe 12 999999998 999999997)"
case "$observer_result" in
  'PASS|'*'bound=12000ms '*) ok "observer-bound-cap [CONTROL]" ;;
  *) bad "observer-bound-cap" "$observer_result" ;;
esac
for observer_case in empty-child empty-grandchild nonnumeric-child nonnumeric-grandchild; do
  case "$observer_case" in
    empty-child) observer_child=""; observer_gc=999999997 ;;
    empty-grandchild) observer_child=999999998; observer_gc="" ;;
    nonnumeric-child) observer_child=invalid; observer_gc=999999997 ;;
    nonnumeric-grandchild) observer_child=999999998; observer_gc=invalid ;;
  esac
  observer_result="$(observer_contract_probe 600 "$observer_child" "$observer_gc")"
  case "$observer_result" in
    'ERROR|'*) ok "observer-done-$observer_case-error [CONTROL]" ;;
    *) bad "observer-done-$observer_case-error" "$observer_result" ;;
  esac
done

report_reap() {
  local row="$1" context="$2"
  case "$FFSR_OBS_STATUS" in
    PASS) ok "$row [DISCRIMINATOR] ($context; $FFSR_OBS_REASON; $FFSR_OBS_DETAIL)" ;;
    ERROR) err "$row" "$context; $FFSR_OBS_REASON; $FFSR_OBS_DETAIL" ;;
    *) bad "$row" "$context; $FFSR_OBS_REASON; $FFSR_OBS_DETAIL" ;;
  esac
}

non_reaping_parent_row() {
  local state="" parent_ready=0 i killed hpg=""
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/sentinel.state
  # Never wait for the harness: exec keeps its parent alive without a SIGCHLD reaper (premise R4).
  bash -c 'bash "$1/harness.sh" "$1" "$2" >/dev/null 2>&1 & exec sleep 600' _ "$FIX" "$LIB" >/dev/null 2>&1 &
  OUTER_PID=$!
  for ((i=0; i<15; i++)); do
    if ffor_identity "$OUTER_PID" && [ "$FFOR_COMM" = sleep ]; then parent_ready=1; break; fi
    sleep 1
  done
  ff_track "$OUTER_PID"
  if [ "$parent_ready" -ne 1 ] || ! wait_for_file "$FIX/gc.pid" 90 || ! wait_for_file "$FIX/sentinel.state" 5; then
    err "non-reaping-parent-still-reaped" "exec-sleep parent or phase fixture did not establish"
  else
    read_pids
    IFS= read -r state < "$FIX/sentinel.state"
    if ! ffor_identity "$HARNESS_PID" || [ "$FFOR_PPID" != "$OUTER_PID" ] || [ ! -e "$state" ] || [ -e "$state.dead" ]; then
      err "non-reaping-parent-still-reaped" "live harness under exec-sleep parent and armed sentinel not established"
    else
      hpg="$FFOR_PGID"
      ff_kill_verified "$HARNESS_PID" "$HARNESS_TOK" 9
      killed="$FFSR_KILL_STAMP"
      if [ -z "$killed" ]; then
        err "non-reaping-parent-still-reaped" "identity-verified kill did not run"
      else
        observe_reap non-reaping-parent "$state" "$killed"
        if [ "$FFSR_OBS_ZOMBIE" -ne 1 ] || [ "$FFSR_OBS_PARENT" -ne 1 ]; then
          err "non-reaping-parent-still-reaped" "unreaped harness shape not observed: zombie=$FFSR_OBS_ZOMBIE parent_alive=$FFSR_OBS_PARENT; $FFSR_OBS_DETAIL"
        else
          report_reap non-reaping-parent-still-reaped "parent never reaped"
        fi
      fi
    fi
  fi
  if [ -n "$state" ] && [ -n "$hpg" ]; then
    ffor_state_read "$state"
    if ffor_resolve_phase "$FFOR_S_PID" "$hpg"; then
      ffor_reap "$FFOR_R_PGID" "" "$FFOR_R_PGID" "$FFOR_R_LEADSTART" "$hpg" 0
      ff_track "$FFOR_S_PID"
    fi
  fi
  ff_reap_tracked
  [ -n "$state" ] && rm -f "$state" "$state.dead" "$state.ticks" "$state.term"
}

# =========================================================================================
# THE FIELD DISCRIMINATOR — killed harness => zero surviving descendants
# =========================================================================================
# A signal inside the LAUNCH-TO-RECORD window: the child exists but its winpid/pgid probes (MSYS
# spawns) have not completed. Recording only AFTER those probes left this window seconds wide — a
# SIGKILL here published nothing, the guard read "nothing in flight", and the leak returned.
# Never release the WinPID gate before the kill: otherwise this discriminator can pass outside its window.
# =========================================================================================
# The suite's OWN teardown is identity-verified, so it is only teardown if the identity it
# recorded still matches. On MSYS `/proc/<pid>/stat` field 20 is not final until ~1s after a pid
# appears, so tracking at spawn time recorded a value that never matched again and
# ff_reap_tracked declined EVERY kill: measured 6 fixture siblings surviving 2 CLEAN runs, each
# a `while :; do sleep 1; done` loop loading every later phase on the host. This row runs FIRST
# because every assertion below depends on that teardown actually working.
# =========================================================================================
ff_spawn_sibling; TR_PID="$FFSR_SIB_PID"
tr_rec="$(ff_tok "$TR_PID")"
ffor_identity "$TR_PID" && tr_live="$FFOR_START $FFOR_COMM" || tr_live="<unresolvable>"
if [ -z "$tr_rec" ]; then
  err "tracked-identity-survives-msys-exec" "ff_track recorded no identity for a live pid (live=[$tr_live]) — the teardown has nothing to verify against and declines every kill"
else
  ff_reap_tracked
  tr_gone="$(ff_ps_gone_within "$TR_PID" "$REAP_CEILING")"
  if [ "$tr_gone" -ge 0 ] 2>/dev/null; then
    ok "tracked-identity-survives-msys-exec [DISCRIMINATOR] (a tracked fixture process still identity-matched and left the process table in ${tr_gone}s; a pre-exec start token makes every teardown decline)"
  else
    ffor_identity "$TR_PID" && tr_post="$FFOR_START $FFOR_COMM" || tr_post="<gone from /proc>"
    bad "tracked-identity-survives-msys-exec" "the tracked fixture process is still in the process table ${REAP_CEILING}s after its OWN identity-verified teardown: recorded=[$tr_rec] live-at-track=[$tr_live] live-now=[$tr_post] — a mismatch means the recorded token was pre-exec and this suite leaks a CPU-consuming process per spawn into every later phase"
  fi
fi

non_reaping_parent_row
if [ "${1:-}" = --nonreaping-only ]; then
  DECLARED_ROWS=(tracked-identity-survives-msys-exec non-reaping-parent-still-reaped)
  finish
fi

ff_spawn_sibling; SIB_PID="$FFSR_SIB_PID"
FFSR_WINPID_RELEASE="$FIX/winpid.release"; start_harness; FFSR_WINPID_RELEASE=""
if wait_for_file "$FIX/gc.pid" 90 && wait_for_file "$FIX/harness.pid" 5 && wait_for_file "$FIX/winpid.waiting" 5; then
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
  # WHY the row above used to fail, pinned as its own assertion (T4). The PUBLISHED pid is the
  # harness's own backgrounded capture subshell, and a background job of a non-interactive shell
  # keeps the SHELL's process group — so resolving the recorded pid yields the HARNESS group,
  # which ffor_reap must refuse. The reapable group is `timeout`'s, one level below it. Measured
  # before the kill, while the whole topology is still live.
  ffor_state_read "$lw_state"
  pg_h=""; ffor_snapshot && ffor_pgid_of "$HARNESS_PID" && pg_h="$FFOR_PGID_OUT"
  if [ -z "$FFOR_S_PID" ] || [ -z "$pg_h" ]; then
    err "phase-group-is-not-the-harness-group" "no published in-flight record, or the harness pgid is unresolvable"
  elif ffor_resolve "$FFOR_S_PID" && [ "$FFOR_R_PGID" != "$pg_h" ]; then
    err "phase-group-is-not-the-harness-group" "the recorded pid resolved to $FFOR_R_PGID, not the harness group $pg_h — this fixture no longer reproduces the topology under test"
  elif ! ffor_resolve_phase "$FFOR_S_PID" "$pg_h"; then
    bad "phase-group-is-not-the-harness-group" "the recorded pid resolves to the harness group $pg_h and no phase group was found below it — the guard has no handle and reaps nothing"
  else
    pg_p="$FFOR_R_PGID"; pg_kids=0
    ffor_group_members "$pg_p"
    while read -r pg_m _; do
      [ "$pg_m" = "$CHILD_PID" ] || [ "$pg_m" = "$GC_PID" ] && pg_kids=$((pg_kids + 1))
    done <<< "$FFOR_MEMBERS"
    if [ "$pg_p" = "$OWN_PGID" ]; then
      bad "phase-group-is-not-the-harness-group" "resolved this test's OWN group ($pg_p) — a reap would kill the suite"
    elif [ "$pg_kids" -eq 2 ]; then
      ok "phase-group-is-not-the-harness-group [DISCRIMINATOR] (recorded pid sits in the harness group $pg_h; the phase child and grandchild are in group $pg_p, resolved one level below it)"
    else
      bad "phase-group-is-not-the-harness-group" "resolved group $pg_p holds $pg_kids of the 2 phase descendants — reaping it would leave the rest alive"
    fi
  fi
  ff_kill_verified "$HARNESS_PID" "$HARNESS_TOK" 9
  lw_killed="$FFSR_KILL_STAMP"
  if [ -n "$lw_killed" ]; then
    observe_reap launch-window "$lw_state" "$lw_killed"
  else
    FFSR_OBS_STATUS=ERROR; FFSR_OBS_REASON="identity-verified kill did not run"
    FFSR_OBS_DETAIL="detect=-1ms TERM=-1ms reaped=-1ms exit(harness/child/grandchild)=-1/-1/-1ms (-1 = unobserved)"
  fi
  capture launch-window "after-observation"
  if [ "$lw_window" = closed ]; then
    err "launch-window-signal-still-reaps" "window=CLOSED despite the unreleased WinPID gate — fixture failed to hold the launch window; $FFSR_OBS_DETAIL"
  elif [ "$lw_window" != open ]; then
    bad "launch-window-signal-still-reaps" "window=$lw_window — harness publication failed to supply a complete in-flight PID record; $FFSR_OBS_DETAIL"
  else
    report_reap launch-window-signal-still-reaps "window provably $lw_window at kill time"
  fi
  if ff_alive "$SIB_PID"; then
    ok "launch-window-sibling-survives [CONTROL] (the independently launched same-executable bash sibling outside the target tree is alive — no collateral)"
  else
    bad "launch-window-sibling-survives" "the unrelated same-executable sibling was killed — over-broad teardown (the bounded-run-msys-collateral-kill class)"
  fi
else
  bad "launch-window-signal-still-reaps" "the launch-window fixture never established within 90s"
  err "phase-group-is-not-the-harness-group" "the launch-window fixture never established within 90s"
  skip "launch-window-sibling-survives" "the launch-window fixture never established within 90s"
fi
: > "$FIX/winpid.release"
ff_reap_tracked
[ -n "${lw_state:-}" ] && rm -f "$lw_state" "$lw_state.dead" "$lw_state.ticks" "$lw_state.term"

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
