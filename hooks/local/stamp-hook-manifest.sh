#!/usr/bin/env bash
# Fusebase Flow — hook-layer manifest STAMP (byte-stable; D1).
#
# Thin wrapper -> hooks/local/lib/hook_manifest.py stamp. Regenerates
# audit/hook-layer-manifest.json as a pure function of (covered file bytes,
# VERSION) — NO timestamps (the stamp date is git history). CI freshness-gates
# the output; never hand-edit the manifest. R1: any commit touching a covered
# path re-runs this and stages the manifest in the SAME commit.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/hook_manifest.py"

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "[stamp-hook-manifest] python3 not found; install Python 3.10+." >&2
    exit 2
  fi
fi

exec "$python_bin" "$LIB" stamp --root "$ROOT" "$@"
