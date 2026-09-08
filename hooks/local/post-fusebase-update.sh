#!/usr/bin/env bash
# Fusebase Flow - post-fusebase-update recovery script.
#
# Lives at hooks/local/, outside the FuseBase CLI refresh manifest in current
# CLI releases. Run after a CLI refresh/update when Flow overlay pieces need to
# be restored.
#
# What this script restores:
#   1. Flow skill mirrors in .claude/skills/ and .agents/skills/
#   2. Flow agent mirrors in .claude/agents/ and .codex/agents/
#   3. AGENTS.md Flow overlay block, wrapped in CLI-preserved CUSTOM:SKILL markers
#   4. CLAUDE.md Flow overlay block
#   5. .claude/settings.json Flow lifecycle events and stop.py hook
#   6. fusebase-flow-health-check skill mirrors
#   7. .claude/commands/*.md (ALL Fusebase Flow slash commands — data-driven
#      from the fusebase-flow-overlays/commands/ snapshot, never a fixed list)
#
# Guardrail:
#   .claude/hooks/** is CLI-owned. Flow recovery does not patch or restore CLI
#   hook helper files. If CLI-owned hook helpers are missing or stale, run the
#   current FuseBase CLI refresh/update first, then run this script.
#
# Flags:
#   --wire-hooks           opt-in: merge Flow lifecycle hooks into .claude/settings.json
#                          and RECORD the wiring intent (state/audit/flow-hook-wiring-intent.json)
#                          so the health check can tell "never opted in" from "opted in,
#                          then stripped".
#   --forget-hook-wiring   record a deliberate opt-out (intent enabled=false) and exit.
#                          Does NOT edit .claude/settings.json — removing the hooks is
#                          yours to do; this stops the health check reporting their
#                          absence as enforcement drift.
#   --refresh-overlays     replace a PRESENT but DRIFTED AGENTS.md/CLAUDE.md overlay block.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

ff_text_has_literal() {
  case "$1" in *"$2"*) return 0 ;; esac
  return 1
}

ff_text_has_exact_line() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ "$line" = "$2" ] && return 0
  done <<< "$1"
  return 1
}

ff_text_has_prefix_line() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$2"*) return 0 ;; esac
  done <<< "$1"
  return 1
}

ff_text_has_custom_detected() {
  case "${1,,}" in *custom\ *\ detected*) return 0 ;; esac
  return 1
}

ff_classify_git_hook_output() {
  local rc="$1" output="$2"
  GH_CUSTOM_PRESERVED=0
  ff_text_has_custom_detected "$output" && GH_CUSTOM_PRESERVED=1
  if [ "$rc" -ne 0 ]; then
    GH_HOOK_CLASS="failed"
  elif [ "$GH_CUSTOM_PRESERVED" -eq 1 ]; then
    GH_HOOK_CLASS="custom"
  elif ff_text_has_prefix_line "$output" "[fusebase-flow] installed "; then
    GH_HOOK_CLASS="installed"
  else
    GH_HOOK_CLASS="current"
  fi
}

ff_read_verify_fields() {
  python3 -I -S -c '
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
allowed = {"skill_mirrors", "agent_mirrors", "agents_overlay", "claude_overlay",
           "claude_settings", "git_hooks", "health_skill", "commands"}
seen = []
for name in ("verified_surfaces", "uncertain_surfaces"):
    items = value[name]
    if not isinstance(items, list) or len(items) != len(set(items)) \
            or any(not isinstance(item, str) or item not in allowed for item in items):
        raise SystemExit(1)
    seen.extend(items)
    print(name + "=" + ",".join(items))
if set(seen) != allowed or len(seen) != len(allowed):
    raise SystemExit(1)
' "$1"
}

# Git-exclude the *.pre-refresh-<ts> backups this recovery drops, so a downstream
# `git add -A` (FuseBase CLI `fusebase update` checkpoint) never stages them. upgrade.sh's
# hooks.pre-upgrade/policies.pre-upgrade snapshots carry the OLD secret-scan fixtures that
# HARD-BLOCK such a checkpoint; git-excluding these .pre-refresh backups too keeps a
# wholesale add clean (field escalation, v4.3.2). Local + idempotent.
ff_git_exclude_backups() {
  local ex line d
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null)" || return 0   # not a git repo -> no staging risk -> no-op
  [ -n "$ex" ] || return 0
  mkdir -p "$(dirname "$ex")" 2>/dev/null || return 1
  [ -e "$ex" ] && { [ -r "$ex" ] || return 1; }
  if [ -s "$ex" ] && [ -n "$(tail -c1 "$ex" 2>/dev/null)" ]; then
    printf '\n' >> "$ex" 2>/dev/null || return 1
  fi
  d='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
  for line in \
    "# Fusebase Flow upgrade/refresh backups (transient; keep until validated) — never stage them." \
    "*.pre-upgrade-$d" \
    "*.pre-bootstrap-$d" \
    "*.pre-refresh-$d"; do
    if ! grep -qxF "$line" "$ex" 2>/dev/null; then
      printf '%s\n' "$line" >> "$ex" 2>/dev/null || return 1
    fi
  done
  return 0
}
# NOTE: called AFTER argument parsing below (so `--help` never mutates .git/info/exclude),
# and its failure routes through WARNINGS (so it isn't swallowed when upgrade.sh filters output).

OVERLAYS="hooks/local/fusebase-flow-overlays"
ACTIONS_TAKEN=()
ACTIONS_SKIPPED=()
WARNINGS=()

