#!/usr/bin/env bash
# Fusebase Flow — hook-layer manifest VERIFY (membership + integrity; D3).
#
# Thin wrapper -> hooks/local/lib/hook_manifest.py verify [--json]. One python
# pass hashing the covered hook layer; OS-independent. Exit codes:
#   0 MATCH · 1 DRIFT (modified/missing/flagged-extra) · 2 BROKEN (corrupt
#   manifest / self-hash mismatch) · 4 ABSENT (no manifest).
# Exit 3 is RESERVED and never emitted (the engine's public exit 3 =
# EXCEPTION_IN_EFFECT — a standalone rc 3 would collide with it).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/hook_manifest.py"

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "[verify-hook-manifest] python3 not found; install Python 3.10+." >&2
    exit 2
  fi
fi

exec "$python_bin" "$LIB" verify --root "$ROOT" "$@"
