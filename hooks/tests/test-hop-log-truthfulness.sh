#!/usr/bin/env bash
# Fusebase Flow — S1: the hop log must report what actually happened.
# Spec: docs/specs/hop-log-truthfulness-and-publisher-scope/spec.md § S1 + corrections.md C1..C5.
#
# ROW CLASSES (what each one can and cannot establish):
#   DRIVEN       runs the REAL hooks/local/post-fusebase-update.sh in a fixture consumer and
#                parses the REAL outcome channel with the REAL helper. It does NOT run
#                upgrade.sh itself (that needs a staged source clone and rewrites the tree);
#                the WIRING rows carry that half.
#   ANTI-REGRESSION  executes the PRE-FIX bytes (v4.15.3 / 497edf1) against the SAME observed
#                run. Without it every "the trailer does not say X" assertion is vacuous.
#   RENDERING    feeds a synthetic state to the shipped renderer. Used only where a fixture
#                cannot produce the state at all (`skipped` git-hook class: it means the
#                installer never ran, which a driven row cannot observe by construction).
#   WIRING       greps the shipped upgrade.sh / post-fusebase-update.sh. Residency only.
#
# TRIPWIRE: the parsed channel is $FFRO_OUTCOME_FILE, never the captured log. A row that
# parses a log re-creates the forgery this suite exists to close (corrections.md C2), so there
# is deliberately NO log-parsing helper here.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: hop-log-truth <name>" / "FAIL: hop-log-truth <name>"; exit = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: hop-log-truth $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-500))"; echo "FAIL: hop-log-truth $1$w"; }
finish() { echo "[test-hop-log-truthfulness] $pass/$((pass + fail)) PASS"; exit $fail; }

RO_LIB="hooks/local/lib/recovery-outcome.sh"
UPGRADE="hooks/local/upgrade.sh"
RECOVERY="hooks/local/post-fusebase-update.sh"
PREFIX_SHA="497edf1"          # the reviewed pre-fix helper (T72); C1/C2 anti-regression source

command -v python3 >/dev/null 2>&1 || { bad setup "python3 not on PATH"; finish; }
# ANTI-VACUITY: with no renderer the empty string satisfies every "does not say X" row, so its
# absence is a hard stop, never a quiet pass.
[ -f "$RO_LIB" ] || { bad setup "$RO_LIB is absent, so every rendering assertion would be vacuous"; finish; }
[ -f "$UPGRADE" ] || { bad setup "missing $UPGRADE"; finish; }
[ -f "$RECOVERY" ] || { bad setup "missing $RECOVERY"; finish; }

BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-s1.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

# The parse call form is taken from the SHIPPED caller, so these rows fail if the call site
# changes shape (e.g. back to parsing the captured log).
CALL="$(grep -oE 'ffro_parse "\$[A-Za-z_][A-Za-z0-9_]*"' "$UPGRADE" | head -1)"
CALL_VAR="${CALL#*\$}"; CALL_VAR="${CALL_VAR%\"}"
[ -n "$CALL_VAR" ] || { bad setup "could not extract the ffro_parse call form from $UPGRADE"; finish; }

# parse_with <lib> <input> -> "<rc>|<state>", running the CALLER's real shell prelude.
parse_with() {
  local out rc
  out="$(bash -euo pipefail -c ". \"\$0\"; $CALL_VAR=\"\$1\"; $CALL; printf '%s' \"\$FFRO_STATE\"" "$1" "$2" 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$out"
}
parsed_state() { local r; r="$(parse_with "$ROOT/$RO_LIB" "$1")"; printf '%s' "${r#*|}"; }
render()       { ( cd "$ROOT" && bash -euo pipefail -c '. "$0"; ffro_parse "$1"; ffro_settings_trailer' "$ROOT/$RO_LIB" "$1" ) 2>&1; }
render_state() { ( cd "$ROOT" && bash -c '. "$0"; FFRO_STATE="$1"; FFRO_DETAIL="$2"; ffro_settings_trailer' "$ROOT/$RO_LIB" "$1" "${2:-}" ) 2>&1; }
render_git()   { ( cd "$ROOT" && bash -c '. "$0"; ffro_git_hook_trailer "$1"' "$ROOT/$RO_LIB" "$1" ) 2>&1; }

