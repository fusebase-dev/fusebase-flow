#!/usr/bin/env bash
# Fusebase Flow — health check engine (read-only).
#
# PROVENANCE:
#   Shipped as part of Fusebase Flow v2.2.0+. Lives at hooks/local/ — outside the
#   Fusebase CLI's refresh manifest, so it survives `fusebase update`.
#
# PURPOSE:
#   Diagnostic inventory of the Fusebase Flow overlay state plus upstream-vs-local
#   comparison. Surfaces drift signatures (especially the `fusebase update`
#   aftermath signature) and recommends a recovery path. NEVER repairs. Operator
#   reads the report and runs `bash hooks/local/post-fusebase-update.sh` themselves
#   if recovery is desired (or replies affirmatively to the recovery offer in chat).
#
# UPGRADE POSTURE:
#   The expected sets of skills, agents, and lifecycle events are auto-discovered
#   from the upstream `.fusebase-flow-source/` clone at runtime — NOT hardcoded.
#   This means minor upstream releases (e.g. v2.2 -> v2.3 adding a new skill)
#   require ZERO maintenance to this engine: the engine simply discovers the
#   new expected count.
#   Major upstream releases (e.g. V2 -> V3) may still require manual edits to:
#     - Heading markers (still hardcoded in the engine + recovery script + overlay templates)
#     - Overlay template content (project-specific values, FR-XX rule references)
#
# USAGE:
#   bash hooks/local/fusebase-flow-health-check.sh
#
# EXIT CODES:
#   0  HEALTHY (no drift detected, upstream in sync)
#   1  DRIFTED (some Fusebase Flow content missing or upstream newer than local)
#   2  BROKEN  (preflight fails or hook tests fail with no operator-authored cause)
#   3  EXCEPTION_IN_EFFECT (drift attributable to active operator approval artifact(s))

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

OVERLAYS="hooks/local/fusebase-flow-overlays"
SOURCE_CLONE=".fusebase-flow-source"

# Tracking
LOCAL_OK=()
LOCAL_DRIFT=()
LOCAL_BROKEN=()
UPSTREAM_NOTES=()
ACTIVE_ARTIFACTS=()      # filenames of non-expired approval artifacts (informational)
ARTIFACT_NOTES=()        # human-readable summaries of each active artifact
DRIFT_SIGNATURE=""
RECOMMENDATIONS=()

###############################################################################
# Section 0 — Active approval artifacts (informational, before any checks)
###############################################################################
# Read state/approvals/*.json, filter for non-expired entries. Active artifacts
# legitimately authorize what hook tests expect to be denied — surfacing them
# upfront prevents false BROKEN verdicts.

if [ -d "state/approvals" ] && command -v python3 >/dev/null 2>&1; then
  while IFS= read -r artifact_file; do
    if [ -z "$artifact_file" ]; then continue; fi
    summary=$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$artifact_file" <<'PY' 2>/dev/null
import json, sys, time
try:
    p = sys.argv[1]
    data = json.loads(open(p, encoding='utf-8').read())
    expires = data.get('expires_at', '')
    now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    if expires and expires < now:
        sys.exit(1)  # expired - skip
    paths = data.get('paths', []) or []
    # Restrict scope to ASCII so it renders cleanly on any console codec
    scope = (data.get('scope', '') or '').encode('ascii', errors='replace').decode('ascii')[:80]
    print(f"paths={len(paths)} expires={expires} scope=\"{scope}\"")
    sys.exit(0)
except Exception:
    sys.exit(2)
PY
)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      ACTIVE_ARTIFACTS+=("$(basename "$artifact_file")")
      ARTIFACT_NOTES+=("$(basename "$artifact_file"): $summary")
    fi
  done < <(find state/approvals -maxdepth 2 -name '*.json' -type f 2>/dev/null)
fi

###############################################################################
# Section 1 — Local inventory (read-only)
###############################################################################

# VERSION
if [ -f VERSION ]; then
  LOCAL_VERSION=$(cat VERSION 2>/dev/null | tr -d '\n')
  LOCAL_OK+=("VERSION file: $LOCAL_VERSION")
else
  LOCAL_VERSION=""
  LOCAL_DRIFT+=("VERSION file missing at repo root")
fi

# AGENTS.md overlay marker
if [ -f AGENTS.md ]; then
  if grep -qF "## Fusebase Flow — workflow lifecycle overlay" AGENTS.md; then
    LOCAL_OK+=("AGENTS.md overlay block: present")
  else
    LOCAL_DRIFT+=("AGENTS.md overlay block: MISSING")
  fi
