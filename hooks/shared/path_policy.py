"""Fusebase Flow — path_policy.

Reads policies/protected-paths.yml and checks whether a given path is protected,
plus whether an exception artifact exists in state/approvals/.
"""
from __future__ import annotations

import fnmatch
import hashlib
import subprocess
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Any

from .approval_artifact import (
    accept_with_audit, compute_repo_id, evaluate_artifact, lifetime_problem, load as load_artifact, now_utc, parse_expiry,
)
from .policy_loader import find_git_root, get_policy

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # no console window when the caller has none (pythonw)

# WS1b: the internals-bootstrap category demands a genuinely SINGLE-USE exception.
# A plain path+TTL artifact is a reusable FR-07 bypass, so for this category the
# artifact must bind to the exact staged changeset (tree_digest over content+mode)
# AND the exact operation, use EXACT path membership (no glob fallback, and any glob
# metacharacter in an approved_path invalidates the artifact), and require every
# approved_path to actually be staged. A second, unrelated protected-path edit
# produces a different staged digest -> no match -> still DENIES.
#
# MAJOR 11 (final-architecture-review finding 11): the digest-bound contract was written
# for ONE category while `ci_cd_config` — the category that actually gates
# `.github/workflows/**`, the release machinery itself — accepted a plain, reusable
# path+TTL artifact. The published protocol (role-discipline shared-protocols § FR-07)
# told the agent to mint a "digest-bound" approval for a workflow edit, and no shipped
# writer/consumer pair could produce or enforce one. The category->operation map below is
# the single place that contract is stated, for writer (write-bootstrap-approval.sh) and
# verifier (this module) alike.
_DIGEST_BOUND_OPERATIONS = {
    "fusebase_flow_internals": "flow-internals-bootstrap",
    "ci_cd_config": "ci-workflow-edit",
}
# 6.0.0-m8 (M6-6, review r2-26): EVERY category is digest-bound and single use; a plain path+TTL artifact for
# fusebase.json or a migration was accepted, and kept authorizing later changes. Another category's operation is
# `<category>-edit`. A digest-bound approval lives at most EDIT_MAX_MINUTES (protected_path_edit's shipped
# artifact_ttl_minutes; the policy may lower it), records `minted_on`, the commit HEAD was at, and the commit that lands
# on it spends it, as the go-ahead's does.
EDIT_MAX_MINUTES = 60
_BOOTSTRAP_CATEGORY = "fusebase_flow_internals"
_BOOTSTRAP_OPERATION = _DIGEST_BOUND_OPERATIONS[_BOOTSTRAP_CATEGORY]
# The operator's go-ahead, minted BEFORE the edit (write-bootstrap-approval.sh --paths): the same operation, the named
# paths and `head_at_mint` instead of a tree_digest. It covers the agent's Edit/Write of those paths and the commit of
# exactly them while HEAD stays where it was minted; the commit that lands moves HEAD and so spends it (brief m6 (9)).
GO_AHEAD_MAX_MINUTES = 30


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


class ApprovalPolicyError(RuntimeError):
    """approval-policy could not be loaded, so approvals cannot be evaluated at all."""


def _strict_approvals(root: Path | None) -> bool:
    """K7 mode flag. FAIL-CLOSED: a policy that will not load RAISES.

    Swallowing the error and returning False was an actual fail-open path: approval-policy is
    the file that says HOW STRICT acceptance is, so a local file that enables strict_approvals
    and also carries an invalid/raised stale_approval_warn_after_days disabled its own strict
    mode. command_policy already denies on a policy load failure; this matches it. Callers that
    do not catch ApprovalPolicyError inherit the raise, which the pre-commit body wrapper turns
    into a BLOCK (same contract as staged_change_paths).
    """
    try:
        return get_policy("approval-policy", root=root).get("strict_approvals") is True
    except BaseException as e:                       # noqa: BLE001 — load errors must not pass
        raise ApprovalPolicyError(
            f"approval-policy could not be loaded ({e!r}); FR-07 approval evaluation cannot run "
            "— fix policies/approval-policy.yml / approval-policy.local.yml"
        ) from e


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