# One reusable fixture consumer. Batched copies only: on MSYS the process spawn, not the bytes,
# is what makes a recovery phase slow.
FX="$BASE_TMP/consumer"
build_fixture() {
  mkdir -p "$FX/hooks" "$FX/flow-skills" "$FX/.claude" || return 1
  cp -R "$ROOT/hooks/local" "$ROOT/hooks/handlers" "$ROOT/hooks/git" "$FX/hooks/" 2>/dev/null || return 1
  [ -d "$ROOT/hooks/shared" ] && cp -R "$ROOT/hooks/shared" "$FX/hooks/" 2>/dev/null
  cp -R "$ROOT/agents" "$FX/agents" 2>/dev/null || return 1
  cp -R "$ROOT/flow-skills/communication" "$ROOT/flow-skills/fusebase-flow-health-check" \
    "$FX/flow-skills/" 2>/dev/null || return 1
  cp "$ROOT/VERSION" "$FX/VERSION" 2>/dev/null || return 1
  printf '# fixture\n' > "$FX/AGENTS.md"
  printf '# fixture\n' > "$FX/CLAUDE.md"
  ( cd "$FX" && git init -q . && git config user.email t@example.invalid && git config user.name t ) || return 1
  return 0
}

# recover <name> [args...] — runs the real recovery with the caller-supplied outcome channel.
# Sets LOG / CHAN / RC (globals: command substitution would discard them in a subshell).
LOG=""; CHAN=""; RC=0
recover() {
  local name="$1"; shift
  LOG="$BASE_TMP/$name.log"; CHAN="$BASE_TMP/$name.chan"; : > "$CHAN"
  ( cd "$FX" && FFRO_OUTCOME_FILE="$CHAN" bash hooks/local/post-fusebase-update.sh "$@" ) > "$LOG" 2>&1
  RC=$?
}

if ! build_fixture; then bad setup "could not build the fixture consumer"; finish; fi

###############################################################################
# C1 — the parser is TOTAL under the caller's own `set -euo pipefail`
###############################################################################
: > "$BASE_TMP/c1-empty"
printf 'diagnostic line\n[post-fusebase-update] some other note\n' > "$BASE_TMP/c1-norecord"
printf '[post-fusebase-update] outcome: settings=merged detail=one\n' > "$BASE_TMP/c1-one"
printf '[post-fusebase-update] outcome: settings=merged detail=a\n[post-fusebase-update] outcome: settings=already-current detail=b\n' \
  > "$BASE_TMP/c1-many"
f=""
for row in "$BASE_TMP/c1-absent-file|0|unknown" "$BASE_TMP/c1-empty|0|unknown" \
           "$BASE_TMP/c1-norecord|0|unknown" "$BASE_TMP/c1-one|0|merged" \
           "$BASE_TMP/c1-many|0|already-current"; do
  IFS='|' read -r inp want_rc want_state <<<"$row"
  got="$(parse_with "$ROOT/$RO_LIB" "$inp")"
  [ "$got" = "$want_rc|$want_state" ] \
    || f="$f [$(basename "$inp"): expected rc $want_rc + state $want_state, got '${got%%|*}' + '${got#*|}']"
done
[ -z "$f" ] && ok "s1-parser-is-total-under-the-callers-shell (absent/empty/no-record/one/many all return rc 0; a missing record is 'unknown', never an abort)" \
            || bad s1-parser-is-total-under-the-callers-shell "$f"

f=""
OLD_LIB="$BASE_TMP/ro-prefix.sh"
if ! git show "$PREFIX_SHA:$RO_LIB" > "$OLD_LIB" 2>/dev/null || [ ! -s "$OLD_LIB" ]; then
  f="$f [could not extract $PREFIX_SHA:$RO_LIB, so this row cannot establish the regression]"
else
  OLD_GOT="$(parse_with "$OLD_LIB" "$BASE_TMP/c1-norecord")"
  [ "${OLD_GOT%%|*}" = "0" ] \
    && f="$f [the pre-fix helper returned rc 0 on a record-less input, so C1's abort was never real]"
  OLD_OK="$(parse_with "$OLD_LIB" "$BASE_TMP/c1-one")"
  [ "$OLD_OK" = "0|merged" ] \
    || f="$f [the pre-fix helper is not exercisable here (a matching input gave '$OLD_OK'), so its failure above proves nothing]"
fi
[ -z "$f" ] && ok "s1-prefix-parser-aborted-the-caller (anti-vacuity: $PREFIX_SHA's helper, run under the same prelude, exits nonzero on a record-less log and never returns 'unknown')" \
            || bad s1-prefix-parser-aborted-the-caller "$f"

