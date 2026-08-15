#!/usr/bin/env bash
# Fusebase Flow — vendored assets must be RENDERED, never template source (S4).
#
# WHY THIS EXISTS
#   Flow shipped 40 occurrences of raw ETA interpolation across 12 vendored files —
#   e.g. `fusebase secret create --app <%= it.flags?.includes("declarative-manifest")
#   ? "<appPath>" : "<appId>" %>`. That is worse than stale guidance: the reader is
#   handed PROGRAM SOURCE FOR A TEMPLATE ENGINE and must guess which branch applies.
#   Two of the twelve sat on the sign-in / magic-link surface. It shipped because
#   nothing asserted that vendored assets are rendered. This is that assertion.
#
# SCOPE IS THE MANIFEST, NOT A DIRECTORY LIST. Every path named in
#   audit/cli-vendor-manifest.json is checked — today that spans .claude/skills,
#   .agents/skills, .claude/agents, .codex/agents and .claude/hooks. Driving it from
#   the manifest means the check follows the vendored surface as it grows instead of
#   silently missing a new one.
#
# WHAT IS AND IS NOT A VIOLATION
#   `<%=` (ETA OUTPUT interpolation) is the violation: it is unrendered source
#   presented as an instruction. `<%` control-flow tags are NOT — CLI 0.29.8 ships 27
#   of them itself in its own project-template, so banning them would assert Flow
#   knows better than the CLI about the CLI's own files.
#
# USAGE
#   bash hooks/local/check-vendored-rendered.sh [--root <dir>] [--manifest <path>]
# EXIT
#   0 clean · 1 at least one vendored asset carries `<%=` · 2 the check could not run
#     (absent/unreadable/empty manifest, or a listed path missing) — NEVER a silent 0.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MANIFEST=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)     ROOT="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash hooks/local/check-vendored-rendered.sh [--root <dir>] [--manifest <path>]"
      exit 0 ;;
    *) echo "[check-vendored-rendered] unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$MANIFEST" ] || MANIFEST="$ROOT/audit/cli-vendor-manifest.json"

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then python_bin="python"
  else echo "[check-vendored-rendered] python3 not found; install Python 3.10+." >&2; exit 2; fi
fi

"$python_bin" - "$ROOT" "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path

root, manifest_path = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
NEEDLE = "<%="

if not manifest_path.is_file():
    print(f"[check-vendored-rendered] CANNOT RUN: manifest not found: {manifest_path}", file=sys.stderr)
    sys.exit(2)
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"[check-vendored-rendered] CANNOT RUN: manifest unreadable ({exc})", file=sys.stderr)
    sys.exit(2)

assets = manifest.get("assets") or []
# TRIPWIRE (vacuity): a check that scans zero files passes every time. An empty asset
# list is a broken/emptied manifest, not a clean tree — exit 2, never 0.
if not assets:
    print("[check-vendored-rendered] CANNOT RUN: manifest lists 0 assets (a check that "
          "scans nothing cannot pass)", file=sys.stderr)
    sys.exit(2)

violations: list[tuple[str, int, str, int]] = []
missing: list[str] = []
scanned = 0

for asset in assets:
    rel = asset.get("path")
    if not rel:
        continue
    fp = root / rel
    if not fp.is_file():
        missing.append(rel)
        continue
    try:
        text = fp.read_bytes().decode("utf-8")
    except UnicodeDecodeError:
        scanned += 1          # binary vendored asset cannot carry template source
        continue
    scanned += 1
    if NEEDLE not in text:
        continue
    for n, line in enumerate(text.split("\n"), 1):
        # TRIPWIRE: count OCCURRENCES, not matching lines — a single line can carry two
        # interpolations (fusebase-cli/SKILL.md:385 did), and a per-line count silently
        # under-reports the contamination it is supposed to size.
        if NEEDLE in line:
            violations.append((rel, n, line.strip()[:120], line.count(NEEDLE)))

if missing:
    print(f"[check-vendored-rendered] CANNOT RUN: {len(missing)} manifest path(s) missing from "
          f"the tree — re-stamp with hooks/local/stamp-cli-provenance.sh:", file=sys.stderr)
    for rel in missing[:10]:
        print(f"  MISSING {rel}", file=sys.stderr)
    sys.exit(2)

if violations:
    total = sum(v[3] for v in violations)
    print(f"[check-vendored-rendered] FAIL: {total} unrendered '{NEEDLE}' occurrence(s) on "
          f"{len(violations)} line(s) in {len({v[0] for v in violations})} vendored file(s):", file=sys.stderr)
    for rel, n, line, c in violations:
        print(f"  {rel}:{n}: ({c}x) {line}", file=sys.stderr)
    print("[check-vendored-rendered] Vendored assets are instructions an agent follows, not "
          "template source. Re-vendor from a rendered CLI tree: "
          "bash hooks/local/refresh-cli-vendor.sh --source <cli-tree> --cli-version <x.y.z>",
          file=sys.stderr)
    sys.exit(1)

print(f"[check-vendored-rendered] OK: {scanned} vendored asset(s) scanned, 0 '{NEEDLE}' occurrences")
PY
