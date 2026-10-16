"""Fusebase Flow — git_utils.

Thin wrapper around git CLI for hook handlers. We shell out rather than depend
on libgit2 to keep the runtime dep set minimal (PyYAML only).
"""
from __future__ import annotations

import subprocess
from pathlib import Path


def _run(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    # encoding="utf-8" (not the platform default): git emits UTF-8, but `text=True` alone
    # decodes with locale.getpreferredencoding() — cp1252 on Windows — which raises
    # UnicodeDecodeError on bytes undefined there (0x81/0x8D/0x8F/0x90/0x9D) and leaves
    # .stdout None. Callers here read commit messages (recent_commits) and full staged file
    # content (staged_content), both of which routinely carry such bytes. errors="replace"
    # degrades gracefully instead of crashing a hook.
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def is_git_repo(path: Path) -> bool:
    r = _run(["git", "rev-parse", "--is-inside-work-tree"], cwd=path)
    return r.returncode == 0 and r.stdout.strip() == "true"


def status_short(cwd: Path) -> str:
    r = _run(["git", "status", "--short"], cwd=cwd)
    return r.stdout


def is_clean(cwd: Path) -> bool:
    return status_short(cwd).strip() == ""


def diff_paths(cwd: Path, *, against: str = "HEAD") -> list[str]:
    """List paths with diff vs the given ref."""
    r = _run(["git", "diff", "--name-only", against], cwd=cwd)
    return [line for line in r.stdout.splitlines() if line.strip()]


def diff_against_paths(cwd: Path, paths: list[str], *, against: str = "HEAD") -> dict[str, bool]:
    """For each path glob, return True if diff is empty, False if not.

    Used by FR-07 worker-undisturbed verification.
    """
    out: dict[str, bool] = {}
    for p in paths:
        r = _run(["git", "diff", "--quiet", against, "--", p], cwd=cwd)
        out[p] = r.returncode == 0   # exit 0 means no diff
    return out


def staged_paths(cwd: Path) -> list[str]:
    r = _run(["git", "diff", "--cached", "--name-only"], cwd=cwd)
    return [line for line in r.stdout.splitlines() if line.strip()]


def staged_content(cwd: Path, path: str) -> str:
    """Read the staged version of a single file (after git add)."""
    r = _run(["git", "show", f":{path}"], cwd=cwd)
    return r.stdout


def commit_message_from_args(args: list[str]) -> str | None:
    """For commit-msg hook: the first positional arg is the path to the message file."""
    for a in args:
        if a.endswith("COMMIT_EDITMSG") or a.endswith(".git/COMMIT_EDITMSG"):
            try:
                return Path(a).read_text(encoding="utf-8")
            except OSError:
                return None
    return None


def recent_commits(cwd: Path, n: int = 20) -> str:
    r = _run(["git", "log", "--oneline", f"-{n}"], cwd=cwd)
    return r.stdout


__all__ = [
    "is_git_repo",
    "status_short",
    "is_clean",
    "diff_paths",
    "diff_against_paths",
    "staged_paths",
    "staged_content",
    "commit_message_from_args",
    "recent_commits",
]