# TRIPWIRE (6.0.0-m8 item 10, O-31 (j)): the index is read ONCE per process and again only when the index file
# changes (size, mtime). One `git ls-files` per approved path per staged path per artifact made the protected-path
# stage O(n^2) git calls: 830 s for a fresh install's 85 paths on a loaded host.
_INDEX: dict[str, tuple] = {}
_MEMO: dict[tuple, object] = {}


def _index_stamp(root: Path) -> tuple | None:
    key = ("index-file", str(root))
    if key not in _MEMO:
        try:
            proc = subprocess.run(["git", "rev-parse", "--git-path", "index"], capture_output=True, text=True,
                                  encoding="utf-8", errors="replace", cwd=str(root), creationflags=NO_WINDOW)
            rel = proc.stdout.strip() if proc.returncode == 0 else ""
        except Exception:
            rel = ""
        _MEMO[key] = (Path(rel) if Path(rel).is_absolute() else Path(root) / rel) if rel else None
    index = _MEMO[key]
    try:
        st = index.stat() if index else None
    except OSError:
        return None
    return (st.st_mtime_ns, st.st_size, st.st_ino) if st else None


def _staged_entries(root: Path) -> dict[str, tuple[str, str]] | None:
    """{path: (mode, object-id)} of the whole index (stage 0, else the first stage listed), from one
    `git ls-files --stage -z`; None when git fails."""
    stamp = _index_stamp(root)
    hit = _INDEX.get(str(root))
    if stamp is not None and hit and hit[0] == stamp:
        return hit[1]
    try:
        proc = subprocess.run(["git", "ls-files", "--stage", "-z"], capture_output=True, cwd=str(root),
                              creationflags=NO_WINDOW)
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    entries: dict[str, tuple[str, str]] = {}
    for record in proc.stdout.decode("utf-8", "surrogateescape").split("\0"):
        head, _, entry_path = record.partition("\t")
        parts = head.split()
        if entry_path and len(parts) >= 2:
            entries.setdefault(entry_path, (parts[0], parts[1]))
    if stamp is not None:
        _INDEX[str(root)] = (stamp, entries)
    return entries


def _staged_mode_and_sha(path: str, root: Path) -> tuple[str, str] | None:
    """(mode, object-id) for the staged content of the EXACT `path`, or None.

    `path` MUST be a concrete file path, never a glob: a glob pathspec makes
    `git ls-files --stage` emit MANY lines, and the old field-2-of-strip() parse
    silently kept only the alphabetically-first blob (both reviews flagged this).
    We parse PER LINE and return the line whose trailing `\\t<path>` matches `path`
    exactly, so a single concrete lookup is unambiguous and a multi-match glob can
    never bind. Mode is field 1 (from `git ls-files --stage`), object id is field 2.
    """
    entries = _staged_entries(root)
    if entries is not None:
        return entries.get(path)
    try:
        proc = subprocess.run(
            ["git", "ls-files", "--stage", "--", path],
            capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=str(root), creationflags=NO_WINDOW
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
            capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=str(root), creationflags=NO_WINDOW
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


def operation_for(category: str | None) -> str | None:
    """The single-use operation an approval for `category` carries, or None for no category."""
    return (_DIGEST_BOUND_OPERATIONS.get(category) or f"{category.replace('_', '-')}-edit") if category else None


def edit_cap(root: Path) -> int:
    """EDIT_MAX_MINUTES, lowered (never raised) by approval-policy's protected_path_edit artifact_ttl_minutes."""
    ops = get_policy("approval-policy", root=root).get("require_approval") or {}
    ttl = (ops.get("protected_path_edit") or {}).get("artifact_ttl_minutes") if isinstance(ops, dict) else None
    return min(EDIT_MAX_MINUTES, ttl) if isinstance(ttl, int) and not isinstance(ttl, bool) and ttl > 0 else EDIT_MAX_MINUTES


def _unspent(data: dict, root: Path) -> bool:
    """The approval was minted at the commit HEAD is at, and no commit has landed on that commit since (fails closed)."""
    minted = data.get("minted_on")
    if not isinstance(minted, str) or minted.strip() != _head(root):
        return False
    return not minted.strip() or not _built_on(root, minted.strip(), str(data.get("created_at") or ""))


def _head(root: Path) -> str:
    key = ("head", str(root), _index_stamp(root))
    if key[2] is not None and key in _MEMO:
        return _MEMO[key]
    _MEMO[key] = found = _head_now(root)
    return found


def _head_now(root: Path) -> str:
    try:
        proc = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD^{commit}"], capture_output=True, text=True,
                              cwd=str(root), creationflags=NO_WINDOW)
    except Exception:
        return ""
    return proc.stdout.strip() if proc.returncode == 0 else ""


