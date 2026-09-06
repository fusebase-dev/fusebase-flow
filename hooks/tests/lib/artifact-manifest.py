#!/usr/bin/env python3
"""Emit the mutation harness's deterministic regular-file artifact manifest."""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
from pathlib import Path


def _sort_key(path: str) -> bytes:
    return os.fsencode(path)


EnumerationIdentity = tuple[int, int, int]
OpenIdentity = tuple[int, int, int, int, int]


def _enumeration_identity(info: os.stat_result) -> EnumerationIdentity:
    return (info.st_mode, info.st_size, info.st_mtime_ns)


def _open_identity(info: os.stat_result) -> OpenIdentity:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns)


def _regular_files(root: Path, excluded: set[str]) -> list[tuple[str, Path, EnumerationIdentity]]:
    pending: list[tuple[str, Path]] = [(".", root)]
    files: list[tuple[str, Path, EnumerationIdentity]] = []
    while pending:
        rel_dir, directory = pending.pop()
        try:
            entries = list(os.scandir(directory))
        except OSError as exc:
            raise RuntimeError(f"cannot enumerate {rel_dir}: {exc}") from exc
        entries.sort(key=lambda entry: os.fsencode(entry.name), reverse=True)
        for entry in entries:
            rel = f"./{entry.name}" if rel_dir == "." else f"{rel_dir}/{entry.name}"
            if rel == "./.git":
                continue
            try:
                if entry.is_dir(follow_symlinks=False):
                    pending.append((rel, Path(entry.path)))
                elif entry.is_file(follow_symlinks=False) and rel not in excluded:
                    files.append((rel, Path(entry.path), _enumeration_identity(entry.stat(follow_symlinks=False))))
            except OSError as exc:
                raise RuntimeError(f"cannot classify {rel}: {exc}") from exc
    files.sort(key=lambda item: _sort_key(item[0]))
    return files


def _file_record(rel: str, path: Path, expected: EnumerationIdentity) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise RuntimeError(f"artifact changed type while opening: {rel}")
            if _enumeration_identity(before) != expected:
                raise RuntimeError(f"artifact changed after enumeration: {rel}")
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
            after = os.fstat(stream.fileno())
    except OSError as exc:
        raise RuntimeError(f"cannot read {rel}: {exc}") from exc
    if _open_identity(before) != _open_identity(after):
        raise RuntimeError(f"artifact changed while hashing: {rel}")
    return f"{rel}|file|{after.st_size}|{digest.hexdigest()}"


def build_manifest(root: Path, excluded: set[str]) -> list[str]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise RuntimeError(f"manifest root is not a directory: {root}")
    return [_file_record(rel, path, expected) for rel, path, expected in _regular_files(root, excluded)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--exclude", action="append", default=[])
    args = parser.parse_args()
    excluded = set(args.exclude)
    if any(not item.startswith("./") for item in excluded):
        parser.error("--exclude paths must start with ./")
    try:
        records = build_manifest(args.root, excluded)
    except (OSError, RuntimeError) as exc:
        print(f"artifact-manifest: {exc}", file=sys.stderr)
        return 1
    for record in records:
        sys.stdout.buffer.write(os.fsencode(record) + b"\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
