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
# artifact must bind to the exact staged changeset (tree_digest over content+mode)
# AND the exact operation, use EXACT path membership (no glob fallback, and any glob
# metacharacter in an approved_path invalidates the artifact), and require every
# approved_path to actually be staged. A second, unrelated protected-path edit
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


# TRIPWIRE (WS1b): the internals-bootstrap category treats ANY approved_path
# carrying a glob metacharacter as an invalid artifact — a wildcard must never
# bind a concrete queried path. Keep in sync with the metacharacters git/fnmatch
# would expand (`*`, `?`, `[`, and the `**` recursive form).
def _has_glob_meta(pattern: str) -> bool:
    return any(ch in pattern for ch in ("*", "?", "["))


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


# FR-07 fail-closed at the POLICY load-point (T27/#5): a missing/empty/malformed
# protected-paths.yml made get_policy return {} -> _load_categories() {} -> is_protected
# always False -> FR-07 fully OFF, silently. The enforcement point (pre-commit §3) must
# refuse to run against an absent policy rather than wave every protected edit through.
# Scoped to FR-07: this validates ONLY the protected-paths policy; get_policy for other
# policies is unchanged.
_PROTECTED_SENTINEL_CATEGORY = "fusebase_flow_internals"


def assert_protected_policy_loaded(root: Path | None = None) -> None:
    """Raise RuntimeError unless the protected-paths policy is present + enforceable.

    Enforceable = a mapping carrying a non-empty `fusebase_flow_internals` category with
    a non-empty `paths` list (the Flow-internals sentinel that must always be protected).
    A missing file, a non-mapping, an absent/empty categories map, or an emptied sentinel
    category all mean FR-07 cannot be enforced -> fail closed.
    """
    policy = get_policy("protected-paths", root=root)
    if not isinstance(policy, dict) or not policy:
        raise RuntimeError(
            "protected-paths policy missing/empty; cannot enforce FR-07; "
            "fix policies/protected-paths.yml"
        )
    cats = policy.get("categories")
    if not isinstance(cats, dict) or not cats:
        raise RuntimeError(
            "protected-paths policy has no categories; cannot enforce FR-07; "
            "fix policies/protected-paths.yml"
        )
    sentinel = cats.get(_PROTECTED_SENTINEL_CATEGORY)
    paths = (sentinel or {}).get("paths") if isinstance(sentinel, dict) else None
    if not paths:
        raise RuntimeError(
            f"protected-paths policy has no non-empty '{_PROTECTED_SENTINEL_CATEGORY}' "
            "category; cannot enforce FR-07; fix policies/protected-paths.yml"
        )


def _staged_mode_and_sha(path: str, root: Path) -> tuple[str, str] | None:
    """(mode, object-id) for the staged content of the EXACT `path`, or None.

    `path` MUST be a concrete file path, never a glob: a glob pathspec makes
    `git ls-files --stage` emit MANY lines, and the old field-2-of-strip() parse
    silently kept only the alphabetically-first blob (both reviews flagged this).
    We parse PER LINE and return the line whose trailing `\\t<path>` matches `path`
    exactly, so a single concrete lookup is unambiguous and a multi-match glob can
    never bind. Mode is field 1 (from `git ls-files --stage`), object id is field 2.
    """
    try:
        proc = subprocess.run(
            ["git", "ls-files", "--stage", "--", path],
            capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=str(root),
        )
    except Exception:
        return None
    for line in proc.stdout.splitlines():
        if not line:
            continue
        # `<mode> <object> <stage>\t<path>`; split the trailing path off the tab.
        head, _, entry_path = line.partition("\t")
        if entry_path != path:
            continue
        parts = head.split()
        if len(parts) >= 2:
            return parts[0], parts[1]   # (mode, object-id)
    return None


