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
#   7. .claude/commands/fusebase-health.md
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

if [ ! -d "$OVERLAYS" ]; then
  echo "[post-fusebase-update] FATAL: $OVERLAYS not found. Cannot restore Fusebase Flow overlay." >&2
  exit 1
fi

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
  ACTIONS_SKIPPED+=("AGENTS.md overlay already present")
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
  ACTIONS_SKIPPED+=("CLAUDE.md overlay already present")
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
if [ ! -f .claude/settings.json ]; then
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

echo "[post-fusebase-update] Step 8: /fusebase-health slash command restore..."
HEALTH_CMD_TEMPLATE="$OVERLAYS/commands/fusebase-health.md"
HEALTH_CMD_TARGET=".claude/commands/fusebase-health.md"
if [ ! -f "$HEALTH_CMD_TEMPLATE" ]; then
  WARNINGS+=("$HEALTH_CMD_TEMPLATE missing; cannot restore /fusebase-health slash command")
elif [ -f "$HEALTH_CMD_TARGET" ] && diff -q "$HEALTH_CMD_TEMPLATE" "$HEALTH_CMD_TARGET" >/dev/null 2>&1; then
  ACTIONS_SKIPPED+=("/fusebase-health slash command already in place")
else
  mkdir -p "$(dirname "$HEALTH_CMD_TARGET")"
  cp "$HEALTH_CMD_TEMPLATE" "$HEALTH_CMD_TARGET"
  ACTIONS_TAKEN+=("/fusebase-health slash command: restored to $HEALTH_CMD_TARGET")
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
