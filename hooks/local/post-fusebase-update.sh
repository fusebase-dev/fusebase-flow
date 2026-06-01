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
#   7. .claude/commands/*.md (all Fusebase Flow slash commands: fusebase-health, onboard, product-owner)
#
# Guardrail:
#   .claude/hooks/** is CLI-owned. Flow recovery does not patch or restore CLI
#   hook helper files. If CLI-owned hook helpers are missing or stale, run the
#   current FuseBase CLI refresh/update first, then run this script.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

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
REFRESH_OVERLAYS=0
for arg in "$@"; do
  case "$arg" in
    --wire-hooks) WIRE_HOOKS=1 ;;
    --refresh-overlays) REFRESH_OVERLAYS=1 ;;
    --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "[post-fusebase-update] Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -d "$OVERLAYS" ]; then
  echo "[post-fusebase-update] FATAL: $OVERLAYS not found. Cannot restore Fusebase Flow overlay." >&2
  exit 1
fi

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
  local file="$1" heading="$2" template="$3" label="$4"
  [ -f "$template" ] || { WARNINGS+=("$template missing; cannot refresh $label overlay"); return 0; }

  local heading_line begin_line
  heading_line=$(awk -v h="$heading" 'index($0,h){print NR; exit}' "$file")
  begin_line=$(awk -v hl="$heading_line" '
      index($0,"<!-- CUSTOM:SKILL:BEGIN -->") && (hl=="" || NR<=hl){b=NR}
      END{print b+0}' "$file")
  # Only accept a BEGIN that sits just above the heading (templates put it 4 lines
  # up). A distant BEGIN belongs to a different (e.g. CLI-owned) custom block —
  # treat the Flow block as marker-less so we never truncate that other block.
  if [ "${begin_line:-0}" -gt 0 ] && [ "${heading_line:-0}" -gt 0 ] \
     && [ $((heading_line - begin_line)) -gt 6 ]; then
    begin_line=0
  fi

  local file_block tmpl_block
  tmpl_block=$(awk 'index($0,"<!-- CUSTOM:SKILL:BEGIN -->"){f=1} f' "$template")
  if [ "${begin_line:-0}" -gt 0 ]; then
    file_block=$(awk -v s="$begin_line" 'NR>=s' "$file")
  else
    file_block="__LEGACY_MARKERLESS_BLOCK__"   # force migrate to wrapped form
  fi

  if [ "$file_block" = "$tmpl_block" ]; then
    ACTIONS_SKIPPED+=("$label overlay present and current")
    return 0
  fi

  cp "$file" "$file.pre-refresh-$TS_REFRESH"
  local cut
  if [ "${begin_line:-0}" -gt 0 ]; then cut="$begin_line"; else cut="$heading_line"; fi
  awk -v c="$cut" 'NR<c' "$file.pre-refresh-$TS_REFRESH" > "$file"
  cat "$template" >> "$file"
  ACTIONS_TAKEN+=("$label: refreshed DRIFTED overlay block (backup: $file.pre-refresh-$TS_REFRESH)")
}

###############################################################################
# Step 1 - Re-mirror Fusebase Flow skills.
###############################################################################

echo "[post-fusebase-update] Step 1: re-mirror Fusebase Flow skills..."
if [ -x hooks/local/mirror-skills.sh ]; then
  bash hooks/local/mirror-skills.sh >/dev/null 2>&1 || WARNINGS+=("mirror-skills.sh exited non-zero")
  ACTIONS_TAKEN+=("re-mirrored Fusebase Flow skills (.claude/skills/ + .agents/skills/)")
else
  WARNINGS+=("hooks/local/mirror-skills.sh not found or not executable")
fi

###############################################################################
# Step 2 - Re-mirror Fusebase Flow sub-agents.
###############################################################################

echo "[post-fusebase-update] Step 2: re-mirror Fusebase Flow sub-agents..."
if [ -x hooks/local/mirror-agents.sh ]; then
  bash hooks/local/mirror-agents.sh >/dev/null 2>&1 || WARNINGS+=("mirror-agents.sh exited non-zero")
  ACTIONS_TAKEN+=("re-mirrored Fusebase Flow sub-agents (.claude/agents/ + .codex/agents/)")
else
  WARNINGS+=("hooks/local/mirror-agents.sh not found or not executable")
fi

###############################################################################
# Step 3 - Re-append AGENTS.md overlay if missing.
###############################################################################

echo "[post-fusebase-update] Step 3: AGENTS.md overlay check..."
AGENTS_MARKER="## Fusebase Flow — workflow lifecycle overlay"
if [ ! -f AGENTS.md ]; then
  WARNINGS+=("AGENTS.md not found in repo root; skipping overlay restore")
elif grep -qF "$AGENTS_MARKER" AGENTS.md; then
  # F2: present — refresh if DRIFTED, only under --refresh-overlays (marker-anchored).
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    refresh_overlay_block AGENTS.md "$AGENTS_MARKER" "$OVERLAYS/agents-md-overlay.md" "AGENTS.md"
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

echo "[post-fusebase-update] Step 4: CLAUDE.md overlay check..."
CLAUDE_MARKER="## Fusebase Flow — additional rules (overlay)"
if [ ! -f CLAUDE.md ]; then
  ACTIONS_SKIPPED+=("CLAUDE.md not present (Claude Code not configured for this project)")
