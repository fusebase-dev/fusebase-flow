#!/usr/bin/env bash
# Fusebase Flow — upgrade-engine.sh
#
# PROVENANCE:
#   Shipped as part of Fusebase Flow v2.3.0+. Lives at hooks/local/ — outside the
#   Fusebase CLI's refresh manifest, so it survives `fusebase update`.
#
# PURPOSE:
#   Sync the operator-maintained engine + recovery scripts from .fusebase-flow-source/
#   into the project's local hooks/local/. Bumps the project's VERSION file to
#   match upstream. Use when you've pulled a new upstream version and want the
#   improvements (e.g. v2.2.1's duplicate-marker detection) in your local engine.
#
#   Why this script exists: mirror-skills.sh and mirror-agents.sh sync canonical
#   skills + agents from upstream into provider mirrors. They deliberately do
#   NOT touch hooks/local/*.sh because those are operator-maintained scripts
#   that may carry local customization. This script provides the explicit
#   opt-in path for operators who DO want to adopt new upstream engine versions.
#
# What it syncs (canonical → local):
#   - hooks/local/upgrade-engine.sh       (this script itself, so future runs are seamless)
#   - hooks/local/fusebase-flow-health-check.sh
#   - hooks/local/post-fusebase-update.sh
#   - VERSION                             (project's record of installed version)
#
# What it does NOT touch:
#   - hooks/local/fusebase-flow-overlays/  (operator-customizable overlay templates)
#   - flow-skills/, agents/                (use mirror-skills.sh / mirror-agents.sh)
#   - AGENTS.md, CLAUDE.md, .claude/*       (managed via post-fusebase-update.sh)
#
# Prerequisite:
#   .fusebase-flow-source/ must be present as a git clone of upstream and at the
#   version you want to adopt. Refresh it first with:
#     cd .fusebase-flow-source && git pull origin main
#
# Usage:
#   bash hooks/local/upgrade-engine.sh            # interactive: prints diff stats, prompts
#   bash hooks/local/upgrade-engine.sh --auto-yes # non-interactive
#   bash hooks/local/upgrade-engine.sh --dry-run  # show what would change without applying
#
# Exit codes:
#   0  success (or no changes needed)
#   1  upstream clone missing / file errors
#   2  unknown argument
#   3  operator declined (interactive mode only)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SOURCE_CLONE=".fusebase-flow-source"
AUTO_YES=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --auto-yes|-y) AUTO_YES=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h)
      sed -n '2,46p' "$0"
      exit 0 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 2 ;;
  esac
done

# F5: a git clone enables HEAD reporting, but a plain directory copy (the
# documented install end-state, which drops .git) is also accepted — fall back
# to VERSION-file comparison. Only a fully-missing source is fatal.
if [ ! -d "$SOURCE_CLONE" ]; then
  echo "[upgrade-engine] FATAL: $SOURCE_CLONE/ not found." >&2
  echo "                  Provide an upstream copy first:" >&2
  echo "                    git clone https://github.com/fusebase-dev/fusebase-flow.git $SOURCE_CLONE" >&2
  echo "                  Then re-run this script." >&2
  exit 1
fi

if [ -d "$SOURCE_CLONE/.git" ]; then
  SRC_HEAD=$(cd "$SOURCE_CLONE" && git rev-parse --short HEAD 2>/dev/null || echo "?")
else
  SRC_HEAD="(plain dir — no .git; HEAD/diff unavailable)"
  echo "[upgrade-engine] NOTE: $SOURCE_CLONE/ is a plain directory (no .git);"
  echo "                 comparing by file content + VERSION only."
fi
SRC_VERSION=$(cat "$SOURCE_CLONE/VERSION" 2>/dev/null | tr -d '\n')
LOCAL_VERSION=$(cat VERSION 2>/dev/null | tr -d '\n')

echo "[upgrade-engine] Source: $SOURCE_CLONE/"
echo "[upgrade-engine]   HEAD:    $SRC_HEAD"
echo "[upgrade-engine]   VERSION: $SRC_VERSION"
echo "[upgrade-engine] Local:"
echo "[upgrade-engine]   VERSION: $LOCAL_VERSION"
echo ""

# Helper to safely count diff lines under set -o pipefail.
#
# `|| true` swallows non-zero exit (set -o pipefail makes the pipe exit
# non-zero whenever diff finds differences, even though grep -c then
# succeeds). grep -c always emits the count to stdout, so `|| true`
# doesn't lose data — and avoids polluting stdout with a stray "0"
# appended after the real count (the v2.3.0 cosmetic display bug,
# fixed in v2.3.1).
count_diff_lines() {
  diff "$1" "$2" 2>/dev/null | grep -cE "^[<>]" 2>/dev/null || true
}