###############################################################################
# DRIVEN — created-minimal: a file this run created is not a complete recovery
###############################################################################
recover create --wire-hooks
OUT="$(render "$CHAN")"
f=""
[ "$(parsed_state "$CHAN")" = "created-minimal" ] \
  || f="$f [recovery created .claude/settings.json from nothing but published '$(parsed_state "$CHAN")']"
printf '%s' "$OUT" | grep -qi "minimal" || f="$f [the trailer does not say a minimal file was created]"
printf '%s' "$OUT" | grep -qi "unresolved" || f="$f [the trailer does not say the prior external/CLI entries are still unresolved]"
printf '%s' "$OUT" | grep -qi "fully recovered" && f="$f [the trailer claims full recovery for a tree whose external settings bytes were never restored]"
[ -z "$f" ] && ok "s1-created-minimal-is-not-fully-recovered (a minimal Flow-only file is reported as incomplete, naming the unresolved external entries)" \
            || bad s1-created-minimal-is-not-fully-recovered "$f"

###############################################################################
# DRIVEN — already current: a no-op must not recommend rewiring
###############################################################################
recover noop
OUT="$(render "$CHAN")"
f=""
[ "$(parsed_state "$CHAN")" = "already-current" ] \
  || f="$f [a second recovery over an already-wired tree published '$(parsed_state "$CHAN")' instead of already-current]"
printf '%s' "$OUT" | grep -qi "already carried" || f="$f [the trailer does not say the events were already present]"
printf '%s' "$OUT" | grep -q -- "--wire-hooks" && f="$f [the trailer still recommends --wire-hooks after a run that found the settings current]"
printf '%s' "$OUT" | grep -qi "NOT modified" && f="$f [the trailer says 'NOT modified', which reads as 'never wired' rather than 'already wired']"
[ -z "$f" ] && ok "s1-already-current-carries-no-rewire-advice (no-op run: says already current, recommends nothing)" \
            || bad s1-already-current-carries-no-rewire-advice "$f"

###############################################################################
# DRIVEN + ANTI-REGRESSION — the consumer's E8 scenario
# Strip the Flow events, then run recovery with NO --wire-hooks. The ENABLED schema-1 marker
# authorizes the whole claude_settings surface, so recovery merges. v4.15.3's trailer then
# printed "NOT modified" for this exact run.
###############################################################################
printf '{"hooks": {}}\n' > "$FX/.claude/settings.json"
recover merged
LOG_MERGED="$LOG"; CHAN_MERGED="$CHAN"
OUT="$(render "$CHAN_MERGED")"
f=""
[ "$(parsed_state "$CHAN_MERGED")" = "merged" ] \
  || f="$f [automatic restoration merged the lifecycle events but published '$(parsed_state "$CHAN_MERGED")']"
grep -q "merged Fusebase Flow lifecycle events" "$LOG_MERGED" \
  || f="$f [the fixture did not reproduce the merge; the scenario is not the consumer's]"
printf '%s' "$OUT" | grep -qi "NOT modified" \
  && f="$f [THE REPORTED DEFECT: the summary says 'NOT modified' after a run that merged the events]"
printf '%s' "$OUT" | grep -q -- "--wire-hooks" \
  && f="$f [the summary tells the operator to run --wire-hooks after a run that already wired]"
printf '%s' "$OUT" | grep -q "PreToolUse" \
  || f="$f [the summary does not name the events that were added or repaired]"
printf '%s' "$OUT" | grep -qi "authorized" \
  || f="$f [the summary does not say prior recorded intent authorized the change]"
[ -z "$f" ] && ok "s1-merged-run-is-not-reported-as-untouched (E8: automatic restore merged the events; the summary names them and never says NOT modified)" \
            || bad s1-merged-run-is-not-reported-as-untouched "$f"

# The oracle above only discriminates if v4.15.3 really failed it on the SAME observed run. The
# pre-fix trailer is three literal `echo` statements, so it is EXECUTED here and its output is
# put through the same predicates.
f=""
V4153_BLOCK="$(git show v4.15.3:hooks/local/upgrade.sh 2>/dev/null | grep -B2 -F 'NOT modified — to (re)wire those')"
if ! printf '%s' "$V4153_BLOCK" | grep -q "the Flow git fallback pre-commit was"; then
  f="$f [could not extract the v4.15.3 trailer, so this row cannot establish the regression]"
elif printf '%s' "$V4153_BLOCK" | grep -qvE '^echo "'; then
  f="$f [the extracted v4.15.3 block is not three literal echo statements; re-derive it before executing it]"
