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
#   aftermath signature) and recommends a recovery path. NEVER repairs. The agent
#   surfaces the report; on the operator's go-ahead (an affirmative reply to the
#   recovery offer in chat) the AGENT runs `bash hooks/local/post-fusebase-update.sh`
#   — the operator runs nothing.
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
#   0  HEALTHY (ALL critical checks ran and passed; no drift; upstream may be
#      unverified — upstream is optional and does NOT block exit 0)
#   1  CLI_LAYER_DRIFT / FLOW_LAYER_DRIFT / SHARED_MERGE_DRIFT
#   2  BROKEN  (a completed critical check failed, or a sub-script rc!=0 with no
#      parsable result — a harness crash)
#   3  EXCEPTION_IN_EFFECT (drift attributable to active operator approval artifact(s))
#   4  PARTIAL_UNVERIFIED (a CRITICAL check — preflight, hook layer integrity,
#      conflict reporter — was skipped/timed-out/unavailable and nothing proves
#      BROKEN; NOT a full health verdict. Never exit 0 when a critical did not run.)
#
# CRITICAL checks (must run to claim full health): preflight, hook layer
#   integrity (manifest verify), CLI/Flow conflict reporter (check-cli-flow-conflicts).
# OPTIONAL check: upstream comparison (git fetch + version diff) — may be
#   unavailable WITHOUT forcing exit 4; the verdict text then says
#   "upstream not verified".

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

OVERLAYS="hooks/local/fusebase-flow-overlays"
SOURCE_CLONE=".fusebase-flow-source"

# Bounded-execution helper (extracted per FR-25; see hooks/local/lib/run-with-timeout.sh).
# A missing lib is a critical dependency failure — fail loudly, never silently
# degrade into "criticals can't run".
FFHC_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/run-with-timeout.sh"
if [ ! -f "$FFHC_LIB" ]; then
  echo "[health-check] BROKEN — missing $FFHC_LIB (the bounded-execution helper). Re-clone or run: bash hooks/local/post-fusebase-update.sh" >&2
  exit 2
fi
# shellcheck source=lib/run-with-timeout.sh
. "$FFHC_LIB"
ffhc_detect_timeout   # sets FFHC_TIMEOUT_BIN to "timeout" | "gtimeout" | ""

# U7 (v3.24.x): the PARTIAL_UPGRADE derived-facts check lives in a sourced lib
# (FR-25 — the engine was at the 800-line ceiling). A missing lib degrades the
# check open (the function simply isn't defined; the section below no-ops) — it is
# a NEW signal, not a critical the verdict depends on, so its absence must not flip
# a HEALTHY tree to BROKEN.
FFHC_PARTIAL_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/partial-upgrade-check.sh"
# shellcheck source=lib/partial-upgrade-check.sh
[ -f "$FFHC_PARTIAL_LIB" ] && . "$FFHC_PARTIAL_LIB"

# SLO-budgeted timeouts (seconds), env-overridable. WS4: preflight/tests defaults
# are platform-gated by ffhc_default_timeout (MSYS 60/120, POSIX 30/60) — see the
# lib for the WHY; an explicit FFHC_*_TIMEOUT env value still wins via ${VAR:-…}.
FFHC_FETCH_TIMEOUT="${FFHC_FETCH_TIMEOUT:-15}"
FFHC_PREFLIGHT_TIMEOUT="${FFHC_PREFLIGHT_TIMEOUT:-$(ffhc_default_timeout preflight)}"
FFHC_CONFLICT_TIMEOUT="${FFHC_CONFLICT_TIMEOUT:-30}"
FFHC_TESTS_TIMEOUT="${FFHC_TESTS_TIMEOUT:-$(ffhc_default_timeout tests)}"
# Manifest verify replaces the run-tests CRITICAL (D4) — one python hash pass
# (seconds); budget = the preflight default (30 POSIX / 60 MSYS).
FFHC_MANIFEST_TIMEOUT="${FFHC_MANIFEST_TIMEOUT:-$(ffhc_default_timeout preflight)}"
# Opt-in escape hatch: when no timeout binary exists, run the bounded ops
# UNbounded instead of skipping them (H5 — off by default so a network-impaired
# host can never hang).
FFHC_ALLOW_UNBOUNDED="${FFHC_ALLOW_UNBOUNDED:-0}"

