#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then
    echo "[run-validators] not in a git worktree" >&2
    exit 2
fi
cd "$ROOT" || exit 2

PYTHON_BIN="${PYTHON:-python3}"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || PYTHON_BIN="python"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "[run-validators] Python 3.10+ is required" >&2
    exit 2
fi

RUNNER="$ROOT/hooks/local/lib/validator-runner.py"
LINT_CMD="${FUSEBASE_FLOW_LINT:-}"
TYPECHECK_CMD="${FUSEBASE_FLOW_TYPECHECK:-}"
if [ -z "$LINT_CMD" ] && [ -f package.json ] && grep -q '"lint"' package.json; then
    LINT_CMD="npm run -s lint"
fi
if [ -z "$TYPECHECK_CMD" ] && [ -f package.json ] && grep -q '"typecheck"' package.json; then
    TYPECHECK_CMD="npm run -s typecheck"
fi

if [ -z "$LINT_CMD$TYPECHECK_CMD" ]; then
    echo "[run-validators] no lint or typecheck command configured"
    exit 0
fi

exec "$PYTHON_BIN" -I -S "$RUNNER" --root "$ROOT" --lint "$LINT_CMD" --typecheck "$TYPECHECK_CMD"