# Flags (F2/F3):
#   --wire-hooks       opt-in: merge Flow lifecycle hooks into .claude/settings.json.
#                      DEFAULT IS OFF — recovery never silently changes settings.json
#                      (matches CLAUDE.md's "hooks are opt-in" contract).
#   --refresh-overlays version-aware: if an AGENTS.md/CLAUDE.md overlay block is
#                      PRESENT but DRIFTED from the template, replace it (with a
#                      backup) instead of skipping. Used by upgrade.sh.
WIRE_HOOKS=0
WIRE_HOOKS_REQUESTED=0
RESTORE_GIT_HOOKS=0
AUTO_RESTORE=0
RECOVERY_PARTIAL_REASON=""
REFRESH_OVERLAYS=0
FORGET_HOOK_WIRING=0
for arg in "$@"; do
  case "$arg" in
    --wire-hooks) WIRE_HOOKS=1; WIRE_HOOKS_REQUESTED=1; RESTORE_GIT_HOOKS=1 ;;
    --forget-hook-wiring) FORGET_HOOK_WIRING=1 ;;
    --refresh-overlays) REFRESH_OVERLAYS=1 ;;
    --help|-h) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "[post-fusebase-update] Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# The intent marker's read/write contract (S1). Sourced by the health engine too — one
# definition of the marker's schema, path and validation, never two.
FF_HWI_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/hook-wiring-intent.sh"
# shellcheck source=lib/hook-wiring-intent.sh
[ -f "$FF_HWI_LIB" ] && . "$FF_HWI_LIB"
FF_RECOVERY_PLAN_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/flow-recovery-plan.sh"
[ -f "$FF_RECOVERY_PLAN_LIB" ] && . "$FF_RECOVERY_PLAN_LIB"

if [ "$FORGET_HOOK_WIRING" -eq 1 ]; then
  if [ "$WIRE_HOOKS" -eq 1 ]; then
    echo "[post-fusebase-update] --wire-hooks and --forget-hook-wiring are contradictory; pick one." >&2
    exit 2
  fi
  if ! command -v ffhc_hwi_revoke >/dev/null 2>&1; then
    echo "[post-fusebase-update] FATAL: $FF_HWI_LIB missing; cannot record a hook-wiring opt-out." >&2
    exit 1
  fi
  ffhc_hwi_revoke "$ROOT" || { echo "[post-fusebase-update] FATAL: could not write $FFHC_HWI_REL" >&2; exit 1; }
  echo "[post-fusebase-update] Recorded a hook-wiring OPT-OUT in $FFHC_HWI_REL (enabled=false)."
  echo "[post-fusebase-update] .claude/settings.json was NOT modified. The health check will no"
  echo "[post-fusebase-update] longer report a missing Flow PreToolUse chain as enforcement drift."
  echo "[post-fusebase-update] Re-enable with: bash hooks/local/post-fusebase-update.sh --wire-hooks"
  exit 0
fi

HWI_STATE="ABSENT"
HWI_SURFACES=""
if command -v ffhc_hwi_state >/dev/null 2>&1; then
  HWI_STATE="$(ffhc_hwi_state "$ROOT")"
fi
if [ "$WIRE_HOOKS_REQUESTED" -eq 0 ] && [ "$HWI_STATE" = "ENABLED" ]; then
  HWI_SURFACES="$(ffhc_hwi_surfaces "$ROOT" 2>/dev/null || true)"
  if ff_text_has_exact_line "$HWI_SURFACES" "claude_settings"; then
    WIRE_HOOKS=1
    AUTO_RESTORE=1
  fi
  if ff_text_has_exact_line "$HWI_SURFACES" "git_hooks"; then
    if command -v ffhc_hwi_git_proven >/dev/null 2>&1 && ffhc_hwi_git_proven "$ROOT"; then
      RESTORE_GIT_HOOKS=1
    else
      WARNINGS+=("Git-hook intent has no prior installed-hook receipt; automatic installation was refused (use --wire-hooks to activate explicitly)")
      RECOVERY_PARTIAL_REASON="automatic Git-hook restoration lacks prior ownership proof"
    fi
  fi
fi
if [ "$WIRE_HOOKS_REQUESTED" -eq 0 ] \
    && command -v ffhc_hwi_settings_unresolved >/dev/null 2>&1 \
    && ffhc_hwi_settings_unresolved "$ROOT"; then
  RECOVERY_PARTIAL_REASON="prior external settings bytes remain unresolved; restore them or run --wire-hooks as explicit disposition"
fi

if [ ! -d "$OVERLAYS" ]; then
  echo "[post-fusebase-update] FATAL: $OVERLAYS not found. Cannot restore Fusebase Flow overlay." >&2
  exit 1
fi

ff_prevalidate_recovery() {
  [ -d flow-skills ] || { echo "canonical flow-skills/ missing"; return 1; }
  [ -d agents ] || { echo "canonical agents/ missing"; return 1; }
  [ -f "$OVERLAYS/overlay-block-replace.py" ] || { echo "overlay replacement helper missing"; return 1; }
  [ -f "$OVERLAYS/settings-json-merge.py" ] || { echo "settings merge helper missing"; return 1; }
  if [ "$WIRE_HOOKS" -eq 1 ] && [ -f .claude/settings.json ]; then
    python3 -I -S -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' .claude/settings.json \
      || { echo ".claude/settings.json is invalid"; return 1; }
  fi
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    local row file heading legacy legacy2 template
    for row in \
      "AGENTS.md|## FuseBase Flow — workflow lifecycle overlay|## Fusebase Flow — workflow lifecycle overlay||$OVERLAYS/agents-md-overlay.md" \
      "CLAUDE.md|## FuseBase Flow — Claude Code adapter|## FuseBase Flow — additional rules (overlay)|## Fusebase Flow — additional rules (overlay)|$OVERLAYS/claude-md-overlay.md"; do
      IFS='|' read -r file heading legacy legacy2 template <<<"$row"
      [ -f "$file" ] || continue
      if grep -qF "$heading" "$file" || grep -qF "$legacy" "$file" \
          || { [ -n "$legacy2" ] && grep -qF "$legacy2" "$file"; }; then
        local -a legacy_args=(--legacy-heading "$legacy")
        [ -n "$legacy2" ] && legacy_args+=(--legacy-heading "$legacy2")
        python3 "$OVERLAYS/overlay-block-replace.py" "$file" "$template" "$heading" "$file.preflight-unused" \
          "${legacy_args[@]}" --validate-only >/dev/null \
          || { echo "$file has ambiguous or invalid Flow overlay markers"; return 1; }
      fi
    done
  fi
}

