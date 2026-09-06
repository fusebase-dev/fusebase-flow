#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


SCHEMA = 1


def native_path(raw: str) -> Path:
    if os.name == "nt" and raw.startswith("/"):
        converted = subprocess.run(
            ["cygpath", "-m", raw], check=True, text=True, capture_output=True
        ).stdout.strip()
        return Path(converted)
    return Path(raw)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp = Path(raw)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, sort_keys=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def load_receipt(path: Path) -> dict:
    if not path.exists():
        return {"schema": SCHEMA, "targets": {}}
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("schema") != SCHEMA or not isinstance(value.get("targets"), dict):
        raise RuntimeError("owned-target receipt has invalid schema")
    return value


def safe_target(root: Path, rel: str) -> Path:
    candidate = Path(os.path.abspath(root / rel))
    try:
        candidate.absolute().relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"target escapes repository: {rel}") from exc
    current = candidate.parent
    while current != root:
        if current.is_symlink():
            raise RuntimeError(f"target parent is a symlink: {rel}")
        current = current.parent
    return candidate


def classify(source: Path, target: Path, rel: str, targets: dict) -> tuple[str, str]:
    if source.is_symlink() or not source.is_file():
        return "unsafe", "source is missing, non-file, or symlink"
    source_hash = digest(source)
    if target.is_symlink():
        return "unowned-collision", "target is a symlink"
    if not target.exists():
        return "missing-and-authorized", source_hash
    if not target.is_file():
        return "unowned-collision", "target is not a regular file"
    target_hash = digest(target)
    if target_hash == source_hash:
        return "current", source_hash
    prior = targets.get(rel)
    if isinstance(prior, dict) and prior.get("sha256") == target_hash:
        return "owned-repair", source_hash
    return "unowned-collision", "existing bytes are not proven Flow-owned"


def retained_path(target: Path) -> Path:
    base = target.with_name(f"{target.name}.pre-flow-repair")
    if not base.exists():
        return base
    index = 1
    while base.with_name(f"{base.name}.{index}").exists():
        index += 1
    return base.with_name(f"{base.name}.{index}")


def interrupted(stage: str, rel: str) -> bool:
    requested = os.environ.get("FF_RECOVERY_WRITE_INTERRUPT", "")
    return requested in {stage, f"{stage}:{rel}"}


def copy_atomic(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    temp = Path(raw)
    os.close(fd)
    try:
        shutil.copyfile(source, temp)
        temp.chmod(stat.S_IMODE(source.stat().st_mode))
        os.replace(temp, target)
    finally:
        temp.unlink(missing_ok=True)


def apply(root: Path, plan: Path, result: Path, surface: str) -> int:
    receipt_path = root / "state/audit/recovery-owned-targets.json"
    receipt = load_receipt(receipt_path)
    targets = receipt["targets"]
    rows = []
    partial = False
    for raw in plan.read_text(encoding="utf-8").splitlines():
        if not raw:
            continue
        source_raw, rel = raw.split("\t", 1)
        source = native_path(source_raw).resolve()
        try:
            target = safe_target(root, rel)
            status, detail = classify(source, target, rel, targets)
            backup = ""
            if status == "owned-repair":
                backup_path = retained_path(target)
                copy_atomic(target, backup_path)
                backup = str(backup_path.relative_to(root)).replace("\\", "/")
                if interrupted("after-retain", rel):
                    raise RuntimeError("injected interruption after retained original")
            if status in {"missing-and-authorized", "owned-repair"}:
                if interrupted("before-replace", rel):
                    raise RuntimeError("injected interruption before replace")
                copy_atomic(source, target)
            if status in {"current", "missing-and-authorized", "owned-repair"}:
                targets[rel] = {"sha256": digest(target), "surface": surface}
                atomic_json(receipt_path, receipt)
            else:
                partial = True
            rows.append((status, rel, detail, backup))
        except Exception as exc:
            partial = True
            rows.append(("unsafe", rel, str(exc), ""))
    result.write_text("".join("\t".join(row) + "\n" for row in rows), encoding="utf-8")
    return 1 if partial else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--surface", required=True)
    args = parser.parse_args()
    root = native_path(args.root).resolve()
    try:
        return apply(root, native_path(args.plan), native_path(args.result), args.surface)
    except Exception as exc:
        print(f"[recovery-owned-write] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
