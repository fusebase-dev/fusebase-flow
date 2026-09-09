#!/usr/bin/env bash
# Fusebase Flow — observed settings/git-hook outcome channel.
# Spec: docs/specs/hop-log-truthfulness-and-publisher-scope/spec.md § S1 + corrections.md C1-C4.
#
# TRIPWIRE: a child exit code cannot establish whether settings changed — recovery returns
#   nonzero for warnings raised AFTER a successful merge. ffro_emit therefore runs at the point
#   of determination (end of the settings step), never in the exit path, so a later surface
#   failure cannot erase the settings result.
#
# CONTRACT
#   recovery side: ffro_settings <state> [detail] · ffro_settings_merged <merge-stdout>
#                  ffro_aborted_before_settings <reason-class> [rc] · ffro_emit
#   caller side:   ffro_parse <outcome-channel> -> FFRO_STATE/FFRO_DETAIL · ffro_settings_trailer
#                  ffro_git_hook_states <installer-out> <rc> -> ffro_git_hook_trailer <states>
#   States: merged | already-current | created-minimal | merge-failed | not-authorized | absent
#           | unavailable | unknown (the channel carried no record)
FFRO_MARK="[post-fusebase-update] outcome:"
FFRO_STATE="${FFRO_STATE:-unknown}"
FFRO_DETAIL="${FFRO_DETAIL:-}"
# The CLOSED state vocabulary. A value outside it parses as unknown, so bytes a consumer
# controls can never surface in the caller's trailer as a state.
FFRO_STATES="merged already-current created-minimal merge-failed not-authorized absent unavailable unknown"

# TRIPWIRE: once this run CREATED the settings file, "could not evaluate" must not erase that —
# the file was written either way. Only a merge failure may reclassify it.
ffro_settings() {
  if [ "${FFRO_CREATED_MINIMAL:-0}" = 1 ] && [ "$1" != "merge-failed" ]; then
    FFRO_DETAIL="${FFRO_DETAIL:-}; then ${1}: ${2:-}"; return 0
  fi
  FFRO_STATE="$1"; FFRO_DETAIL="${2:-}"
}

# Turn the merger's itemised "  - <change>" lines into one single-line event list.
# TRIPWIRE: a merge that ran on a file THIS run created reports created-minimal, not merged — the
# events landing does not restore the external/CLI bytes that were unavailable (spec matrix row 4).
ffro_settings_merged() {
  local changes
  changes="$(printf '%s\n' "$1" | sed -n 's/^  - //p' | awk '{printf "%s%s", (NR>1 ? "; " : ""), $0}')"
  [ -n "$changes" ] || changes="Flow lifecycle events merged (the merger itemised no changes)"
  if [ "${FFRO_CREATED_MINIMAL:-0}" = 1 ]; then
    FFRO_STATE="created-minimal"
    FFRO_DETAIL="prior external/CLI settings bytes were unavailable and are still unresolved; this run wrote only: $changes"
    return 0
  fi
  FFRO_STATE="merged"; FFRO_DETAIL="$changes"
}

# TRIPWIRE: the PARSED channel is $FFRO_OUTCOME_FILE — a path the parsing caller creates
# (mktemp beside its capture log) and exports. Only ffro_emit writes it, so consumer bytes that
# reach the captured LOG (validator text quoting a hook key, merger diagnostics printed after
# this record) cannot become a record. The stdout line below is for a human reading a direct
# run: never parse it, and never point ffro_parse at a captured log.
ffro_emit() {
  local rec
  rec="$FFRO_MARK settings=${FFRO_STATE:-unknown} detail=$(printf '%s' "${FFRO_DETAIL:-}" | tr '\r\n' '  ')"
  printf '%s\n' "$rec"
  if [ -n "${FFRO_OUTCOME_FILE:-}" ]; then printf '%s\n' "$rec" > "$FFRO_OUTCOME_FILE" 2>/dev/null || true; fi
  return 0
}

# D1: a deterministic pre-apply abort wrote nothing to the target, so the outcome is KNOWN and
# "cannot say" would be weaker than the truth. TRIPWIRE: the reason class is a FIXED phrase the
# caller chooses — never validator output or a consumer path, which are consumer bytes.
ffro_aborted_before_settings() {
  ffro_settings unavailable "recovery aborted before its settings step ($1); .claude/settings.json was not touched (rc ${2:-2})"
  ffro_emit
}

# TRIPWIRE: TOTAL under `set -euo pipefail` for every input class (absent/empty/no-record/one/
# many). upgrade.sh calls this inside an `if` THEN body with -e live, so any nonzero return here
# kills the upgrade after recovery already ran — the "cannot say" branch below would be
# unreachable on exactly the runs it exists for. Never let a failed match escape as a status.
ffro_parse() {
  local line="" l=""
  FFRO_STATE="unknown"; FFRO_DETAIL=""
  { [ -n "${1:-}" ] && [ -f "$1" ] && [ -r "$1" ]; } || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in "$FFRO_MARK settings="*) line="$l" ;; esac
  done < "$1" || return 0
  [ -n "$line" ] || return 0
  line="${line#*settings=}"
  FFRO_STATE="${line%% detail=*}"
  case "$line" in
    *" detail="*) FFRO_DETAIL="${line#* detail=}" ;;
    *) FFRO_DETAIL="" ;;
  esac
  case " $FFRO_STATES " in *" $FFRO_STATE "*) ;; *) FFRO_STATE="unknown"; FFRO_DETAIL="" ;; esac
  return 0
}

