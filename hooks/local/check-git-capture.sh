#!/usr/bin/env bash
# Fusebase Flow — MSYS capture-hang gate.
#
# Rejects any command substitution that captures a git (or Flow git-hook) process tree in a
# GATED shell file. A native git descendant can retain the write end of the substitution pipe
# past exit, so the shell waits for an EOF that never comes and the run hangs until some outer
# wall fires. docs/problem-catalog/msys-git-command-substitution-hang/problem.md.
#
# TRIPWIRE: FF_GIT_CAPTURE_GATED is the enforced surface, and it is deliberately NOT the whole
# repo — every commit-path hook plus the release harness that executes them. ~150 further
# `$(git …)` sites exist under hooks/local/**; they are one-shot operator tooling, not the
# release gate, and converting them is a separate outcome (named in the catalog entry).
# Adding a file here is a one-line change; removing one needs a recorded reason.
set -uo pipefail

ROOT=""
_cap="$(mktemp 2>/dev/null || true)"
if [ -n "$_cap" ]; then
    git rev-parse --show-toplevel > "$_cap" 2>/dev/null || :
    IFS= read -r ROOT < "$_cap" 2>/dev/null || :
    rm -f "$_cap" 2>/dev/null
fi
[ -n "$ROOT" ] || ROOT="$(pwd)"

FF_GIT_CAPTURE_GATED=(
    hooks/git/pre-commit
    hooks/git/commit-msg
    hooks/tests/run-tests.sh
    hooks/tests/test-secret-scan-staged.sh
    hooks/local/lib/run-with-timeout.sh
    hooks/tests/lib/orphan-reap.sh
    hooks/tests/lib/run-preconditions.sh
)

SCANNER="$ROOT/hooks/local/lib/git-capture-scan.py"
if [ ! -f "$SCANNER" ]; then
    echo "[check-git-capture] BLOCK — scanner missing at $SCANNER" >&2
    exit 2
fi

if [ "${1:-}" = "--list" ]; then
    printf '%s\n' "${FF_GIT_CAPTURE_GATED[@]}"
    exit 0
fi

targets=()
if [ "$#" -gt 0 ]; then
    targets=("$@")
else
    for rel in "${FF_GIT_CAPTURE_GATED[@]}"; do
        if [ ! -f "$ROOT/$rel" ]; then
            echo "[check-git-capture] BLOCK — gated file missing: $rel" >&2
            exit 2
        fi
        targets+=("$ROOT/$rel")
    done
fi

python3 "$SCANNER" "${targets[@]}"