def _built_on(root: Path, head: str, since: str) -> bool:
    """Whether a commit made since the mint has `head` as a parent, in any ref or reflog: the go-ahead's commit landed,
    even if HEAD went back to `head` since (git reset --soft, a branch or a detached HEAD there). Fails closed."""
    key = ("built-on", str(root), head, since, _index_stamp(root))
    if key[4] is not None and key in _MEMO:
        return _MEMO[key]
    _MEMO[key] = found = _built_on_now(root, head, since)
    return found


def _built_on_now(root: Path, head: str, since: str) -> bool:
    when = [f"--since={since}"] if parse_expiry(since) is not None else []
    try:
        proc = subprocess.run(["git", "rev-list", "--all", "--reflog", "--parents", *when], capture_output=True,
                              text=True, encoding="utf-8", errors="replace", cwd=str(root), creationflags=NO_WINDOW)
    except Exception:
        return True
    return proc.returncode != 0 or any(head in line.split()[1:] for line in proc.stdout.splitlines())


def _go_ahead_holds(data: dict, path: str, approved: list[str], root: Path, artifact: Path, category: str) -> bool:
    """A go-ahead artifact authorizes `path` while HEAD is the commit it was minted at, its expiry is at most
    GO_AHEAD_MAX_MINUTES away, and every staged path is one it names (the commit touches only those). Each use
    leaves an audit line."""
    head, expires = data.get("head_at_mint"), parse_expiry(data.get("expires_at"))
    if not isinstance(head, str) or not head.strip() or expires is None:
        return False
    if expires - now_utc() > timedelta(minutes=GO_AHEAD_MAX_MINUTES + 1) or head.strip() != _head(root):
        return False
    if _built_on(root, head.strip(), str(data.get("created_at") or "")):
        return False
    if not set(staged_change_paths(root)) <= set(approved):
        return False
    try:
        from .audit_logger import emit
        emit("approval_go_ahead", decision="allow", rule_id="FR-07",
             reason=f"FR-07: {path} ({category}) allowed by {artifact.name}, the operator's go-ahead for the paths it "
                    f"names, while HEAD stays at {head.strip()[:12]}",
             extra={"artifact": artifact.name, "path": path, "category": category, "head_at_mint": head.strip()},
             root=root)
    except BaseException:                        # noqa: BLE001 — logging never gates
        pass
    return True


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

    Every category (6.0.0-m8 M6-6): the artifact carries the category's exact `operation` and a tree_digest that matches
    the CURRENT staged content of its approved paths, lives at most edit_cap() minutes and is unspent (`minted_on`), so
    it is single use; or, in the go-ahead form, `head_at_mint` (_go_ahead_holds; never a CI workflow).
    """
    root = root or find_git_root()
    if category is None:
        _, category = is_protected(path)
    expected_operation = operation_for(category)
    # Read the policy FIRST: an unloadable approval policy must deny even when the
    # approvals directory is absent, so the outcome never depends on which check ran first.
    _strict_approvals(root)
    approvals_dir = root / "state" / "approvals"
    if expected_operation is None or not approvals_dir.exists():
        return False
    cap = edit_cap(root)
    staged_set: set[str] | None = None
    for f in approvals_dir.glob("protected_path_edit-*.json"):
        artifact = load_artifact(f)
        if artifact is None or artifact.data is None:
            continue
        data = artifact.data
        # Expiry/schema are the SHARED semantics (decision K1) — the same parsed-datetime
        # comparison command_policy uses, replacing the `expires and expires < now` string
        # compare that read a missing/empty expiry as valid forever. K17 pass-sets: the
        # bootstrap category accepts VALID only; other categories keep compat unless
        # strict_approvals is on. The digest/operation/exact-path checks below are
        # UNCHANGED and ADDITIONAL to this.
        # repo_id binding (MAJOR 11): approve-local.sh RECORDS a repo_id, and this consumer
        # passed none — so `_binding_ok` saw a recorded-but-unobserved binding and returned
        # BINDING_MISMATCH for every artifact that writer produced. The documented mint path
        # could not authorize anything, silently. Supplying the real repo id makes the
        # recorded binding VERIFIABLE (and still rejects an artifact carried into another
        # checkout), instead of making every bound artifact unusable.
        verdict = evaluate_artifact(data, expected_action="protected_path_edit",
                                    repo_id=compute_repo_id(root))
        if not accept_with_audit(verdict, strict=True, carrier="path_policy",
                                 artifact_path=f, action="protected_path_edit", root=root):
            continue
        approved_paths = data.get("paths") or []
        if True:  # every category is digest-bound (6.0.0-m8 M6-6); the block keeps its indentation
            # Single-use gate for every digest-bound category. Hardened (WS1b,
            # both reviews): EXACT membership only — a glob approved_path like
            # `hooks/shared/**` must NOT match a concrete queried path, so the glob
            # fallback (`_matches_any`) that other categories keep is DROPPED here.
            if path not in approved_paths:
                continue
            # A crafted wildcard artifact can never bind: any glob metacharacter in
            # ANY approved_path invalidates the whole artifact for this category.
            if any(_has_glob_meta(p) for p in approved_paths):
                continue
            # operation + staged-digest binding required; a plain path+TTL artifact is NOT
            # sufficient for a digest-bound category. The operation is category-SPECIFIC, so
            # an internals approval cannot be replayed to authorize a workflow edit.
            if data.get("operation") != expected_operation:
                continue
            if "head_at_mint" in data:  # the go-ahead form: no tree_digest; it binds HEAD; never a CI workflow
                if category != "ci_cd_config" and _go_ahead_holds(data, path, list(approved_paths), root, f, category):
                    return True
                continue
            recorded = data.get("tree_digest", "")
            if not recorded or lifetime_problem(data, cap) or not _unspent(data, root):
                continue
            # An approvable internals path must actually be IN the pending commit.
            # A path with staged content (A/C/M) has a blob; a DELETE or rename-SOURCE
            # legitimately has NO staged blob yet is genuinely staged — so "no blob"
            # is acceptable ONLY when the path is in the staged change set (T23:
            # delete/rename coverage). A path entirely absent from the commit (no blob
            # AND not staged) is still rejected — an artifact cannot approve a path the
            # pending commit never touches. The digest (with the `-\0-` placeholder for
            # the deleted path) still binds the artifact single-use to THIS changeset.
            if staged_set is None:
                staged_set = set(staged_change_paths(root))
            if any(
                _staged_mode_and_sha(p, root) is None and p not in staged_set
                for p in approved_paths
            ):
                continue
            if recorded != compute_staged_tree_digest(list(approved_paths), root):
                continue
            return True
    return False


def evaluate(path: str, *, root: Path | None = None) -> PathDecision:
    protected, category = is_protected(path)
    if not protected:
        return PathDecision(path=path, protected=False, category=None, has_exception=False, decision="allow")
    try:
        exception = has_active_exception(path, root, category=category)
    except ApprovalPolicyError as e:
        # DENY regardless of on_unapproved_edit: with no loadable approval policy there is no
        # basis for accepting any exception artifact, so `warn` would be a configuration-driven
        # FR-07 bypass.
        return PathDecision(
            path=path, protected=True, category=category, has_exception=False, decision="deny",
            reason=f"FR-07 fail-closed: {e}",
        )
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
    "ApprovalPolicyError", "PathDecision", "is_protected", "has_active_exception",
    "compute_staged_tree_digest", "staged_change_paths", "evaluate", "evaluate_many",
    "assert_protected_policy_loaded", "GO_AHEAD_MAX_MINUTES", "EDIT_MAX_MINUTES", "edit_cap", "operation_for",
]
