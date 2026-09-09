#!/usr/bin/env bash
# Fusebase Flow — S1: the hop log must report what actually happened.
# Spec: docs/specs/hop-log-truthfulness-and-publisher-scope/spec.md § S1 (outcome matrix).
#
# THE DEFECT THIS PINS: upgrade.sh:803-805 was an UNCONDITIONAL echo asserting
# ".claude/settings.json (Claude Code lifecycle hooks) was NOT modified — to (re)wire those, run
# … --wire-hooks". Since 0829d16 (first released in v4.15.0) recovery restores settings
# automatically from a valid ENABLED intent marker, so the same run could merge the lifecycle
# events and then print "NOT modified". A consumer read the trailer, believed the file was
# untouched, and filed a wrong regression diagnosis off it. The Git-fallback half of the same
# sentence had the identical defect: it claimed "the fixed pre-commit is live" even on the
# installer-failure and custom-hook-preserved branches directly above it.
#
# THE MISSING CHECK, NAMED: agreement between a component's observed outcome and every caller's
# summary — including the failure, preservation and no-op branches.
#
# WHAT EACH ROW CLASS PROVES, AND WHAT IT DOES NOT:
#   DRIVEN       runs the REAL hooks/local/post-fusebase-update.sh in a fixture consumer, then
#                renders the REAL upgrade.sh trailer (hooks/local/lib/recovery-outcome.sh) from
#                the log upgrade.sh actually captures. Behavioural end-to-end across the
#                reporting seam. It does NOT run upgrade.sh itself (that needs a staged source
#                clone and rewrites the tree); the WIRING rows below carry that half.
#   ANTI-REGRESSION  replays the v4.15.3 trailer bytes against the DRIVEN merged run. Without it
#                "no forbidden phrase" would be vacuous — this row establishes that the same
#                observed run did produce the contradiction before the fix.
#   RENDERING    feeds a synthetic outcome line to the shipped renderer. Used ONLY for
#                merge-failed, which a fixture cannot reach: lib/recovery-preflight.py validates
#                .claude/settings.json AND executes the merger before Step 5, so a broken merger
#                or malformed settings aborts the run with rc 2 instead of a Step-5 merge failure.
#   WIRING       greps the shipped upgrade.sh / post-fusebase-update.sh. Residency only — it
#                establishes that the caller forwards the parsed outcome and that the outcome is
#                published before the exit paths, not that any particular run printed it.
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

command -v python3 >/dev/null 2>&1 || { bad setup "python3 not on PATH"; finish; }
# ANTI-VACUITY: every rendering row below is "the trailer does not say X". With no renderer the
# empty string satisfies all of them, so its absence is a hard stop, never a quiet pass.
[ -f "$RO_LIB" ] || { bad setup "$RO_LIB is absent, so every rendering assertion would be vacuous"; finish; }
[ -f "$UPGRADE" ] || { bad setup "missing $UPGRADE"; finish; }
[ -f "$RECOVERY" ] || { bad setup "missing $RECOVERY"; finish; }

BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-s1.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

# The trailer upgrade.sh renders for a captured recovery log, produced by the SHIPPED renderer.
render() {
  ( cd "$ROOT" && bash -c '. "$0"; ffro_parse "$1"; ffro_settings_trailer' "$ROOT/$RO_LIB" "$1" 2>&1 )
}
render_state() {
  ( cd "$ROOT" && bash -c '. "$0"; FFRO_STATE="$1"; FFRO_DETAIL="$2"; ffro_settings_trailer' "$ROOT/$RO_LIB" "$1" "${2:-}" 2>&1 )
}
render_git() {
  ( cd "$ROOT" && bash -c '. "$0"; ffro_git_hook_trailer "$1"' "$ROOT/$RO_LIB" "$1" 2>&1 )
}
outcome_of() { grep -F "outcome: settings=" "$1" 2>/dev/null | tail -1 | sed 's/.*settings=\([^ ]*\).*/\1/'; }

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

# recover <log-name> [args...] -> runs the real recovery; echoes the log path.
recover() {
  local name="$1"; shift
  ( cd "$FX" && bash hooks/local/post-fusebase-update.sh "$@" ) > "$BASE_TMP/$name.log" 2>&1
  echo "$BASE_TMP/$name.log"
}

if ! build_fixture; then bad setup "could not build the fixture consumer"; finish; fi

###############################################################################
# DRIVEN — created-minimal: a file this run created is not a complete recovery
###############################################################################
LOG_CREATE="$(recover create --wire-hooks)"
OUT="$(render "$LOG_CREATE")"
f=""
[ "$(outcome_of "$LOG_CREATE")" = "created-minimal" ] \
  || f="$f [recovery created .claude/settings.json from nothing but published outcome '$(outcome_of "$LOG_CREATE")']"