RECOVERY_PREFLIGHT="hooks/local/lib/recovery-preflight.py"
if ! command -v python3 >/dev/null 2>&1; then
  echo "[post-fusebase-update] FATAL: recovery plan validation requires python3" >&2
  exit 2
fi
PREFLIGHT_PLAN="$(mktemp "${TMPDIR:-/tmp}/flow-recovery-plan.XXXXXX")"
PREFLIGHT_ARGS=(--root "$ROOT" --output "$PREFLIGHT_PLAN")
[ "$WIRE_HOOKS" -eq 1 ] && PREFLIGHT_ARGS+=(--wire-hooks)
[ "$RESTORE_GIT_HOOKS" -eq 1 ] && PREFLIGHT_ARGS+=(--restore-git-hooks)
[ "$REFRESH_OVERLAYS" -eq 1 ] && PREFLIGHT_ARGS+=(--refresh-overlays)
set +e
PREVALIDATION_OUTPUT="$(python3 -B "$RECOVERY_PREFLIGHT" "${PREFLIGHT_ARGS[@]}" 2>&1)"
PREVALIDATION_RC=$?
set -e
if [ "$PREVALIDATION_RC" -ne 0 ]; then
  rm -f "$PREFLIGHT_PLAN"
  echo "[post-fusebase-update] FATAL: recovery plan validation failed: $PREVALIDATION_OUTPUT" >&2
  exit 2
fi
RECOVERY_PLAN_ID="$(tail -n 1 <<<"$PREVALIDATION_OUTPUT" | tr -d '\r')"

if command -v ffrp_begin >/dev/null 2>&1; then
  ffrp_begin "$ROOT" "skill_mirrors,agent_mirrors,agents_overlay,claude_overlay,claude_settings,git_hooks,health_skill,commands" "$RECOVERY_PLAN_ID"
fi

