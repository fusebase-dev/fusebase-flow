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

HELPER="$ROOT/hooks/local/lib/validator-evidence.py"
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

TOKEN="$("$PYTHON_BIN" -S "$HELPER" begin --root "$ROOT" --lint "$LINT_CMD" --typecheck "$TYPECHECK_CMD")" || exit 2
cleanup() {
    "$PYTHON_BIN" -S "$HELPER" invalidate --root "$ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if [ -n "$LINT_CMD" ]; then
    echo "[run-validators] running lint: $LINT_CMD" >&2
    eval "$LINT_CMD" || exit 1
fi
if [ -n "$TYPECHECK_CMD" ]; then
    echo "[run-validators] running typecheck: $TYPECHECK_CMD" >&2
    eval "$TYPECHECK_CMD" || exit 1
fi

RECEIPT="$("$PYTHON_BIN" -S "$HELPER" finish --root "$ROOT" --token "$TOKEN")" || exit 2
trap - EXIT INT TERM
echo "[run-validators] authentic exact-state receipt: $RECEIPT"
