#!/usr/bin/env python3
"""The --apply half of `flow.py migrate` (handoff WP 12 steps 3 to 8): backup, removal, the overlay,
install and carry-over, the four documents with the migration report, and the migration commit."""
from __future__ import annotations

import datetime as dt
import os
import shutil
import stat
from pathlib import Path

import flow
import migrate as m

BACKUP_PREFIX = ".flow-migrate-"
EXCLUDE_LINES = ("# Fusebase Flow migration backups (flow.py migrate): never stage them.", f"/{BACKUP_PREFIX}*/")


def say(line: str) -> None:
    print(f"[flow migrate] {line}".rstrip())


def source(target: Path, rel: str) -> Path:
    return m.hooks_dir(target) / rel.rsplit("/", 1)[-1] if rel.startswith(".git/hooks/") else target / rel


def backup_rel(rel: str) -> str:
    return ".git-hooks/" + rel.rsplit("/", 1)[-1] if rel.startswith(".git/hooks/") else rel


def exclude(target: Path, lines: tuple[str, ...]) -> None:
    path = Path(m.git(target, "rev-parse", "--git-path", "info/exclude").stdout.decode().strip())
    path = path if path.is_absolute() else target / path
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    missing = [line for line in lines if line not in text.splitlines()]
    if missing:
        with open(path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(("" if not text or text.endswith("\n") else "\n") + "\n".join(missing) + "\n")


def backup(inv: m.Inventory, stamp: str) -> tuple[Path, list[str]]:
    folder = inv.target / f"{BACKUP_PREFIX}{stamp}"
    exclude(inv.target, EXCLUDE_LINES)  # before the first copy, so git never lists the folder
    folder.mkdir()
    files = inv.removals() + inv.replace + [r for r in m.REWRITTEN if (inv.target / r).is_file()]
    for rel in files:
        dst = folder / backup_rel(rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source(inv.target, rel), dst)
    return folder, files


def remove(inv: m.Inventory, folder: Path) -> tuple[list[str], list[str], int]:
    """Deletes the remove list; a file the surface will not delete moves into the backup folder instead."""
    moved, failed, parents = [], [], set()
    for rel in inv.removals():
        src = source(inv.target, rel)
        try:
            try:
                src.unlink()
            except PermissionError:
                os.chmod(src, stat.S_IWRITE)  # a read-only file on Windows
                src.unlink()
        except OSError:
            try:
                os.replace(src, folder / backup_rel(rel))  # its copy is already there
                moved.append(rel)
            except OSError as exc:
                failed.append(f"{rel} ({exc.strerror or exc})")
                continue
        if not rel.startswith(".git/"):
            parents.update(p for p in src.parents if inv.target in p.parents)
    pruned = 0
    for d in sorted(parents, key=lambda p: len(p.parts), reverse=True):
        try:
            d.rmdir()  # only a folder the removal left empty
            pruned += 1
        except OSError:
            pass
    return moved, failed, pruned


def overlay_and_version(inv: m.Inventory) -> list[str]:
    """Replaces each 5.x Flow section by heading with the 6.0 block; the FLOW:PRESERVE region rides along verbatim."""
    done = []
    for name, o in inv.overlays.items():
        path = inv.target / name
        raw = path.read_bytes()
        block = (flow.CORE / flow.OVERLAY[name]).read_bytes()
        if o.crlf:
            block = block.replace(b"\n", b"\r\n")  # the file's own line endings (autocrlf checkouts)
        if o.preserve:
            block = block[:block.index(m.P_BEGIN)] + o.preserve + block[block.index(m.P_END):]
        flow.write_bytes(path, raw[:o.start] + block + raw[o.end:], False)
        done.append(f"{name}: the '{o.heading}' section ({o.end_lf - o.start_lf:,} bytes) replaced by the 6.0 block"
                    + (f", FLOW:PRESERVE ({o.preserve_lf():,} bytes) carried verbatim" if o.preserve else ""))
    if inv.version_is_flow:
        flow.write_bytes(inv.target / "VERSION", (flow.CORE / "VERSION").read_bytes(), False)
        done.append(f"VERSION: {inv.version} -> {(flow.CORE / 'VERSION').read_text(encoding='utf-8').strip()}")
    return done


def apply(inv: m.Inventory) -> int:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    folder, files = backup(inv, stamp)
    say(f"backup: {folder.name}/ holds {len(files)} files: remove {len(inv.removals())} + replace "
        f"{len(inv.replace)} + {len(files) - len(inv.removals()) - len(inv.replace)} rewritten in place; "
        "listed in .git/info/exclude")
    moved, failed, pruned = remove(inv, folder)
    say(f"removed: {len(inv.removals()) - len(moved) - len(failed)} files deleted, {pruned} folders the removal "
        "left empty pruned")
    if moved:
        say(f"moved into {folder.name}/ because this surface refused the deletion: {len(moved)} files "
            "(delete the folder once the migration is accepted)")
    if failed:
        say(f"STOPPED: {len(failed)} files could be neither deleted nor moved; the backup holds every file:")
        for line in failed:
            say(f"  {line}")
        return 1
    for line in overlay_and_version(inv):
        say(line)
    return 0
