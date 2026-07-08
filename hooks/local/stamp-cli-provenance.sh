#!/usr/bin/env bash
# Fusebase Flow — CLI vendor provenance stamp (B2 / v3.2.0).
#
# Writes a read-only provenance manifest for every VENDORED FuseBase CLI-owned
# asset that ships inside this Fusebase Flow edition (FuseBase CLI 0.25.16): the
# 20 provider skills (SKILL.md + references/**) under .claude/skills and
# .agents/skills, the CLI app-agents under .claude/agents and .codex/agents, and
# the .claude/hooks/* quality hooks. The skill/agent name lists are data-driven
# from agent-surface-ownership.json, so the count tracks that map, not this text.
#
# The skill and agent NAME lists are driven from the known_names arrays in
# hooks/local/fusebase-flow-overlays/agent-surface-ownership.json, so this stays
# in lock-step with the ownership map (no second hand-maintained list).
#
# Output: audit/cli-vendor-manifest.json (COMMITTED — a document of record like
# audit/skill-mirror-manifest.txt; it is NOT gitignored).
#
#   {
#     "schema_version": 1,
#     "generated_at": "<UTC date>",
#     "source_cli_version": "unknown",   # UNVERIFIABLE_LOCALLY — see below
#     "assets": [ { "path": "<repo-rel>", "sha256": "<hex>" }, ... ]
#   }
#
# source_cli_version is the literal "unknown" sentinel: the bundling tool cannot
# know which live FuseBase CLI bundle a vendored copy came from. Freshness is
# advisory only and never blocks. generated_at records when this manifest was
# stamped; the per-file sha256 is the drift-detection source for
# check-cli-flow-conflicts.sh (CLI_SNAPSHOT_STALE).
#
# Read-only / idempotent: only writes audit/cli-vendor-manifest.json. Running it
# twice with no asset change produces a byte-identical manifest (modulo the
# generated_at date). Does NOT touch any CLI-owned asset.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1

MANIFEST_SRC="$ROOT/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
OUT="$ROOT/audit/cli-vendor-manifest.json"

if [ ! -f "$MANIFEST_SRC" ]; then
  echo "[stamp-cli-provenance] ownership manifest not found: $MANIFEST_SRC" >&2
  exit 2
fi

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "[stamp-cli-provenance] python3 not found; install Python 3.10+." >&2
    exit 2
  fi
fi

mkdir -p "$(dirname "$OUT")"

"$python_bin" - "$ROOT" "$MANIFEST_SRC" "$OUT" <<'PY'
from __future__ import annotations

import datetime
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
ownership_path = Path(sys.argv[2]).resolve()
out_path = Path(sys.argv[3]).resolve()

ownership = json.loads(ownership_path.read_text(encoding="utf-8"))


def known_names_for(token: str) -> list[str]:
    """Collect known_names from every ownership entry whose path contains token,
    de-duplicated and sorted."""
    names: set[str] = set()
    for entry in ownership.get("paths", []):
        if token in entry.get("path", ""):
            for name in entry.get("known_names", []) or []:
                names.add(name)
    return sorted(names)


skill_names = known_names_for("<cli-provider-skill>")
agent_names = known_names_for("<cli-provider-agent>")

# Vendored skill mirror roots and agent mirror roots.
skill_roots = [".claude/skills", ".agents/skills"]
agent_roots = [".claude/agents", ".codex/agents"]
hooks_root = ".claude/hooks"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(path: Path) -> str:
    return str(path.relative_to(root)).replace("\\", "/")


asset_paths: list[Path] = []

# 1. Provider skills: SKILL.md + every file under references/** (recursively),
#    across both mirror roots.
for mirror in skill_roots:
    for name in skill_names:
        skill_dir = root / mirror / name
        if not skill_dir.is_dir():
            continue
        for fp in sorted(skill_dir.rglob("*")):
            if fp.is_file():
                asset_paths.append(fp)

# 2. CLI app-agents across both agent mirror roots.
for mirror in agent_roots:
    for name in agent_names:
        fp = root / mirror / f"{name}.md"
        if fp.is_file():
            asset_paths.append(fp)

# 3. CLI quality hooks: every file under .claude/hooks (flat).
hooks_dir = root / hooks_root
if hooks_dir.is_dir():
    for fp in sorted(hooks_dir.iterdir()):
        if fp.is_file():
            asset_paths.append(fp)

# Deterministic ordering by repo-relative path.
seen: set[str] = set()
assets = []
for fp in sorted(asset_paths, key=rel):
    r = rel(fp)
    if r in seen:
        continue
    seen.add(r)
    assets.append({"path": r, "sha256": sha256_of(fp)})

manifest = {
    "schema_version": 1,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    "source_cli_version": "unknown",
    "description": (
        "Provenance for vendored FuseBase CLI-owned assets shipped in this "
        "Fusebase Flow edition. source_cli_version is UNVERIFIABLE_LOCALLY "
        "(literal 'unknown' sentinel); freshness is advisory only. Per-file "
        "sha256 feeds the CLI_SNAPSHOT_STALE advisory in "
        "check-cli-flow-conflicts.sh. Regenerate with "
        "hooks/local/stamp-cli-provenance.sh."
    ),
    "asset_count": len(assets),
    "assets": assets,
}

out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"[stamp-cli-provenance] wrote {out_path.relative_to(root)} "
      f"({len(assets)} asset(s); source_cli_version=unknown)")
PY