# Flags (H3): --no-upstream = full local verdict, exit 0 OK (upstream is
# optional). --fast = skip the slow hook tests (and upstream) for a quick verdict
# but it is EXPLICITLY PARTIAL — exit 4, never 0 — because a critical check
# (hook tests) deliberately did not run. Both keep preflight.
OPT_NO_UPSTREAM=0
OPT_FAST=0
OPT_RUN_HOOK_TESTS=0
OPT_RUN_HOOK_TESTS_FULL=0
for arg in "$@"; do
  case "$arg" in
    --no-upstream) OPT_NO_UPSTREAM=1 ;;
    --fast|--skip-hook-tests) OPT_FAST=1; OPT_NO_UPSTREAM=1 ;;   # --skip-hook-tests = --fast alias (B3): the Windows escape for the slow critical
    --run-hook-tests) OPT_RUN_HOOK_TESTS=1 ;;                    # OPTIONAL deep diagnostic (D5/D14 v4): platform-adaptive (POSIX=full run-tests.sh; MSYS=fast subset); never required for the verdict
    --run-hook-tests-full) OPT_RUN_HOOK_TESTS=1; OPT_RUN_HOOK_TESTS_FULL=1 ;;   # force the FULL suite even on MSYS (also: FFHC_RUN_HOOK_TESTS_FULL=1)
    -h|--help)
      echo "Usage: bash hooks/local/fusebase-flow-health-check.sh [--fast|--skip-hook-tests] [--run-hook-tests|--run-hook-tests-full] [--no-upstream]"
      echo "  --no-upstream      skip the optional upstream comparison (full local verdict; exit 0 OK)"
      echo "  --fast             skip the hook-layer-integrity critical + upstream for a quick verdict (PARTIAL; exit 4, never 0)"
      echo "  --skip-hook-tests  alias for --fast (skips the integrity critical; PARTIAL; exit 4, never 0)"
      echo "  --run-hook-tests   optional deep diagnostic (never required for the verdict). PLATFORM-ADAPTIVE: POSIX runs the FULL run-tests.sh; MSYS/Git-Bash runs the FAST subset (single-process fixtures + git-smoke + hook-manifest, < 120s)"
      echo "  --run-hook-tests-full  force the FULL run-tests.sh suite even on MSYS (also: FFHC_RUN_HOOK_TESTS_FULL=1)"
      echo "Env knobs (seconds): FFHC_FETCH_TIMEOUT FFHC_PREFLIGHT_TIMEOUT FFHC_CONFLICT_TIMEOUT FFHC_MANIFEST_TIMEOUT FFHC_TESTS_TIMEOUT"
      echo "  FFHC_ALLOW_UNBOUNDED=1  run bounded ops unbounded when no timeout binary exists"
      echo "  FFHC_RUN_HOOK_TESTS_FULL=1  force the full deep-run suite on MSYS (same as --run-hook-tests-full)"
      exit 0 ;;
    *) echo "[health-check] unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# Tracking
LOCAL_OK=()
LOCAL_DRIFT=()
LOCAL_BROKEN=()
LOCAL_UNVERIFIED=()      # CRITICAL checks that could not run (timed out / skipped / no timeout binary) — drive PARTIAL_UNVERIFIED/exit 4; NEVER let exit be 0 (engine v3.x+ / H4)
LOCAL_DEFERRED=()        # drift items deferred via active health_check_deferral artifact (engine v2.4.0+)
CLI_LAYER_DRIFT=()
SHARED_MERGE_DRIFT=()
UPSTREAM_NOTES=()
ACTIVE_ARTIFACTS=()      # filenames of non-expired approval artifacts (informational)
ARTIFACT_NOTES=()        # human-readable summaries of each active artifact
DEFERRED_CHECKS=()       # check_ids deferred via active health_check_deferral-*.json (engine v2.4.0+)
DEFERRED_BY_ARTIFACT=()  # parallel array — for each entry in DEFERRED_CHECKS, the artifact filename that authorized it
DRIFT_SIGNATURE=""
RECOMMENDATIONS=()
PARTIAL_UPGRADE_FINDINGS=()   # U7: stale derived-fact mismatches (version/FR/plugin vs live strings)
DEEP_RUN_NOTES=()             # --run-hook-tests optional deep-run notes (NEVER affect the verdict)

###############################################################################
# Section 0 — Active approval artifacts (informational, before any checks)
###############################################################################
# Read state/approvals/*.json, filter for non-expired entries. Two artifact types:
#
#   - protected_path_edit-*.json  (existing, since v2.0)
#       Authorizes specific protected-path edits. Lists `paths`. Allows hook test
#       failures named *protected_path_edit* to be attributed to the artifact.
#
#   - health_check_deferral-*.json  (new in engine v2.4.0)
#       Authorizes deliberate deferral of specific health-check items. Lists
#       `deferred_checks` — an array of stable check_ids (see docs/health-check-deferrals.md
#       for the canonical taxonomy). Engine reclassifies matching drift items to
#       LOCAL_DEFERRED, which counts toward EXCEPTION_IN_EFFECT verdict instead of
#       layer drift / BROKEN. Use when an install brief deliberately omits parts
#       of the canonical Fusebase Flow setup (e.g. settings.json lifecycle hooks
#       intentionally not wired).

# Extracted to a sourced lib per FR-25 (the U7 PARTIAL_UPGRADE section pushed the
# engine to the ceiling). The function populates ACTIVE_ARTIFACTS / ARTIFACT_NOTES /
# DEFERRED_CHECKS / DEFERRED_BY_ARTIFACT in THIS scope (sourced => shared scope).
FFHC_APPROVALS_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/active-approvals.sh"
# shellcheck source=lib/active-approvals.sh
if [ -f "$FFHC_APPROVALS_LIB" ]; then
  . "$FFHC_APPROVALS_LIB"
  ffhc_collect_active_approvals
fi

###############################################################################
# Helper: record_drift — push to LOCAL_DRIFT or LOCAL_DEFERRED based on whether
# the check_id is in the operator's active deferral list.
###############################################################################
record_drift() {
  local check_id="$1"
  local message="$2"
  local i found=""
  if [ "${#DEFERRED_CHECKS[@]}" -gt 0 ]; then
    for i in "${!DEFERRED_CHECKS[@]}"; do
      if [ "${DEFERRED_CHECKS[$i]}" = "$check_id" ]; then
        found="${DEFERRED_BY_ARTIFACT[$i]}"
        break
      fi
    done
  fi
  if [ -n "$found" ]; then
    LOCAL_DEFERRED+=("$message [check_id=$check_id; deferred per $found]")
  else
    LOCAL_DRIFT+=("$message")
  fi
}

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

