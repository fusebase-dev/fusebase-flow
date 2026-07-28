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
# TRIPWIRE (decision K20b): this is an UPSTREAM/CI tool. A CONSUMER must never be advised
# to run it to "fix" a missing or drifted base — stamping from a consumer tree records
# their local edits as upstream's base, and the next upstream change to those files then
# classifies upstream-only and OVERWRITES them. Consumer-side base recovery comes only
# from the exact prior upstream tag/package (hooks/local/bootstrap-upgrade.sh).
#
# Usage: bash hooks/local/stamp-managed-content-manifest.sh [--root <dir>] [--out <path>]
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
exec python3 "$ROOT/hooks/local/lib/managed_content_manifest.py" stamp --root "$ROOT" "$@"
