#!/usr/bin/env python3
"""Fusebase Flow — hook-layer content manifest (stamp + verify).

Single module shared by hooks/local/stamp-hook-manifest.sh (stamp) and
hooks/local/verify-hook-manifest.sh (verify). The covered set is resolved ONLY
here (collect_assets) so stamp and verify agree — a tampered manifest cannot
shrink its own coverage.

Byte-stable stamp (D1): the manifest is a pure function of (covered file bytes,
VERSION). NO timestamps of any kind — the stamp date is git history; CI enforces
freshness with `stamp && git diff --exit-code`. Fixed key order, indent=2,
trailing newline, LF on write.

verify exit codes (D3): 0 MATCH · 1 DRIFT · 2 BROKEN · 4 ABSENT.
Exit 3 is RESERVED and NEVER emitted here — the health engine's public exit 3
means EXCEPTION_IN_EFFECT and a standalone rc 3 would collide with it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

MANIFEST_REL = "audit/hook-layer-manifest.json"
SCHEMA_VERSION = 1
# Fixed, timestamp-free description (D1). If you add a date here the CI freshness
# gate goes red the day after every merge — the stamp date lives in git history.
DESCRIPTION = (
    "Content-hash manifest of the Fusebase Flow-owned hook layer (handlers, "
    "shared, git wrappers, tests + fixtures, local scripts + lib). Byte-stable: "
    "NO timestamps — the stamp date is git history. Regenerate with "
    "hooks/local/stamp-hook-manifest.sh; CI freshness-gates it (stamp + git diff "
    "--exit-code). Membership resolved by hook_manifest.py::collect_assets."
)

# Scan B (D3): python startup files are a pre-check injection surface; the names
# mirror policies/protected-paths.yml:93-100. NO exclusions apply to Scan B.
STARTUP_BASENAMES = {"sitecustomize.py", "usercustomize.py"}


def _rel(root: Path, p: Path) -> str:
    return str(p.relative_to(root)).replace("\\", "/")


def _files_in(root: Path, subdir: str) -> list[Path]:
    d = root / subdir
    if not d.is_dir():
        return []
    # iterdir() is non-recursive, so __pycache__/ dirs are never descended and a
    # *.pyc inside them is never listed; is_file() drops the __pycache__ dir entry.
    return [f for f in d.iterdir() if f.is_file()]


def collect_assets(root: Path) -> list[str]:
    """Repo-relative POSIX paths of the covered hook layer, sorted (D2).

    Resolver of record: stamp AND verify both call this — one code path, no
    drift between what is stamped and what is checked.
    """
    root = Path(root).resolve()
    out: list[Path] = []
    # hooks/handlers/*.py, hooks/shared/*.py (skip __pycache__/ + *.pyc)
    for sub in ("hooks/handlers", "hooks/shared"):
        out += [f for f in _files_in(root, sub) if f.suffix == ".py"]
    # hooks/git/* — all plain files
    out += _files_in(root, "hooks/git")
    # hooks/tests/*.sh + run_hook_tests.py
    out += [f for f in _files_in(root, "hooks/tests")
            if f.suffix == ".sh" or f.name == "run_hook_tests.py"]
    # hooks/tests/fixtures/* — ALL files (incl. *.jsonl transcripts)
    out += _files_in(root, "hooks/tests/fixtures")
    # hooks/local/*.sh EXCLUDING *.local.* (operator overrides, preserved on upgrade)
    out += [f for f in _files_in(root, "hooks/local")
            if f.suffix == ".sh" and ".local." not in f.name]
    # hooks/local/lib/* : *.sh + the manifest lib hook_manifest.py (covers itself)
    out += [f for f in _files_in(root, "hooks/local/lib")
            if f.suffix == ".sh" or f.name == "hook_manifest.py"]
    return sorted(_rel(root, f) for f in out)


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
    """Self-hash over (schema_version, flow_version, assets) only — excludes
    description / asset_count / itself. Detects corruption + hand-edits (D1);
    NOT a defense against a recomputing attacker (trust model in the spec)."""
    payload = json.dumps(
        {"schema_version": schema_version, "flow_version": flow_version, "assets": assets},
        sort_keys=True, separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_manifest(root: Path) -> dict:
    root = Path(root).resolve()
    flow_version = _flow_version(root)
    assets = [{"path": rel, "sha256": sha256_of(root / rel)} for rel in collect_assets(root)]
    return {
        "schema_version": SCHEMA_VERSION,
        "flow_version": flow_version,
        "description": DESCRIPTION,
        "asset_count": len(assets),
        "assets": assets,
        "manifest_self_sha256": _self_hash(SCHEMA_VERSION, flow_version, assets),
    }


def stamp(root: Path) -> int:
    root = Path(root).resolve()
    doc = build_manifest(root)
    out_path = root / MANIFEST_REL
    out_path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(doc, indent=2) + "\n"
    # newline="\n": LF even on Windows, so the committed manifest is byte-identical
    # across platforms and the CI freshness gate is deterministic.
    with out_path.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"[hook-manifest] wrote {MANIFEST_REL} ({doc['asset_count']} asset(s); "
          f"flow_version={doc['flow_version']})")
    return 0


def _blank_counts() -> dict:
    return {"listed": 0, "matched": 0, "modified": 0, "missing": 0, "extra": 0}


def _emit(result: dict, as_json: bool, rc: int) -> int:
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        c = result["counts"]
        print(f"[hook-manifest] verify: {result['verdict']} (listed={c['listed']} "
              f"matched={c['matched']} modified={c['modified']} missing={c['missing']} "
              f"extra={c['extra']}; flow_version={result.get('flow_version', '')})")
        for f in result.get("files", []):
            reason = f.get("reason")
            print(f"  {f['status']}: {f['path']}" + (f" ({reason})" if reason else ""))
        if result.get("reason"):
            print(f"  reason: {result['reason']}")
    return rc


def verify(root: Path, as_json: bool) -> int:
    root = Path(root).resolve()
    manifest_path = root / MANIFEST_REL

    # ABSENT => exit 4 (NOT 3 — SF8; 3 is reserved for the engine's EXCEPTION_IN_EFFECT).
    if not manifest_path.is_file():
        return _emit({"verdict": "ABSENT", "flow_version": "", "counts": _blank_counts(),
                      "files": [], "reason": "manifest absent"}, as_json, 4)

    try:
        doc = json.loads(manifest_path.read_text(encoding="utf-8"))
        listed_assets = doc["assets"]
        flow_version = doc.get("flow_version", "")
        listed = {a["path"]: a["sha256"] for a in listed_assets}
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return _emit({"verdict": "BROKEN", "flow_version": "", "counts": _blank_counts(),
                      "files": [], "reason": "unparseable manifest"}, as_json, 2)

    # Self-hash: BROKEN (exit 2) — the integrity anchor itself is untrustworthy.
    expected_self = doc.get("manifest_self_sha256")
    actual_self = _self_hash(doc.get("schema_version"), flow_version, listed_assets)
    if not expected_self or expected_self != actual_self:
        counts = _blank_counts()
        counts["listed"] = len(listed)
        return _emit({"verdict": "BROKEN", "flow_version": flow_version, "counts": counts,
                      "files": [], "reason": "manifest self-hash mismatch"}, as_json, 2)

    files: list[dict] = []
    modified = missing = 0
    for path, sha in listed.items():
        fp = root / path
        if not fp.is_file():
            missing += 1
            files.append({"path": path, "status": "missing"})
        elif sha256_of(fp) != sha:
            modified += 1
            files.append({"path": path, "status": "modified"})
    matched = len(listed) - modified - missing

    flagged: set[str] = set()
    extra = 0
    # Scan A — import-adjacent extras (hooks/handlers/*.py, hooks/shared/*.py not in E).
    for sub in ("hooks/handlers", "hooks/shared"):
        for f in _files_in(root, sub):
            if f.suffix != ".py":
                continue
            rel = _rel(root, f)
            if rel not in listed and rel not in flagged:
                flagged.add(rel)
                extra += 1
                files.append({"path": rel, "status": "extra", "reason": "import-adjacent-extra"})
    # Scan B — python startup tripwire: recursive hooks/**, ANY sitecustomize.py /
    # usercustomize.py not in E, NO exclusions (mirrors protected-paths.yml:93-100).
    hooks_dir = root / "hooks"
    if hooks_dir.is_dir():
        for f in hooks_dir.rglob("*"):
            if f.is_file() and f.name in STARTUP_BASENAMES:
                rel = _rel(root, f)
                if rel not in listed and rel not in flagged:
                    flagged.add(rel)
                    extra += 1
                    files.append({"path": rel, "status": "extra", "reason": "python-startup-file"})

    verdict = "MATCH" if (modified == 0 and missing == 0 and extra == 0) else "DRIFT"
    rc = 0 if verdict == "MATCH" else 1
    counts = {"listed": len(listed), "matched": matched, "modified": modified,
              "missing": missing, "extra": extra}
    return _emit({"verdict": verdict, "flow_version": flow_version, "counts": counts,
                  "files": files}, as_json, rc)


def _git_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip()).resolve()
    except Exception:
        return Path.cwd().resolve()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="hook_manifest.py")
    parser.add_argument("command", choices=["stamp", "verify"])
    parser.add_argument("--json", action="store_true", help="verify: emit machine-readable JSON")
    parser.add_argument("--root", default=None, help="repo root (default: git toplevel)")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve() if args.root else _git_root()
    if args.command == "stamp":
        return stamp(root)
    return verify(root, args.json)


if __name__ == "__main__":
    raise SystemExit(main())