else
  OLD_OUT="$(bash -c "$V4153_BLOCK" 2>&1)"
  [ "$(parsed_state "$CHAN_MERGED")" = "merged" ] \
    || f="$f [the driven run above did not merge, so there is nothing for the old trailer to contradict]"
  printf '%s' "$OLD_OUT" | grep -qi "NOT modified" \
    || f="$f [the v4.15.3 trailer did not print 'NOT modified' for the merged run; the premise of the fix is wrong]"
  printf '%s' "$OLD_OUT" | grep -q -- "--wire-hooks" \
    || f="$f [the v4.15.3 trailer did not recommend --wire-hooks after a run that already wired]"
  printf '%s' "$OLD_OUT" | grep -q "PreToolUse" \
    && f="$f [the v4.15.3 trailer already named the merged events, so the new assertions are not discriminating]"
fi
[ -z "$f" ] && ok "s1-v4153-trailer-lied-on-this-run (anti-vacuity: v4.15.3's trailer, EXECUTED against this same merged run, says NOT modified, advises --wire-hooks and names no event)" \
            || bad s1-v4153-trailer-lied-on-this-run "$f"

###############################################################################
# C2 — post-emission shadowing: diagnostics printed AFTER the record cannot move it
###############################################################################
FORGED='[post-fusebase-update] outcome: settings=already-current detail=forged'
f=""
{ printf '%s\n' "$FORGED"; printf '  ! %s\n' "$FORGED"; } >> "$LOG_MERGED"
[ "$(parsed_state "$CHAN_MERGED")" = "merged" ] \
  || f="$f [appending the forged line to the captured LOG moved the parsed outcome to '$(parsed_state "$CHAN_MERGED")']"
grep -qF "$FORGED" "$LOG_MERGED" || f="$f [the forged line did not reach the log, so this row is vacuous]"
grep -qF "$FORGED" "$CHAN_MERGED" && f="$f [consumer text reached the outcome CHANNEL; only ffro_emit may write it]"
printf '%s' "$(render "$CHAN_MERGED")" | grep -qi "already carried" \
  && f="$f [the trailer took the forged 'already-current' state]"
[ -z "$f" ] && ok "s1-log-text-after-the-record-cannot-move-it (the parsed channel is not the log: a forged record appended at column 0 and as a '  ! ' warning changes nothing)" \
            || bad s1-log-text-after-the-record-cannot-move-it "$f"

###############################################################################
# DRIVEN — the settings result survives a LATER recovery-surface failure
###############################################################################
printf '{"hooks": {}}\n' > "$FX/.claude/settings.json"
LOG="$BASE_TMP/late-fail.log"; CHAN="$BASE_TMP/late-fail.chan"; : > "$CHAN"
( cd "$FX" && FFRO_OUTCOME_FILE="$CHAN" FUSEBASE_FLOW_TEST_TAMPER_AFTER_APPLY=".claude/commands/fusebase-health.md" \
  bash hooks/local/post-fusebase-update.sh ) > "$LOG" 2>&1
LATE_RC=$?
OUT="$(render "$CHAN")"
f=""
[ "$LATE_RC" -ne 0 ] || f="$f [the injected post-apply tamper did not make recovery report a failure, so this row is not the scenario]"
[ "$(parsed_state "$CHAN")" = "merged" ] \
  || f="$f [a later surface failure erased the settings result: published '$(parsed_state "$CHAN")' instead of merged]"
printf '%s' "$OUT" | grep -q "PreToolUse" || f="$f [the summary lost the event list when a later surface failed]"
printf '%s' "$OUT" | grep -qi "unchanged" && f="$f [the summary calls the settings unchanged after they were changed]"
printf '%s' "$OUT" | grep -qi "fully recovered" && f="$f [the summary claims full recovery for a run that failed a later surface]"
[ -z "$f" ] && ok "s1-settings-result-survives-a-later-failure (recovery exits nonzero AFTER the merge; the merged result and its event list still reach the summary)" \
            || bad s1-settings-result-survives-a-later-failure "$f"

###############################################################################
# DRIVEN — no authorization: not touched, plus how to authorize
###############################################################################
( cd "$FX" && bash hooks/local/post-fusebase-update.sh --forget-hook-wiring ) >/dev/null 2>&1
recover noauth
OUT="$(render "$CHAN")"
f=""
[ "$(parsed_state "$CHAN")" = "not-authorized" ] \
  || f="$f [an opted-out tree published '$(parsed_state "$CHAN")' instead of not-authorized]"