# AGENTS.md overlay marker — count occurrences to catch duplicates.
# WS6 dual-marker: the ERE accepts BOTH legacy `## Fusebase Flow — …` and new
# `## FuseBase Flow — …` so the capitalization migration never breaks the installed
# base; the count spans both spellings, so a stray OLD+NEW pair still reads DUPLICATE.
if [ -f AGENTS.md ]; then
  AGENTS_OVERLAY_COUNT=$(grep -cE "^## Fuse[bB]ase Flow — workflow lifecycle overlay" AGENTS.md 2>/dev/null || true)
  if [ "$AGENTS_OVERLAY_COUNT" -eq 0 ]; then
    if grep -qF "Fusebase Flow always-on baseline" AGENTS.md 2>/dev/null; then
      LOCAL_OK+=("AGENTS.md baseline: present (source-template / edition mode)")
    else
      record_drift "agents_md_overlay" "AGENTS.md overlay block: MISSING"
    fi
  elif [ "$AGENTS_OVERLAY_COUNT" -eq 1 ]; then
    LOCAL_OK+=("AGENTS.md overlay block: present")
  else
    # Duplicate is a real config error worth investigating; not deferrable
    LOCAL_DRIFT+=("AGENTS.md overlay block: DUPLICATE ($AGENTS_OVERLAY_COUNT copies present — likely from a heading-marker rename without first removing the old block; remove the older block manually)")
  fi
else
  LOCAL_DRIFT+=("AGENTS.md: file missing")
fi

# CLAUDE.md overlay marker (Claude Code only) — same count logic + WS6 dual-accept.
if [ -f CLAUDE.md ]; then
  CLAUDE_OVERLAY_COUNT=$(grep -cE "^## Fuse[bB]ase Flow — additional rules \(overlay\)" CLAUDE.md 2>/dev/null || true)
  if [ "$CLAUDE_OVERLAY_COUNT" -eq 0 ]; then
    if grep -qF "Claude Code adapter for Fusebase Flow" CLAUDE.md 2>/dev/null; then
      LOCAL_OK+=("CLAUDE.md baseline: present (source-template / edition mode)")
    else
      record_drift "claude_md_overlay" "CLAUDE.md overlay block: MISSING"
    fi
  elif [ "$CLAUDE_OVERLAY_COUNT" -eq 1 ]; then
    LOCAL_OK+=("CLAUDE.md overlay block: present")
  else
    LOCAL_DRIFT+=("CLAUDE.md overlay block: DUPLICATE ($CLAUDE_OVERLAY_COUNT copies present — likely from a heading-marker rename without first removing the old block; remove the older block manually)")
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
  # Windows CRLF guard (engine v2.4.1+): Python's print() on Windows emits CRLF.
  # The for-loop word-splits on whitespace including \r, so the last event name
  # would inherit a trailing CR without this strip. Idempotent on Linux/Mac.
  EXPECTED_EVENTS_STR="${EXPECTED_EVENTS_STR//$'\r'/}"
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
  if grep -q "hooks/handlers/stop.py" .claude/settings.json 2>/dev/null; then
    FLOW_STOP_WIRED=1
  else
    FLOW_STOP_WIRED=0
  fi
  if [ "$EVENTS_PRESENT" -eq "$EXPECTED_EVENT_COUNT" ] && [ "$FLOW_STOP_WIRED" -eq 1 ]; then
    LOCAL_OK+=(".claude/settings.json: $EVENTS_PRESENT/$EXPECTED_EVENT_COUNT lifecycle events wired (incl. Fusebase Flow stop.py)")
  elif [ "$EVENTS_PRESENT" -eq "$EXPECTED_EVENT_COUNT" ] && [ "$FLOW_STOP_WIRED" -eq 0 ]; then
    # All Flow event keys present but stop.py absent from the Stop chain = a genuine
    # mis-wire (e.g. the U14 shared-Stop discovery bug). Keep this as drift.
    record_drift "settings_json_lifecycle_events" ".claude/settings.json: $EVENTS_PRESENT/$EXPECTED_EVENT_COUNT events present BUT Fusebase Flow stop.py missing from Stop chain"
  elif [ "$FLOW_STOP_WIRED" -eq 1 ]; then
    # stop.py wired but the Flow event set is incomplete = genuine partial degradation.
    record_drift "settings_json_lifecycle_events" ".claude/settings.json: only $EVENTS_PRESENT/$EXPECTED_EVENT_COUNT lifecycle events wired (stop.py present but events incomplete)"
  else
    # F2/U11: Flow lifecycle hooks are OPT-IN (F3). A settings.json with CLI hooks but
    # no Flow stop.py and no Flow events wired is the DELIBERATE overlay-only default —
    # benign, not SHARED_MERGE_DRIFT (consistent with check-cli-flow-conflicts.sh). The
    # CLI's own hooks are preserved. Reserve drift for the wired-then-broken cases above.
    LOCAL_OK+=(".claude/settings.json: Flow lifecycle hooks not wired (opt-in default; enable with: bash hooks/local/post-fusebase-update.sh --wire-hooks). Existing CLI hooks preserved.")
  fi
fi

# Auto-discover canonical Fusebase Flow skill names. Canonical lives at
# flow-skills/ (v3.9.0+); root skills/ is the legacy pre-3.9.0 location, still
# accepted as a fallback. Prefer the upstream staging clone, then local.
SKILL_NAMES=()
CANON_SKILLS_DIR=""
for cand in "$SOURCE_CLONE/flow-skills" "$SOURCE_CLONE/skills" "flow-skills" "skills"; do
  if [ -d "$cand" ]; then CANON_SKILLS_DIR="$cand"; break; fi