ff_restore_provider_backup() {
  local target="$1" backup detail temp
  local -a fields=()
  mapfile -t fields < <(python3 -I -S -c '
import json,sys
value=json.load(open(sys.argv[1], encoding="utf-8"))
row=next((row for row in value["overlays"] if row["surface"] == sys.argv[2]), {})
print(row.get("backup", ""))
print(row.get("backup_error", ""))
' "$PREFLIGHT_PLAN" "$target")
  backup="${fields[0]:-}"
  detail="${fields[1]:-}"
  backup="${backup%$'\r'}"
  detail="${detail%$'\r'}"
  if [ -z "$backup" ]; then
    [ -n "$detail" ] && WARNINGS+=("$target provider restore unavailable: $detail")
    return 1
  fi
  temp="$(mktemp ".${target}.flow-XXXXXX")"
  cp "$backup" "$temp"
  mv "$temp" "$target"
  ACTIONS_TAKEN+=("$target: restored ownership-verified provider bytes from $backup")
}
RECOVERY_FINALIZED=0
ff_recovery_on_exit() {
  local rc="$1"
  if [ "$RECOVERY_FINALIZED" -eq 0 ] && command -v ffrp_finish >/dev/null 2>&1; then
    ffrp_finish "partial" "${rc:-1}" "recovery ended before final verification" || true
  fi
  if [ -n "${PREFLIGHT_PLAN:-}" ]; then
    rm -f "$PREFLIGHT_PLAN"
  fi
  return "$rc"
}
trap 'ff_recovery_on_exit $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Git-exclude the .pre-refresh backups this recovery drops (after arg parsing, so --help is
# a pure no-op). Best-effort + NON-fatal: a non-git dir is a no-op success (helper returns
# 0); a genuine write failure in a git repo is a plain note — NOT a WARNING (which would
# `exit 1` below and wrongly fail an overlay recovery that actually succeeded).
ff_git_exclude_backups || echo "[post-fusebase-update] note: could not update .git/info/exclude — .pre-refresh backups may be stageable by a later 'git add -A' (delete or unstage them before committing)." >&2

TS_REFRESH=$(date -u +%Y%m%dT%H%M%SZ)

# F2: version-aware overlay refresh — anchored on the CUSTOM:SKILL markers, NOT
# the heading. Both overlay templates wrap their heading INSIDE
# `<!-- CUSTOM:SKILL:BEGIN -->` … `<!-- CUSTOM:SKILL:END -->`. The previous
# heading-anchored logic compared (heading→EOF) against the full marker-wrapped
# template, so they could never match — every run reported DRIFTED and re-appended
# the wrapper, duplicating the BEGIN marker and unbalancing the block. This helper
# compares the live marker-wrapped block (the BEGIN immediately preceding the
# heading → EOF) against the template's marker-wrapped block and replaces it in
# place (with a .pre-refresh backup) only when they genuinely differ. A legacy
# marker-less block is treated as drifted and migrated to the wrapped form.
refresh_overlay_block() {
  local file="$1" heading="$2" legacy_heading="$3" template="$4" label="$5" legacy_heading2="${6:-}"
  [ -f "$template" ] || { WARNINGS+=("$template missing; cannot refresh $label overlay"); return 0; }

  local helper="$OVERLAYS/overlay-block-replace.py" backup="$file.pre-refresh-$TS_REFRESH"
  [ -f "$helper" ] || { WARNINGS+=("$helper missing; cannot refresh $label overlay"); return 0; }
  local output rc
  local -a legacy_args=(--legacy-heading "$legacy_heading")
  [ -n "$legacy_heading2" ] && legacy_args+=(--legacy-heading "$legacy_heading2")
  set +e
  output=$(python3 "$helper" "$file" "$template" "$heading" "$backup" "${legacy_args[@]}" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    WARNINGS+=("$label overlay refresh refused: $output")
    return 0
  fi
  if [ "$output" = "current" ]; then
    ACTIONS_SKIPPED+=("$label overlay present and current")
    return 0
  fi
  ACTIONS_TAKEN+=("$label: refreshed DRIFTED overlay block (backup: $backup)")
}

# ff_migrate_marker FILE OLD_HEADING NEW_HEADING: rewrite an exact overlay heading
# line (OLD -> NEW) in place. WS6 marker capitalization migration. Line-anchored on
# the full literal heading so it never rewrites the same words appearing in prose;
# awk (not sed) so the em-dash + parens are matched as literal bytes without ERE
# metacharacter escaping. Idempotent by construction — the caller only invokes this
# when OLD is present and NEW is absent, and it exits 0 only when it actually
# rewrote a line. Never touches file bytes other than the matched heading line(s).
ff_migrate_marker() {
  local file="$1" old="$2" new="$3" tmp
  tmp="$(mktemp)" || return 1
  awk -v o="$old" -v n="$new" '
    $0==o { print n; c++; next }
    { print }
    END { print c+0 > "/dev/stderr" }
  ' "$file" 2>"$tmp.n" >"$tmp"
  local n; n="$(cat "$tmp.n" 2>/dev/null)"; rm -f "$tmp.n"
  if [ "${n:-0}" -gt 0 ]; then
    cat "$tmp" > "$file"; rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"; return 1
}

###############################################################################
# Step 1 - Re-mirror Fusebase Flow skills.
###############################################################################

echo "[post-fusebase-update] Step 1: re-mirror Fusebase Flow skills..."
if [ -x hooks/local/mirror-skills.sh ]; then
  SKILL_MIRROR_OUTPUT="$(bash hooks/local/mirror-skills.sh 2>&1)" \
    || WARNINGS+=("mirror-skills.sh exited non-zero: $SKILL_MIRROR_OUTPUT")
  if ff_text_has_literal "$SKILL_MIRROR_OUTPUT" "copied 0;"; then
    ACTIONS_SKIPPED+=("Fusebase Flow skill mirrors already current")
  else
    ACTIONS_TAKEN+=("re-mirrored Fusebase Flow skills (.claude/skills/ + .agents/skills/)")
  fi
else
  WARNINGS+=("hooks/local/mirror-skills.sh not found or not executable")
fi

###############################################################################
# Step 2 - Re-mirror Fusebase Flow sub-agents.
###############################################################################

command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "skill_mirrors"
echo "[post-fusebase-update] Step 2: re-mirror Fusebase Flow sub-agents..."
if [ -x hooks/local/mirror-agents.sh ]; then
  AGENT_MIRROR_OUTPUT="$(bash hooks/local/mirror-agents.sh 2>&1)" \
    || WARNINGS+=("mirror-agents.sh exited non-zero: $AGENT_MIRROR_OUTPUT")
  if ff_text_has_literal "$AGENT_MIRROR_OUTPUT" "copied 0;"; then
    ACTIONS_SKIPPED+=("Fusebase Flow agent mirrors already current")
  else
    ACTIONS_TAKEN+=("re-mirrored Fusebase Flow sub-agents (.claude/agents/ + .codex/agents/)")
  fi
else
  WARNINGS+=("hooks/local/mirror-agents.sh not found or not executable")
fi

###############################################################################
# Step 3 - Re-append AGENTS.md overlay if missing.
###############################################################################

command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "agent_mirrors"
echo "[post-fusebase-update] Step 3: AGENTS.md overlay check..."
# WS6 marker migration: the heading was recapitalized Fusebase->FuseBase. Migrate
# an existing OLD marker to the NEW one IN PLACE (idempotent: only rewrites the
# legacy spelling, does nothing once already NEW) BEFORE the present/refresh check,
# so an upgraded installed base moves to the new marker without a hand edit and the
# NEW-marker refresh logic below then matches. Dual-accept means either spelling is
# valid; migration just converges the installed base on the canonical NEW form.
AGENTS_MARKER="## FuseBase Flow — workflow lifecycle overlay"
AGENTS_MARKER_OLD="## Fusebase Flow — workflow lifecycle overlay"
if [ "$REFRESH_OVERLAYS" -ne 1 ] && [ -f AGENTS.md ] && grep -qF "$AGENTS_MARKER_OLD" AGENTS.md && ! grep -qF "$AGENTS_MARKER" AGENTS.md; then
  # sed over the exact heading line only (leading `## `), never elsewhere in prose.
  ff_migrate_marker AGENTS.md "$AGENTS_MARKER_OLD" "$AGENTS_MARKER" \
    && ACTIONS_TAKEN+=("AGENTS.md: migrated overlay heading marker Fusebase->FuseBase (WS6)")
fi
if [ ! -f AGENTS.md ]; then
  if ! ff_restore_provider_backup AGENTS.md; then
    WARNINGS+=("AGENTS.md provider bytes unavailable and no ownership-verified backup exists; base was not synthesized")
    RECOVERY_PARTIAL_REASON="provider bytes could not be restored authoritatively"
  fi
elif grep -qF "$AGENTS_MARKER" AGENTS.md || grep -qF "$AGENTS_MARKER_OLD" AGENTS.md; then
  # F2: present — refresh if DRIFTED, only under --refresh-overlays (marker-anchored).
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    refresh_overlay_block AGENTS.md "$AGENTS_MARKER" "$AGENTS_MARKER_OLD" "$OVERLAYS/agents-md-overlay.md" "AGENTS.md"
  else
    ACTIONS_SKIPPED+=("AGENTS.md overlay already present (use --refresh-overlays to update a drifted block)")
  fi
else
  if [ ! -f "$OVERLAYS/agents-md-overlay.md" ]; then
    WARNINGS+=("$OVERLAYS/agents-md-overlay.md missing; cannot restore AGENTS.md")
  else
    cat "$OVERLAYS/agents-md-overlay.md" >> AGENTS.md
    ACTIONS_TAKEN+=("AGENTS.md: appended Fusebase Flow overlay block")
  fi
fi

###############################################################################
# Step 4 - Re-append CLAUDE.md overlay if missing.
###############################################################################

command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "agents_overlay"
echo "[post-fusebase-update] Step 4: CLAUDE.md overlay check..."
# WS6 marker migration (idempotent) — same as AGENTS.md above.
CLAUDE_MARKER="## FuseBase Flow — Claude Code adapter"
CLAUDE_MARKER_OLD="## FuseBase Flow — additional rules (overlay)"
CLAUDE_MARKER_OLDER="## Fusebase Flow — additional rules (overlay)"
if [ "$REFRESH_OVERLAYS" -ne 1 ] && [ -f CLAUDE.md ] && ! grep -qF "$CLAUDE_MARKER" CLAUDE.md; then
  for old_marker in "$CLAUDE_MARKER_OLD" "$CLAUDE_MARKER_OLDER"; do
    if grep -qF "$old_marker" CLAUDE.md; then
      ff_migrate_marker CLAUDE.md "$old_marker" "$CLAUDE_MARKER" \
        && ACTIONS_TAKEN+=("CLAUDE.md: migrated legacy overlay heading")
      break
    fi
  done
fi
if [ ! -f CLAUDE.md ]; then
  if ! ff_restore_provider_backup CLAUDE.md; then
    WARNINGS+=("CLAUDE.md provider bytes unavailable and no ownership-verified backup exists; base was not synthesized")
    RECOVERY_PARTIAL_REASON="provider bytes could not be restored authoritatively"
  fi
elif grep -qF "$CLAUDE_MARKER" CLAUDE.md || grep -qF "$CLAUDE_MARKER_OLD" CLAUDE.md \
    || grep -qF "$CLAUDE_MARKER_OLDER" CLAUDE.md; then
  # F2: present — refresh if DRIFTED, only under --refresh-overlays (marker-anchored).
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    refresh_overlay_block CLAUDE.md "$CLAUDE_MARKER" "$CLAUDE_MARKER_OLD" "$OVERLAYS/claude-md-overlay.md" "CLAUDE.md" "$CLAUDE_MARKER_OLDER"
  else
    ACTIONS_SKIPPED+=("CLAUDE.md overlay already present (use --refresh-overlays to update a drifted block)")
  fi
else
  if [ ! -f "$OVERLAYS/claude-md-overlay.md" ]; then
    WARNINGS+=("$OVERLAYS/claude-md-overlay.md missing; cannot restore CLAUDE.md")
  else
    cat "$OVERLAYS/claude-md-overlay.md" >> CLAUDE.md
    ACTIONS_TAKEN+=("CLAUDE.md: appended Fusebase Flow overlay block")
  fi
fi

###############################################################################
# Step 5 - Merge .claude/settings.json with Fusebase Flow lifecycle hooks.
###############################################################################

command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "claude_overlay"
echo "[post-fusebase-update] Step 5: .claude/settings.json merge check..."
MERGE_SCRIPT="$OVERLAYS/settings-json-merge.py"
if [ "$WIRE_HOOKS" -eq 1 ] && [ ! -f .claude/settings.json ]; then
  mkdir -p .claude
  SETTINGS_SEED="$(mktemp .claude/.settings.json.flow-XXXXXX)"
  printf '{}\n' > "$SETTINGS_SEED"
  mv "$SETTINGS_SEED" .claude/settings.json
  RECOVERY_PARTIAL_REASON="created minimal Flow-only settings; prior external settings bytes were unavailable"
  if [ "$AUTO_RESTORE" -eq 1 ] && command -v ffhc_hwi_set_settings_unresolved >/dev/null 2>&1; then
    ffhc_hwi_set_settings_unresolved "$ROOT" true \
      || WARNINGS+=("could not persist unresolved external settings state")
  fi
  ACTIONS_TAKEN+=(".claude/settings.json: created minimal Flow-only settings from valid intent")
fi
if [ "$WIRE_HOOKS" -ne 1 ]; then
  # F3: opt-in. By default recovery does NOT touch settings.json — this matches
  # CLAUDE.md's "hooks are opt-in: nothing runs until you copy settings.json.example."
  if [ -f .claude/settings.json ]; then
    ACTIONS_SKIPPED+=(".claude/settings.json NOT modified (hook wiring is opt-in — re-run with --wire-hooks to merge Flow lifecycle hooks)")
  else
    ACTIONS_SKIPPED+=(".claude/settings.json not present (Claude Code not configured)")
  fi
elif [ ! -f .claude/settings.json ]; then
  ACTIONS_SKIPPED+=(".claude/settings.json not present (Claude Code not configured)")
elif ! command -v python3 >/dev/null 2>&1; then
  WARNINGS+=("python3 not on PATH - cannot AUTO-MERGE .claude/settings.json (the merge script is Python). To enable hooks without it: cp .claude/settings.json.example .claude/settings.json (it ships the run-handler.sh wrapper, which auto-detects py/python at runtime or self-disables). Install Python 3.11+ (or set FUSEBASE_FLOW_PYTHON) for the auto-merge and to run the handlers.")
elif [ ! -f "$MERGE_SCRIPT" ]; then
  WARNINGS+=("$MERGE_SCRIPT missing; cannot merge settings.json")
else
  CLI_STOP_BASELINE="state/audit/cli-stop-baseline.json"
  set +e
  MERGE_OUTPUT=$(python3 "$MERGE_SCRIPT" .claude/settings.json \
    --baseline-out "$CLI_STOP_BASELINE" --backup-out .claude/settings.json.pre-flow-merge 2>&1)
  MERGE_EXIT=$?
  set -e
  # S1 intent: recorded ONLY when the tree ACHIEVED the wiring (the canonical handler is in the
  # merged file), never on the merge's exit code — see the TRIPWIRE on ffhc_hwi_record_wiring.
  # A failed merge (rc 3) stays silent: the merge failure is already reported below.
  HWI_RC=""
  if [ "$WIRE_HOOKS_REQUESTED" -eq 1 ] && [ "$HWI_STATE" != "ENABLED" ] \
      && command -v ffhc_hwi_record_wiring >/dev/null 2>&1; then
    set +e
    ffhc_hwi_record_wiring "$ROOT" "$MERGE_EXIT"; HWI_RC=$?
    set -e
    case "$HWI_RC" in
      0|3) : ;;
      4) WARNINGS+=("hook wiring NOT achieved: the settings merge exited 0 but $FFHC_HWI_HANDLER is still absent from .claude/settings.json, so Flow runtime enforcement (FR-06/07/12) is NOT wired. No intent marker was written — recording one here would make the health check report ENFORCEMENT STRIPPED and prescribe this same command. Inspect the PreToolUse array by hand, or start from the shipped wiring: cp .claude/settings.json.example .claude/settings.json") ;;
      *) WARNINGS+=("could not record the hook-wiring intent marker ($FFHC_HWI_REL); the health check will read this tree as 'not known to have opted in'") ;;
    esac
  fi
  if [ "$MERGE_EXIT" -eq 0 ]; then
    if [ "$WIRE_HOOKS_REQUESTED" -eq 1 ] \
        && command -v ffhc_hwi_set_settings_unresolved >/dev/null 2>&1 \
        && [ "$(ffhc_hwi_state "$ROOT")" = "ENABLED" ]; then
      ffhc_hwi_set_settings_unresolved "$ROOT" false \
        || WARNINGS+=("could not record explicit disposition of prior external settings uncertainty")
    fi
    if [ "$HWI_RC" = "0" ]; then
      ACTIONS_TAKEN+=(".claude/settings.json: recorded Flow hook-wiring intent ($FFHC_HWI_REL)")
    fi
    if ff_text_has_literal "$MERGE_OUTPUT" "baseline receipt already current"; then
      ACTIONS_SKIPPED+=(".claude/settings.json: CLI Stop baseline receipt already current")
    else
      ACTIONS_TAKEN+=(".claude/settings.json: wrote CLI Stop baseline receipt ($CLI_STOP_BASELINE)")
    fi
    if ff_text_has_literal "$MERGE_OUTPUT" "already up to date" \
        || ff_text_has_literal "$MERGE_OUTPUT" "byte-identical"; then
      ACTIONS_SKIPPED+=(".claude/settings.json: Fusebase Flow events already wired")
    else
      ACTIONS_TAKEN+=(".claude/settings.json: merged Fusebase Flow lifecycle events (backup at .claude/settings.json.pre-flow-merge)")
    fi
  else
    WARNINGS+=("Python merge failed (exit $MERGE_EXIT); atomic target write was not completed. Output: $MERGE_OUTPUT")
  fi