printf '%s' "$OUT" | grep -qi "minimal" || f="$f [the trailer does not say a minimal file was created]"
printf '%s' "$OUT" | grep -qi "unresolved" || f="$f [the trailer does not say the prior external/CLI entries are still unresolved]"
printf '%s' "$OUT" | grep -qi "fully recovered" && f="$f [the trailer claims full recovery for a tree whose external settings bytes were never restored]"
[ -z "$f" ] && ok "s1-created-minimal-is-not-fully-recovered (a minimal Flow-only file is reported as incomplete, naming the unresolved external entries)" \
            || bad s1-created-minimal-is-not-fully-recovered "$f"

###############################################################################
# DRIVEN — already current: a no-op must not recommend rewiring
###############################################################################
LOG_NOOP="$(recover noop)"
OUT="$(render "$LOG_NOOP")"
f=""
[ "$(outcome_of "$LOG_NOOP")" = "already-current" ] \
  || f="$f [a second recovery over an already-wired tree published '$(outcome_of "$LOG_NOOP")' instead of already-current]"
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
LOG_MERGED="$(recover merged)"
OUT="$(render "$LOG_MERGED")"
f=""
[ "$(outcome_of "$LOG_MERGED")" = "merged" ] \
  || f="$f [automatic restoration merged the lifecycle events but published '$(outcome_of "$LOG_MERGED")']"
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
# pre-fix trailer is three literal `echo` statements, so it is EXECUTED here against the merged
# run's log and its output is put through the same predicates.
f=""
V4153_BLOCK="$(git show v4.15.3:hooks/local/upgrade.sh 2>/dev/null | grep -B2 -F 'NOT modified — to (re)wire those')"
if ! printf '%s' "$V4153_BLOCK" | grep -q "the Flow git fallback pre-commit was"; then
  f="$f [could not extract the v4.15.3 trailer, so this row cannot establish the regression]"
elif printf '%s' "$V4153_BLOCK" | grep -qvE '^echo "'; then
  f="$f [the extracted v4.15.3 block is not three literal echo statements; re-derive it before executing it]"
else
  OLD_OUT="$(bash -c "$V4153_BLOCK" 2>&1)"
  [ "$(outcome_of "$LOG_MERGED")" = "merged" ] \
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
# DRIVEN — the settings result survives a LATER recovery-surface failure
###############################################################################
printf '{"hooks": {}}\n' > "$FX/.claude/settings.json"
( cd "$FX" && FUSEBASE_FLOW_TEST_TAMPER_AFTER_APPLY=".claude/commands/fusebase-health.md" \
  bash hooks/local/post-fusebase-update.sh ) > "$BASE_TMP/late-fail.log" 2>&1
LATE_RC=$?
LOG_LATE="$BASE_TMP/late-fail.log"
OUT="$(render "$LOG_LATE")"
f=""
[ "$LATE_RC" -ne 0 ] || f="$f [the injected post-apply tamper did not make recovery report a failure, so this row is not the scenario]"
[ "$(outcome_of "$LOG_LATE")" = "merged" ] \
  || f="$f [a later surface failure erased the settings result: published '$(outcome_of "$LOG_LATE")' instead of merged]"
printf '%s' "$OUT" | grep -q "PreToolUse" || f="$f [the summary lost the event list when a later surface failed]"
printf '%s' "$OUT" | grep -qi "unchanged" && f="$f [the summary calls the settings unchanged after they were changed]"
printf '%s' "$OUT" | grep -qi "fully recovered" && f="$f [the summary claims full recovery for a run that failed a later surface]"
[ -z "$f" ] && ok "s1-settings-result-survives-a-later-failure (recovery exits nonzero AFTER the merge; the merged result and its event list still reach the summary)" \
            || bad s1-settings-result-survives-a-later-failure "$f"

###############################################################################
# DRIVEN — no authorization: not touched, plus how to authorize
###############################################################################
( cd "$FX" && bash hooks/local/post-fusebase-update.sh --forget-hook-wiring ) >/dev/null 2>&1
LOG_NOAUTH="$(recover noauth)"
OUT="$(render "$LOG_NOAUTH")"
f=""
[ "$(outcome_of "$LOG_NOAUTH")" = "not-authorized" ] \
  || f="$f [an opted-out tree published '$(outcome_of "$LOG_NOAUTH")' instead of not-authorized]"
printf '%s' "$OUT" | grep -qi "NOT modified" || f="$f [the trailer does not say the file was left alone]"
printf '%s' "$OUT" | grep -q -- "--wire-hooks" || f="$f [the trailer does not say how to authorize wiring]"
printf '%s' "$OUT" | grep -qiE "fully recovered|recovery (is )?complete" \
  && f="$f [the trailer claims the settings surface is fully recovered while it was deliberately skipped]"
