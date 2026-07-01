"""Fusebase Flow — path_policy.

Reads policies/protected-paths.yml and checks whether a given path is protected,
plus whether an exception artifact exists in state/approvals/.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .policy_loader import find_git_root, get_policy

# WS1b: the internals-bootstrap category demands a genuinely SINGLE-USE exception.
# A plain path+TTL artifact is a reusable FR-07 bypass, so for this category the
# artifact must additionally be bound to the exact staged changeset (tree_digest)
# and the exact operation (operation), and it is consumed/cleaned by the bootstrap
# writer after the setup commit passes. A second, unrelated protected-path edit
# produces a different staged digest -> no match -> still DENIES.
_BOOTSTRAP_CATEGORY = "fusebase_flow_internals"
_BOOTSTRAP_OPERATION = "flow-internals-bootstrap"


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


def _staged_blob_sha(path: str, root: Path) -> str | None:
    """git's object id for the staged content of `path` (index side), or None.

    This is the exact bytes the pending commit would write for `path`; hashing
    over these ids binds an exception to one specific staged changeset.
    """
    try:
        proc = subprocess.run(
            ["git", "ls-files", "--stage", "--", path],
            capture_output=True, text=True, cwd=str(root),
        )
    except Exception:
        return None
    line = proc.stdout.strip()
    if not line:
        return None
    # `<mode> <object> <stage>\t<path>` — the object id is field 2.
    parts = line.split()
    return parts[1] if len(parts) >= 2 else None


def compute_staged_tree_digest(paths: list[str], root: Path) -> str:
    """Digest binding an exception to the exact staged content of `paths`.

    sha256 over sorted `<path>\\0<staged-blob-sha>` lines. A path with no staged
    content contributes `<path>\\0-`; a later, unrelated edit changes the set of
    staged blob ids, so the digest no longer matches (the single-use property).
    """
    lines = sorted(f"{p}\0{_staged_blob_sha(p, root) or '-'}" for p in paths)
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def has_active_exception(
    path: str, root: Path | None = None, *, category: str | None = None
) -> bool:
    """True iff a non-expired approval artifact authorizes editing `path`.

    Backward-compatible for every category EXCEPT fusebase_flow_internals: for that
    category the artifact must ALSO carry operation == flow-internals-bootstrap and a
    tree_digest that matches the CURRENT staged content of its approved paths
    (single-use — a second unrelated protected-path edit changes the digest and
    still DENIES). Other categories keep plain path+TTL matching.
    """
    root = root or find_git_root()
    if category is None:
        _, category = is_protected(path)
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
        if not (path in approved_paths or any(_matches_any(path, [p]) for p in approved_paths)):
            continue
        if category == _BOOTSTRAP_CATEGORY:
            # Single-use gate: operation + staged-digest binding required. A plain
            # path+TTL artifact is NOT sufficient for the internals category.
            if data.get("operation") != _BOOTSTRAP_OPERATION:
                continue
            recorded = data.get("tree_digest", "")
            if not recorded:
                continue
            if recorded != compute_staged_tree_digest(list(approved_paths), root):
                continue
            return True
        return True
    return False


def evaluate(path: str, *, root: Path | None = None) -> PathDecision:
    protected, category = is_protected(path)
    if not protected:
        return PathDecision(path=path, protected=False, category=None, has_exception=False, decision="allow")
    exception = has_active_exception(path, root, category=category)
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


__all__ = [
    "PathDecision", "is_protected", "has_active_exception", "compute_staged_tree_digest",
    "evaluate", "evaluate_many",
]