fi

###############################################################################
# Step 5b - (Re)install the Flow git fallback hooks (WS1c).
###############################################################################
# Under --wire-hooks, (re)install the git pre-commit/commit-msg so the FIXED
# pre-commit is live after an upgrade (the "upgrade doesn't wire the fixed
# pre-commit" gap). install-git-hooks.sh is SAFE: a custom .git/hooks/pre-commit
# is backed up + preserved, never silently clobbered (needs --force to replace).
command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "claude_settings"
echo "[post-fusebase-update] Step 5b: Flow git-hook (re)install check..."
if [ "$RESTORE_GIT_HOOKS" -eq 1 ] && [ -d .git/hooks ] && [ -x hooks/local/install-git-hooks.sh ]; then
  # TRIPWIRE (T24): capture OUTPUT + RC SEPARATELY. The old `install-git-hooks.sh | grep`
  # keyed off `$?` of grep, not the installer — an rc≠0 install that didn't print the
  # custom-preserve line was recorded as "(re)installed" (a silent false success).
  # set +e around the capture keeps a nonzero from aborting under set -euo pipefail.
  set +e
  GH_OUTPUT="$(bash hooks/local/install-git-hooks.sh 2>&1)"; GH_RC=$?
  set -e
  ff_classify_git_hook_output "$GH_RC" "$GH_OUTPUT"
  if [ "$GH_HOOK_CLASS" = "failed" ]; then
    WARNINGS+=("git fallback hook (re)install FAILED (exit $GH_RC); Flow hooks may be stale — re-run 'bash hooks/local/install-git-hooks.sh' and review. Output: $GH_OUTPUT")
  elif [ "$GH_HOOK_CLASS" = "custom" ]; then
    WARNINGS+=("custom .git/hooks preserved (not overwritten); re-run 'bash hooks/local/install-git-hooks.sh --force' to install the Flow hook")
  elif [ "$GH_HOOK_CLASS" = "installed" ]; then
    ACTIONS_TAKEN+=("(re)installed Flow git fallback hooks (.git/hooks/pre-commit, commit-msg)")
  else
    ACTIONS_SKIPPED+=("Flow git fallback hooks already current")
  fi
  if [ "$GH_RC" -eq 0 ] && [ "$GH_CUSTOM_PRESERVED" -eq 0 ]; then
    if [ "$WIRE_HOOKS_REQUESTED" -eq 1 ] && command -v ffhc_hwi_write >/dev/null 2>&1; then
      ffhc_hwi_write "$ROOT" true "claude_settings,git_hooks" \
        || WARNINGS+=("could not extend hook-wiring intent to the verified Git-hook surface")
    fi
  fi