done
if [ -n "$CANON_SKILLS_DIR" ]; then
  while IFS= read -r d; do
    [ -f "$d/SKILL.md" ] && SKILL_NAMES+=("$(basename "$d")")
  done < <(find "$CANON_SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
fi
EXPECTED_SKILL_COUNT="${#SKILL_NAMES[@]}"

# Fusebase Flow skills mirrored to .claude/skills/
# Note (engine v2.3.2+): when upstream clone is absent and no local skills/
# directory exists, classify as informational OK rather than BROKEN.
# install-fusebase-cli-project.md and install-existing-project.md both
# instruct operators to clean up `.fusebase-flow-source/` after install,
# so this state is the documented post-install norm — not a failure.
if [ "$EXPECTED_SKILL_COUNT" -eq 0 ]; then
  LOCAL_OK+=(".claude/skills/: count not verified (no .fusebase-flow-source/ clone available; re-clone to enable upstream comparison)")
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
    record_drift "claude_skills_mirror_count" ".claude/skills/: only $SKILLS_PRESENT/$EXPECTED_SKILL_COUNT Fusebase Flow skills mirrored"
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
# (engine v2.3.2+ — same reclassification rationale as the skills check above)
if [ "$EXPECTED_AGENT_COUNT" -eq 0 ]; then
  LOCAL_OK+=(".claude/agents/: count not verified (no .fusebase-flow-source/ clone available; re-clone to enable upstream comparison)")
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
    record_drift "claude_agents_mirror_count" ".claude/agents/: only $AGENTS_PRESENT/$EXPECTED_AGENT_COUNT Fusebase Flow sub-agents mirrored"
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

# Preflight (CRITICAL, read-only — bounded). Timed-out/skipped => UNVERIFIED
# (never silently OK); a completed run that fails => BROKEN (AC4a).
if [ -x hooks/local/preflight.sh ]; then
  ffhc_run_bounded "$FFHC_PREFLIGHT_TIMEOUT" bash hooks/local/preflight.sh
  if [ "$FFHC_LAST_TIMED_OUT" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("preflight: UNVERIFIED — timed out after ${FFHC_PREFLIGHT_TIMEOUT}s (raise FFHC_PREFLIGHT_TIMEOUT or run 'bash hooks/local/preflight.sh')")
  elif [ "$FFHC_LAST_SKIPPED" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("preflight: UNVERIFIED — skipped (no timeout binary; install coreutils or set FFHC_ALLOW_UNBOUNDED=1)")
  elif [ "$FFHC_LAST_RC" -eq 0 ]; then
    LOCAL_OK+=("preflight: clean (0 errors)")
  else
    LOCAL_BROKEN+=("preflight: errors detected (run 'bash hooks/local/preflight.sh' to inspect)")
  fi
fi

# Hook layer integrity (CRITICAL) — manifest verify replaces the run-tests critical
# (D4): one python hash pass (seconds, OS-independent) that ALSO catches local
# tampering (which re-running tests does NOT — tampered code can still pass tests).
# The logic lives in a sourced lib (FR-25 — the engine is at the line ceiling); a
# missing lib degrades to LOCAL_UNVERIFIED + a re-upgrade hint (degrade-sane,
# consistent with the absent-manifest class — never a false HEALTHY). --run-hook-tests
# adds the OPTIONAL full run-tests.sh deep diagnostic (D5), gated inside the lib.
FFHC_INTEGRITY_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/hook-integrity-check.sh"
if [ -f "$FFHC_INTEGRITY_LIB" ]; then
  # shellcheck source=lib/hook-integrity-check.sh
  . "$FFHC_INTEGRITY_LIB"
  ffhc_hook_manifest_verify
  ffhc_hook_tests_deep_run
else
  LOCAL_UNVERIFIED+=("hook layer integrity: UNVERIFIED — missing $FFHC_INTEGRITY_LIB (re-clone or run 'bash hooks/local/upgrade.sh')")
fi

# CLI/Flow ownership report (CRITICAL, read-only — bounded; does full-tree scans
# that are slow in large repos). Timed-out/skipped => UNVERIFIED. JSON is read
# from stdout only (stderr suppressed) so the parser sees clean output.
CONFLICT_TIMED_OUT=0
CONFLICT_SKIPPED=0
if [ -x hooks/local/check-cli-flow-conflicts.sh ]; then
  # Bounded stdout-only capture via the lib's belt-#2 helper (D-B1): tempfile +
  # MSYS tree-reap so a descendant can't starve the parent; stderr dropped so the
  # JSON parser's input is identical to before. Map the FFHC_LAST_* globals to the
  # local CONFLICT_* the verdict logic below reads (no-binary SKIP policy preserved).
  ffhc_run_bounded_stdout "$FFHC_CONFLICT_TIMEOUT" bash hooks/local/check-cli-flow-conflicts.sh --json
  CONFLICT_JSON="$FFHC_LAST_OUT"; CONFLICT_RC="$FFHC_LAST_RC"
  CONFLICT_TIMED_OUT="$FFHC_LAST_TIMED_OUT"; CONFLICT_SKIPPED="$FFHC_LAST_SKIPPED"
  if [ "$CONFLICT_TIMED_OUT" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("CLI/Flow ownership report: UNVERIFIED — timed out after ${FFHC_CONFLICT_TIMEOUT}s (raise FFHC_CONFLICT_TIMEOUT or run 'bash hooks/local/check-cli-flow-conflicts.sh')")
  elif [ "$CONFLICT_SKIPPED" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("CLI/Flow ownership report: UNVERIFIED — skipped (no timeout binary; install coreutils or set FFHC_ALLOW_UNBOUNDED=1)")
  elif [ -n "$CONFLICT_JSON" ] && command -v python3 >/dev/null 2>&1; then
    CONFLICT_PARSED=$(printf '%s' "$CONFLICT_JSON" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print("VERDICT\t" + str(data.get("verdict", "")))
for f in data.get("findings", []):
    if f.get("status") not in {"MISSING", "DRIFT"}:
        continue
    print("\t".join([
        str(f.get("layer", "")),
        str(f.get("status", "")),
        str(f.get("path", "")),
        str(f.get("detail", "")),
        str(f.get("action", "")),
    ]))
' 2>/dev/null)
    if [ -n "$CONFLICT_PARSED" ]; then
      while IFS=$'\t' read -r layer status path detail action; do
        [ -z "$layer" ] && continue
        if [ "$layer" = "VERDICT" ]; then
          LOCAL_OK+=("CLI/Flow ownership report: $status")
          continue
        fi
        msg="$path: $status"
        [ -n "$detail" ] && msg="$msg ($detail)"
        [ -n "$action" ] && msg="$msg; action: $action"
        case "$layer" in
          cli) CLI_LAYER_DRIFT+=("$msg"); LOCAL_DRIFT+=("CLI layer: $msg") ;;
          shared) SHARED_MERGE_DRIFT+=("$msg"); LOCAL_DRIFT+=("Shared merge: $msg") ;;
          flow) record_drift "flow_owned_surface" "$msg" ;;
        esac
      done <<< "$CONFLICT_PARSED"
    else
      LOCAL_BROKEN+=("CLI/Flow ownership report: could not parse reporter output")
    fi
  else
    LOCAL_BROKEN+=("CLI/Flow ownership report: python3 unavailable or empty reporter output")
  fi
else
  LOCAL_DRIFT+=("hooks/local/check-cli-flow-conflicts.sh: MISSING (ownership report unavailable)")
fi

###############################################################################
# Section 1b — PARTIAL_UPGRADE derived-facts check (U7, read-only, local).
###############################################################################
# Compare derived facts (VERSION, FR-range, plugin version) against the LIVE
# attestation strings in the adapters. A mismatch == an upgrade that bumped VERSION
# but left stale strings (interrupted run / an adapter with no overlay-refresh
# path). Findings are genuine DRIFT (concrete, repairable) — recorded so the
# verdict can name PARTIAL_UPGRADE (a sub-class of the drift exit, code 1). NOT
# exit 4: this check RAN and FOUND drift; exit 4 is for a critical that couldn't run.
if command -v ffhc_partial_upgrade_findings >/dev/null 2>&1; then
  while IFS= read -r pu; do
    [ -z "$pu" ] && continue
    PARTIAL_UPGRADE_FINDINGS+=("$pu")
    record_drift "partial_upgrade" "PARTIAL_UPGRADE — $pu"
  done < <(ffhc_partial_upgrade_findings 2>/dev/null)
fi

###############################################################################
# Section 2 — Upstream comparison (.fusebase-flow-source/)
###############################################################################

if [ "$OPT_NO_UPSTREAM" -eq 1 ]; then
  # --no-upstream / --fast: upstream is optional, so skipping it is a NOTE only —
  # it never becomes UNVERIFIED and never blocks exit 0 (H3/H4).
  UPSTREAM_NOTES+=("upstream comparison skipped (--no-upstream/--fast); local verdict only.")
elif [ -d "$SOURCE_CLONE/.git" ]; then
  cd "$SOURCE_CLONE"

  IS_SHALLOW=$(git rev-parse --is-shallow-repository 2>/dev/null || echo "true")
  # OPTIONAL network op — bounded so a network-impaired host can't hang. A
  # timeout/skip is a NOTE ONLY (upstream not verified); it must NOT become
  # UNVERIFIED and must NOT force exit 4 (upstream is optional — H4/AC1).
  # GIT_TERMINAL_PROMPT=0 + low-speed config make the fetch fail fast rather than
  # block on a credential prompt or a stalled connection.
  FETCH_TIMED_OUT=0
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    GIT_TERMINAL_PROMPT=0 run_with_timeout "$FFHC_FETCH_TIMEOUT" \
      git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime="$FFHC_FETCH_TIMEOUT" \
      fetch origin --tags >/dev/null 2>&1
    ffhc_timed_out "$?" && FETCH_TIMED_OUT=1
  elif [ "$FFHC_ALLOW_UNBOUNDED" = "1" ]; then
    GIT_TERMINAL_PROMPT=0 git fetch origin --tags >/dev/null 2>&1 || true
  else
    FETCH_TIMED_OUT=1   # no timeout binary: skip the unbounded network op (treat as not-verified)
  fi
  if [ "$FETCH_TIMED_OUT" -eq 1 ]; then
    UPSTREAM_NOTES+=("upstream not verified (fetch timed out or skipped); comparison below uses whatever the local clone already had.")
  fi
  LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")
  REMOTE_HEAD=$(git rev-parse origin/main 2>/dev/null || echo "")
  UPSTREAM_VERSION=$(MSYS_NO_PATHCONV=1 git show origin/main:VERSION 2>/dev/null | tr -d '\n' || echo "?")
  SRC_VER=$(tr -d '\n\r' < VERSION 2>/dev/null || echo "?")

  if [ "$IS_SHALLOW" = "true" ] || [ -z "$REMOTE_HEAD" ]; then
    # F4: a `--depth 1` / `--branch <tag>` staging clone (the bootstrap default) has
    # no resolvable origin/main and can't traverse history, so any "behind by N" is
    # bogus. Report unavailable instead of a spurious "upstream NEWER … behind by ?".
    UPSTREAM_NOTES+=("upstream comparison unavailable (shallow/tag staging clone — no resolvable origin/main). Staged source VERSION: $SRC_VER. For a precise comparison: cd $SOURCE_CLONE && git fetch --unshallow origin main, or re-clone without --depth.")
  elif [ -z "$LOCAL_HEAD" ]; then
    UPSTREAM_NOTES+=("upstream fetch failed; cannot compare versions")
  elif [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
    UPSTREAM_NOTES+=("upstream in sync: local commit = origin/main = $LOCAL_HEAD ($UPSTREAM_VERSION)")
  else
    BEHIND=$(git rev-list --count "$LOCAL_HEAD..origin/main" 2>/dev/null || echo "")
    if [ -z "$BEHIND" ] || [ "$BEHIND" = "?" ]; then
      UPSTREAM_NOTES+=("upstream differs from local but the commit distance is unavailable (shallow history). local ${LOCAL_HEAD:0:7} ($LOCAL_VERSION) vs origin/main ${REMOTE_HEAD:0:7} ($UPSTREAM_VERSION).")
    else
      UPSTREAM_NOTES+=("upstream NEWER: local at ${LOCAL_HEAD:0:7} ($LOCAL_VERSION), origin/main at ${REMOTE_HEAD:0:7} ($UPSTREAM_VERSION); local behind by $BEHIND commits")
      UPSTREAM_NOTES+=("recent upstream commits:")
      while IFS= read -r line; do UPSTREAM_NOTES+=("  $line"); done < <(git log --oneline "$LOCAL_HEAD..origin/main" 2>/dev/null | head -5)
    fi
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
UNVERIFIED_COUNT="${#LOCAL_UNVERIFIED[@]}"
DEFERRED_COUNT="${#LOCAL_DEFERRED[@]}"
CLI_LAYER_DRIFT_COUNT="${#CLI_LAYER_DRIFT[@]}"
SHARED_MERGE_DRIFT_COUNT="${#SHARED_MERGE_DRIFT[@]}"

# Count drift items that are explainable by an active approval artifact
# (existing v2 hook-test attribution path)
ARTIFACT_DRIFT_COUNT=0
if [ "$DRIFT_COUNT" -gt 0 ]; then
  ARTIFACT_DRIFT_COUNT=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "active approval artifact" || true)
fi

# U7: count drift items that are stale-derived-fact (PARTIAL_UPGRADE) findings, and
# whether they account for ALL of LOCAL_DRIFT. When they do (and there's no
# CLI/shared-layer drift and no breakage), the verdict is named PARTIAL_UPGRADE —
# a sub-class of the drift exit (1), so the v3.24.0 exit contract is unchanged.
PARTIAL_UPGRADE_COUNT="${#PARTIAL_UPGRADE_FINDINGS[@]}"
PARTIAL_UPGRADE_DRIFT_COUNT=0
if [ "$DRIFT_COUNT" -gt 0 ]; then
  PARTIAL_UPGRADE_DRIFT_COUNT=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "^PARTIAL_UPGRADE — " || true)
fi

# Verdict precedence (LOCKED contract / H4): BROKEN > real drift > EXCEPTION
# (only-deferred) > PARTIAL_UNVERIFIED > HEALTHY. HEALTHY requires that EVERY
# critical check ran clean — UNVERIFIED_COUNT must be 0 — so a timed-out/skipped
# critical can NEVER read HEALTHY/0 (the false-HEALTHY blocker). Real drift is a
# concrete finding (exit 1) and still outranks UNVERIFIED; the PARTIAL_UNVERIFIED
# branch fires only when nothing else did. Upstream is optional and is never
# recorded in LOCAL_UNVERIFIED, so it cannot force exit 4.
if [ "$DRIFT_COUNT" -eq 0 ] && [ "$BROKEN_COUNT" -eq 0 ] && [ "$UNVERIFIED_COUNT" -eq 0 ] && [ "$DEFERRED_COUNT" -eq 0 ] && [ "$CLI_LAYER_DRIFT_COUNT" -eq 0 ] && [ "$SHARED_MERGE_DRIFT_COUNT" -eq 0 ]; then
  DRIFT_SIGNATURE="HEALTHY"
elif [ "$BROKEN_COUNT" -gt 0 ]; then
  # Genuine breakage trumps everything (including deferrals — operator can't defer real breakage)
  DRIFT_SIGNATURE="BROKEN"
elif [ "$PARTIAL_UPGRADE_DRIFT_COUNT" -gt 0 ] && [ "$PARTIAL_UPGRADE_DRIFT_COUNT" -eq "$DRIFT_COUNT" ] \
     && [ "$CLI_LAYER_DRIFT_COUNT" -eq 0 ] && [ "$SHARED_MERGE_DRIFT_COUNT" -eq 0 ]; then
  # U7: stale derived facts (version/FR/plugin vs live strings) account for ALL real
  # drift, with no CLI/shared-layer drift or breakage — an interrupted/partial upgrade.
  # Named so the operator gets the precise repair command. Drift class => exit 1
  # (NOT exit 4 — the check ran and FOUND the mismatch).
  DRIFT_SIGNATURE="PARTIAL_UPGRADE"
elif [ "$DRIFT_COUNT" -eq 0 ] && [ "$CLI_LAYER_DRIFT_COUNT" -eq 0 ] && [ "$SHARED_MERGE_DRIFT_COUNT" -eq 0 ] && [ "$DEFERRED_COUNT" -gt 0 ]; then
  # Only deferred items remain (no real drift, no breakage). v2.4.0+: this is
  # the deferral artifact mechanism working as designed.
  DRIFT_SIGNATURE="EXCEPTION_IN_EFFECT"
elif [ "$CLI_LAYER_DRIFT_COUNT" -gt 0 ]; then
  DRIFT_SIGNATURE="CLI_LAYER_DRIFT"
elif [ "$SHARED_MERGE_DRIFT_COUNT" -gt 0 ]; then
  DRIFT_SIGNATURE="SHARED_MERGE_DRIFT"
elif [ "$ARTIFACT_DRIFT_COUNT" -eq "$DRIFT_COUNT" ] && [ "$ARTIFACT_DRIFT_COUNT" -gt 0 ]; then
  # Every drift item is attributable to an active operator approval artifact —
  # this is the v2 hook-test artifact mechanism working as designed, not real drift.
  DRIFT_SIGNATURE="EXCEPTION_IN_EFFECT"
elif [ "$DRIFT_COUNT" -eq 0 ] && [ "$UNVERIFIED_COUNT" -gt 0 ]; then
  # No drift/breakage/exception, but a CRITICAL check did not run — cannot claim
  # full health. New in engine v3.x (H4): partial, unverified — exit 4, never 0.
  DRIFT_SIGNATURE="PARTIAL_UNVERIFIED"
else
  # settings.json reduced is the core `fusebase update` aftermath signature.
  # AGENTS.md may be missing on legacy/plain-overlay installs, or still present
  # after recovery has installed the CLI-preserved CUSTOM:SKILL wrapper.
  AGENTS_MISSING=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "AGENTS.md overlay block: MISSING" || true)
  AGENTS_PRESENT=$(printf '%s\n' "${LOCAL_OK[@]}" | grep -c "AGENTS.md overlay block: present" || true)
  SETTINGS_REDUCED=$(printf '%s\n' "${LOCAL_DRIFT[@]}" | grep -c "settings.json: only" || true)

  if [ "$SETTINGS_REDUCED" -gt 0 ] && { [ "$AGENTS_MISSING" -gt 0 ] || [ "$AGENTS_PRESENT" -gt 0 ]; }; then
    DRIFT_SIGNATURE="SHARED_MERGE_DRIFT"
  else
    DRIFT_SIGNATURE="FLOW_LAYER_DRIFT"
  fi
fi

###############################################################################
# Section 4 — Recommendations
###############################################################################

case "$DRIFT_SIGNATURE" in
  HEALTHY)
    RECOMMENDATIONS+=("No action required. Fusebase Flow overlay is intact.") ;;
  PARTIAL_UPGRADE)
    RECOMMENDATIONS+=("PARTIAL UPGRADE — VERSION/content advanced but live attestation strings are STALE (an interrupted upgrade, or an adapter with no overlay-refresh path). The stale-fact items are listed above as 'PARTIAL_UPGRADE — …'.")
    RECOMMENDATIONS+=("Repair (re-syncs the derived strings + re-applies adapter overlays):")
    RECOMMENDATIONS+=("  bash hooks/local/sync-version-strings.sh")
    RECOMMENDATIONS+=("  bash hooks/local/post-fusebase-update.sh --refresh-overlays")
    RECOMMENDATIONS+=("Then re-run this health check (expect HEALTHY). If a re-run still reports the same surface, that adapter has no overlay-refresh path yet (e.g. GEMINI.md before the U6 follow-up) — sync-version-strings now covers it (U5).") ;;
  EXCEPTION_IN_EFFECT)
    if [ "${#LOCAL_DEFERRED[@]}" -gt 0 ]; then
      RECOMMENDATIONS+=("All non-OK items are operator-authored deferrals (active health_check_deferral-*.json artifact(s) in state/approvals/). This is engine v2.4.0+ acknowledging that the install brief or operator deliberately omitted parts of the canonical Fusebase Flow setup.")
      RECOMMENDATIONS+=("Recovery script CAN fix the underlying state if you decide to revisit any deferral — the script is additive + idempotent. Run: bash hooks/local/post-fusebase-update.sh")
      RECOMMENDATIONS+=("To clear the deferral artifact(s) themselves: delete the listed artifact file(s) or wait for their expires_at to pass.")
    else
      RECOMMENDATIONS+=("All drift is attributable to active approval artifact(s) in state/approvals/. This is the protected-paths exception mechanism working as designed.")
      RECOMMENDATIONS+=("Recovery script will NOT fix this — it doesn't touch state/approvals/.")
      RECOMMENDATIONS+=("To clear: when the protected work is done, delete the listed artifact(s) or wait for their expires_at to pass. Then re-run this health check.")
    fi ;;
  CLI_LAYER_DRIFT)
    RECOMMENDATIONS+=("CLI-owned agent assets are missing or structurally damaged.")
    RECOMMENDATIONS+=("Run the current FuseBase CLI refresh/update for this project first so the CLI restores its own files.")
    RECOMMENDATIONS+=("After CLI refresh, run: bash hooks/local/post-fusebase-update.sh") ;;
  SHARED_MERGE_DRIFT)
    RECOMMENDATIONS+=("Shared CLI/Flow files are missing Flow overlay or merge additions.")
    RECOMMENDATIONS+=("Run: bash hooks/local/post-fusebase-update.sh")
    RECOMMENDATIONS+=("The script restores Flow overlay blocks, Flow lifecycle settings, Flow skill/agent mirrors, and does not patch CLI hook helper files.") ;;
  FLOW_LAYER_DRIFT)
    RECOMMENDATIONS+=("Flow-owned overlay assets are missing or drifted.")
    RECOMMENDATIONS+=("Run: bash hooks/local/post-fusebase-update.sh")
    RECOMMENDATIONS+=("If CLI-owned assets are also damaged, refresh the current FuseBase CLI first, then rerun Flow recovery.") ;;
  BROKEN)
    RECOMMENDATIONS+=("Genuine failure detected (NOT attributable to an active approval artifact).")
    RECOMMENDATIONS+=("Inspect the LOCAL_BROKEN items above; address each manually.")
    RECOMMENDATIONS+=("After fixes, re-run this health check.") ;;
  PARTIAL_UNVERIFIED)
    RECOMMENDATIONS+=("PARTIAL — not a full health verdict. One or more CRITICAL checks did not run (timed out, skipped, or no timeout binary available); see the 'unverified' items above.")
    RECOMMENDATIONS+=("This is NOT a failure and NOT full health. Exit code 4. Nothing that DID run proved drift or breakage.")
    # WS4 DX: name the exact knob + current effective value (copy-ready re-run), + platform.
    if ffhc_is_msys; then FFHC_PLATFORM_NOTE="MSYS/Git-Bash (higher defaults auto-applied)"; else FFHC_PLATFORM_NOTE="POSIX"; fi
    RECOMMENDATIONS+=("Current effective timeout budgets ($FFHC_PLATFORM_NOTE): FFHC_PREFLIGHT_TIMEOUT=${FFHC_PREFLIGHT_TIMEOUT}s  FFHC_TESTS_TIMEOUT=${FFHC_TESTS_TIMEOUT}s  FFHC_FETCH_TIMEOUT=${FFHC_FETCH_TIMEOUT}s  FFHC_CONFLICT_TIMEOUT=${FFHC_CONFLICT_TIMEOUT}s. Raise the one named in the unverified item above (e.g. FFHC_TESTS_TIMEOUT=240) and re-run.")
    RECOMMENDATIONS+=("To get a full verdict: re-run on a host with more time/CPU, raise the relevant FFHC_*_TIMEOUT env knob (values above), or run the named check directly. If a timeout binary is missing, install coreutils (provides 'timeout'/'gtimeout') or opt into unbounded runs with FFHC_ALLOW_UNBOUNDED=1.") ;;
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
echo "Local state ($((${#LOCAL_OK[@]} + ${#LOCAL_DRIFT[@]} + ${#LOCAL_BROKEN[@]} + ${#LOCAL_UNVERIFIED[@]} + ${#LOCAL_DEFERRED[@]} + ${#CLI_LAYER_DRIFT[@]} + ${#SHARED_MERGE_DRIFT[@]})) checks):"
for x in "${LOCAL_OK[@]}";    do echo "  ✓ $x"; done
for x in "${LOCAL_DRIFT[@]}"; do echo "  ✗ $x"; done
for x in "${LOCAL_BROKEN[@]}";do echo "  ⚠ $x"; done
for x in "${LOCAL_UNVERIFIED[@]}"; do echo "  ? $x"; done
for x in "${LOCAL_DEFERRED[@]}"; do echo "  ⊘ $x"; done
echo ""

