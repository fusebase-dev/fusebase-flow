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

# TRIPWIRE (re-review B8): this script's EXIT CODE is a verdict — the health engine
# (hook-integrity-check.sh), preflight, CI and the upgrade hop all branch on it — so the
# interpreter that produces it is trust-bearing and must not be caller-selectable.
#   * NO `${PYTHON:-...}` here (deliberately unlike the stamp/tooling wrappers, which decide
#     nothing): `PYTHON=/bin/true bash verify-hook-manifest.sh` would otherwise exit 0 and read
#     as MATCH. Discovery still falls back python3 -> python for genuine environments.
#   * `-I -S`: without them a sitecustomize/.pth on an inherited PYTHONPATH, or a json.py beside
#     hook_manifest.py, runs before the verifier and can print anything then os._exit(0).
# hook_manifest.py is stdlib-only, so isolation costs it nothing. Same close as ff_boot_py in
# bootstrap-upgrade.sh; see hooks/tests/test-upgrade-preboundary-consumed-tree.sh.
python_bin="python3"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "[verify-hook-manifest] python3 not found; install Python 3.10+." >&2
    exit 2
  fi
fi

exec "$python_bin" -I -S "$LIB" verify --root "$ROOT" "$@"