# Self-update detection (special case — handled outside main loop).
#
# Why: when the script overwrites itself via cp mid-execution, bash
# continues running from the old in-memory script but the file on
# disk is replaced. The old loop's APPLIED+=("$f") tracking became
# unreliable for the self-target on Windows + Git Bash (B1 in
# docs/fusebase-health/BACKLOG.md, fixed here in v2.3.2). Treating
# self-update as a special case before the main loop tracks it
# correctly + lets the apply-summary advise that NEW logic only
# kicks in on next run.
SELF_TARGET="hooks/local/upgrade-engine.sh"
SELF_SRC="$SOURCE_CLONE/$SELF_TARGET"
SELF_CHANGED=0
SELF_NEW=0
if [ -f "$SELF_SRC" ]; then
  if [ ! -f "$SELF_TARGET" ]; then
    SELF_NEW=1
  elif ! diff -q "$SELF_SRC" "$SELF_TARGET" >/dev/null 2>&1; then
    SELF_CHANGED=1
  fi
fi

# Files to sync (operator-maintained scripts that should match upstream version)
# upgrade-engine.sh is handled separately above.
FILES_TO_SYNC=(
  "hooks/local/fusebase-flow-health-check.sh"
  "hooks/local/post-fusebase-update.sh"
)

CHANGES=()
if [ "$SELF_NEW" -eq 1 ]; then
  CHANGES+=("$SELF_TARGET (NEW — not present locally) [self-update]")
elif [ "$SELF_CHANGED" -eq 1 ]; then
  diff_count=$(count_diff_lines "$SELF_SRC" "$SELF_TARGET")
  CHANGES+=("$SELF_TARGET ($diff_count line diffs) [self-update]")
fi
for f in "${FILES_TO_SYNC[@]}"; do
  src="$SOURCE_CLONE/$f"
  if [ ! -f "$src" ]; then
    echo "[upgrade-engine] WARNING: $src not present in upstream clone; skipping" >&2
    continue
  fi
  if [ ! -f "$f" ]; then
    CHANGES+=("$f (NEW — not present locally)")
  elif diff -q "$src" "$f" >/dev/null 2>&1; then
    : # byte-identical; skip
  else
    diff_count=$(count_diff_lines "$src" "$f")
    CHANGES+=("$f ($diff_count line diffs)")
  fi
done

# VERSION sync
VERSION_CHANGE=""
if [ "$SRC_VERSION" != "$LOCAL_VERSION" ]; then
  VERSION_CHANGE="VERSION: $LOCAL_VERSION -> $SRC_VERSION"
fi

if [ "${#CHANGES[@]}" -eq 0 ] && [ -z "$VERSION_CHANGE" ]; then
  echo "[upgrade-engine] Already up to date. Nothing to do."
  exit 0
fi

echo "[upgrade-engine] Pending changes:"
for c in "${CHANGES[@]}"; do echo "  • $c"; done
[ -n "$VERSION_CHANGE" ] && echo "  • $VERSION_CHANGE"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[upgrade-engine] (dry-run; no changes applied)"
  exit 0
fi

# Confirm
if [ "$AUTO_YES" -ne 1 ]; then
  printf "[upgrade-engine] Apply these changes? [y/N] "
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS]) ;;
    *)
      echo "[upgrade-engine] Aborted."
      exit 3 ;;
  esac
fi

# Apply
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
APPLIED=()

# Self-update first (special case — see SELF_CHANGED detection block above).
# Tracked in APPLIED separately because the script overwrites itself mid-execution
# and the loop body that adds to APPLIED isn't reliably reached for the self-target
# on Windows + Git Bash. Doing it here ensures the apply summary is accurate.
if [ "$SELF_NEW" -eq 1 ] || [ "$SELF_CHANGED" -eq 1 ]; then
  if [ "$SELF_CHANGED" -eq 1 ]; then
    cp "$SELF_TARGET" "$SELF_TARGET.pre-upgrade-$TIMESTAMP"
  fi
  cp "$SELF_SRC" "$SELF_TARGET"
  chmod +x "$SELF_TARGET"
  APPLIED+=("$SELF_TARGET (self-update; new logic active on next run)")
fi

for f in "${FILES_TO_SYNC[@]}"; do
  src="$SOURCE_CLONE/$f"
  if [ ! -f "$src" ]; then continue; fi
  if [ -f "$f" ] && diff -q "$src" "$f" >/dev/null 2>&1; then
    continue # byte-identical; skip
  fi
  if [ -f "$f" ]; then
    cp "$f" "$f.pre-upgrade-$TIMESTAMP"
  fi
  cp "$src" "$f"
  if [[ "$f" == *.sh ]]; then
    chmod +x "$f"
  fi
  APPLIED+=("$f")
done

if [ -n "$VERSION_CHANGE" ]; then
  cp VERSION "VERSION.pre-upgrade-$TIMESTAMP" 2>/dev/null || true
  echo "$SRC_VERSION" > VERSION
  APPLIED+=("VERSION ($LOCAL_VERSION -> $SRC_VERSION)")
fi

echo ""
echo "[upgrade-engine] Applied (${#APPLIED[@]}):"
for a in "${APPLIED[@]}"; do echo "  ✓ $a"; done
[ "$AUTO_YES" -ne 1 ] && echo ""
echo "[upgrade-engine] Backups written with suffix .pre-upgrade-$TIMESTAMP — remove once validated."
echo ""
echo "[upgrade-engine] Recommended next:"
echo "  bash hooks/local/fusebase-flow-health-check.sh    # confirm HEALTHY"
echo "  git diff                                          # review changes"
echo "  git add -A && git commit -m 'chore(flow): upgrade engine to v$SRC_VERSION'"
exit 0
