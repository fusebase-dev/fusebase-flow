#!/usr/bin/env bash
# Fusebase Flow — FR-25 module-size ratchet (wrapper for hooks/shared/module_size.py).
#
# Usage:
#   bash hooks/local/check-module-size.sh                   # --staged (pre-commit default)
#   bash hooks/local/check-module-size.sh --worktree        # changes vs HEAD (Stop-hook use)
#   bash hooks/local/check-module-size.sh --all             # every tracked source file
#   bash hooks/local/check-module-size.sh --write-baseline  # (re)generate the committed
#                                                           # baseline — operator-run only
#   bash hooks/local/check-module-size.sh --write-baseline <path>  # re-key ONE row
#                                                           # (rename remedy; no global amnesty)
#
# Policy: policies/module-size.yml (+ optional gitignored module-size.local.yml).
# Exit 1 = ratchet violation under enforcement=block; warn-only while no baseline.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
    python_bin="python"
fi
if ! command -v "$python_bin" >/dev/null 2>&1; then
    echo "[module-size] python not found; skipping FR-25 check" >&2
    exit 0
fi

# All args forwarded; a bare path is only valid after --write-baseline.
exec "$python_bin" "$ROOT/hooks/shared/module_size.py" "${@:---staged}"
