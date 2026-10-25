"""Fusebase Flow — git_utils.

Thin wrapper around git CLI for hook handlers. We shell out rather than depend
on libgit2 to keep the runtime dep set minimal (PyYAML only).
"""
from __future__ import annotations

import subprocess
from pathlib import Path

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # no console window when the caller has none (pythonw)


def _run(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    # encoding="utf-8" (not the platform default): git emits UTF-8, but `text=True` alone
    # decodes with locale.getpreferredencoding() — cp1252 on Windows — which raises
    # UnicodeDecodeError on bytes undefined there (0x81/0x8D/0x8F/0x90/0x9D) and leaves
    # .stdout None. Callers here read paths (status_short, diff_paths), which can carry
    # such bytes. errors="replace" degrades gracefully instead of crashing a hook.
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False, creationflags=NO_WINDOW
    )


def status_short(cwd: Path) -> str:
    r = _run(["git", "status", "--short"], cwd=cwd)
    return r.stdout


def diff_paths(cwd: Path, *, against: str = "HEAD") -> list[str]:
    """List paths with diff vs the given ref."""
    r = _run(["git", "diff", "--name-only", against], cwd=cwd)
    return [line for line in r.stdout.splitlines() if line.strip()]


__all__ = ["status_short", "diff_paths"]