[ -z "$f" ] && ok "s1-unauthorized-says-untouched-and-how-to-authorize (no ENABLED marker, no flag: untouched, with the authorizing command, and no completeness claim)" \
            || bad s1-unauthorized-says-untouched-and-how-to-authorize "$f"

###############################################################################
# RENDERING — merge failure (unreachable in a fixture; see the header)
###############################################################################
OUT="$(render_state merge-failed "merger exit 3; the atomic target write did not complete")"
f=""
printf '%s' "$OUT" | grep -qi "FAILED" || f="$f [the trailer does not say the merge failed]"
printf '%s' "$OUT" | grep -qi "UNCERTAIN" || f="$f [the trailer does not say the settings state is uncertain]"
printf '%s' "$OUT" | grep -q "exit 3" || f="$f [the trailer does not carry the detail that locates the failure]"
printf '%s' "$OUT" | grep -qiE "unchanged|NOT modified" && f="$f [a failed merge is reported as if the file were untouched]"
[ -z "$f" ] && ok "s1-merge-failure-renders-uncertain-not-unchanged (rendering row: a Step-5 merge failure is uncertain state plus a detail pointer, never 'unchanged')" \
            || bad s1-merge-failure-renders-uncertain-not-unchanged "$f"

###############################################################################
# RENDERING — the Git-fallback half of the SAME sentence
###############################################################################
f=""
render_git installed | grep -qi "pre-commit is live" \
  || f="$f [the installed branch dropped the 'fixed pre-commit is live' statement]"
for cls in custom failed skipped; do
  render_git "$cls" | grep -qi "pre-commit is live" \
    && f="$f [class '$cls' still claims the fixed pre-commit is live]"
done
render_git custom | grep -q -- "--force" || f="$f [the preserved-custom-hook branch does not say how to install the Flow hook]"
render_git failed | grep -qi "FAILED" || f="$f [the installer-failure branch does not report the failure]"
[ -z "$f" ] && ok "s1-git-fallback-claim-follows-the-observed-class ('the fixed pre-commit is live' is printed for installed only; custom/failed/skipped each report their own outcome)" \
            || bad s1-git-fallback-claim-follows-the-observed-class "$f"

###############################################################################
# WIRING — upgrade.sh forwards the observed outcome instead of asserting one
###############################################################################
f=""
UPG_CODE="$(grep -vE '^[[:space:]]*#' "$UPGRADE")"
printf '%s' "$UPG_CODE" | grep -q "ffro_parse" || f="$f [$UPGRADE never parses the recovery outcome]"
printf '%s' "$UPG_CODE" | grep -q "ffro_settings_trailer" || f="$f [$UPGRADE never renders the settings outcome]"
printf '%s' "$UPG_CODE" | grep -q "ffro_git_hook_trailer" || f="$f [$UPGRADE never renders the git-hook outcome]"
printf '%s' "$UPG_CODE" | grep -qE 'echo .*settings\.json.*NOT modified' \
  && f="$f [the unconditional 'settings.json … NOT modified' echo is still in $UPGRADE]"
# The log is deleted on both the success and the failure path; the parse has to come first.
PARSE_LN="$(grep -n "ffro_parse" "$UPGRADE" | head -1 | cut -d: -f1)"
RM_LN="$(grep -n 'rm -f "\$RECOVERY_LOG"' "$UPGRADE" | head -1 | cut -d: -f1)"
if [ -n "$PARSE_LN" ] && [ -n "$RM_LN" ]; then
  [ "$PARSE_LN" -lt "$RM_LN" ] || f="$f [the outcome is parsed after the captured log is deleted]"
else
  f="$f [could not locate the parse/delete pair in $UPGRADE]"
fi
for cls in failed custom installed; do
  printf '%s' "$UPG_CODE" | grep -q "GH_TRAILER=$cls" \
    || f="$f [the installer branch '$cls' does not record its observed class for the trailer]"
done
[ -z "$f" ] && ok "s1-upgrade-forwards-the-observed-outcome (residency: parses the captured log before deleting it, renders both surfaces, records all three installer classes, and the static claim is gone)" \
            || bad s1-upgrade-forwards-the-observed-outcome "$f"

###############################################################################
# WIRING — the outcome is published at determination time, not in the exit path
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
[ -z "$f" ] && ok "s1-outcome-published-before-the-exit-paths (residency: every settings branch records an outcome and it is emitted before the summary/exit block)" \
            || bad s1-outcome-published-before-the-exit-paths "$f"

finish
