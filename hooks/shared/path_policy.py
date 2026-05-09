"""Fusebase Flow — path_policy.

Reads policies/protected-paths.yml and checks whether a given path is protected,
plus whether an exception artifact exists in state/approvals/.
"""
from __future__ import annotations

import fnmatch
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .policy_loader import find_git_root, get_policy


@dataclass
class PathDecision:
    path: str
    protected: bool
    category: str | None
    has_exception: bool
    decision: str           # allow | deny | warn
    reason: str = ""
    rule_id: str = "FR-07"


def _matches_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pat) or _glob_starstar(path, pat) for pat in patterns)


def _glob_starstar(path: str, pattern: str) -> bool:
    """Approximate ** matching beyond fnmatch's single-segment wildcard."""
    if "**" not in pattern:
        return False
    # Convert **/foo to a regex-ish prefix match.
    parts = pattern.split("**")
    if len(parts) != 2:
        return False
    head, tail = parts
    if head and not path.startswith(head.rstrip("/")):
        return False
    if tail and not path.endswith(tail.lstrip("/")):
        return False
    return True


def _load_categories() -> dict[str, dict[str, Any]]:
    return get_policy("protected-paths").get("categories") or {}


def is_protected(path: str) -> tuple[bool, str | None]:
    cats = _load_categories()
    for name, cfg in cats.items():
        patterns = cfg.get("paths") or []
        if _matches_any(path, patterns):
            return True, name
    return False, None


def has_active_exception(path: str, root: Path | None = None) -> bool:
    """Look for a non-expired protected_path_edit-*.json that lists this path."""
    root = root or find_git_root()
    approvals_dir = root / "state" / "approvals"
    if not approvals_dir.exists():
        return False
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    for f in approvals_dir.glob("protected_path_edit-*.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        expires = data.get("expires_at", "")
        if expires and expires < now_iso:
            continue
        approved_paths = data.get("paths") or []
        if path in approved_paths or any(_matches_any(path, [p]) for p in approved_paths):
            return True
    return False


def evaluate(path: str, *, root: Path | None = None) -> PathDecision:
    protected, category = is_protected(path)
    if not protected:
        return PathDecision(path=path, protected=False, category=None, has_exception=False, decision="allow")
    exception = has_active_exception(path, root)
    if exception:
        return PathDecision(
            path=path,
            protected=True,
            category=category,
            has_exception=True,
            decision="allow",
            reason=f"protected ({category}) but active exception artifact present",
        )
    policy = get_policy("protected-paths")
    on_unapproved = policy.get("on_unapproved_edit", "deny")
    return PathDecision(
        path=path,
        protected=True,
        category=category,
        has_exception=False,
        decision=on_unapproved,
        reason=f"FR-07: path is protected (category={category}); no active exception artifact found.",
    )


def evaluate_many(paths: list[str], *, root: Path | None = None) -> list[PathDecision]:
    return [evaluate(p, root=root) for p in paths]


__all__ = ["PathDecision", "is_protected", "has_active_exception", "evaluate", "evaluate_many"]
