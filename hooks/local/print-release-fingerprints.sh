#!/usr/bin/env bash
# Fusebase Flow — emit the release-fingerprint rows for docs/release-fingerprints.md.
#
# Usage: bash hooks/local/print-release-fingerprints.sh <ref> [<ref>…]
#
# TRIPWIRE: the table in docs/release-fingerprints.md must be REGENERATED, never hand-edited —
# a transcribed hook-layer count was wrong (203 vs 156) and a consumer propagated it.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1

[ "$#" -ge 1 ] || { echo "usage: $0 <ref> [<ref>...]" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "[fingerprints] python3 required" >&2; exit 1; }

echo "| Release / tree | \`VERSION\` | managed-content \`manifest_self_sha256\` | assets | hook-layer \`manifest_self_sha256\` | assets |"
echo "|---|---:|---|---:|---|---:|"

rc=0
for ref in "$@"; do
    # A manifest absent at a ref is a real, reportable state (see F1) — never invent a value.
    ver="$(git show "$ref:VERSION" 2>/dev/null | tr -d '\r\n')" || ver=""
    row="$(FF_REF="$ref" python3 - <<'PY'
import json, os, subprocess, sys

ref = os.environ["FF_REF"]

def read(path):
    try:
        raw = subprocess.run(["git", "show", f"{ref}:{path}"],
                             capture_output=True, check=True).stdout
        m = json.loads(raw)
        return f"`{m['manifest_self_sha256']}`", str(m["asset_count"])
    except Exception:
        return "_absent_", "n/a"

mc_sha, mc_n = read("audit/managed-content-manifest.json")
hl_sha, hl_n = read("audit/hook-layer-manifest.json")
if mc_sha == "_absent_" and hl_sha == "_absent_":
    sys.exit(3)
print(f"{mc_sha} | {mc_n} | {hl_sha} | {hl_n}")
PY
)" || { echo "[fingerprints] no manifest readable at '$ref'" >&2; rc=1; continue; }
    printf '| `%s` | %s | %s |\n' "$ref" "${ver:-n/a}" "$row"
done
exit "$rc"
