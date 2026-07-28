#!/usr/bin/env python3
"""Fusebase Flow — managed-content manifest: what upstream actually shipped.

The upgrade engine could tell that a managed directory DIFFERED from upstream, but not
whether UPSTREAM changed it or the CONSUMER did — so it overwrote consumer edits. This
module records a sha256 per managed path at install/upgrade time (the "base"), and
classifies base x local x upstream into the ten states of decision K9.

CANONICAL LIST HOME (decision K14): MANAGED_DIRS / MANAGED_FILES below are the single
definition of "managed". hooks/local/upgrade.sh populates its arrays from `list-managed`
instead of declaring them inline — two definitions would eventually disagree about what
"managed" means, which is a silent correctness hole in the classifier.

Byte-stable stamp (mirrors hook_manifest.py): the manifest is a pure function of the
covered file bytes + VERSION. NO timestamps — the stamp date is git history, and CI
freshness-gates it with `stamp && git diff --exit-code`.

Exit codes: verify 0 MATCH / 1 DRIFT / 2 BROKEN / 4 ABSENT (same contract as
hook_manifest.py; 3 stays reserved for the health engine's EXCEPTION_IN_EFFECT).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

MANIFEST_REL = "audit/managed-content-manifest.json"
SCHEMA_VERSION = 1

# TRIPWIRE (decision K14): these two lists ARE the definition of "managed content" for
# both the manifest and the upgrade engine. upgrade.sh reads them via `list-managed`;
# never re-declare them in shell. Adding a tree here puts it under classification and
# under the CI freshness gate at the same time — which is the point.
MANAGED_DIRS = (
    "flow-skills", "agents", "workflows", "policies", "templates", "hooks",
    ".claude-plugin", ".codex-plugin",
)
MANAGED_FILES = (
    "FLOW_RULES.md",
    "FLOW_RULES_HISTORY.md",
    "audit/hook-layer-manifest.json",
    # K13b: the base manifest travels with the upgrade and is installed LAST, so the next
    # upgrade classifies against what THIS one actually delivered.
    MANIFEST_REL,
)

# Never part of the managed set: operator overrides that upgrade deliberately preserves,
# build noise, and the transient backup twins upgrade/bootstrap drop.
_EXCLUDED_DIR_NAMES = {"__pycache__", ".git", "node_modules"}
_EXCLUDED_SUFFIXES = (".pyc", ".pyo")
_BACKUP_MARKERS = (".pre-upgrade-", ".pre-bootstrap-", ".pre-refresh-")


def _excluded(rel: str) -> bool:
    name = rel.rsplit("/", 1)[-1]
    if any(part in _EXCLUDED_DIR_NAMES for part in rel.split("/")):
        return True
    if rel.endswith(_EXCLUDED_SUFFIXES):
        return True
    if any(marker in name for marker in _BACKUP_MARKERS):
        return True
    # `*.local.*` are operator overrides; upgrade never overwrites them, so upstream has
    # no opinion about their content and they must never classify as consumer-divergent.
    return ".local." in name


def _rel(root: Path, p: Path) -> str:
    return str(p.relative_to(root)).replace("\\", "/")


def _resolve_root(root: Path) -> Path:
    r"""Windows extended-length form so >MAX_PATH files stat normally (hook_manifest.py
    does the same; a silently-dropped file would be a coverage hole, not an error)."""
    p = Path(root).resolve()
    s = str(p)
    if os.name == "nt" and not s.startswith("\\\\?\\"):
        s = ("\\\\?\\UNC\\" + s[2:]) if s.startswith("\\\\") else "\\\\?\\" + s
        p = Path(s)
    return p


def collect_paths(root: Path) -> list[str]:
    """Every managed FILE that exists under `root`, repo-relative POSIX, sorted."""
    root = _resolve_root(root)
    out: set[str] = set()
    for d in MANAGED_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for f in base.rglob("*"):
            if not f.is_file():
                continue
            rel = _rel(root, f)
            if not _excluded(rel):
                out.add(rel)
    for f in MANAGED_FILES:
        if (root / f).is_file() and not _excluded(f):
            out.add(f)
    return sorted(out)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _flow_version(root: Path) -> str:
    vf = root / "VERSION"
    return vf.read_text(encoding="utf-8").strip() if vf.is_file() else ""


def _self_hash(schema_version, flow_version, assets: list) -> str:
    payload = json.dumps(
        {"schema_version": schema_version, "flow_version": flow_version, "assets": assets},
        sort_keys=True, separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_manifest(root: Path) -> dict:
    root = _resolve_root(root)
    flow_version = _flow_version(root)
    # TRIPWIRE: the manifest must never hash ITSELF — a self-referential entry can never
    # settle (stamping changes the file, which changes its own hash). It stays in
    # MANAGED_FILES so the upgrade engine still COPIES it; it is excluded here only.
    assets = [{"path": rel, "sha256": sha256_of(root / rel)}
              for rel in collect_paths(root) if rel != MANIFEST_REL]
    return {
        "schema_version": SCHEMA_VERSION,
        "flow_version": flow_version,
        "description": (
            "Content-hash manifest of Fusebase Flow-managed content (the trees + files "
            "hooks/local/upgrade.sh refreshes). Recorded at install/upgrade so the NEXT "
            "upgrade can tell an upstream change from a consumer edit (decision K9). "
            "Byte-stable: NO timestamps. Regenerate with "
            "hooks/local/stamp-managed-content-manifest.sh; membership resolved by "
            "managed_content_manifest.py::collect_paths."
        ),
        "asset_count": len(assets),
        "assets": assets,
        "manifest_self_sha256": _self_hash(SCHEMA_VERSION, flow_version, assets),
    }


def stamp(root: Path, out_rel: str = MANIFEST_REL) -> int:
    root = _resolve_root(root)
    doc = build_manifest(root)
    out_path = root / out_rel
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(doc, indent=2) + "\n")
    print(f"[managed-content] wrote {out_rel} ({doc['asset_count']} asset(s); "
          f"flow_version={doc['flow_version']})")
    return 0


def load_manifest(path: Path) -> dict[str, str] | None:
    """{repo-relative path: sha256} from a manifest file, or None if unusable."""
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
        return {a["path"]: a["sha256"] for a in doc["assets"]}
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None


def verify(root: Path, as_json: bool) -> int:
    root = _resolve_root(root)
    manifest_path = root / MANIFEST_REL
    if not manifest_path.is_file():
        result = {"verdict": "ABSENT", "reason": "manifest absent", "files": []}
        return _emit_verify(result, as_json, 4)
    try:
        doc = json.loads(manifest_path.read_text(encoding="utf-8"))
        listed = {a["path"]: a["sha256"] for a in doc["assets"]}
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return _emit_verify({"verdict": "BROKEN", "reason": "unparseable manifest",
                             "files": []}, as_json, 2)
    expected_self = doc.get("manifest_self_sha256")
    actual_self = _self_hash(doc.get("schema_version"), doc.get("flow_version", ""),
                             doc["assets"])
    if not expected_self or expected_self != actual_self:
        return _emit_verify({"verdict": "BROKEN", "reason": "manifest self-hash mismatch",
                             "files": []}, as_json, 2)

    files = []
    present = {p for p in collect_paths(root) if p != MANIFEST_REL}
    for path, sha in listed.items():
        fp = root / path
        if not fp.is_file():
            files.append({"path": path, "status": "missing"})
        elif sha256_of(fp) != sha:
            files.append({"path": path, "status": "modified"})
    for path in sorted(present - set(listed)):
        files.append({"path": path, "status": "extra"})
    verdict = "MATCH" if not files else "DRIFT"
    return _emit_verify({"verdict": verdict, "listed": len(listed), "files": files},
                        as_json, 0 if verdict == "MATCH" else 1)


def _emit_verify(result: dict, as_json: bool, rc: int) -> int:
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"[managed-content] verify: {result['verdict']} "
              f"(listed={result.get('listed', 0)} drifted={len(result.get('files', []))})")
        for f in result.get("files", [])[:50]:
            print(f"  {f['status']}: {f['path']}")
        if result.get("reason"):
            print(f"  reason: {result['reason']}")
    return rc


def classify(base_manifest: Path | None, local_root: Path, upstream_root: Path) -> list[dict]:
    """The K9 truth table over base B x local L x upstream U, one row per managed path.

    B is the manifest recorded by the consumer's LAST install/upgrade (what upstream shipped
    them), NOT the incoming tree. Passing the incoming tree as the base would declare every
    consumer edit `current` or `consumer-only` against the wrong reference (K13 option B).
    """
    base = load_manifest(base_manifest) if base_manifest else None
    local_root = _resolve_root(local_root)
    upstream_root = _resolve_root(upstream_root)

    local = {p: sha256_of(local_root / p) for p in collect_paths(local_root)}
    upstream = {p: sha256_of(upstream_root / p) for p in collect_paths(upstream_root)}

    rows: list[dict] = []
    for path in sorted(set(local) | set(upstream) | set(base or {})):
        b = (base or {}).get(path)
        loc = local.get(path)
        up = upstream.get(path)
        rows.append({"path": path, "classification": _classify_one(b, loc, up),
                     "in_base": b is not None, "in_local": loc is not None,
                     "in_upstream": up is not None})
    return rows


def _classify_one(b: str | None, loc: str | None, up: str | None) -> str:
    """One cell of the K9 table. Row numbers below are that table's rows."""
    if loc is not None and up is not None and loc == up:
        return "current"                                          # row 1
    if b is None:
        if loc is not None and up is None:
            return "consumer-added"                               # row 7
        if loc is None and up is not None:
            return "upstream-added"                               # row 8
        return "unknown-base"                                     # row 10
    if loc is None:
        # Base had it, local does not. Upstream still ships it -> the consumer deleted it.
        return "consumer-deleted" if up is not None else "current"  # row 9 / both gone
    if up is None:
        # Upstream dropped it. Clean iff the consumer never touched it (row 5 vs row 6).
        return "upstream-deleted-clean" if loc == b else "upstream-deleted-dirty"
    if loc == b:
        return "upstream-only"                                    # row 2
    if up == b:
        return "consumer-only"                                    # row 3
    return "changed-by-both"                                      # row 4


