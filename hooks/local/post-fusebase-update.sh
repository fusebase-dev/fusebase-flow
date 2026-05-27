#!/usr/bin/env bash
# Fusebase Flow — post-fusebase-update recovery script.
#
# PROVENANCE:
#   Shipped as part of Fusebase Flow v2.2.0+. Lives at hooks/local/ — outside the
#   Fusebase CLI's refresh manifest, so it survives `fusebase update`.
#
#   If a future Fusebase CLI release expands its refresh manifest, run
#   `fusebase update --dry-run` once after the CLI bump to confirm hooks/local/
#   is still untouched.
#
# PURPOSE:
#   Run after `fusebase update` (without --skip-skills) to restore the Fusebase
#   Flow overlay that the CLI's full-refresh may remove or reduce. Idempotent:
#   safe to run multiple times; only re-applies pieces that are actually missing.
#
# What this script restores:
#   1. .claude/skills/<all Fusebase Flow skills>/      via upstream mirror-skills.sh
#   2. .agents/skills/<all Fusebase Flow skills>/      via upstream mirror-skills.sh
#   3. .claude/agents/<all Fusebase Flow sub-agents>.md  via upstream mirror-agents.sh
#   4. .codex/agents/<all Fusebase Flow sub-agents>.md   via upstream mirror-agents.sh
#   5. AGENTS.md "## Fusebase Flow — workflow lifecycle overlay" block
#      wrapped in CLI-preserved CUSTOM:SKILL markers (if missing)
#   6. CLAUDE.md "## Fusebase Flow — additional rules (overlay)" block (if missing)
#   7. .claude/settings.json — lifecycle event keys + Stop hook chain (if missing)
#   8. .claude/hooks/run-typecheck-features.js — Windows shell:true patch (until upstream CLI fix)
#   9. .claude/skills/fusebase-flow-health-check/  + .agents/skills/fusebase-flow-health-check/
#  10. .claude/commands/fusebase-health.md         (Claude Code slash command)
#
# Recommended workflow:
#   bash hooks/local/post-fusebase-update.sh
#   git diff                                   # review what changed
#   bash hooks/local/preflight.sh              # validate
#   bash hooks/tests/run-tests.sh              # all hook tests should pass
#   git add .gitignore AGENTS.md CLAUDE.md .claude/ .agents/ .codex/agents/
#   git commit -m "chore(flow): restore Fusebase Flow overlay after fusebase update"

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
# Step 1 — Re-mirror Fusebase Flow skills (upstream tool, idempotent by design)
###############################################################################

echo "[post-fusebase-update] Step 1: re-mirror Fusebase Flow skills..."
if [ -x hooks/local/mirror-skills.sh ]; then
  bash hooks/local/mirror-skills.sh >/dev/null 2>&1 || WARNINGS+=("mirror-skills.sh exited non-zero")
  ACTIONS_TAKEN+=("re-mirrored Fusebase Flow skills (.claude/skills/ + .agents/skills/)")
else
  WARNINGS+=("hooks/local/mirror-skills.sh not found or not executable")
fi

###############################################################################
# Step 2 — Re-mirror Fusebase Flow sub-agents (upstream tool, idempotent)
###############################################################################

echo "[post-fusebase-update] Step 2: re-mirror Fusebase Flow sub-agents..."
if [ -x hooks/local/mirror-agents.sh ]; then
  bash hooks/local/mirror-agents.sh >/dev/null 2>&1 || WARNINGS+=("mirror-agents.sh exited non-zero")
  ACTIONS_TAKEN+=("re-mirrored Fusebase Flow sub-agents (.claude/agents/ + .codex/agents/)")
else
  WARNINGS+=("hooks/local/mirror-agents.sh not found or not executable")
fi

###############################################################################
# Step 3 — Re-append AGENTS.md overlay if missing. The overlay template is
# wrapped in the CLI's CUSTOM:SKILL markers so current Fusebase CLI refreshes
# capture and restore it instead of evicting it on later full updates.
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
# Step 4 — Re-append CLAUDE.md overlay if missing (only if Claude Code is in use)
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
# Step 5 — Re-merge .claude/settings.json with Fusebase Flow lifecycle hooks
#          (Python-based; no jq dependency — Python is already a Fusebase Flow
#          hook-runtime requirement)
###############################################################################

echo "[post-fusebase-update] Step 5: .claude/settings.json merge check..."
MERGE_SCRIPT="$OVERLAYS/settings-json-merge.py"
if [ ! -f .claude/settings.json ]; then
  ACTIONS_SKIPPED+=(".claude/settings.json not present (Claude Code not configured)")
elif ! command -v python3 >/dev/null 2>&1; then
  WARNINGS+=("python3 not on PATH — cannot merge .claude/settings.json automatically; install Python 3 (also required by Fusebase Flow hooks)")
elif [ ! -f "$MERGE_SCRIPT" ]; then
  WARNINGS+=("$MERGE_SCRIPT missing; cannot merge settings.json")
