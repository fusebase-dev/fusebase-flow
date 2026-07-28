#!/usr/bin/env bash
# Fusebase Flow — stamp audit/managed-content-manifest.json (the upgrade classifier's BASE).
#
# Records a sha256 per managed path so the NEXT upgrade can tell an upstream change from a
# consumer edit (decision K9). Byte-stable + timestamp-free: re-running with no content
# change produces a byte-identical file, which is what makes the CI freshness gate
# (`stamp && git diff --exit-code`) meaningful.
#
# Thin wrapper — all logic lives in hooks/local/lib/managed_content_manifest.py (K14).
#
# Usage: bash hooks/local/stamp-managed-content-manifest.sh [--root <dir>] [--out <path>]
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
exec python3 "$ROOT/hooks/local/lib/managed_content_manifest.py" stamp --root "$ROOT" "$@"
