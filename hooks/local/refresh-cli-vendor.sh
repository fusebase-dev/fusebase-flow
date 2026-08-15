#!/usr/bin/env bash
# Fusebase Flow — guarded re-vendor of CLI-owned assets (S2 / spec
# docs/specs/cli-0298-compatibility/spec.md).
#
# WHAT THIS IS FOR
#   Refreshing the vendored FuseBase CLI assets from a newer CLI tree. The obvious
#   implementation — `cp -r` from the CLI's project-template — DESTROYS the
#   `<!-- CUSTOM:SKILL:BEGIN -->…END` blocks Flow authors inside CLI-owned files
#   (today: a full "Consuming Another Fusebase App's API" workflow in
#   app-dev-practices, and the flow-selection rule in file-upload). The existing
#   CLI_CUSTOM_AT_RISK advisory exists to warn about exactly that and cannot stop it,
#   because it does not change the exit code. This script is the three-way refresh
#   that makes the warning unnecessary: upstream content wins, CUSTOM blocks survive
#   byte-for-byte.
#
# SCOPE = the ownership map, never a hardcoded list. Skill and agent names come from
#   hooks/local/fusebase-flow-overlays/agent-surface-ownership.json (the same source
#   stamp-cli-provenance.sh reads), so this tracks the map as it grows.
#
# PROVENANCE IS DERIVED, NOT ASSERTED. stamp-cli-provenance.sh hashes the LOCAL files,
#   which can only ever prove "matches what we shipped". This script additionally records
#   each asset's sha256 computed from the SOURCE CLI TREE into
#   audit/cli-upstream-manifest.json, so CLI_SNAPSHOT_STALE can distinguish "matches
#   upstream 0.29.8" from "matches whatever we shipped". Files carrying a CUSTOM block are
#   merge-derived and marked `merge_derived: true` — they are exempt from exact-match
#   rather than pretending to match.
#
# NOT IN SCOPE: .claude/hooks/* (the 4 CLI quality hooks — verified byte-identical and
#   deliberately untouched) and any Flow-owned skill.
#
# USAGE
#   bash hooks/local/refresh-cli-vendor.sh --source <cli-tree> --cli-version <x.y.z>
#                                          [--dest <repo-root>] [--blind] [--dry-run]
#   --blind   DIAGNOSTIC ONLY: perform the naive copy (no CUSTOM preservation). Exists so
#             the oracle can demonstrate what a blind copy would have destroyed. Never use
#             it to actually re-vendor.

set -uo pipefail

SRC=""; CLI_VERSION=""; DEST=""; BLIND=0; DRY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)      SRC="${2:-}"; shift 2 ;;
    --cli-version) CLI_VERSION="${2:-}"; shift 2 ;;
    --dest)        DEST="${2:-}"; shift 2 ;;
    --blind)       BLIND=1; shift ;;
    --dry-run)     DRY=1; shift ;;
    -h|--help)
      echo "Usage: bash hooks/local/refresh-cli-vendor.sh --source <cli-tree> --cli-version <x.y.z> [--dest <root>] [--blind] [--dry-run]"
      exit 0 ;;
    *) echo "[refresh-cli-vendor] unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

[ -n "$DEST" ] || DEST="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "[refresh-cli-vendor] --source must name an existing FuseBase Apps CLI tree" >&2
  exit 2
fi
if [ -z "$CLI_VERSION" ]; then
  echo "[refresh-cli-vendor] --cli-version is required (the manifest must not guess)" >&2
  exit 2
fi

OWNERSHIP="$DEST/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
if [ ! -f "$OWNERSHIP" ]; then
  echo "[refresh-cli-vendor] ownership manifest not found: $OWNERSHIP" >&2
  exit 2
fi

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then python_bin="python"
  else echo "[refresh-cli-vendor] python3 not found; install Python 3.10+." >&2; exit 2; fi
fi

"$python_bin" - "$SRC" "$DEST" "$OWNERSHIP" "$CLI_VERSION" "$BLIND" "$DRY" <<'PY'
from __future__ import annotations

import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

src_root, dest_root, ownership_path, cli_version, blind, dry = (
    Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(),
    Path(sys.argv[3]).resolve(), sys.argv[4], sys.argv[5] == "1", sys.argv[6] == "1",
)

ownership = json.loads(ownership_path.read_text(encoding="utf-8"))


def known_names_for(token: str) -> list[str]:
    names: set[str] = set()
    for entry in ownership.get("paths", []):
        if token in entry.get("path", ""):
            for name in entry.get("known_names", []) or []:
                names.add(name)
    return sorted(names)