printf '%s' "$OUT" | grep -qi "NOT modified" || f="$f [the trailer does not say the file was left alone]"
printf '%s' "$OUT" | grep -q -- "--wire-hooks" || f="$f [the trailer does not say how to authorize wiring]"
printf '%s' "$OUT" | grep -qiE "fully recovered|recovery (is )?complete" \
  && f="$f [the trailer claims the settings surface is fully recovered while it was deliberately skipped]"
[ -z "$f" ] && ok "s1-unauthorized-says-untouched-and-how-to-authorize (no ENABLED marker, no flag: untouched, with the authorizing command, and no completeness claim)" \
            || bad s1-unauthorized-says-untouched-and-how-to-authorize "$f"

###############################################################################
# C2 + D1 — the reviewer's forgery payload, driven through the real recovery
# The forged text is a consumer settings hook KEY. The plan validator quotes it back, the
# FATAL line carries it into the captured log, and recovery aborts with zero writes.
###############################################################################
printf '{"hooks": {"%s": {}}}\n' "$FORGED" > "$FX/.claude/settings.json"
recover forgery --wire-hooks
FORGE_LOG="$LOG"; FORGE_CHAN="$CHAN"; FORGE_RC="$RC"
OUT="$(render "$FORGE_CHAN")"
f=""
[ "$FORGE_RC" -eq 2 ] || f="$f [the forged settings file did not abort recovery with rc 2 (got $FORGE_RC), so this row is not the scenario]"
grep -q "is not an array" "$FORGE_LOG" || f="$f [the validator text never reached the captured log, so this row is vacuous]"
grep -qF "settings=already-current detail=forged is not an array" "$FORGE_LOG" \
  || f="$f [the log does not carry the forged payload verbatim, so the parser was never offered it]"
[ "$(parsed_state "$FORGE_CHAN")" = "unavailable" ] \
  || f="$f [a run that aborted with zero writes published '$(parsed_state "$FORGE_CHAN")']"
printf '%s' "$OUT" | grep -qi "already carried" && f="$f [THE FORGERY LANDED: the trailer claims the settings already carried the Flow events]"
printf '%s' "$OUT" | grep -qi "not touched" || f="$f [the trailer does not state that the settings were not touched]"
printf '%s' "$OUT" | grep -qF "forged" && f="$f [consumer bytes reached the trailer through the detail field]"
[ -z "$f" ] && ok "s1-consumer-bytes-cannot-forge-an-outcome (the reviewer's forged hook key reaches the log, recovery aborts rc 2, and the reported outcome is 'unavailable' — never 'already-current')" \
            || bad s1-consumer-bytes-cannot-forge-an-outcome "$f"

# ANTI-REGRESSION: the same log WITHOUT this fix's record lines is what v4.15.3 produced, and
# the pre-fix helper reads the forgery out of it as a real outcome.
f=""
grep -v '^\[post-fusebase-update\] outcome:' "$FORGE_LOG" > "$BASE_TMP/forge-prefix.log"
if [ ! -s "$OLD_LIB" ]; then
  f="$f [the pre-fix helper bytes are unavailable, so this row cannot establish the regression]"
else
  OLD_GOT="$(parse_with "$OLD_LIB" "$BASE_TMP/forge-prefix.log")"
  [ "$OLD_GOT" = "0|already-current" ] \
    || f="$f [the pre-fix helper read '$OLD_GOT' from the forged log instead of 0|already-current; the defect premise is wrong]"
  printf '%s' "$(render_state already-current)" | grep -qi "already carried" \
    || f="$f [the already-current branch does not claim the events were already present, so the forgery would have been harmless]"
fi
[ -z "$f" ] && ok "s1-prefix-parser-took-the-forgery ($PREFIX_SHA's helper, on the same aborted run's log, reports already-current — the state that renders 'nothing was written to it')" \
            || bad s1-prefix-parser-took-the-forgery "$f"

###############################################################################
# C2 — a record outside the closed vocabulary is not a state
###############################################################################
printf '[post-fusebase-update] outcome: settings=forged-state detail=surprise\n' > "$BASE_TMP/vocab.chan"
f=""
[ "$(parsed_state "$BASE_TMP/vocab.chan")" = "unknown" ] \
  || f="$f [an out-of-vocabulary record parsed as '$(parsed_state "$BASE_TMP/vocab.chan")']"