if [ "${#LOCAL_UNVERIFIED[@]}" -gt 0 ]; then
  echo "Unverified critical checks (${#LOCAL_UNVERIFIED[@]} — could not run; engine v3.x+):"
  echo "  Each ? above is a CRITICAL check that did not complete (timed out,"
  echo "  skipped, or no timeout binary). These items would make the verdict"
  echo "  PARTIAL_UNVERIFIED (exit 4) — NOT full health and NOT a failure —"
  echo "  unless a higher-priority finding (BROKEN/DRIFT/EXCEPTION) takes"
  echo "  precedence (see 'Verdict:' below for the final result). Re-run with"
  echo "  more time/CPU, raise the relevant FFHC_*_TIMEOUT knob, or run the"
  echo "  named check directly."
  echo ""
fi

if [ "${#LOCAL_DEFERRED[@]}" -gt 0 ]; then
  echo "Deferred checks (${#LOCAL_DEFERRED[@]} — operator-authored exceptions; engine v2.4.0+):"
  echo "  Each ⊘ above is reclassified from drift to deferred via a"
  echo "  state/approvals/health_check_deferral-*.json artifact. These items"
  echo "  count toward EXCEPTION_IN_EFFECT, NOT layer drift or BROKEN. Run the"
  echo "  recovery script later if/when you want to revisit any deferral —"
  echo "  the script is additive + idempotent."
  echo ""