elif grep -qF "$CLAUDE_MARKER" CLAUDE.md; then
  # F2: present — refresh if DRIFTED, only under --refresh-overlays (marker-anchored).
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    refresh_overlay_block CLAUDE.md "$CLAUDE_MARKER" "$OVERLAYS/claude-md-overlay.md" "CLAUDE.md"
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

echo "[post-fusebase-update] Step 5: .claude/settings.json merge check..."
MERGE_SCRIPT="$OVERLAYS/settings-json-merge.py"
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
  WARNINGS+=("python3 not on PATH - cannot merge .claude/settings.json automatically")
elif [ ! -f "$MERGE_SCRIPT" ]; then
  WARNINGS+=("$MERGE_SCRIPT missing; cannot merge settings.json")
else
  cp .claude/settings.json .claude/settings.json.pre-flow-merge
  set +e
  MERGE_OUTPUT=$(python3 "$MERGE_SCRIPT" .claude/settings.json 2>&1)
  MERGE_EXIT=$?
  set -e
  if [ "$MERGE_EXIT" -eq 0 ]; then
    if echo "$MERGE_OUTPUT" | grep -q "already up to date\|byte-identical"; then
      ACTIONS_SKIPPED+=(".claude/settings.json: Fusebase Flow events already wired")
      rm -f .claude/settings.json.pre-flow-merge
    else
      ACTIONS_TAKEN+=(".claude/settings.json: merged Fusebase Flow lifecycle events (backup at .claude/settings.json.pre-flow-merge)")
    fi
  else
    WARNINGS+=("Python merge failed (exit $MERGE_EXIT); .claude/settings.json restored from backup. Output: $MERGE_OUTPUT")
    cp .claude/settings.json.pre-flow-merge .claude/settings.json
    rm -f .claude/settings.json.pre-flow-merge
  fi
fi

###############################################################################
# Step 6 - CLI hook ownership guardrail.
###############################################################################

echo "[post-fusebase-update] Step 6: CLI hook ownership guardrail..."
ACTIONS_SKIPPED+=(".claude/hooks/** is CLI-owned; Flow recovery does not patch CLI hook helpers")

###############################################################################
# Step 7 - Restore fusebase-flow-health-check skill mirror.
###############################################################################

echo "[post-fusebase-update] Step 7: fusebase-flow-health-check skill restore..."
HEALTH_SKILL_TEMPLATE="$OVERLAYS/skills/fusebase-flow-health-check/SKILL.md"
if [ ! -f "$HEALTH_SKILL_TEMPLATE" ]; then
  WARNINGS+=("$HEALTH_SKILL_TEMPLATE missing; cannot restore fusebase-flow-health-check skill")
else
  RESTORED=0
  for target_dir in .claude/skills .agents/skills; do
    target_path="$target_dir/fusebase-flow-health-check/SKILL.md"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$target_path" ] && diff -q "$HEALTH_SKILL_TEMPLATE" "$target_path" >/dev/null 2>&1; then
      :
    else
      cp "$HEALTH_SKILL_TEMPLATE" "$target_path"
      RESTORED=$((RESTORED + 1))
    fi
  done
  if [ "$RESTORED" -gt 0 ]; then
    ACTIONS_TAKEN+=("fusebase-flow-health-check skill: restored to $RESTORED of 2 mirror paths")
  else
    ACTIONS_SKIPPED+=("fusebase-flow-health-check skill already mirrored to both paths")
  fi
fi

###############################################################################
# Step 8 - Restore /fusebase-health slash command.
###############################################################################

echo "[post-fusebase-update] Step 8: Fusebase Flow slash commands restore..."
CMD_TEMPLATE_DIR="$OVERLAYS/commands"
CMD_TARGET_DIR=".claude/commands"
if [ ! -d "$CMD_TEMPLATE_DIR" ]; then
  WARNINGS+=("$CMD_TEMPLATE_DIR missing; cannot restore Fusebase Flow slash commands")
else
  CMD_RESTORED=0
  CMD_TOTAL=0
  mkdir -p "$CMD_TARGET_DIR"
  for cmd_template in "$CMD_TEMPLATE_DIR"/*.md; do
    [ -f "$cmd_template" ] || continue
    CMD_TOTAL=$((CMD_TOTAL + 1))
    cmd_name="$(basename "$cmd_template")"
    cmd_target="$CMD_TARGET_DIR/$cmd_name"
    if [ -f "$cmd_target" ] && diff -q "$cmd_template" "$cmd_target" >/dev/null 2>&1; then
      :
    else
      cp "$cmd_template" "$cmd_target"
      CMD_RESTORED=$((CMD_RESTORED + 1))
    fi
  done
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

echo "Recommended next steps:"
echo "  1. Review changes:   git diff"
echo "  2. Run validation:   bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh"
echo "  3. Commit if clean:  git add AGENTS.md CLAUDE.md .claude/settings.json .claude/commands .claude/skills .agents/skills .claude/agents .codex/agents && git commit -m 'chore(flow): restore Fusebase Flow overlay after fusebase update'"

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  exit 1
fi
exit 0