OUT="$(render "$BASE_TMP/vocab.chan")"
printf '%s' "$OUT" | grep -qF "forged-state" && f="$f [the invented state reached the trailer]"
printf '%s' "$OUT" | grep -qF "surprise" && f="$f [the detail of an invented state reached the trailer]"
printf '%s' "$OUT" | grep -qi "cannot say" || f="$f [an unparsable record does not render the 'cannot say' branch]"
[ -z "$f" ] && ok "s1-out-of-vocabulary-record-is-unknown (only the eight closed states parse; anything else renders 'cannot say' and carries no consumer text)" \
            || bad s1-out-of-vocabulary-record-is-unknown "$f"

###############################################################################
# D1 — the other deterministic pre-Step-5 abort: no python3
###############################################################################
path_without_python3() {
  local d out="" IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    { [ -x "$d/python3" ] || [ -x "$d/python3.exe" ]; } && continue
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}
NP="$(path_without_python3)"
f=""
if PATH="$NP" command -v python3 >/dev/null 2>&1; then
  f="$f [python3 is still reachable after pruning its PATH entries, so this row cannot be driven here]"
else
  CHAN="$BASE_TMP/nopy.chan"; : > "$CHAN"
  ( cd "$FX" && PATH="$NP" FFRO_OUTCOME_FILE="$CHAN" bash hooks/local/post-fusebase-update.sh --wire-hooks ) \
    > "$BASE_TMP/nopy.log" 2>&1
  NOPY_RC=$?
  [ "$NOPY_RC" -eq 2 ] || f="$f [a python3-less tree exited $NOPY_RC, not the documented rc 2]"
  [ "$(parsed_state "$CHAN")" = "unavailable" ] \
    || f="$f [a python3-less abort published '$(parsed_state "$CHAN")' instead of unavailable]"
  OUT="$(render "$CHAN")"
  printf '%s' "$OUT" | grep -qi "not touched" || f="$f [the trailer does not say the settings were not touched]"
  printf '%s' "$OUT" | grep -qi "cannot say" && f="$f [a known-zero-write abort renders 'cannot say', which is weaker than the truth]"
fi
[ -z "$f" ] && ok "s1-missing-python3-reports-untouched-not-unknown (D1: a deterministic pre-apply abort emits 'unavailable' with the reason class and rc, never 'cannot say')" \
            || bad s1-missing-python3-reports-untouched-not-unknown "$f"

###############################################################################
# C5 — DRIVEN merge failure. Preflight imports the merger's validator but never RUNS the
# merge (recovery-preflight.py:282-286), so a Step-5 write failure is reachable: point the
# merger's backup target at a DIRECTORY and its write raises after preflight passed.
###############################################################################
printf '{"hooks": {}}\n' > "$FX/.claude/settings.json"
rm -f "$FX/.claude/settings.json.pre-flow-merge" 2>/dev/null
mkdir -p "$FX/.claude/settings.json.pre-flow-merge" || { bad setup "could not stage the merge-failure injection"; finish; }
recover mergefail --wire-hooks
MF_LOG="$LOG"; MF_CHAN="$CHAN"; MF_RC="$RC"
OUT="$(render "$MF_CHAN")"
f=""
[ "$MF_RC" -ne 0 ] || f="$f [the injected write failure did not make recovery report a failure, so this row is not the scenario]"
[ "$(parsed_state "$MF_CHAN")" = "merge-failed" ] \
  || f="$f [a Step-5 merge failure published '$(parsed_state "$MF_CHAN")' instead of merge-failed]"
grep -q "Python merge failed" "$MF_LOG" || f="$f [recovery's summary does not carry the merger output as a warning]"
grep -q "^Step 5" "$MF_LOG" || grep -q "Step 5: .claude/settings.json merge check" "$MF_LOG" \
  || f="$f [the run never reached Step 5, so the failure was not a merge failure]"
printf '%s' "$OUT" | grep -qi "FAILED" || f="$f [the trailer does not say the merge failed]"
printf '%s' "$OUT" | grep -qi "UNCERTAIN" || f="$f [the trailer does not say the settings state is uncertain]"
printf '%s' "$OUT" | grep -qiE "unchanged|NOT modified|already" && f="$f [a failed merge is reported as if the file were untouched or already wired]"
[ -z "$f" ] && ok "s1-driven-merge-failure-is-uncertain-not-unchanged (a real Step-5 write failure after a passing preflight: merge-failed, trailer says FAILED + UNCERTAIN, merger output kept as a warning)" \
            || bad s1-driven-merge-failure-is-uncertain-not-unchanged "$f"
