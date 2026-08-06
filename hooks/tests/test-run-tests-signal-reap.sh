#!/usr/bin/env bash
# Fusebase Flow — S2 signal-reap red arm (T3). Plan: docs/specs/backlog-triage-execution/
# execution-plan.md §S2 · Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# STATUS AT T3: RED BY DESIGN. The reap assertions FAIL against the shipped harness — that
# failure IS the deliverable (gate G2). It is registered in FF_TAGS and has a run_shell_phase
# line, but run-tests.sh runs it ONLY when the tag is EXPLICITLY selected, so a known-open
# defect cannot turn the unscoped gate red. T4 removes that guard and wires it green.
#
# WHAT IT DRIVES: a miniature bounded phase (child bash + its own grandchild bash) through the
# REAL ffhc_run_bounded path with a byte-copy of run-tests.sh's `trap _ff_exit_reap EXIT`
# reaper, then kills the harness from outside mid-flight. The 26-min cli-flow-recovery phase is
# never used — the defect is in the lifecycle, not in that phase.
#
# CONTROLS (the failures matter as much as the passes): an independently launched
# SAME-EXECUTABLE bash sibling outside the target tree must survive every capture; the caller
# shell must survive; a PID-reuse identity mismatch must kill nothing; a normal exit must kill
# nothing. docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md is why: an
# over-broad MSYS tree kill has already terminated unrelated sessions.
#
# PROVENANCE (plan §5 / AC12): the retained trace records role, POSIX pid/ppid/pgid, Windows
# pid, executable BASENAME, and liveness only — never a raw command line, absolute path, or
# environment. Evidence: state/audit/run-tests-signal-reap/<full-head>/.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: signal-reap <name>" / "FAIL: signal-reap <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS: signal-reap $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: signal-reap $1 (${2:-})"; }
skip() { pass=$((pass + 1)); echo "PASS: signal-reap $1 [SKIP — $2]"; }
finish() { echo "[test-run-tests-signal-reap] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$LIB" ] || { bad "setup-lib-present" "missing $LIB"; finish; }

# Cleanup deadline is the EXISTING grace (E8) — never a second constant.
GRACE="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; GSEC="${GRACE%[!0-9]*}"
case "$GSEC" in ''|*[!0-9]*) GSEC=5 ;; esac
# MSYS spawn is ~1s/process, so a strict grace edge would flake; the leak this must catch runs
# for tens of minutes, so +3s cannot swallow it.
REAP_CEILING=$((GSEC + 3))

HEAD_FULL="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
EVID="${FF_SIGNAL_REAP_EVIDENCE_DIR:-$ROOT/state/audit/run-tests-signal-reap/$HEAD_FULL}"
mkdir -p "$EVID" 2>/dev/null || true
TRACE="$EVID/topology.tsv"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) : ;;
  *) skip "child-reaped-within-grace" "off-MSYS — POSIX process-group teardown reaps the phase tree; this defect is MSYS-only"
     skip "grandchild-reaped-within-grace" "off-MSYS"
     skip "sibling-survives" "off-MSYS"
     skip "signal-exit-status" "off-MSYS"
     skip "normal-exit-performs-no-kill" "off-MSYS"
     skip "pid-reuse-mismatch-kills-nothing" "off-MSYS"
     finish ;;
esac
[ -n "$(command -v timeout || true)" ] || { skip "child-reaped-within-grace" "no timeout binary"; finish; }

# ---------------------------------------------------------------------------------------
# Miniature fixture. phase.sh + gc.sh are named so their BASENAME is the identity marker —
# that is why the trace never needs a raw command line.
# ---------------------------------------------------------------------------------------
FIX="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-signal-reap.XXXXXX")" || { bad "setup-fixture" "mktemp failed"; finish; }
cleanup_fixture() {
  for f in "$FIX"/gc.pid "$FIX"/phase.pid "$FIX"/harness.pid; do
    [ -f "$f" ] && kill -9 "$(cat "$f" 2>/dev/null)" 2>/dev/null
  done
  rm -rf "$FIX" 2>/dev/null
}
trap cleanup_fixture EXIT

