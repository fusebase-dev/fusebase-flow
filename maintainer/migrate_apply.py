#!/usr/bin/env python3
"""The --apply half of `flow.py migrate` (handoff WP 12 steps 3 to 8): backup, removal, the overlay,
install and carry-over, the four documents with the migration report, and the migration commit."""
from __future__ import annotations

import datetime as dt
import shutil
from pathlib import Path

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


def apply(inv: m.Inventory) -> int:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    folder, files = backup(inv, stamp)
    say(f"backup: {folder.name}/ holds {len(files)} files: remove {len(inv.removals())} + replace "
        f"{len(inv.replace)} + {len(files) - len(inv.removals()) - len(inv.replace)} rewritten in place; "
        "listed in .git/info/exclude")
    return 0
