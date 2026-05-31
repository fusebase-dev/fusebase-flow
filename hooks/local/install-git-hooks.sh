#!/usr/bin/env bash
# Fusebase Flow — install-git-hooks
# Copies (NOT symlinks, for cross-platform portability) the git fallback hooks
# into .git/hooks/. Re-run after pulling Fusebase Flow updates.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/hooks/git"
DEST="$ROOT/.git/hooks"

if [ ! -d "$SRC" ]; then
    echo "Source dir not found: $SRC" >&2
    exit 1
fi
if [ ! -d "$DEST" ]; then
    echo "Git hooks dir not found: $DEST (is this a git repo?)" >&2
    exit 1
fi

for hook in pre-commit commit-msg; do
    src_file="$SRC/$hook"
    dest_file="$DEST/$hook"
    if [ -f "$src_file" ]; then
        cp "$src_file" "$dest_file"
        chmod +x "$dest_file"
        echo "[fusebase-flow] installed $hook -> $dest_file"
    fi
done

echo "[fusebase-flow] git hooks installed. Test with: bash $SRC/../tests/run-tests.sh"
