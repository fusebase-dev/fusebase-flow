#!/usr/bin/env bash
# Fusebase Flow — install-git-hooks
# Copies (NOT symlinks, for cross-platform portability) the git fallback hooks
# into .git/hooks/. Re-run after pulling Fusebase Flow updates (upgrade.sh and
# post-fusebase-update.sh call this so the FIXED pre-commit is live on upgrade).
#
# SAFE (re)install (WS1c): a Flow-managed hook (carrying the UNIQUE managed marker
# `fusebase-flow-managed-hook: v1`) is refreshed in place; a CUSTOM hook (no unique
# marker) is NEVER silently clobbered — it is backed up and left in place, and
# overwriting it requires the explicit --force opt-in. The marker is a token no
# hand-written custom hook carries, so a consumer's custom hook that merely mentions
# "Fusebase Flow" in a comment is treated as CUSTOM (preserved), not clobbered.

set -euo pipefail

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "[fusebase-flow] unknown argument: $arg (supported: --force)" >&2; exit 2 ;;
    esac
done

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/hooks/git"
DEST="$ROOT/.git/hooks"
FLOW_MARKER="fusebase-flow-managed-hook:"   # UNIQUE token in every Flow-managed hook header (WS1c/T11)

if [ ! -d "$SRC" ]; then
    echo "Source dir not found: $SRC" >&2
    exit 1
fi
if [ ! -d "$DEST" ]; then
    echo "Git hooks dir not found: $DEST (is this a git repo?)" >&2
    exit 1
fi

# is_flow_managed FILE: 0 (true) iff FILE carries the UNIQUE managed marker in its
# header (first ~5 lines) — i.e. it is a Flow-installed hook safe to refresh in place.
is_flow_managed() {
    [ -f "$1" ] && head -5 "$1" 2>/dev/null | grep -qF "$FLOW_MARKER"
}

skipped_custom=0
for hook in pre-commit commit-msg; do
    src_file="$SRC/$hook"
    dest_file="$DEST/$hook"
    [ -f "$src_file" ] || continue

    if [ -f "$dest_file" ] && ! is_flow_managed "$dest_file"; then
        # A pre-existing CUSTOM hook. Back it up; never silent-clobber.
        backup="$dest_file.pre-flow-$(date -u +%Y%m%dT%H%M%SZ)"
        cp "$dest_file" "$backup"
        if [ "$FORCE" -eq 1 ]; then
            cp "$src_file" "$dest_file"
            chmod +x "$dest_file"
            echo "[fusebase-flow] custom $hook backed up -> $backup, then overwritten (--force)"
        else
            skipped_custom=1
            echo "[fusebase-flow] WARNING: custom $hook detected at $dest_file — NOT overwritten." >&2
            echo "[fusebase-flow]   backup written: $backup" >&2
            echo "[fusebase-flow]   to install the Flow hook, re-run with --force (your custom hook stays in the backup)." >&2
        fi
        continue
    fi

    # Absent or already Flow-managed => safe to (re)install in place.
    cp "$src_file" "$dest_file"
    chmod +x "$dest_file"
    echo "[fusebase-flow] installed $hook -> $dest_file"
done

if [ "$skipped_custom" -eq 1 ]; then
    echo "[fusebase-flow] one or more custom hooks were preserved (not overwritten). Re-run with --force to replace them." >&2
fi

echo "[fusebase-flow] git hooks install complete. Test with: bash $SRC/../tests/run-tests.sh"
