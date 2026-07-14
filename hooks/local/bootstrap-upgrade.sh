#!/usr/bin/env bash
# Fusebase Flow — bootstrap-upgrade.sh  (U5: first-hop upgrade for pre-3.6.0 installs)
#
# PROVENANCE:
#   Shipped Fusebase Flow v3.8.0+. Lives at hooks/local/ — outside the FuseBase CLI
#   refresh manifest.
#
# PURPOSE:
#   The blessed in-place upgrade path is `upgrade.sh`, but it ships *inside* the
#   version you're trying to reach. A pre-3.6.0 "append-only overlay" install has
#   no upgrade.sh / sync-version-strings.sh / .fusebase-flow-source/. This script
#   is the one-shot first hop: it stages an upstream copy, copies the engine
#   scripts into hooks/local/, then runs upgrade.sh.
#
#   For an install that ALSO lacks this bootstrap script (truly old), copy-paste
#   the equivalent one-liner from the README "Upgrading an installed overlay"
#   section — it does the same clone + copy + run.
#
# What it does:
#   1. Ensure .fusebase-flow-source/ exists — clone upstream if absent (or reuse a
#      plain dir you already staged).
#   2. Copy the engine + recovery + mirror scripts from the source into hooks/local/
#      (upgrade.sh, upgrade-engine.sh, sync-version-strings.sh, post-fusebase-update.sh,
#      mirror-skills.sh, mirror-agents.sh, preflight.sh) + the overlay templates dir
#      + the engine's sourced lib dir hooks/local/lib/ (the new upgrade.sh sources
#      merge-module-size-baseline.sh from there; staging it BEFORE handoff is what
#      lets the v3.25.x baseline merge-preserve actually run on the adoption hop).
#   3. Hand off to upgrade.sh (passing through any flags, e.g. --dry-run / --auto-yes).
#
# What it does NOT do:
#   - Touch application code, .claude/settings.json, or CLI-owned assets.
#   - Delete anything (every copied target that already exists is backed up
#     .pre-bootstrap-<ts>).
#
# Usage:
#   bash hooks/local/bootstrap-upgrade.sh [--source <dir>] [--repo <url>] [--ref <branch>] [-- <upgrade.sh flags>]
# Examples:
#   bash hooks/local/bootstrap-upgrade.sh --dry-run
#   bash hooks/local/bootstrap-upgrade.sh -- --auto-yes
#   bash hooks/local/bootstrap-upgrade.sh --source ../fusebase-flow
#
# Exit: 0 success; 1 error; 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SOURCE_CLONE=".fusebase-flow-source"
REPO_URL="https://github.com/fusebase-dev/fusebase-flow.git"
REF="main"
SRC_OVERRIDE=""
PASSTHROUGH=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SRC_OVERRIDE="${2:-}"; shift 2 ;;
    --repo)   REPO_URL="${2:-}"; shift 2 ;;
    --ref)    REF="${2:-}"; shift 2 ;;
    --help|-h) sed -n '2,38p' "$0"; exit 0 ;;
    --) shift; PASSTHROUGH=("$@"); break ;;
    *) echo "[bootstrap-upgrade] Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y%m%dT%H%M%SZ)

# ---- Step 1: ensure a source copy ----
if [ -n "$SRC_OVERRIDE" ]; then
  if [ ! -d "$SRC_OVERRIDE" ]; then
    echo "[bootstrap-upgrade] FATAL: --source '$SRC_OVERRIDE' is not a directory." >&2
    exit 1
  fi
  SOURCE_CLONE="$SRC_OVERRIDE"
  echo "[bootstrap-upgrade] Using source: $SOURCE_CLONE"
elif [ -d "$SOURCE_CLONE" ]; then
  echo "[bootstrap-upgrade] Reusing existing $SOURCE_CLONE/"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] FATAL: git not found and no $SOURCE_CLONE/ present." >&2
    echo "                    Stage an upstream copy at $SOURCE_CLONE/ manually, then re-run." >&2
    exit 1
  fi
  echo "[bootstrap-upgrade] Cloning $REPO_URL ($REF) -> $SOURCE_CLONE/ ..."
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$SOURCE_CLONE"
fi

if [ ! -f "$SOURCE_CLONE/VERSION" ]; then
  echo "[bootstrap-upgrade] FATAL: $SOURCE_CLONE/VERSION missing — not a Fusebase Flow source tree." >&2
  exit 1