else
  LOCAL_DRIFT+=("AGENTS.md: file missing")
fi

# CLAUDE.md overlay marker (only if Claude Code in use)
if [ -f CLAUDE.md ]; then
  if grep -qF "## Fusebase Flow — additional rules (overlay)" CLAUDE.md; then
    LOCAL_OK+=("CLAUDE.md overlay block: present")
  else
    LOCAL_DRIFT+=("CLAUDE.md overlay block: MISSING")
  fi
fi

# Auto-discover canonical event names from upstream's settings.json.example
# (or local fallback). Falls back to hardcoded 6-event list if neither exists.
EXPECTED_EVENTS=()
if [ -f "$SOURCE_CLONE/.claude/settings.json.example" ] && command -v python3 >/dev/null 2>&1; then
  EXPECTED_EVENTS_STR=$(MSYS_NO_PATHCONV=1 python3 -c "
import json
try:
    data = json.load(open('$SOURCE_CLONE/.claude/settings.json.example', encoding='utf-8'))
    print(' '.join((data.get('hooks') or {}).keys()))
except Exception:
    pass
" 2>/dev/null)
  for e in $EXPECTED_EVENTS_STR; do EXPECTED_EVENTS+=("$e"); done
fi
if [ "${#EXPECTED_EVENTS[@]}" -eq 0 ]; then
  EXPECTED_EVENTS=(SessionStart UserPromptSubmit PreToolUse PostToolUse Stop PreCompact)
fi
EXPECTED_EVENT_COUNT="${#EXPECTED_EVENTS[@]}"

# .claude/settings.json — N lifecycle events (where N = upstream-canonical event count)
if [ -f .claude/settings.json ]; then
  EVENTS_PRESENT=0
  for event in "${EXPECTED_EVENTS[@]}"; do
    if grep -q "\"$event\":" .claude/settings.json 2>/dev/null; then
      EVENTS_PRESENT=$((EVENTS_PRESENT + 1))
    fi
  done
  if [ "$EVENTS_PRESENT" -eq "$EXPECTED_EVENT_COUNT" ]; then
    # Also check Fusebase Flow stop.py is in the Stop chain
    if grep -q "hooks/handlers/stop.py" .claude/settings.json 2>/dev/null; then
      LOCAL_OK+=(".claude/settings.json: $EVENTS_PRESENT/$EXPECTED_EVENT_COUNT lifecycle events wired (incl. Fusebase Flow stop.py)")
    else
      LOCAL_DRIFT+=(".claude/settings.json: $EVENTS_PRESENT/$EXPECTED_EVENT_COUNT events present BUT Fusebase Flow stop.py missing from Stop chain")
    fi
  else
    LOCAL_DRIFT+=(".claude/settings.json: only $EVENTS_PRESENT/$EXPECTED_EVENT_COUNT lifecycle events wired")
  fi
fi

# Auto-discover canonical Fusebase Flow skill names from upstream's skills/
# (or local skills/ as fallback).
SKILL_NAMES=()
if [ -d "$SOURCE_CLONE/skills" ]; then
  while IFS= read -r d; do
    [ -f "$d/SKILL.md" ] && SKILL_NAMES+=("$(basename "$d")")
  done < <(find "$SOURCE_CLONE/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
elif [ -d "skills" ]; then
  while IFS= read -r d; do
    [ -f "$d/SKILL.md" ] && SKILL_NAMES+=("$(basename "$d")")
  done < <(find skills -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
fi
EXPECTED_SKILL_COUNT="${#SKILL_NAMES[@]}"

# Fusebase Flow skills mirrored to .claude/skills/
if [ "$EXPECTED_SKILL_COUNT" -eq 0 ]; then
  LOCAL_BROKEN+=(".claude/skills/: cannot determine expected skill set (no upstream clone, no local skills/)")
else
  SKILLS_PRESENT=0
  for s in "${SKILL_NAMES[@]}"; do
    if [ -f ".claude/skills/$s/SKILL.md" ]; then
      SKILLS_PRESENT=$((SKILLS_PRESENT + 1))
    fi
  done
  if [ "$SKILLS_PRESENT" -eq "$EXPECTED_SKILL_COUNT" ]; then
    LOCAL_OK+=(".claude/skills/: $SKILLS_PRESENT/$EXPECTED_SKILL_COUNT Fusebase Flow skills mirrored")
  else
    LOCAL_DRIFT+=(".claude/skills/: only $SKILLS_PRESENT/$EXPECTED_SKILL_COUNT Fusebase Flow skills mirrored")
  fi
fi

# Auto-discover canonical Fusebase Flow agent names from upstream's agents/
# (or local agents/ as fallback).
AGENT_NAMES=()
if [ -d "$SOURCE_CLONE/agents" ]; then
  while IFS= read -r d; do
    AGENT_NAMES+=("$(basename "$d")")
  done < <(find "$SOURCE_CLONE/agents" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
elif [ -d "agents" ]; then
  while IFS= read -r d; do
    AGENT_NAMES+=("$(basename "$d")")
  done < <(find agents -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
fi
EXPECTED_AGENT_COUNT="${#AGENT_NAMES[@]}"

# Sub-agents mirrored to .claude/agents/
if [ "$EXPECTED_AGENT_COUNT" -eq 0 ]; then
  LOCAL_BROKEN+=(".claude/agents/: cannot determine expected agent set (no upstream clone, no local agents/)")
else
  AGENTS_PRESENT=0
  for a in "${AGENT_NAMES[@]}"; do
    if [ -f ".claude/agents/$a.md" ]; then
      AGENTS_PRESENT=$((AGENTS_PRESENT + 1))
    fi
  done
  AGENT_LIST=$(IFS=,; echo "${AGENT_NAMES[*]}" | sed 's/,/, /g')
  if [ "$AGENTS_PRESENT" -eq "$EXPECTED_AGENT_COUNT" ]; then
    LOCAL_OK+=(".claude/agents/: $AGENTS_PRESENT/$EXPECTED_AGENT_COUNT Fusebase Flow sub-agents mirrored ($AGENT_LIST)")
  else
    LOCAL_DRIFT+=(".claude/agents/: only $AGENTS_PRESENT/$EXPECTED_AGENT_COUNT Fusebase Flow sub-agents mirrored")
  fi
fi

# Health-check skill self-presence (sanity — this skill should be mirrored too)
if [ -f .claude/skills/fusebase-flow-health-check/SKILL.md ]; then
  LOCAL_OK+=(".claude/skills/fusebase-flow-health-check/: present (this skill, self-check)")
else
  LOCAL_DRIFT+=(".claude/skills/fusebase-flow-health-check/: MISSING (this skill not mirrored)")
fi

# Recovery script presence
if [ -x hooks/local/post-fusebase-update.sh ]; then
  LOCAL_OK+=("hooks/local/post-fusebase-update.sh: present and executable")
else
  LOCAL_BROKEN+=("hooks/local/post-fusebase-update.sh: MISSING — recovery is unavailable")
fi

# Overlay templates folder
if [ -d "$OVERLAYS" ]; then
  LOCAL_OK+=("$OVERLAYS/: present")
else
  LOCAL_BROKEN+=("$OVERLAYS/: MISSING — overlay templates unavailable; recovery cannot rebuild AGENTS.md/CLAUDE.md/settings.json")
fi

# Preflight (read-only — captures exit code only)
if [ -x hooks/local/preflight.sh ]; then
  if bash hooks/local/preflight.sh >/dev/null 2>&1; then
    LOCAL_OK+=("preflight: clean (0 errors)")
  else
    LOCAL_BROKEN+=("preflight: errors detected (run 'bash hooks/local/preflight.sh' to inspect)")
  fi
fi

# Hook tests — capture full output and attribute failures
if [ -x hooks/tests/run-tests.sh ]; then
  HOOK_TEST_OUTPUT=$(bash hooks/tests/run-tests.sh 2>&1 || true)
  HOOK_TEST_PASS_LINE=$(echo "$HOOK_TEST_OUTPUT" | grep -E "^\[run-tests\] [0-9]+/[0-9]+ PASS" | tail -1)
  HOOK_TEST_FAILS=$(echo "$HOOK_TEST_OUTPUT" | grep -E "^FAIL:" || true)

  if [ -z "$HOOK_TEST_FAILS" ]; then
    LOCAL_OK+=("hook tests: $HOOK_TEST_PASS_LINE")
  else
    artifact_attributable=0
    true_failures=0
    failed_names=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      # Example line:
      # FAIL: 07_pre_tool_use_blocked_protected_path_edit.json  (description) -> expected=deny got=allow ...
      test_name=$(echo "$line" | sed -E 's|^FAIL: ([0-9]+_[a-zA-Z_]+)\.json.*|\1|')
      failed_names+=("$test_name")
      case "$test_name" in
        *protected_path_edit*|*protected_paths*)
          if [ "${#ACTIVE_ARTIFACTS[@]}" -gt 0 ]; then
            artifact_attributable=$((artifact_attributable + 1))
          else
            true_failures=$((true_failures + 1))
          fi ;;
        *)
          true_failures=$((true_failures + 1)) ;;
      esac
    done <<< "$HOOK_TEST_FAILS"

    if [ "$true_failures" -gt 0 ]; then
      LOCAL_BROKEN+=("hook tests: $true_failures genuine failure(s) — ${failed_names[*]} (run 'bash hooks/tests/run-tests.sh' to inspect)")
    fi
    if [ "$artifact_attributable" -gt 0 ]; then
      LOCAL_DRIFT+=("hook tests: $artifact_attributable failure(s) attributable to active approval artifact(s); see Active Approvals section")
    fi
  fi
fi

# Windows shell:true patch (only relevant on Windows)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    if [ -f .claude/hooks/run-typecheck-features.js ]; then
      if grep -q '^\s*shell:' .claude/hooks/run-typecheck-features.js 2>/dev/null; then
        LOCAL_OK+=("Windows shell:true patch on run-typecheck-features.js: applied")
      else
        LOCAL_DRIFT+=("Windows shell:true patch on run-typecheck-features.js: MISSING (Windows + Node 22+ typecheck would EINVAL)")
      fi
    fi ;;
esac

###############################################################################
# Section 2 — Upstream comparison (.fusebase-flow-source/)
###############################################################################

if [ -d "$SOURCE_CLONE/.git" ]; then
  cd "$SOURCE_CLONE"

  UPSTREAM_FETCH_OUTPUT=$(git fetch origin --tags 2>&1)
  LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")
  REMOTE_HEAD=$(git rev-parse origin/main 2>/dev/null || echo "")
  UPSTREAM_VERSION=$(MSYS_NO_PATHCONV=1 git show origin/main:VERSION 2>/dev/null | tr -d '\n' || echo "?")

  if [ -z "$LOCAL_HEAD" ] || [ -z "$REMOTE_HEAD" ]; then
    UPSTREAM_NOTES+=("upstream fetch failed; cannot compare versions")
  elif [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
    UPSTREAM_NOTES+=("upstream in sync: local commit = origin/main = $LOCAL_HEAD ($UPSTREAM_VERSION)")
  else
    BEHIND=$(git rev-list --count "$LOCAL_HEAD..origin/main" 2>/dev/null || echo "?")
    UPSTREAM_NOTES+=("upstream NEWER: local at ${LOCAL_HEAD:0:7} ($LOCAL_VERSION), origin/main at ${REMOTE_HEAD:0:7} ($UPSTREAM_VERSION); local behind by $BEHIND commits")
    UPSTREAM_NOTES+=("recent upstream commits:")
    while IFS= read -r line; do UPSTREAM_NOTES+=("  $line"); done < <(git log --oneline "$LOCAL_HEAD..origin/main" 2>/dev/null | head -5)
  fi

  cd "$ROOT"
else
  UPSTREAM_NOTES+=(".fusebase-flow-source/ not present as a git clone; cannot fetch upstream comparison")
fi

###############################################################################
# Section 3 — Drift signature analysis
###############################################################################

DRIFT_COUNT="${#LOCAL_DRIFT[@]}"
BROKEN_COUNT="${#LOCAL_BROKEN[@]}"

# Count drift items that are explainable by an active approval artifact
ARTIFACT_DRIFT_COUNT=0
if [ "$DRIFT_COUNT" -gt 0 ]; then
  ARTIFACT_DRIFT_COUNT=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "active approval artifact" || true)
fi

if [ "$DRIFT_COUNT" -eq 0 ] && [ "$BROKEN_COUNT" -eq 0 ]; then
  DRIFT_SIGNATURE="HEALTHY"
elif [ "$BROKEN_COUNT" -gt 0 ]; then
  # Genuine breakage trumps everything
  DRIFT_SIGNATURE="BROKEN"
elif [ "$ARTIFACT_DRIFT_COUNT" -eq "$DRIFT_COUNT" ] && [ "$ARTIFACT_DRIFT_COUNT" -gt 0 ]; then
  # Every drift item is attributable to an active operator approval artifact —
  # this is the artifact mechanism working as designed, not real drift.
  DRIFT_SIGNATURE="EXCEPTION_IN_EFFECT"
else
  # AGENTS.md overlay missing + settings.json reduced is the canonical
  # `fusebase update` aftermath signature for current CLI versions.
  AGENTS_MISSING=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "AGENTS.md overlay block: MISSING" || true)
  SETTINGS_REDUCED=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "settings.json: only" || true)
  WIN_PATCH_MISSING=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "Windows shell:true patch.*MISSING" || true)

  if [ "$AGENTS_MISSING" -gt 0 ] && [ "$SETTINGS_REDUCED" -gt 0 ]; then
    DRIFT_SIGNATURE="FUSEBASE_UPDATE_AFTERMATH"
  elif [ "$WIN_PATCH_MISSING" -gt 0 ] && [ "$AGENTS_MISSING" -eq 0 ] && [ "$SETTINGS_REDUCED" -eq 0 ]; then
    DRIFT_SIGNATURE="DRIFTED"
  else
    DRIFT_SIGNATURE="DRIFTED"
  fi