else
  ACTIONS_SKIPPED+=(".git/hooks NOT touched (git-hook (re)install runs under --wire-hooks only)")
fi

###############################################################################
# Step 6 - CLI hook ownership guardrail.
###############################################################################

command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "git_hooks"
echo "[post-fusebase-update] Step 6: CLI hook ownership guardrail..."
ACTIONS_SKIPPED+=(".claude/hooks/** is CLI-owned; Flow recovery does not patch CLI hook helpers")

###############################################################################
# Step 7 - Restore fusebase-flow-health-check skill mirror.
###############################################################################

echo "[post-fusebase-update] Step 7: fusebase-flow-health-check skill restore..."
HEALTH_SKILL_CANON="flow-skills/fusebase-flow-health-check/SKILL.md"
HEALTH_SKILL_SNAPSHOT="hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md"
HEALTH_SKILL_SOURCE=""
if [ -f "$HEALTH_SKILL_CANON" ]; then
  HEALTH_SKILL_SOURCE="$HEALTH_SKILL_CANON"
elif command -v ffrp_owned_snapshot >/dev/null 2>&1 \
    && ffrp_owned_snapshot "$ROOT" "$HEALTH_SKILL_SNAPSHOT"; then
  HEALTH_SKILL_SOURCE="$HEALTH_SKILL_SNAPSHOT"
  ACTIONS_SKIPPED+=("canonical health skill unavailable; used ownership-verified recovery snapshot")