skill_names = known_names_for("<cli-provider-skill>")
agent_names = known_names_for("<cli-provider-agent>")

SKILL_MIRRORS = [".claude/skills", ".agents/skills"]
AGENT_MIRRORS = [".claude/agents", ".codex/agents"]
SRC_SKILLS = src_root / "project-template" / ".claude" / "skills"
SRC_AGENTS = src_root / "project-template" / ".claude" / "agents"

if not SRC_SKILLS.is_dir():
    print(f"[refresh-cli-vendor] source skills dir not found: {SRC_SKILLS}", file=sys.stderr)
    sys.exit(2)

BEGIN = "<!-- CUSTOM:SKILL:BEGIN -->"
END = "<!-- CUSTOM:SKILL:END -->"
# TRIPWIRE: DOTALL + non-greedy, anchored on whole lines. A greedy match across two blocks
# would splice unrelated content into one "preserved" block and the byte-comparison would
# still pass — the failure would be invisible.
BLOCK_RE = re.compile(
    r"^" + re.escape(BEGIN) + r"\n.*?^" + re.escape(END) + r"$",
    re.DOTALL | re.MULTILINE,
)


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def read_text(p: Path) -> str:
    # TRIPWIRE: decode the RAW bytes — never open() in text mode. Universal-newline
    # translation would rewrite a CRLF file's block into LF and the "byte-for-byte
    # preservation" claim would quietly become false on Windows checkouts.
    return p.read_bytes().decode("utf-8")


def block_title(block: str) -> str:
    """The block's own first non-blank line after BEGIN — its identity. Two blocks with the
    same title are two versions of the same section, not two different sections."""
    for line in block.split("\n")[1:]:
        if line.strip() and not line.startswith(END):
            return line.strip()
    return ""


def extract_blocks(text: str) -> list[tuple[str, str | None]]:
    """[(block_text, anchor_line_or_None)]. The anchor is the first non-blank line AFTER the
    block in the OLD file — normally the '## …' heading the block sits in front of. Re-inserting
    before that same heading in the NEW file keeps the block where its author put it."""
    out = []
    for m in BLOCK_RE.finditer(text):
        tail = text[m.end():].split("\n")
        anchor = None
        for line in tail:
            if line.strip():
                anchor = line
                break
        out.append((m.group(0), anchor))
    return out


def merge(new_text: str, old_text: str, rel: str) -> tuple[str, int, list[dict]]:
    """Upstream content wins; every local CUSTOM block is re-inserted VERBATIM — EXCEPT one
    that upstream has since adopted under the same title.

    WHY the exception (found at 0.29.8, not anticipated by the spec): the CLI now ships its OWN
    CUSTOM block titled '## Consuming Another Fusebase App's API' — a strict superset of Flow's,
    which additionally CORRECTS Flow's line (`client:<clientId>` -> `client:<productId>`, "not an
    app id"). Re-inserting Flow's copy beside it would ship the same heading twice AND keep
    teaching the corrected-away form: the exact defect class this ticket exists to close. The
    preserve rule protects Flow-authored content from destruction; when upstream has adopted that
    content, applying the rule literally works against its own purpose (FR-20).

    The exception is DELIBERATELY narrow and never silent: it fires only on an exact title match,
    and every superseded block is returned with its sha256 for the manifest's audit record."""
    blocks = extract_blocks(old_text)
    if not blocks:
        return new_text, 0, []
    upstream_titles = {block_title(b): b for b, _ in extract_blocks(new_text)}
    result = new_text
    kept = 0
    superseded: list[dict] = []
    for block, anchor in blocks:
        if block in result:            # byte-identical copy already upstream: nothing to do
            continue
        title = block_title(block)
        if title and title in upstream_titles:
            superseded.append({
                "path": rel,
                "title": title,
                "local_sha256": sha256_bytes(block.encode("utf-8")),
                "local_bytes": len(block.encode("utf-8")),
                "upstream_sha256": sha256_bytes(upstream_titles[title].encode("utf-8")),
                "upstream_bytes": len(upstream_titles[title].encode("utf-8")),
            })
            continue
        placed = False
        if anchor:
            lines = result.split("\n")
            for i, line in enumerate(lines):
                if line == anchor:
                    lines[i:i] = [block, ""]
                    result = "\n".join(lines)
                    placed = True
                    break
        if not placed:
            # Anchor gone from the new upstream text: append rather than drop. Losing a block
            # upstream has NOT adopted is the one outcome this script exists to prevent.
            if not result.endswith("\n"):
                result += "\n"
            result += "\n" + block + "\n"
        kept += 1
    return result, kept, superseded


