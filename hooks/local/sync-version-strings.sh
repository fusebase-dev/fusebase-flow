#!/usr/bin/env bash
# Fusebase Flow — sync-version-strings.sh
#
# PURPOSE (F7):
#   The live self-attestation / banner strings ("... under Fusebase Flow vX.Y.Z",
#   "This repo runs **Fusebase Flow vX.Y.Z**") drift from the VERSION file whenever
#   a release bumps VERSION but not the prose. A fresh agent invoked as Product
#   Owner / AI Developer reads the agent definition + adapters, so a stale string
#   there makes it self-attest the wrong version. This script derives the version
#   from VERSION and rewrites ONLY those live strings, so VERSION is the single
#   source of truth.
#
# CONTEXT-ANCHORED (critical): it rewrites only the two live phrasings —
#     "under Fusebase Flow v<semver>"
#     "runs **Fusebase Flow v<semver>**"
#   It deliberately does NOT do a blanket `Fusebase Flow v<semver>` replace,
#   because many files carry HISTORICAL/provenance refs that must be preserved:
#     "Shipped as part of Fusebase Flow v2.3.0+"   (upgrade-engine.sh)
#     "Available since: Fusebase Flow v2.4.0"       (health-check-deferrals.md)
#     "DEPRECATED (Fusebase Flow v3.2.0 / B5)"      (deprecated stop hooks)
#     "v2 (Fusebase Flow v2.7.0+)"                  (approval-policy.yml)
#   Rewriting those would falsify history.
#
# What it scans (canonical sources + standalone adapters):
#   Root adapters:     AGENTS.md, CLAUDE.md, GEMINI.md, FLOW_RULES.md
#   Other adapters:    .github/copilot-instructions.md, .cursor/rules/*.mdc
#   Canonical:         agents/**/AGENT.md, skills/**/SKILL.md, workflows/*.md,
#                      templates/*.md, hooks/local/fusebase-flow-overlays/*.md,
#                      docs/*.md (top-level framework docs only)
#   It then RE-MIRRORS (mirror-agents.sh + mirror-skills.sh) so the generated
#   provider copies under .claude/ .agents/ .codex/ — and their audit manifests —
#   reflect the canonical edits. (Those dirs are generated; never edited directly.)
#
# What it NEVER touches:
#   - Dated history: CHANGELOG.md, docs/release-notes/**, docs/handoff/**,
#     docs/specs/** (excluded from the scan).
#   - Generated mirror dirs directly (.claude/ .agents/ .codex/ — refreshed via
#     re-mirror so a single canonical source of truth is preserved).
#   - .fusebase-flow-source/, internal/, node_modules/, .git/, *.pre-* backups.
#
# Usage:
#   bash hooks/local/sync-version-strings.sh            # apply (+ re-mirror)
#   bash hooks/local/sync-version-strings.sh --dry-run  # show what would change
#
# Exit: 0 success (or nothing to do); 1 error; 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h) sed -n '2,52p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -f VERSION ]; then
  echo "[sync-version-strings] FATAL: VERSION file missing." >&2
  exit 1
fi
VER="$(tr -d '\n\r' < VERSION)"
if [ -z "$VER" ]; then
  echo "[sync-version-strings] FATAL: VERSION is empty." >&2
  exit 1
fi

# Discover scan targets: canonical sources + standalone adapters (*.md / *.mdc),
# pruning dated history, generated mirror dirs, and non-source trees. Generated
# mirror dirs (.claude .agents .codex) are intentionally excluded — they are
# refreshed by the re-mirror step so canonical stays the single source of truth.
mapfile -t CANDIDATES < <(
  find . \
    \( -type d \( \
        -name '.git' -o -name '.fusebase-flow-source' -o -name 'node_modules' \
        -o -name '.claude' -o -name '.agents' -o -name '.codex' \
        -o -path './internal' \
        -o -path './docs/release-notes' -o -path './docs/handoff' -o -path './docs/specs' \
      \) -prune \) -o \
    \( -type f \( -name '*.md' -o -name '*.mdc' \) \
        ! -name 'CHANGELOG.md' \
        ! -name '*.pre-upgrade-*' ! -name '*.pre-refresh-*' ! -name '*.pre-flow-merge' \
        -print \)
)

# Two context-anchored substitutions — live attestation + live banner only.
CHANGED=()
TOUCHED_CANONICAL=0
for f in "${CANDIDATES[@]}"; do
  [ -f "$f" ] || continue
  before="$(cat "$f")"
  after="$(printf '%s' "$before" | sed -E \
    -e "s/(under Fusebase Flow v)[0-9]+\.[0-9]+\.[0-9]+/\1${VER}/g" \
    -e "s/(runs \*\*Fusebase Flow v)[0-9]+\.[0-9]+\.[0-9]+/\1${VER}/g")"
  if [ "$before" != "$after" ]; then
    CHANGED+=("$f")
    case "$f" in
      ./agents/*|./skills/*) TOUCHED_CANONICAL=1 ;;
    esac
    if [ "$DRY_RUN" -eq 0 ]; then
      printf '%s' "$after" > "$f"
    fi
  fi
done

if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "[sync-version-strings] All live version strings already match VERSION ($VER)."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[sync-version-strings] (dry-run) would update live version → v$VER in:"
  for c in "${CHANGED[@]}"; do echo "  • $c"; done
  case " ${CHANGED[*]} " in
    *" ./agents/"*|*" ./skills/"*) echo "  • (would re-mirror agents + skills to refresh provider copies)";;
  esac
  exit 0
fi

echo "[sync-version-strings] updated live version → v$VER in:"
for c in "${CHANGED[@]}"; do echo "  • $c"; done

# Propagate canonical agent/skill edits into the generated provider mirrors
# (and refresh their audit manifests). Re-mirroring is idempotent: if the edit
# only touched non-canonical adapters, this is skipped.
if [ "$TOUCHED_CANONICAL" -eq 1 ]; then
  [ -x hooks/local/mirror-agents.sh ] && bash hooks/local/mirror-agents.sh >/dev/null 2>&1 || true
  [ -x hooks/local/mirror-skills.sh ] && bash hooks/local/mirror-skills.sh >/dev/null 2>&1 || true
  echo "  • re-mirrored agents + skills (provider copies + manifests refreshed)"
fi
exit 0