fi

if [ "${#ACTIVE_ARTIFACTS[@]}" -gt 0 ]; then
  echo "Active approval artifacts (${#ACTIVE_ARTIFACTS[@]}):"
  for x in "${ARTIFACT_NOTES[@]}"; do echo "  • $x"; done
  echo ""
fi

echo "Upstream comparison:"
for x in "${UPSTREAM_NOTES[@]}"; do echo "  $x"; done
echo ""

if [ "$OPT_FAST" -eq 1 ]; then
  echo "fast mode — not a full health verdict (hook-layer-integrity critical skipped; exit 4)."
  echo ""
fi

if [ "${#DEEP_RUN_NOTES[@]}" -gt 0 ]; then
  echo "Deep hook-test run (--run-hook-tests; optional, verdict-neutral):"
  for x in "${DEEP_RUN_NOTES[@]}"; do echo "  • $x"; done
  echo ""
fi

echo "Verdict: $DRIFT_SIGNATURE"
echo ""

echo "Recommendations:"
for x in "${RECOMMENDATIONS[@]}"; do echo "  • $x"; done
echo ""

echo "============================================================"

# Exit codes (LOCKED contract). PARTIAL_UNVERIFIED must NEVER fall through to a
# 0; it is its own code 4 so callers can tell "partial/unverified" apart from
# both full health (0) and drift/breakage (1/2). U7: PARTIAL_UPGRADE is a named
# drift sub-class -> exit 1 (NOT 4 — exit 4 is reserved for a critical that could
# not RUN; PARTIAL_UPGRADE means the check ran and FOUND stale derived facts).
case "$DRIFT_SIGNATURE" in
  HEALTHY)             exit 0 ;;
  EXCEPTION_IN_EFFECT) exit 3 ;;
  BROKEN)              exit 2 ;;
  PARTIAL_UNVERIFIED)  exit 4 ;;
  PARTIAL_UPGRADE)     exit 1 ;;
  *)                   exit 1 ;;
esac
