#!/usr/bin/env bash
# Fusebase Flow — observed settings/git-hook outcome channel (S1).
#
# PROVENANCE:
#   Spec docs/specs/hop-log-truthfulness-and-publisher-scope/spec.md § S1. Extracted per FR-25
#   (upgrade.sh sits at its baselined ceiling) and because recovery and its callers must share
#   ONE outcome vocabulary — two copies of these state names would drift apart exactly the way
#   the static trailer drifted away from the merger.
#
# WHY: upgrade.sh printed an unconditional ".claude/settings.json was NOT modified — run
#   --wire-hooks" trailer while the nested post-fusebase-update.sh run had merged the lifecycle
#   events in the SAME hop (authorized by a schema-1 intent marker since 0829d16 / v4.15.0). A
#   consumer read the trailer, believed the file was untouched, and filed a wrong diagnosis. The
#   observer owns the fact; the caller renders it.
#
# TRIPWIRE: a child exit code cannot establish whether settings changed — recovery returns
#   nonzero for warnings raised AFTER a successful merge. ffro_emit therefore runs at the point
#   of determination (end of the settings step), never in the exit path, so a later surface
#   failure cannot erase the settings result.
#
# CONTRACT
#   recovery side: ffro_settings <state> [detail] · ffro_settings_merged <merge-stdout> · ffro_emit
#   caller side:   ffro_parse <captured-log> -> FFRO_STATE/FFRO_DETAIL · ffro_settings_trailer
#                  ffro_git_hook_trailer <installed|custom|failed|skipped>
#   States: merged | already-current | created-minimal | merge-failed | not-authorized | absent
#           | unavailable | unknown (the log carried no outcome line)

FFRO_MARK="[post-fusebase-update] outcome:"
FFRO_STATE="${FFRO_STATE:-unknown}"
FFRO_DETAIL="${FFRO_DETAIL:-}"

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

ffro_emit() { printf '%s settings=%s detail=%s\n' "$FFRO_MARK" "${FFRO_STATE:-unknown}" "${FFRO_DETAIL:-}"; }

ffro_parse() {
  local line=""
  FFRO_STATE="unknown"; FFRO_DETAIL=""
  [ -f "${1:-}" ] || return 0
  line="$(grep -F "$FFRO_MARK settings=" "$1" 2>/dev/null | tail -1)"
  [ -n "$line" ] || return 0
  line="${line#*settings=}"
  FFRO_STATE="${line%% detail=*}"
  case "$line" in
    *" detail="*) FFRO_DETAIL="${line#* detail=}" ;;
    *) FFRO_DETAIL="" ;;
  esac
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

ffro_git_hook_trailer() {
  case "${1:-skipped}" in
    installed)
      echo "[upgrade] NOTE: the Flow git fallback hooks were (re)installed above, so the fixed pre-commit is live."
      ;;
    custom)
      echo "[upgrade] NOTE: a CUSTOM .git/hooks hook was preserved above — the Flow pre-commit is NOT live."
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
}
