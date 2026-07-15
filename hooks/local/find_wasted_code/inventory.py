"""Repo inventory — deterministic, host-independent file sets.

Primary source of truth is `git ls-files -z` (tracked, exact-case, sorted). That
gives Windows-safe existence checks (compare against the exact tracked path, not
Path.exists() which is case-insensitive on Windows) and excludes untracked local
state. If `.git` exists but `git ls-files` fails, we FAIL CLOSED (raise) rather
than silently switching to a filesystem walk — a partial walk could pull in
untracked/foreign content. A non-git tree (selftest fixtures git-init, but be
robust) falls back to a contained walk that refuses symlinked entries.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .constants import (
    MAX_FILE_BYTES, in_scan_scope, is_backup_path, is_binary_ext,
)


class InventoryError(Exception):
    pass


class Inventory:
    def __init__(self, root: Path, tracked: list[str]):
        self.root = root
        # EXISTENCE universe: every tracked path (mirrors/overlays/output included)
        # minus backup snapshots. Used to resolve whether a referenced target exists.
        self.files = set(p for p in tracked if not is_backup_path(p))
        self.dirs = set()
        for p in self.files:
            parts = p.split("/")
            for i in range(1, len(parts)):
                self.dirs.add("/".join(parts[:i]))
        # lowercase index for case-mismatch detection (Windows-safe).
        self._lower = {p.lower(): p for p in self.files}
        # SCAN set: files we READ for references.
        self.scan_files = sorted(p for p in self.files if in_scan_scope(p))

    def exists(self, rel: str) -> bool:
        rel = rel.rstrip("/")
        return rel in self.files or rel in self.dirs

    def case_mismatch(self, rel: str):
        """If rel exists only under a different case, return the real path, else None."""
        rel = rel.rstrip("/")
        if self.exists(rel):
            return None
        real = self._lower.get(rel.lower())
        return real

    def read_text(self, rel: str):
        """Return (text, note). note != None means skipped (coverage), text is None.

        Refuses symlinks (input containment) and oversize/binary files.
        """
        if is_binary_ext(rel):
            return None, "binary"
        abspath = self.root / rel
        try:
            if abspath.is_symlink():
                return None, "symlink-skipped"
            st = abspath.stat()
        except OSError:
            return None, "unreadable"
        if not abspath.is_file():
            return None, "not-a-file"
        if st.st_size > MAX_FILE_BYTES:
            return None, "oversize"
        try:
            data = abspath.read_bytes()
        except OSError:
            return None, "unreadable"
        try:
            return data.decode("utf-8"), None
        except UnicodeDecodeError:
            return data.decode("utf-8", errors="replace"), "invalid-utf8-replaced"


def _git_tracked(root: Path):
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True, timeout=30,
    )
    if out.returncode != 0:
        raise InventoryError(
            "git ls-files failed rc=%d (refusing to fall back to a filesystem walk "
            "in a git repo — fail closed)" % out.returncode)
    raw = out.stdout.decode("utf-8", errors="replace")
    return [p for p in raw.split("\0") if p]


def _walk_tracked(root: Path):
    """Contained fallback for a non-git tree: regular files only, no symlinks."""
    files = []
    skip_dirs = {".git", "node_modules", "state", ".fusebase-flow-source"}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs
                       and not os.path.islink(os.path.join(dirpath, d))]
        for fn in filenames:
            ap = Path(dirpath) / fn
            if ap.is_symlink():
                continue
            rel = ap.relative_to(root).as_posix()
            files.append(rel)
    return files


def build(root: Path) -> Inventory:
    if (root / ".git").exists():
        tracked = _git_tracked(root)
    else:
        tracked = _walk_tracked(root)
    return Inventory(root, tracked)