#: K9's action columns. `auto_overwrite` False means --auto-yes must PRESERVE.
CLASSIFICATIONS = {
    "current":                 {"auto_overwrite": False, "report": False, "abort": False},
    "upstream-only":           {"auto_overwrite": True,  "report": False, "abort": False},
    "consumer-only":           {"auto_overwrite": False, "report": True,  "abort": False},
    "changed-by-both":         {"auto_overwrite": False, "report": True,  "abort": True},
    "upstream-deleted-clean":  {"auto_overwrite": True,  "report": False, "abort": False},
    "upstream-deleted-dirty":  {"auto_overwrite": False, "report": True,  "abort": False},
    "consumer-added":          {"auto_overwrite": False, "report": False, "abort": False},
    "upstream-added":          {"auto_overwrite": True,  "report": False, "abort": False},
    "consumer-deleted":        {"auto_overwrite": False, "report": True,  "abort": False},
    "unknown-base":            {"auto_overwrite": False, "report": True,  "abort": False},
}


def _git_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip()).resolve()
    except Exception:
        return Path.cwd().resolve()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="managed_content_manifest.py")
    parser.add_argument("command",
                        choices=["stamp", "verify", "classify", "list-managed"])
    parser.add_argument("--root", default=None)
    parser.add_argument("--out", default=MANIFEST_REL, help="stamp: manifest destination")
    parser.add_argument("--base", default=None, help="classify: base manifest path")
    parser.add_argument("--upstream", default=None, help="classify: upstream tree root")
    parser.add_argument("--dirs", action="store_true", help="list-managed: dirs only")
    parser.add_argument("--files", action="store_true", help="list-managed: files only")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve() if args.root else _git_root()

    if args.command == "list-managed":
        if args.dirs:
            print("\n".join(MANAGED_DIRS))
        elif args.files:
            print("\n".join(MANAGED_FILES))
        else:
            for d in MANAGED_DIRS:
                print(f"dir\t{d}")
            for f in MANAGED_FILES:
                print(f"file\t{f}")
        return 0
    if args.command == "stamp":
        return stamp(root, args.out)
    if args.command == "verify":
        return verify(root, args.json)

    if not args.upstream:
        print("[managed-content] classify requires --upstream <tree>", file=sys.stderr)
        return 2
    rows = classify(Path(args.base) if args.base else None, root, Path(args.upstream))
    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        for r in rows:
            print(f"{r['classification']}\t{r['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