fi
echo "[bootstrap-upgrade] Source VERSION: $(tr -d '\n\r' < "$SOURCE_CLONE/VERSION")"

# Git-exclude the *.pre-*-<ts> backup snapshots we are about to drop, so a downstream
# `git add -A` (notably FuseBase CLI's `fusebase update` checkpoint) never stages them.
# upgrade.sh's hooks.pre-upgrade/policies.pre-upgrade snapshots carry the OLD secret-scan
# fixtures that HARD-BLOCK such a checkpoint; git-excluding ALL backup families (incl. these
# .pre-bootstrap ones) keeps a wholesale add clean (field escalation, v4.3.2). Local + idempotent.
ff_git_exclude_backups() {
  local ex line d
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null)" || return 1
  [ -n "$ex" ] || return 1
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
ff_git_exclude_backups || echo "[bootstrap-upgrade] WARN: could not update .git/info/exclude — backups may be stageable by a later 'git add -A' (delete or unstage before committing)." >&2

# ---- Step 2: copy the engine scripts in (with backups) ----
ENGINE_SCRIPTS=(
  "hooks/local/upgrade.sh"
  "hooks/local/upgrade-engine.sh"
  "hooks/local/sync-version-strings.sh"
  "hooks/local/post-fusebase-update.sh"
  "hooks/local/mirror-skills.sh"
  "hooks/local/mirror-agents.sh"
  "hooks/local/preflight.sh"
)
mkdir -p hooks/local
COPIED=0
for s in "${ENGINE_SCRIPTS[@]}"; do
  if [ -f "$SOURCE_CLONE/$s" ]; then
    if [ -f "$s" ] && ! diff -q "$SOURCE_CLONE/$s" "$s" >/dev/null 2>&1; then
      cp "$s" "$s.pre-bootstrap-$TS"
    fi
    mkdir -p "$(dirname "$s")"
    cp "$SOURCE_CLONE/$s" "$s"
    chmod +x "$s" 2>/dev/null || true
    COPIED=$((COPIED + 1))
  fi
done
# Overlay templates the engine needs (post-fusebase-update / refresh).
if [ -d "$SOURCE_CLONE/hooks/local/fusebase-flow-overlays" ]; then
  [ -d hooks/local/fusebase-flow-overlays ] && [ ! -e "hooks/local/fusebase-flow-overlays.pre-bootstrap-$TS" ] && cp -R hooks/local/fusebase-flow-overlays "hooks/local/fusebase-flow-overlays.pre-bootstrap-$TS"
  mkdir -p hooks/local/fusebase-flow-overlays
  cp -R "$SOURCE_CLONE/hooks/local/fusebase-flow-overlays/." hooks/local/fusebase-flow-overlays/
fi
# Engine-sourced lib dir (hooks/local/lib/). The new upgrade.sh sources its merge
# rule (merge-module-size-baseline.sh) from here; if it isn't staged before handoff,
# the merge function is undefined when Step 1a runs and the W2 baseline-clobber fix
# silently no-ops on the adoption hop. Stage the WHOLE dir (future libs too).
if [ -d "$SOURCE_CLONE/hooks/local/lib" ]; then
  [ -d hooks/local/lib ] && [ ! -e "hooks/local/lib.pre-bootstrap-$TS" ] && cp -R hooks/local/lib "hooks/local/lib.pre-bootstrap-$TS"
  mkdir -p hooks/local/lib
  cp -R "$SOURCE_CLONE/hooks/local/lib/." hooks/local/lib/
  chmod +x hooks/local/lib/*.sh 2>/dev/null || true
fi
echo "[bootstrap-upgrade] Staged $COPIED engine script(s) + hooks/local/lib/ into hooks/local/ (backups: .pre-bootstrap-$TS)."

if [ ! -x hooks/local/upgrade.sh ] && [ ! -f hooks/local/upgrade.sh ]; then
  echo "[bootstrap-upgrade] FATAL: upgrade.sh was not staged; cannot continue." >&2
  exit 1
fi

# ---- Step 3: hand off to upgrade.sh ----
echo "[bootstrap-upgrade] Handing off to upgrade.sh ${PASSTHROUGH[*]:-}"
echo ""
if [ "${#PASSTHROUGH[@]}" -gt 0 ]; then
  exec bash hooks/local/upgrade.sh "${PASSTHROUGH[@]}"
else
  exec bash hooks/local/upgrade.sh
fi
