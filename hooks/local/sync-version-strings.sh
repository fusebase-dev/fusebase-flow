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
#   Canonical:         agents/**/AGENT.md, flow-skills/**/SKILL.md, workflows/*.md,
#                      templates/*.md, hooks/local/fusebase-flow-overlays/*.md,
#                      docs/*.md (top-level framework docs only)
#   It then RE-MIRRORS (mirror-agents.sh + mirror-skills.sh) so the generated
#   provider copies under .claude/ .agents/ .codex/ — and their audit manifests —
#   reflect the canonical edits. (Those dirs are generated; never edited directly.)
#
# What it NEVER touches:
#   - Dated history: CHANGELOG.md, docs/release-notes/**, docs/handoff/** (archive),
#     docs/tmp/handoff/** (formal dated relays, v3.13.0+), docs/specs/**
#     (excluded from the scan).
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

# U3: version is not the only derived attestation fact. The live self-attestation
# also names the FR-range ("FR-01 through FR-NN" / "FR-01..FR-NN") and some
# adapters/overlays name the skill count ("(NN canonical skills total)"). All three
# are derived from the framework and must match on every upgrade — otherwise an
# adapter without an overlay-refresh path (e.g. GEMINI.md) ends up self-attesting
# "vX.Y.Z … FR-01 through FR-(N-1)". Derive them here so one tool keeps all three
# consistent.
FR_MAX="$(grep -oE 'FR-[0-9]+' FLOW_RULES.md 2>/dev/null | sed 's/FR-//' | sort -n | tail -1)"
if [ -n "$FR_MAX" ]; then
  FR_HI="$(printf 'FR-%02d' "$FR_MAX")"     # e.g. FR-21
else
  FR_HI=""
fi
# Canonical skills: flow-skills/ (v3.9.0+); legacy root skills/ as fallback.
SKILLS_CANON="flow-skills"; [ -d "$SKILLS_CANON" ] || SKILLS_CANON="skills"
SKILL_COUNT="$(find "$SKILLS_CANON" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

# Discover scan targets: canonical sources + standalone adapters (*.md / *.mdc),
# pruning dated history, generated mirror dirs, and non-source trees. Generated
# mirror dirs (.claude .agents .codex) are intentionally excluded — they are
# refreshed by the re-mirror step so canonical stays the single source of truth.
# Tripwire: -path is exact (no implicit depth) — nested per-app docs
# (docs/<app>/handoff, docs/<app>/specs …) need the ./docs/*/ variant too.
mapfile -t CANDIDATES < <(
  find . \
    \( -type d \( \
        -name '.git' -o -name '.fusebase-flow-source' -o -name 'node_modules' \
        -o -name '.claude' -o -name '.agents' -o -name '.codex' \
        -o -path './internal' \
        -o -path './docs/release-notes'   -o -path './docs/*/release-notes' \
        -o -path './docs/handoff'         -o -path './docs/*/handoff' \
        -o -path './docs/tmp/handoff' \
        -o -path './docs/specs'           -o -path './docs/*/specs' \
        -o -path './docs/fusebase-health' -o -path './docs/*/fusebase-health' \
      \) -prune \) -o \
    \( -type f \( -name '*.md' -o -name '*.mdc' \) \
        ! -name 'CHANGELOG.md' \
        ! -name '*.pre-upgrade-*' ! -name '*.pre-refresh-*' ! -name '*.pre-flow-merge' \
        -print \)
)

# Context-anchored substitutions — live attestation + banner + FR-range + skill
# count only. Never a blanket replace (historical/provenance refs must survive).
# Build the sed program dynamically so FR-range / skill-count subs are added only
# when their derived value is known.
SED_ARGS=(
  -e "s/(under Fusebase Flow v)[0-9]+\.[0-9]+\.[0-9]+/\1${VER}/g"
  -e "s/(runs \*\*Fusebase Flow v)[0-9]+\.[0-9]+\.[0-9]+/\1${VER}/g"
)
if [ -n "$FR_HI" ]; then
  SED_ARGS+=( -e "s/FR-01 through FR-[0-9]+/FR-01 through ${FR_HI}/g" )
  SED_ARGS+=( -e "s/FR-01\.\.FR-[0-9]+/FR-01..${FR_HI}/g" )
fi
if [ -n "$SKILL_COUNT" ] && [ "$SKILL_COUNT" -gt 0 ] 2>/dev/null; then
  # Only the parenthesized "(NN canonical … skills total)" form (overlays/adapters);
  # leaves README's bold/heading counts to release-time edits.
  SED_ARGS+=( -e "s/\(([0-9]+) canonical/(${SKILL_COUNT} canonical/g" )
fi

CHANGED=()
TOUCHED_CANONICAL=0
for f in "${CANDIDATES[@]}"; do
  [ -f "$f" ] || continue
  # U8: strip null bytes so command substitution doesn't warn on a stray-NUL file.
  before="$(tr -d '\0' < "$f")"
  after="$(printf '%s' "$before" | sed -E "${SED_ARGS[@]}")"
  if [ "$before" != "$after" ]; then
    CHANGED+=("$f")
    case "$f" in
      ./agents/*|./flow-skills/*|./skills/*) TOUCHED_CANONICAL=1 ;;
    esac
    if [ "$DRY_RUN" -eq 0 ]; then
      printf '%s' "$after" > "$f"
    fi
  fi
done

DERIVED="version v$VER${FR_HI:+, FR-01..$FR_HI}${SKILL_COUNT:+, $SKILL_COUNT skills}"

if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "[sync-version-strings] All live derived strings already match the repo ($DERIVED)."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[sync-version-strings] (dry-run) would sync derived strings ($DERIVED) in:"
  for c in "${CHANGED[@]}"; do echo "  • $c"; done
  case " ${CHANGED[*]} " in
    *" ./agents/"*|*" ./flow-skills/"*|*" ./skills/"*) echo "  • (would re-mirror agents + skills to refresh provider copies)";;
  esac
  exit 0
fi

echo "[sync-version-strings] synced derived strings ($DERIVED) in:"
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
