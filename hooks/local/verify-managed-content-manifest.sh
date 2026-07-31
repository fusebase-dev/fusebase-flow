#!/usr/bin/env bash
# Fusebase Flow — verify audit/managed-content-manifest.json against the working tree.
#
# Exit: 0 MATCH · 1 DRIFT · 2 BROKEN · 4 ABSENT. (3 is reserved for the health engine's
# EXCEPTION_IN_EFFECT and is never emitted here — same contract as verify-hook-manifest.sh.)
#
# Thin wrapper — logic lives in hooks/local/lib/managed_content_manifest.py (K14).
#
# Usage: bash hooks/local/verify-managed-content-manifest.sh [--json]
#
# TRIPWIRE (re-review B8): this exit code is a verdict (preflight and CI branch on it), so the
# interpreter is trust-bearing. `-I -S` keeps a sitecustomize/.pth on an inherited PYTHONPATH,
# and a json.py sitting beside managed_content_manifest.py, from running before the verifier and
# forging a clean exit. The module is stdlib-only, so isolation costs it nothing. Deliberately no
# `${PYTHON:-...}` override here — a caller-chosen interpreter must never pick a verdict.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
exec python3 -I -S "$ROOT/hooks/local/lib/managed_content_manifest.py" verify --root "$ROOT" "$@"