else
  cp .claude/settings.json .claude/settings.json.pre-flow-merge
  MERGE_OUTPUT=$(python3 "$MERGE_SCRIPT" .claude/settings.json 2>&1)
  MERGE_EXIT=$?
  if [ $MERGE_EXIT -eq 0 ]; then
    if echo "$MERGE_OUTPUT" | grep -q "already up to date\|byte-identical"; then
      ACTIONS_SKIPPED+=(".claude/settings.json: Fusebase Flow events already wired")
      rm -f .claude/settings.json.pre-flow-merge   # no real change; backup unnecessary
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
# Step 6 — Re-apply Windows shell:true patch on run-typecheck-features.js
# (until upstream Fusebase CLI fix lands; mitigates spawnSync npm.cmd EINVAL on Node 22+)
###############################################################################

echo "[post-fusebase-update] Step 6: Windows typecheck wrapper patch check..."
TYPECHECK_FILE=".claude/hooks/run-typecheck-features.js"
if [ ! -f "$TYPECHECK_FILE" ]; then
  ACTIONS_SKIPPED+=("$TYPECHECK_FILE not present (CLI may not have shipped this hook on this version)")
elif grep -q '^\s*shell:' "$TYPECHECK_FILE"; then
  ACTIONS_SKIPPED+=("$TYPECHECK_FILE Windows shell:true patch already applied")
elif [ "$(uname -s)" != "MINGW64_NT-10.0-26200" ] && [ "$(uname -s)" != "MINGW64_NT" ] && [[ "$(uname -s)" != MINGW* ]] && [[ "$(uname -s)" != MSYS* ]] && [[ "$(uname -s)" != CYGWIN* ]]; then
  ACTIONS_SKIPPED+=("$TYPECHECK_FILE Windows patch not applied (not on Windows; uname=$(uname -s))")
else
  # Patch the spawnSync call to add shell: process.platform === 'win32'
  if grep -q '^\s*encoding: "utf-8",$' "$TYPECHECK_FILE"; then
    # Use python because portable across MSYS / WSL / cygwin
    python3 - <<'PYTHON_PATCH'
import re, pathlib
p = pathlib.Path(".claude/hooks/run-typecheck-features.js")
src = p.read_text(encoding="utf-8")
# Add shell line right after the encoding line (only if not already present)
if "shell:" not in src:
    src = re.sub(
        r'(\s+)encoding: "utf-8",\n',
        r'\1encoding: "utf-8",\n\1shell: process.platform === "win32",\n',
        src,
        count=1,
    )
    p.write_text(src, encoding="utf-8")
    print("PATCHED")
else:
    print("ALREADY_PATCHED")
PYTHON_PATCH
    if grep -q 'shell: process.platform === "win32"' "$TYPECHECK_FILE"; then
      ACTIONS_TAKEN+=("$TYPECHECK_FILE: re-applied Windows shell:true patch (CVE-2024-27980 mitigation)")
    else
      WARNINGS+=("$TYPECHECK_FILE: Windows shell:true patch attempt did not stick; review manually")
    fi
  else
    WARNINGS+=("$TYPECHECK_FILE: expected anchor 'encoding: \"utf-8\",' not found; CLI may have changed the file shape; manual patch required")
  fi
fi

###############################################################################
# Step 9 — Restore fusebase-flow-health-check skill mirror
###############################################################################

echo "[post-fusebase-update] Step 9: fusebase-flow-health-check skill restore..."
HEALTH_SKILL_TEMPLATE="$OVERLAYS/skills/fusebase-flow-health-check/SKILL.md"
if [ ! -f "$HEALTH_SKILL_TEMPLATE" ]; then
  WARNINGS+=("$HEALTH_SKILL_TEMPLATE missing; cannot restore fusebase-flow-health-check skill")
else
  RESTORED=0
  for target_dir in .claude/skills .agents/skills; do
    target_path="$target_dir/fusebase-flow-health-check/SKILL.md"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$target_path" ] && diff -q "$HEALTH_SKILL_TEMPLATE" "$target_path" >/dev/null 2>&1; then
      :  # already in place + byte-identical
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
# Step 10 — Restore /fusebase-health slash command
###############################################################################

echo "[post-fusebase-update] Step 10: /fusebase-health slash command restore..."
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
  for a in "${ACTIONS_TAKEN[@]}"; do echo "  ✓ $a"; done
  echo ""
fi
if [ "${#ACTIONS_SKIPPED[@]}" -gt 0 ]; then
  echo "Already in place (${#ACTIONS_SKIPPED[@]}):"
  for a in "${ACTIONS_SKIPPED[@]}"; do echo "  · $a"; done
  echo ""
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo "Warnings (${#WARNINGS[@]}):"
  for w in "${WARNINGS[@]}"; do echo "  ⚠ $w"; done
  echo ""
fi

echo "Recommended next steps:"
echo "  1. Review changes:   git diff"
echo "  2. Run validation:   bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && npm run lint"
echo "  3. Commit if clean:  git add . && git commit -m 'chore(flow): restore Fusebase Flow overlay after fusebase update'"

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  exit 1
fi
exit 0