assets: list[dict] = []
changed: list[str] = []
preserved: list[str] = []
superseded_all: list[dict] = []
orphans: list[str] = []


def vendor_file(src_file: Path, dest_file: Path, rel: str) -> None:
    new_bytes = src_file.read_bytes()
    merge_derived = False
    out_bytes = new_bytes
    if dest_file.exists() and not blind:
        old_text = read_text(dest_file)
        if BEGIN in old_text:
            merged, n, sup = merge(new_bytes.decode("utf-8"), old_text, rel)
            superseded_all.extend(sup)
            if n:
                out_bytes = merged.encode("utf-8")
                merge_derived = True
                preserved.append(f"{rel} ({n} CUSTOM block(s))")
    if not dry:
        dest_file.parent.mkdir(parents=True, exist_ok=True)
        prior = dest_file.read_bytes() if dest_file.exists() else None
        if prior != out_bytes:
            dest_file.write_bytes(out_bytes)
            changed.append(rel)
    elif not dest_file.exists() or dest_file.read_bytes() != out_bytes:
        changed.append(rel)
    assets.append({
        "path": rel,
        "upstream_source": str(src_file.relative_to(src_root)).replace("\\", "/"),
        "upstream_sha256": sha256_bytes(new_bytes),
        "merge_derived": merge_derived,
    })


for name in skill_names:
    sdir = SRC_SKILLS / name
    if not sdir.is_dir():
        orphans.append(f"skill '{name}' absent from the source CLI tree — local copy left as-is")
        continue
    for sf in sorted(p for p in sdir.rglob("*") if p.is_file()):
        sub = sf.relative_to(sdir)
        for mirror in SKILL_MIRRORS:
            rel = f"{mirror}/{name}/{sub}".replace("\\", "/")
            vendor_file(sf, dest_root / rel, rel)

for name in agent_names:
    sf = SRC_AGENTS / f"{name}.md"
    if not sf.is_file():
        orphans.append(f"agent '{name}' absent from the source CLI tree — local copy left as-is")
        continue
    for mirror in AGENT_MIRRORS:
        rel = f"{mirror}/{name}.md"
        vendor_file(sf, dest_root / rel, rel)

manifest = {
    "schema_version": 1,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    "cli_version": cli_version,
    "description": (
        "UPSTREAM provenance for vendored FuseBase CLI-owned assets: each sha256 is computed "
        "from the SOURCE CLI tree, not from the local copy, so freshness can be derived rather "
        "than asserted. merge_derived=true marks a file that carries a Flow-authored "
        "CUSTOM:SKILL block and is therefore exempt from exact upstream match. Regenerate with "
        "hooks/local/refresh-cli-vendor.sh."
    ),
    "asset_count": len(assets),
    # Blocks superseded BY THIS RUN. TRIPWIRE: transient by construction — a second (idempotent)
    # run has nothing left to supersede and writes []. The DURABLE record of a supersession is
    # the commit that performed it plus git history (FR-18); do not read an empty list here as
    # "no block was ever superseded".
    "superseded_custom_blocks": sorted(superseded_all, key=lambda s: (s["path"], s["title"])),
    "assets": sorted(assets, key=lambda a: a["path"]),
}
if not dry and not blind:
    out = dest_root / "audit" / "cli-upstream-manifest.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    # newline="\n": see the tripwire in stamp-cli-provenance.sh. A CRLF manifest describes
    # bytes that never ship, and the local stamper/verifier pair cannot see it by construction.
    with out.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(manifest, indent=2) + "\n")

mode = "BLIND (diagnostic)" if blind else ("dry-run" if dry else "guarded")
print(f"[refresh-cli-vendor] mode={mode} cli_version={cli_version} assets={len(assets)} changed={len(changed)}")
for p in preserved:
    print(f"[refresh-cli-vendor] preserved {p}")
for s in superseded_all:
    print(f"[refresh-cli-vendor] SUPERSEDED {s['path']} :: {s['title']} — "
          f"local {s['local_sha256'][:12]} ({s['local_bytes']}B) dropped; upstream ships the same "
          f"titled block {s['upstream_sha256'][:12]} ({s['upstream_bytes']}B). Bytes remain in git history.")
for o in orphans:
    print(f"[refresh-cli-vendor] NOTE {o}")
if blind:
    print("[refresh-cli-vendor] WARNING: --blind skipped CUSTOM:SKILL preservation. "
          "This mode exists only to demonstrate what a naive copy destroys.")
PY
