#!/usr/bin/env bash
# Fusebase Flow — verify audit/managed-content-manifest.json against the working tree.
#
# Exit: 0 MATCH · 1 DRIFT · 2 BROKEN · 4 ABSENT. (3 is reserved for the health engine's
# EXCEPTION_IN_EFFECT and is never emitted here — same contract as verify-hook-manifest.sh.)
#
# Thin wrapper — logic lives in hooks/local/lib/managed_content_manifest.py (K14).
#
# Usage: bash hooks/local/verify-managed-content-manifest.sh [--json]
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
exec python3 "$ROOT/hooks/local/lib/managed_content_manifest.py" verify --root "$ROOT" "$@"