rmdir "$FX/.claude/settings.json.pre-flow-merge" 2>/dev/null

###############################################################################
# C4 — DRIVEN per-hook git-hook outcomes through the REAL installer
###############################################################################
GH_ROOT="$BASE_TMP/gh"
gh_fixture() {
  local d="$GH_ROOT/$1"
  mkdir -p "$d/hooks" || return 1
  cp -R "$ROOT/hooks/git" "$d/hooks/" 2>/dev/null || return 1
  ( cd "$d" && git init -q . ) || return 1
  printf '%s' "$d"
}
gh_states() {
  local d="$1" out rc
  out="$( cd "$d" && bash "$ROOT/hooks/local/install-git-hooks.sh" 2>&1 )"; rc=$?
  bash -euo pipefail -c '. "$0"; ffro_git_hook_states "$1" "$2"' "$ROOT/$RO_LIB" "$out" "$rc"
}
custom_hook() { printf '#!/bin/sh\n# a consumer hook Flow does not own\nexit 0\n' > "$1"; chmod +x "$1"; }

f=""
D="$(gh_fixture both-absent)"
S="$(gh_states "$D")"
[ "$S" = "pre-commit=installed commit-msg=installed" ] || f="$f [a virgin .git/hooks derived '$S']"
render_git "$S" | grep -qi "pre-commit is live" || f="$f [both installed but the trailer does not say the fixed pre-commit is live]"

S="$(gh_states "$D")"
[ "$S" = "pre-commit=current commit-msg=current" ] || f="$f [a second install over Flow-managed hooks derived '$S']"
render_git "$S" | grep -qi "pre-commit is live" || f="$f [already-current hooks are not reported live]"

D="$(gh_fixture custom-commit-msg)"; custom_hook "$D/.git/hooks/commit-msg"
S="$(gh_states "$D")"
[ "$S" = "pre-commit=installed commit-msg=custom" ] || f="$f [a custom commit-msg beside an installable pre-commit derived '$S']"
OUT="$(render_git "$S")"
printf '%s' "$OUT" | grep -qi "pre-commit is live" \
  || f="$f [THE C4 DEFECT: a custom commit-msg suppressed the 'pre-commit is live' fact for a pre-commit that WAS installed]"
printf '%s' "$OUT" | grep -qi "pre-commit is NOT live" \
  && f="$f [THE C4 DEFECT: the trailer asserts the Flow pre-commit is not live after installing it]"
printf '%s' "$OUT" | grep -qi "commit-msg" || f="$f [the preserved custom hook is not named by its hook name]"

D="$(gh_fixture custom-pre-commit)"; custom_hook "$D/.git/hooks/pre-commit"
S="$(gh_states "$D")"
[ "$S" = "pre-commit=custom commit-msg=installed" ] || f="$f [a custom pre-commit beside an installable commit-msg derived '$S']"
OUT="$(render_git "$S")"
printf '%s' "$OUT" | grep -qi "pre-commit is NOT live" || f="$f [a preserved custom pre-commit is not reported as not live]"
printf '%s' "$OUT" | grep -q -- "--force" || f="$f [the preserved-custom branch does not say how to install the Flow hook]"

D="$(gh_fixture installer-fails)"; mv "$D/hooks/git" "$D/hooks/git-moved"
S="$(gh_states "$D")"
[ "$S" = "pre-commit=failed commit-msg=failed" ] || f="$f [an installer exiting nonzero derived '$S']"
OUT="$(render_git "$S")"
printf '%s' "$OUT" | grep -qi "FAILED" || f="$f [the installer-failure branch does not report the failure]"
printf '%s' "$OUT" | grep -qi "is live" && f="$f [an installer failure still claims a hook is live]"
[ -z "$f" ] && ok "s1-git-hook-outcome-is-per-hook (driven through the real installer: installed/current/custom/failed derive per hook, and a custom commit-msg never denies a live pre-commit)" \
            || bad s1-git-hook-outcome-is-per-hook "$f"

###############################################################################
# RENDERING — the class a fixture cannot produce: the installer never ran
###############################################################################
f=""
render_git skipped | grep -qi "pre-commit is live" && f="$f [the skipped class claims the fixed pre-commit is live]"
render_git skipped | grep -qi "NOT (re)installed" || f="$f [the skipped class does not say the hooks were not installed here]"
[ -z "$f" ] && ok "s1-skipped-git-class-claims-nothing (rendering row: 'installer never ran' is unobservable from a driven install, and it must claim no outcome)" \
            || bad s1-skipped-git-class-claims-nothing "$f"