else
  WARNINGS+=("canonical health skill missing and recovery snapshot ownership is unverified")
fi
if [ -z "$HEALTH_SKILL_SOURCE" ]; then
  :
else
  RESTORED=0
  HEALTH_PLAN="$(mktemp "${TMPDIR:-/tmp}/flow-health-write-plan.XXXXXX")"
  HEALTH_RESULT="$(mktemp "${TMPDIR:-/tmp}/flow-health-write-result.XXXXXX")"
  for target_dir in .claude/skills .agents/skills; do
    target_path="$target_dir/fusebase-flow-health-check/SKILL.md"
    printf '%s\t%s\n' "$HEALTH_SKILL_SOURCE" "$target_path" >> "$HEALTH_PLAN"
  done
  set +e
  python3 "$ROOT/hooks/local/lib/recovery-owned-write.py" --root "$ROOT" \
    --surface health-skill --plan "$HEALTH_PLAN" --result "$HEALTH_RESULT"
  HEALTH_RC=$?
  set -e
  while IFS=$'\t' read -r status target_path detail backup; do
    case "$status" in
      missing-and-authorized|owned-repair) RESTORED=$((RESTORED + 1)) ;;
      current) : ;;
      *) WARNINGS+=("health-skill target preserved: $target_path ($status: $detail)") ;;
    esac
  done < "$HEALTH_RESULT"
  rm -f "$HEALTH_PLAN" "$HEALTH_RESULT"
  [ "$HEALTH_RC" -eq 0 ] || RECOVERY_PARTIAL_REASON="one or more health-skill targets were preserved"
  if [ "$RESTORED" -gt 0 ]; then
    ACTIONS_TAKEN+=("fusebase-flow-health-check skill: restored to $RESTORED of 2 mirror paths")
  else
    ACTIONS_SKIPPED+=("fusebase-flow-health-check skill already mirrored to both paths")
  fi
fi

###############################################################################
# Step 8 - Restore Fusebase Flow slash commands (data-driven from the
#          recovery snapshot — this is the installer step new commands ship in).
###############################################################################

command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "health_skill"
echo "[post-fusebase-update] Step 8: Fusebase Flow slash commands restore..."
CMD_TEMPLATE_DIR="$OVERLAYS/commands"
CMD_TARGET_DIR=".claude/commands"
if [ ! -d "$CMD_TEMPLATE_DIR" ]; then
  WARNINGS+=("$CMD_TEMPLATE_DIR missing; cannot restore Fusebase Flow slash commands")