def staged_change_paths(root: Path) -> list[str]:
    """Every path touched by the pending commit, including DELETES + RENAMES.

    `git diff --cached --name-status -M`: A/C/M -> the path; D -> the deleted path;
    R -> BOTH the old (source, leaving protection) and new (destination) path. The
    ACM-only `--name-only` set the pre-commit used to gate on silently dropped
    deletes and rename sources, so a `git rm`/rename of a protected file never
    reached path_policy (the shipped FR-07 bypass). Returns concrete paths only —
    a single-use approval still binds each via compute_staged_tree_digest.

    FAIL-CLOSED (T27/#4): the enumeration must never SILENTLY hand back a partial or
    empty list on a git failure. `subprocess.run` does NOT raise on a nonzero rc, so a
    truncated `--name-status` (nonzero rc + partial stdout) previously yielded a
    nonempty-but-INCOMPLETE list that could miss a protected path. On EITHER a
    subprocess exception OR a nonzero returncode we RAISE — the pre-commit body wrapper
    (BaseException, T27/#3) catches it and BLOCKS; other callers must tolerate the raise
    fail-closed (see has_active_exception / pre_tool_use). rc0 parses normally (an empty
    list is the LEGITIMATE no-staged-changes case).
    """
    try:
        proc = subprocess.run(
            ["git", "diff", "--cached", "--name-status", "-M"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=str(root),
        )
    except Exception as e:
        raise RuntimeError(f"staged_change_paths: git name-status subprocess failed ({e!r})") from e
    if proc.returncode != 0:
        raise RuntimeError(
            f"staged_change_paths: git name-status failed rc={proc.returncode} "
            "(refusing a partial/incomplete staged set — FR-07 fail-closed)"
        )
    out: list[str] = []
    for line in proc.stdout.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        status = fields[0]
        if status and status[0] == "R" and len(fields) >= 3:
            out.append(fields[1])   # rename source (leaving protection)
            out.append(fields[2])   # rename destination
        elif len(fields) >= 2:
            out.append(fields[1])   # A/C/M/D path
    # Preserve first-seen order, drop dups (a rename's src/dst never collide).
    seen: set[str] = set()
    return [p for p in out if not (p in seen or seen.add(p))]


def compute_staged_tree_digest(paths: list[str], root: Path) -> str:
    """Digest binding an exception to the exact staged content+mode of `paths`.

    sha256 over sorted `<path>\\0<mode>\\0<staged-blob-sha>` lines. A path with no
    staged content contributes `<path>\\0-\\0-`; a later, unrelated edit (or a mode
    flip) changes the set of staged (mode, blob) pairs, so the digest no longer
    matches (the single-use property). `write-bootstrap-approval.sh` calls THIS
    same function on concrete `git diff --cached` paths, so writer and verifier
    never drift.
    """
    def _entry(p: str) -> str:
        ms = _staged_mode_and_sha(p, root)
        return f"{p}\0{ms[0]}\0{ms[1]}" if ms else f"{p}\0-\0-"
    lines = sorted(_entry(p) for p in paths)
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
        if category == _BOOTSTRAP_CATEGORY:
            # Single-use gate for the internals-bootstrap category. Hardened (WS1b,
            # both reviews): EXACT membership only — a glob approved_path like
            # `hooks/shared/**` must NOT match a concrete queried path, so the glob
            # fallback (`_matches_any`) that other categories keep is DROPPED here.
            if path not in approved_paths:
                continue
            # A crafted wildcard artifact can never bind: any glob metacharacter in
            # ANY approved_path invalidates the whole artifact for this category.
            if any(_has_glob_meta(p) for p in approved_paths):
                continue
            # operation + staged-digest binding required; a plain path+TTL artifact
            # is NOT sufficient for the internals category.
            if data.get("operation") != _BOOTSTRAP_OPERATION:
                continue
            recorded = data.get("tree_digest", "")
            if not recorded:
                continue
            # An approvable internals path must actually be IN the pending commit.
            # A path with staged content (A/C/M) has a blob; a DELETE or rename-SOURCE
            # legitimately has NO staged blob yet is genuinely staged — so "no blob"
            # is acceptable ONLY when the path is in the staged change set (T23:
            # delete/rename coverage). A path entirely absent from the commit (no blob
            # AND not staged) is still rejected — an artifact cannot approve a path the
            # pending commit never touches. The digest (with the `-\0-` placeholder for
            # the deleted path) still binds the artifact single-use to THIS changeset.
            staged_set = set(staged_change_paths(root))
            if any(
                _staged_mode_and_sha(p, root) is None and p not in staged_set
                for p in approved_paths
            ):
                continue
            if recorded != compute_staged_tree_digest(list(approved_paths), root):
                continue
            return True
        # Non-bootstrap categories: backward-compatible plain path+TTL matching
        # (exact membership OR glob).
        if path in approved_paths or any(_matches_any(path, [p]) for p in approved_paths):
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
    "staged_change_paths", "evaluate", "evaluate_many", "assert_protected_policy_loaded",
]