cat > "$FIX/gc.sh" <<'GC'
#!/usr/bin/env bash
D="$1"
echo $$ > "$D/gc.pid"; cat "/proc/$$/winpid" > "$D/gc.winpid" 2>/dev/null
while :; do sleep 1; done
GC
cat > "$FIX/phase.sh" <<'PH'
#!/usr/bin/env bash
D="$1"
echo $$ > "$D/phase.pid"; cat "/proc/$$/winpid" > "$D/phase.winpid" 2>/dev/null
bash "$D/gc.sh" "$D" &
while :; do sleep 1; done
PH
# TRIPWIRE: the reaper block below is a byte-copy of run-tests.sh:116-122. If that block
# changes and this does not, the red arm stops describing the shipped harness.
cat > "$FIX/harness.sh" <<'HN'
#!/usr/bin/env bash
set -uo pipefail
D="$1"; LIB="$2"; PHASE="${3:-$D/phase.sh}"
. "$LIB"
ffhc_detect_timeout
FFHC_HEARTBEAT_SECS="${FFHC_HEARTBEAT_SECS:-30}"
FFHC_LAST_WINPID=""
FFHC_LAST_CHILD_PID=""
_ff_exit_reap() {
    echo "trap-ran winpid=$FFHC_LAST_WINPID child=$FFHC_LAST_CHILD_PID" >> "$D/trap.log"
    ffhc_is_msys || return 0
    [ -n "$FFHC_LAST_WINPID" ] && ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID" "$FFHC_LAST_CHILD_PID"
}
trap _ff_exit_reap EXIT
echo $$ > "$D/harness.pid"; cat "/proc/$$/winpid" > "$D/harness.winpid" 2>/dev/null
ffhc_run_bounded 300 bash "$PHASE" "$D"
echo "phase-returned rc=$FFHC_LAST_RC" >> "$D/harness.log"
HN
cat > "$FIX/fast.sh" <<'FA'
#!/usr/bin/env bash
D="$1"
echo $$ > "$D/phase.pid"; cat "/proc/$$/winpid" > "$D/phase.winpid" 2>/dev/null
bash -c 'echo $$ > "'"$1"'/gc.pid"; exit 0'
echo fast-marker
FA

# ---------------------------------------------------------------------------------------
# Topology capture. One `ps` + one `tasklist` snapshot per capture point (MSYS spawns are
# ~1s, so per-role probes would distort the very timing under test).
# ---------------------------------------------------------------------------------------
# Truncated per run (FR-18): a stacked trace cannot be read as one run's topology.
printf 'head\tscenario\tcapture\trole\tpid\tppid\tpgid\twinpid\texe_basename\talive_posix\talive_win\n' > "$TRACE"

capture() {   # capture <scenario> <label> ; roles read from the fixture's pid files + ps
  local scen="$1" label="$2" snap tl role pid win ppid pgid exe am aw
  snap="$(ps 2>/dev/null)"
  tl="$(tasklist //NH //FO CSV 2>/dev/null)"
  for role in harness child grandchild sibling wrapper heartbeat; do
    case "$role" in
      harness)     pid="$(cat "$FIX/harness.pid" 2>/dev/null)" ;;
      child)       pid="$(cat "$FIX/phase.pid" 2>/dev/null)" ;;
      grandchild)  pid="$(cat "$FIX/gc.pid" 2>/dev/null)" ;;
      sibling)     pid="$SIB_PID" ;;
      wrapper)     pid="$(printf '%s\n' "$snap" | awk -v h="$(cat "$FIX/harness.pid" 2>/dev/null)" '$2==h && /timeout/ {print $1; exit}')" ;;
      heartbeat)   pid="$(printf '%s\n' "$snap" | awk -v h="$(cat "$FIX/harness.pid" 2>/dev/null)" '$2==h && /bash/ {print $1; exit}')" ;;
    esac
    [ -n "${pid:-}" ] || continue
    ppid="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $2; exit}')"
    pgid="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $3; exit}')"
    win="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $4; exit}')"
    exe="$(printf '%s\n' "$snap" | awk -v p="$pid" '$1==p{print $NF; exit}')"; exe="${exe##*/}"
    kill -0 "$pid" 2>/dev/null && am=alive || am=gone
    aw=gone
    [ -n "${win:-}" ] && printf '%s\n' "$tl" | grep -q "\",\"${win}\"," && aw=alive
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${HEAD_FULL:0:12}" "$scen" "$label" "$role" "$pid" "${ppid:-?}" "${pgid:-?}" \
      "${win:-?}" "${exe:-?}" "$am" "$aw" >> "$TRACE"
  done
}

alive() { kill -0 "${1:-0}" 2>/dev/null; }

# gone_within <pid> <ceiling> : seconds until the pid disappears, or -1 if it never did.
gone_within() {
  local pid="$1" ceil="$2" i=0
  while [ "$i" -le "$ceil" ]; do
    alive "$pid" || { echo "$i"; return 0; }
    sleep 1; i=$((i + 1))
  done
  echo "-1"; return 1
}

