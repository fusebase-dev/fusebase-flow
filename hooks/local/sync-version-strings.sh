#!/usr/bin/env bash
# Fusebase Flow — sync-version-strings.sh
#
# PURPOSE (F7):
#   Embedded self-attestation / banner strings ("Fusebase Flow vX.Y.Z") drift
#   from the VERSION file whenever a patch bumps VERSION but not the prose.
#   This script derives the version from VERSION and rewrites those embedded
#   strings in the non-historical surfaces, so VERSION is the single source of
#   truth. Called by upgrade.sh; also runnable standalone.
#
# What it rewrites (self-attestation + "This repo runs" lines only):
#   - AGENTS.md, CLAUDE.md, GEMINI.md
#   - hooks/local/fusebase-flow-overlays/agents-md-overlay.md
#   - hooks/local/fusebase-flow-overlays/claude-md-overlay.md
#
# What it NEVER touches:
#   - CHANGELOG.md, docs/release-notes/**, docs/handoff/**, docs/specs/**
#     (dated historical records — rewriting would falsify history)
#
# Usage:
#   bash hooks/local/sync-version-strings.sh            # apply
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
    --help|-h) sed -n '2,27p' "$0"; exit 0 ;;
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

TARGETS=(
  "AGENTS.md"
  "CLAUDE.md"
  "GEMINI.md"
  "hooks/local/fusebase-flow-overlays/agents-md-overlay.md"
  "hooks/local/fusebase-flow-overlays/claude-md-overlay.md"
)

CHANGED=()
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  # Rewrite "Fusebase Flow vX.Y.Z" → "Fusebase Flow v<VER>" only where it directly
  # precedes the attestation/banner context. The pattern is specific: the literal
  # "Fusebase Flow v" followed by a semver. Dated files are excluded by not being
  # in TARGETS, so a blanket per-file replace of this exact pattern is safe here.
  before="$(cat "$f")"
  after="$(printf '%s' "$before" | sed -E "s/Fusebase Flow v[0-9]+\.[0-9]+\.[0-9]+/Fusebase Flow v${VER}/g")"
  if [ "$before" != "$after" ]; then
    CHANGED+=("$f")
    if [ "$DRY_RUN" -eq 0 ]; then
      printf '%s' "$after" > "$f"
    fi
  fi
done

if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "[sync-version-strings] All embedded version strings already match VERSION ($VER)."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[sync-version-strings] (dry-run) would update embedded version → v$VER in:"
else
  echo "[sync-version-strings] updated embedded version → v$VER in:"
fi
for c in "${CHANGED[@]}"; do echo "  • $c"; done
exit 0