###############################################################################
# WIRING — upgrade.sh forwards the observed outcome through a channel it owns
###############################################################################
f=""
UPG_CODE="$(grep -vE '^[[:space:]]*#' "$UPGRADE")"
printf '%s' "$UPG_CODE" | grep -q 'FFRO_OUTCOME_FILE="\$(mktemp)"' \
  || f="$f [$UPGRADE does not create its own outcome channel]"
printf '%s' "$UPG_CODE" | grep -q 'export FFRO_OUTCOME_FILE' \
  || f="$f [the outcome channel is not exported, so the recovery child cannot write it]"
printf '%s' "$UPG_CODE" | grep -q 'ffro_parse "\$FFRO_OUTCOME_FILE"' \
  || f="$f [$UPGRADE does not parse the channel]"
printf '%s' "$UPG_CODE" | grep -q 'ffro_parse "\$RECOVERY_LOG"' \
  && f="$f [$UPGRADE parses the captured LOG again — consumer bytes share that stream (C2)]"
printf '%s' "$UPG_CODE" | grep -q 'ffro_settings_trailer' || f="$f [$UPGRADE never renders the settings outcome]"
printf '%s' "$UPG_CODE" | grep -q 'ffro_git_hook_trailer' || f="$f [$UPGRADE never renders the git-hook outcome]"
printf '%s' "$UPG_CODE" | grep -q 'ffro_git_hook_states "\$_gh_out" "\$_gh_rc"' \
  || f="$f [$UPGRADE no longer derives the git-hook outcome PER HOOK from the installer's own lines]"
printf '%s' "$UPG_CODE" | grep -qE 'echo .*settings\.json.*NOT modified' \
  && f="$f [the unconditional 'settings.json … NOT modified' echo is still in $UPGRADE]"
# Both temp files are deleted on the success and the failure path; the parse has to come first.
PARSE_LN="$(grep -n "ffro_parse" "$UPGRADE" | head -1 | cut -d: -f1)"
RM_LN="$(grep -n 'rm -f "\$RECOVERY_LOG" "\$FFRO_OUTCOME_FILE"' "$UPGRADE" | head -1 | cut -d: -f1)"
if [ -n "$PARSE_LN" ] && [ -n "$RM_LN" ]; then
  [ "$PARSE_LN" -lt "$RM_LN" ] || f="$f [the outcome is parsed after the channel is deleted]"
else
  f="$f [could not locate the parse/delete pair in $UPGRADE — the channel must share the log's lifetime]"
fi
[ -z "$f" ] && ok "s1-upgrade-forwards-the-observed-outcome (residency: creates+exports+deletes its own channel, parses it before deleting it, renders both surfaces, derives git state per hook)" \
            || bad s1-upgrade-forwards-the-observed-outcome "$f"

###############################################################################
# WIRING — every settings branch records an outcome, before the exit paths
###############################################################################
f=""
EMIT_LN="$(grep -n "^ffro_emit" "$RECOVERY" | head -1 | cut -d: -f1)"
SUMMARY_LN="$(grep -n "^# Summary" "$RECOVERY" | head -1 | cut -d: -f1)"
if [ -n "$EMIT_LN" ] && [ -n "$SUMMARY_LN" ]; then
  [ "$EMIT_LN" -lt "$SUMMARY_LN" ] \
    || f="$f [the settings outcome is published in/after the summary, so a crash between Step 5 and the summary erases it]"
else
  f="$f [could not locate ffro_emit and the Summary section in $RECOVERY]"
fi
grep -q "ffro_settings merge-failed" "$RECOVERY" || f="$f [the merge-failure branch records no outcome]"
grep -q "ffro_settings_merged" "$RECOVERY" || f="$f [the merged branch records no outcome]"
grep -q "ffro_settings already-current" "$RECOVERY" || f="$f [the no-op branch records no outcome]"
grep -q "ffro_settings not-authorized" "$RECOVERY" || f="$f [the unauthorized branch records no outcome]"
[ "$(grep -c "ffro_aborted_before_settings" "$RECOVERY")" -ge 3 ] \
  || f="$f [the deterministic pre-Step-5 aborts (no python3, plan validation rejected) do not both emit (D1)]"
[ -z "$f" ] && ok "s1-outcome-published-before-the-exit-paths (residency: every settings branch and both deterministic pre-apply aborts record an outcome, emitted before the summary/exit block)" \
            || bad s1-outcome-published-before-the-exit-paths "$f"

finish