fi

###############################################################################
# Section 4 — Recommendations
###############################################################################

case "$DRIFT_SIGNATURE" in
  HEALTHY)
    RECOMMENDATIONS+=("No action required. Fusebase Flow overlay is intact.") ;;
  EXCEPTION_IN_EFFECT)
    RECOMMENDATIONS+=("All drift is attributable to active approval artifact(s) in state/approvals/. This is the protected-paths exception mechanism working as designed.")
    RECOMMENDATIONS+=("Recovery script will NOT fix this — it doesn't touch state/approvals/.")
    RECOMMENDATIONS+=("To clear: when the protected work is done, delete the listed artifact(s) or wait for their expires_at to pass. Then re-run this health check.") ;;
  FUSEBASE_UPDATE_AFTERMATH)
    RECOMMENDATIONS+=("Drift signature matches the 'fusebase update' aftermath pattern (AGENTS.md overlay missing AND settings.json reduced).")
    RECOMMENDATIONS+=("Recommended recovery: bash hooks/local/post-fusebase-update.sh")
    RECOMMENDATIONS+=("That script is idempotent and restores AGENTS.md overlay, settings.json events, Windows typecheck patch, plus re-mirrors skills/agents (no-op if already present).")
    RECOMMENDATIONS+=("To avoid this in future: prefer 'fusebase update --skip-skills' for routine updates.") ;;
  DRIFTED)
    RECOMMENDATIONS+=("Drift detected but signature does NOT match a clean fusebase update aftermath. Review the LOCAL_DRIFT items above and investigate manually.")
    RECOMMENDATIONS+=("If you want the recovery script to attempt restoration anyway, run: bash hooks/local/post-fusebase-update.sh") ;;
  BROKEN)
    RECOMMENDATIONS+=("Genuine failure detected (NOT attributable to an active approval artifact).")
    RECOMMENDATIONS+=("Inspect the LOCAL_BROKEN items above; address each manually.")
    RECOMMENDATIONS+=("After fixes, re-run this health check.") ;;