# ---------------------------------------------------------------------------------------
# Scenario driver. `timeout -s SIG -k <grace>` reproduces the field case exactly: the outer
# wall signals the harness's process group, then SIGKILLs it after the grace.
# ---------------------------------------------------------------------------------------
SIB_PID=""
run_scenario() {   # run_scenario <name> <signal> <seconds-until-signal>
  local scen="$1" sig="$2" wall="$3"
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log
  # Control: a SAME-EXECUTABLE (bash) sibling in its own tree, started before the harness.
  bash -c 'sleep 240' & SIB_PID=$!
  timeout -s "$sig" -k "$GRACE" "$wall" bash "$FIX/harness.sh" "$FIX" "$LIB" >/dev/null 2>&1 &
  local outer=$!
  local i=0
  while [ ! -s "$FIX/gc.pid" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  if [ ! -s "$FIX/gc.pid" ]; then
    bad "$scen-fixture-established" "the miniature phase/grandchild never started within 30s"
    kill -9 "$SIB_PID" "$outer" 2>/dev/null; wait 2>/dev/null; return 1
  fi
  local hp cp gp
  hp="$(cat "$FIX/harness.pid")"; cp="$(cat "$FIX/phase.pid")"; gp="$(cat "$FIX/gc.pid")"
  capture "$scen" "before-signal"
  wait "$outer" 2>/dev/null; OUTER_RC=$?
  local t_child t_gc
  t_child="$(gone_within "$cp" "$REAP_CEILING")"
  t_gc="$(gone_within "$gp" "$REAP_CEILING")"
  capture "$scen" "after-grace"
  SCEN_CHILD_T="$t_child"; SCEN_GC_T="$t_gc"
  SCEN_SIB_ALIVE=no; alive "$SIB_PID" && SCEN_SIB_ALIVE=yes
  SCEN_TRAP=none; [ -f "$FIX/trap.log" ] && SCEN_TRAP="$(tr '\n' ' ' < "$FIX/trap.log")"
  SCEN_HARNESS_ALIVE=no; alive "$hp" && SCEN_HARNESS_ALIVE=yes
  sleep 25
  capture "$scen" "plus-30s"
  SCEN_CHILD_30=no; alive "$cp" && SCEN_CHILD_30=yes
  SCEN_GC_30=no; alive "$gp" && SCEN_GC_30=yes
  # Strictly-scoped teardown of OUR OWN recorded pids only — never a tree kill on an ancestor.
  kill -9 "$gp" "$cp" "$hp" 2>/dev/null
  kill -9 "$SIB_PID" 2>/dev/null; wait 2>/dev/null
  return 0
}

# --- Scenario A: external TERM (the field case: an outer `timeout` wall) ------------------
# The 20s wall is evidence hygiene, not patience: MSYS spawns (~1s each) plus the ps/tasklist
# snapshot take seconds, and a shorter wall makes the "before-signal" capture race the signal.
if run_scenario term TERM 20; then
  if [ "$SCEN_CHILD_T" -ge 0 ] 2>/dev/null; then
    ok "child-reaped-within-grace (TERM: phase child gone ${SCEN_CHILD_T}s after the signal, <= ${REAP_CEILING}s)"
  else
    bad "child-reaped-within-grace" "TERM: the phase child was STILL ALIVE ${REAP_CEILING}s after the signal (alive at +30s: $SCEN_CHILD_30; harness alive: $SCEN_HARNESS_ALIVE; EXIT trap: $SCEN_TRAP) — the orphan leak"
  fi
  if [ "$SCEN_GC_T" -ge 0 ] 2>/dev/null; then
    ok "grandchild-reaped-within-grace (TERM: grandchild gone ${SCEN_GC_T}s after the signal)"
  else
    bad "grandchild-reaped-within-grace" "TERM: the grandchild was STILL ALIVE ${REAP_CEILING}s after the signal (alive at +30s: $SCEN_GC_30; EXIT trap: $SCEN_TRAP) — a child-only reap does not close this"
  fi
  if [ "$SCEN_SIB_ALIVE" = yes ]; then
    ok "sibling-survives (TERM: the independently launched same-executable bash sibling outside the target tree is alive — no collateral)"
  else
    bad "sibling-survives" "TERM: the unrelated same-executable sibling was killed — over-broad teardown (the bounded-run-msys-collateral-kill class)"
  fi
  echo "NOTE: signal-reap TERM trap-observation: ${SCEN_TRAP}" >&2
else
  bad "child-reaped-within-grace" "TERM scenario could not be established"
fi

# --- Scenario B: external INT (operator Ctrl-C — the more common real case) ---------------
if run_scenario int INT 20; then
  if [ "$SCEN_CHILD_T" -ge 0 ] 2>/dev/null && [ "$SCEN_GC_T" -ge 0 ] 2>/dev/null; then
    ok "int-child+grandchild-reaped-within-grace (INT: child ${SCEN_CHILD_T}s / grandchild ${SCEN_GC_T}s after the signal)"
  else
    bad "int-child+grandchild-reaped-within-grace" "INT: child_gone_after=${SCEN_CHILD_T}s grandchild_gone_after=${SCEN_GC_T}s (-1 = still alive at the ${REAP_CEILING}s deadline; alive at +30s: child=$SCEN_CHILD_30 grandchild=$SCEN_GC_30; EXIT trap: $SCEN_TRAP)"
  fi
  if [ "$SCEN_SIB_ALIVE" = yes ]; then
    ok "int-sibling-survives (INT: unrelated same-executable sibling alive)"
  else
    bad "int-sibling-survives" "INT: the unrelated same-executable sibling was killed — over-broad teardown"
  fi
else
  bad "int-child+grandchild-reaped-within-grace" "INT scenario could not be established"
fi

# --- Signal-correct exit status: TERM => 143, INT => 130 ----------------------------------
# Signalled DIRECTLY (not through the outer wall) so the wrapper survives to record the rc —
# `timeout`'s own 124 would otherwise mask the harness's status.
sig_status() {   # sig_status <signal> ; echoes the harness's exit status or "none"
  local sig="$1"
  rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/rc.log "$FIX"/trap.log
  bash -c 'bash "$1" "$2" "$3" >/dev/null 2>&1; echo "$?" > "$2/rc.log"' _ \
    "$FIX/harness.sh" "$FIX" "$LIB" &
  local w=$! i=0
  while [ ! -s "$FIX/gc.pid" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  [ -s "$FIX/harness.pid" ] || { kill -9 "$w" 2>/dev/null; echo none; return; }
  kill -"$sig" "$(cat "$FIX/harness.pid")" 2>/dev/null
  i=0; while [ ! -s "$FIX/rc.log" ] && [ "$i" -lt "$REAP_CEILING" ]; do sleep 1; i=$((i + 1)); done
  kill -9 "$(cat "$FIX/gc.pid" 2>/dev/null)" "$(cat "$FIX/phase.pid" 2>/dev/null)" \
          "$(cat "$FIX/harness.pid" 2>/dev/null)" "$w" 2>/dev/null
  wait 2>/dev/null
  cat "$FIX/rc.log" 2>/dev/null || echo none
}
term_rc="$(sig_status TERM)"; int_rc="$(sig_status INT)"
if [ "$term_rc" = "143" ] && [ "$int_rc" = "130" ]; then
  ok "signal-exit-status (TERM => 143, INT => 130)"
else
  bad "signal-exit-status" "TERM => $term_rc (want 143), INT => $int_rc (want 130); 'none' means the harness never exited within ${REAP_CEILING}s of the signal — an unacted-on signal, not a wrong code"
fi

# --- Control: a NORMAL exit performs no kill (behaviour must stay byte-identical) ---------
rm -f "$FIX"/*.pid "$FIX"/*.winpid "$FIX"/trap.log "$FIX"/harness.log
bash -c 'sleep 60' & SIB_PID=$!
bash "$FIX/harness.sh" "$FIX" "$LIB" "$FIX/fast.sh" >/dev/null 2>&1
norm_rc=$?
if [ "$norm_rc" -eq 0 ] && alive "$SIB_PID" && grep -q "phase-returned rc=0" "$FIX/harness.log" 2>/dev/null; then
  ok "normal-exit-performs-no-kill (fast phase: harness rc 0, phase rc 0, unrelated sibling untouched)"
else
  bad "normal-exit-performs-no-kill" "harness rc=$norm_rc sibling_alive=$(alive "$SIB_PID" && echo yes || echo no) harness.log=[$(cat "$FIX/harness.log" 2>/dev/null)]"
fi
kill -9 "$SIB_PID" 2>/dev/null; wait 2>/dev/null

# --- Control: an identity (PID-reuse) mismatch kills NOTHING ------------------------------
# Drives the shipped guard directly: a recorded winpid that no longer maps to the recorded
# child must be skipped, never killed on the winpid alone.
# shellcheck source=/dev/null
. "$LIB"
bash -c 'sleep 60' & VICTIM=$!
sleep 1
VWIN="$(cat "/proc/$VICTIM/winpid" 2>/dev/null)"
if [ -n "$VWIN" ] && alive "$VICTIM"; then
  ffhc_msys_taskkill_winpid "$VWIN" "999999"   # 999999 = a pid that cannot map to $VWIN
  sleep 1
  if alive "$VICTIM"; then
    ok "pid-reuse-mismatch-kills-nothing (recorded winpid + non-matching child pid => the guard skipped the taskkill; the process survived)"
  else
    bad "pid-reuse-mismatch-kills-nothing" "the taskkill fired on a winpid whose recorded child pid no longer matches — the PID-reuse guard is not holding"
  fi
else
  skip "pid-reuse-mismatch-kills-nothing" "could not resolve a winpid for the control process"
fi
kill -9 "$VICTIM" 2>/dev/null; wait 2>/dev/null

echo "[test-run-tests-signal-reap] trace: ${TRACE#"$ROOT/"}" >&2
finish