ffro_settings_trailer() {
  case "${FFRO_STATE:-unknown}" in
    merged)
      echo "[upgrade] NOTE: .claude/settings.json WAS updated by the recovery step above (a recorded"
      echo "          hook-wiring intent authorized it). Changes: $FFRO_DETAIL"
      echo "          Review: git diff .claude/settings.json   (backup: .claude/settings.json.pre-flow-merge)"
      ;;
    already-current)
      echo "[upgrade] NOTE: .claude/settings.json already carried the Flow lifecycle events; nothing"
      echo "          was written to it."
      ;;
    created-minimal)
      echo "[upgrade] NOTE: .claude/settings.json did not exist, so recovery CREATED a minimal Flow-only"
      echo "          file. Not a complete settings recovery: $FFRO_DETAIL"
      echo "          Restore your external/CLI entries, then: bash hooks/local/post-fusebase-update.sh --wire-hooks"
      ;;
    merge-failed)
      echo "[upgrade] WARN: the .claude/settings.json merge FAILED — its wiring state is UNCERTAIN."
      echo "          Detail: $FFRO_DETAIL"
      echo "          Inspect the file, then re-run: bash hooks/local/post-fusebase-update.sh --wire-hooks"
      ;;
    not-authorized)
      echo "[upgrade] NOTE: .claude/settings.json was NOT modified — no recorded wiring intent covers it"
      echo "          and this run did not pass --wire-hooks. To authorize Flow lifecycle hooks:"
      echo "            bash hooks/local/post-fusebase-update.sh --wire-hooks"
      ;;
    absent)
      echo "[upgrade] NOTE: .claude/settings.json is not present (Claude Code not configured here), so no"
      echo "          lifecycle wiring was attempted. To create and wire it:"
      echo "            bash hooks/local/post-fusebase-update.sh --wire-hooks"
      ;;
    unavailable)
      echo "[upgrade] WARN: .claude/settings.json wiring could not be evaluated: $FFRO_DETAIL"
      ;;
    *)
      echo "[upgrade] WARN: the recovery step reported no .claude/settings.json outcome, so this run"
      echo "          cannot say whether it changed. Check it directly:"
      echo "            bash hooks/local/post-fusebase-update.sh"
      ;;
  esac
}

# ffro_git_hook_states <installer-output> <installer-rc> -> "pre-commit=<s> commit-msg=<s>"
# States: installed | current | custom | failed | skipped.
# TRIPWIRE: derive PER HOOK. install-git-hooks.sh loops over both and reports each one
# independently (and skipping a custom one does not change its exit code), so a custom
# commit-msg is NOT evidence that the Flow pre-commit is dead — that inference is the
# caller-summary defect this ticket exists to remove.
ffro_git_hook_states() {
  local out="${1:-}" rc="${2:-0}" h st states=""
  for h in pre-commit commit-msg; do
    st=skipped
    if [ "$rc" -ne 0 ]; then
      st=failed
    else
      case "$out" in
        *"installed $h ->"*|*"custom $h backed up"*) st=installed ;;
        *"current $h ->"*) st=current ;;
        *"custom $h detected"*) st=custom ;;
      esac
    fi
    states="${states:+$states }$h=$st"
  done
  printf '%s\n' "$states"
}

# ffro_git_hook_state <states-string> <hook> -> that hook's state (skipped when unnamed).
ffro_git_hook_state() {
  case " $1 " in *" $2="*) : ;; *) printf 'skipped'; return 0 ;; esac
  local rest="${1#*$2=}"
  printf '%s' "${rest%% *}"
}

# ffro_git_hook_trailer <states-string | single-state>
# A bare token means "both hooks in that state" — one vocabulary, two arities.
# TRIPWIRE: "the fixed pre-commit is live" belongs to pre-commit ∈ {installed,current} ONLY.
ffro_git_hook_trailer() {
  local spec="${1:-skipped}" pc cm
  case "$spec" in
    *=*) pc="$(ffro_git_hook_state "$spec" pre-commit)"; cm="$(ffro_git_hook_state "$spec" commit-msg)" ;;
    *) pc="$spec"; cm="$spec" ;;
  esac
  case "$pc" in
    installed|current)
      echo "[upgrade] NOTE: the Flow .git/hooks/pre-commit is installed and current, so the fixed pre-commit is live."
      ;;
    custom)
      echo "[upgrade] NOTE: a CUSTOM .git/hooks/pre-commit was preserved above — the Flow pre-commit is NOT live."
      echo "          Install it explicitly: bash hooks/local/install-git-hooks.sh --force"
      ;;
    failed)
      echo "[upgrade] WARN: the git fallback hook (re)install FAILED above — Flow git hooks may be STALE."
      echo "          Re-run and review: bash hooks/local/install-git-hooks.sh"
      ;;
    *)
      echo "[upgrade] NOTE: the Flow git fallback hooks were NOT (re)installed here (no .git/hooks, or the"
      echo "          installer is absent). Install them: bash hooks/local/install-git-hooks.sh"
      ;;
  esac
  if [ "$cm" = custom ] && [ "$pc" != custom ]; then
    echo "[upgrade] NOTE: a CUSTOM .git/hooks/commit-msg was preserved above (not overwritten); the Flow"
    echo "          commit-msg is NOT live. Install it explicitly: bash hooks/local/install-git-hooks.sh --force"
  fi
}