esac

###############################################################################
# Section 5 — Output
###############################################################################

echo ""
echo "============================================================"
echo "Fusebase Flow — Health Check Report"
echo "============================================================"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Project root: $ROOT"
echo ""
echo "Local state ($((${#LOCAL_OK[@]} + ${#LOCAL_DRIFT[@]} + ${#LOCAL_BROKEN[@]})) checks):"
for x in "${LOCAL_OK[@]}";    do echo "  ✓ $x"; done
for x in "${LOCAL_DRIFT[@]}"; do echo "  ✗ $x"; done
for x in "${LOCAL_BROKEN[@]}";do echo "  ⚠ $x"; done
echo ""

if [ "${#ACTIVE_ARTIFACTS[@]}" -gt 0 ]; then
  echo "Active approval artifacts (${#ACTIVE_ARTIFACTS[@]}):"
  for x in "${ARTIFACT_NOTES[@]}"; do echo "  • $x"; done
  echo ""
fi

echo "Upstream comparison:"
for x in "${UPSTREAM_NOTES[@]}"; do echo "  $x"; done
echo ""

echo "Verdict: $DRIFT_SIGNATURE"
echo ""

echo "Recommendations:"
for x in "${RECOMMENDATIONS[@]}"; do echo "  • $x"; done
echo ""

echo "============================================================"

# Exit codes
case "$DRIFT_SIGNATURE" in
  HEALTHY)             exit 0 ;;
  EXCEPTION_IN_EFFECT) exit 3 ;;
  BROKEN)              exit 2 ;;
  *)                   exit 1 ;;
esac
