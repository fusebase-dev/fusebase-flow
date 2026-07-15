"""Report write path — containment + symlink/hardlink refusal + atomic replace +
sentinel-guarded overwrite. Mirrors find-wasted-effort.py's output discipline.
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path

from .constants import REPORT_RELPATH, SENTINEL


class WriteError(Exception):
    pass


def _contained(root: Path, target: Path):
    root_r = root.resolve()
    # Resolve parents that exist; the file itself may not exist yet.
    probe = target
    try:
        probe_r = probe.resolve()
    except OSError as e:
        raise WriteError("cannot resolve output path: %s" % e)
    try:
        probe_r.relative_to(root_r)
    except ValueError:
        raise WriteError("output path escapes repo root: %s" % probe_r)


def write_report(root: Path, content: str) -> Path:
    target = root / REPORT_RELPATH
    _contained(root, target)
    parent = target.parent
    # Refuse a symlinked directory anywhere in docs/wasted-code chain.
    p = parent
    while True:
        if p.is_symlink():
            raise WriteError("refusing to write through a symlinked dir: %s" % p)
        if p == root or p.parent == p:
            break
        p = p.parent
    parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if target.is_symlink():
            raise WriteError("refusing to overwrite a symlink: %s" % target)
        try:
            if target.stat().st_nlink > 1:
                raise WriteError("refusing to overwrite a hardlinked file: %s" % target)
        except OSError:
            pass
        # sentinel guard: never clobber a file we did not generate.
        try:
            head = target.read_text(encoding="utf-8", errors="replace")[:200]
        except OSError:
            head = ""
        if SENTINEL not in head:
            raise WriteError(
                "refusing to overwrite %s — it lacks the generated-file sentinel "
                "(hand-authored file protection)" % target)
    # mkstemp opens with O_CREAT|O_EXCL, so it creates a fresh unique file and
    # never follows a pre-placed symlink/hardlink at the temp path.
    fd, tmp_path = tempfile.mkstemp(dir=str(parent), prefix=".fwc-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        os.replace(tmp_path, str(target))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return target