else
  CMD_RESTORED=0
  CMD_TOTAL=0
  CMD_PLAN="$(mktemp "${TMPDIR:-/tmp}/flow-command-write-plan.XXXXXX")"
  CMD_RESULT="$(mktemp "${TMPDIR:-/tmp}/flow-command-write-result.XXXXXX")"
  for cmd_template in "$CMD_TEMPLATE_DIR"/*.md; do
    [ -f "$cmd_template" ] || continue
    CMD_TOTAL=$((CMD_TOTAL + 1))
    cmd_name="$(basename "$cmd_template")"
    cmd_target="$CMD_TARGET_DIR/$cmd_name"
    printf '%s\t%s\n' "$cmd_template" "$cmd_target" >> "$CMD_PLAN"
  done
  set +e
  python3 "$ROOT/hooks/local/lib/recovery-owned-write.py" --root "$ROOT" \
    --surface command --plan "$CMD_PLAN" --result "$CMD_RESULT"
  CMD_RC=$?
  set -e
  while IFS=$'\t' read -r status cmd_target detail backup; do
    case "$status" in
      missing-and-authorized|owned-repair) CMD_RESTORED=$((CMD_RESTORED + 1)) ;;
      current) : ;;
      *) WARNINGS+=("command target preserved: $cmd_target ($status: $detail)") ;;
    esac
  done < "$CMD_RESULT"
  rm -f "$CMD_PLAN" "$CMD_RESULT"
  [ "$CMD_RC" -eq 0 ] || RECOVERY_PARTIAL_REASON="one or more command targets were preserved"
  if [ "$CMD_RESTORED" -gt 0 ]; then
    ACTIONS_TAKEN+=("Fusebase Flow slash commands: restored $CMD_RESTORED of $CMD_TOTAL to $CMD_TARGET_DIR")
  else
    ACTIONS_SKIPPED+=("Fusebase Flow slash commands already in place ($CMD_TOTAL command(s))")
  fi
fi

###############################################################################
# Summary
###############################################################################

echo ""
echo "============================================================"
command -v ffrp_applied >/dev/null 2>&1 && ffrp_applied "commands"
if [ -n "${FUSEBASE_FLOW_TEST_TAMPER_AFTER_APPLY:-}" ]; then
  printf '\nT15 POST-APPLY TAMPER\n' >> "$FUSEBASE_FLOW_TEST_TAMPER_AFTER_APPLY"
fi
VERIFY_RESULT="$(mktemp "${TMPDIR:-/tmp}/flow-recovery-verify.XXXXXX")"
set +e
VERIFY_OUTPUT="$(python3 -B hooks/local/lib/recovery-verify.py --root "$ROOT" \
  --plan "$PREFLIGHT_PLAN" --result "$VERIFY_RESULT" 2>&1)"
VERIFY_RC=$?
set -e
if [ -s "$VERIFY_RESULT" ]; then
  set +e
  VERIFY_FIELDS_OUTPUT="$(ff_read_verify_fields "$VERIFY_RESULT" 2>&1)"
  VERIFY_FIELDS_RC=$?
  set -e
  mapfile -t VERIFY_FIELDS <<< "$VERIFY_FIELDS_OUTPUT"
  VERIFY_FIELDS=("${VERIFY_FIELDS[0]-}" "${VERIFY_FIELDS[1]-}")
  VERIFY_FIELDS=("${VERIFY_FIELDS[0]%$'\r'}" "${VERIFY_FIELDS[1]%$'\r'}")
  if [ "$VERIFY_FIELDS_RC" -eq 0 ] && [ "${#VERIFY_FIELDS[@]}" -eq 2 ] \
      && [[ "${VERIFY_FIELDS[0]}" == verified_surfaces=* ]] \
      && [[ "${VERIFY_FIELDS[1]}" == uncertain_surfaces=* ]]; then
    VERIFIED_SURFACES="${VERIFY_FIELDS[0]#verified_surfaces=}"
    UNCERTAIN_SURFACES="${VERIFY_FIELDS[1]#uncertain_surfaces=}"
    command -v ffrp_verified >/dev/null 2>&1 \
      && ffrp_verified "$VERIFIED_SURFACES" "$UNCERTAIN_SURFACES"
  else
    VERIFY_RC=1
    VERIFY_OUTPUT="${VERIFY_OUTPUT:+$VERIFY_OUTPUT; }verification result parse failed: $VERIFY_FIELDS_OUTPUT"
  fi
else
  VERIFY_RC=1
  VERIFY_OUTPUT="${VERIFY_OUTPUT:+$VERIFY_OUTPUT; }verification result was missing or empty"
fi
rm -f "$VERIFY_RESULT" "$PREFLIGHT_PLAN"
PREFLIGHT_PLAN=""
if [ "$VERIFY_RC" -ne 0 ]; then
  WARNINGS+=("post-apply verification found incomplete surfaces: $VERIFY_OUTPUT")
  RECOVERY_PARTIAL_REASON="one or more recovery surfaces could not be verified"
fi
echo "[post-fusebase-update] Summary"
echo "============================================================"
echo ""
if [ "${#ACTIONS_TAKEN[@]}" -gt 0 ]; then
  echo "Actions taken (${#ACTIONS_TAKEN[@]}):"
  for a in "${ACTIONS_TAKEN[@]}"; do echo "  * $a"; done
  echo ""
fi
if [ "${#ACTIONS_SKIPPED[@]}" -gt 0 ]; then
  echo "Already in place (${#ACTIONS_SKIPPED[@]}):"
  for a in "${ACTIONS_SKIPPED[@]}"; do echo "  - $a"; done
  echo ""
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo "Warnings (${#WARNINGS[@]}):"
  for w in "${WARNINGS[@]}"; do echo "  ! $w"; done
  echo ""
fi
if [ -n "$RECOVERY_PARTIAL_REASON" ]; then
  echo "Recovery uncertainty: $RECOVERY_PARTIAL_REASON"
  echo ""
fi

echo "Recommended next steps:"
echo "  1. Review changes:   git diff"
echo "  2. Verify recovery:  bash hooks/local/mirror-skills.sh --check && bash hooks/tests/test-hook-wiring-intent.sh"
echo "  3. On the operator's go-ahead the AGENT stages + commits (the operator runs nothing; NO --no-verify):"
echo "       git add AGENTS.md CLAUDE.md .claude/settings.json .claude/commands .claude/skills .agents/skills .claude/agents .codex/agents"
echo "       # if the changeset touches Flow-internal protected paths, mint the single-use"
echo "       # bootstrap approval FIRST (digest-bound to exactly this staged changeset):"
echo "       bash hooks/local/write-bootstrap-approval.sh"
echo "       git commit -m 'chore(flow): restore Fusebase Flow overlay after fusebase update'"
echo "       bash hooks/local/write-bootstrap-approval.sh --consume   # single-use: clean up after"

if [ "${#WARNINGS[@]}" -gt 0 ] || [ -n "$RECOVERY_PARTIAL_REASON" ]; then
  command -v ffrp_finish >/dev/null 2>&1 \
    && ffrp_finish "partial" "1" "${RECOVERY_PARTIAL_REASON:-recovery completed with warnings}"
  RECOVERY_FINALIZED=1
  exit 1
fi
command -v ffrp_finish >/dev/null 2>&1 && ffrp_finish "complete" "0" "all authorized surfaces verified"
RECOVERY_FINALIZED=1
exit 0
