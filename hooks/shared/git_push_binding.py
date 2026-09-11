"""Fusebase Flow — git_push_binding: the ref updates a `git push` performs (profile git_push_v1).

Two inputs, one output shape (approval_artifact.canonical_updates):
  * resolve_command_updates — what a proposed push COMMAND would update, resolved before
    it runs (command gate + approve-local.sh writer share it, so they cannot drift);
  * boundary_updates — what git ACTUALLY hands the pre-push hook (the execution boundary).

TRIPWIRE: the resolver only has to be right when it answers. Anything it cannot resolve
exactly as git would — compound or dynamic shell text, an option that adds or remaps refs,
config that remaps destinations, an ambiguous source — returns None and the gate denies.
Widening what it accepts needs the git source behaviour cited, not a guess; the pre-push
boundary re-checks the real updates either way. Rationale: docs/backlog/approval-binding-omits-head/.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

from .approval_artifact import (
    PROFILE_GIT_PUSH, Update, canonical_endpoint, canonical_updates, valid_destination_ref,
)

__all__ = ["PROFILE_GIT_PUSH", "boundary_updates", "resolve_command_updates"]

_GIT_TIMEOUT = 30
# One plain `git push` invocation: no quoting, expansion, redirection or command chaining.
# TRIPWIRE: separators are space/tab ONLY — `\s` would accept a newline, i.e. a second
# command. A leading `+` (force refspec) or `~` (tilde expansion) is refused per token below.
_PLAIN_PUSH = re.compile(r"[ \t]*git[ \t]+push(?:[ \t]+[A-Za-z0-9._/@:+^~=,%-]+)*[ \t]*")
# Options that change neither which refs are pushed nor where.
_NEUTRAL_OPTIONS = frozenset({
    "-u", "--set-upstream", "-q", "--quiet", "-v", "--verbose", "--atomic", "--no-atomic",
    "--porcelain", "--progress", "--no-progress", "--no-recurse-submodules",
})
# TRIPWIRE: `--dry-run`/`-n` is NOT neutral for AUTHORIZATION, only for effect. git runs
# pre-push with the same update lines for a dry run, and that boundary cannot see the
# command, so an approval minted for a dry run would authorize the REAL push of the same
# objects — approve something that changes nothing, then push for real on it. A bindable
# command must be one whose execution performs exactly the updates it binds.
_DRY_RUN_OPTIONS = frozenset({"-n", "--dry-run"})
_ZERO_OID = re.compile(r"0{40}|0{64}")
_HEX_OID = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")

Resolution = tuple["tuple[Update, ...] | None", str]


def _git(root: Path, *args: str) -> tuple[int, str]:
    """(rc, stdout). rc -1 when git could not be run at all — callers fail closed."""
    try:
        proc = subprocess.run(["git", *args], cwd=str(root), capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=_GIT_TIMEOUT)
    except (OSError, subprocess.SubprocessError, ValueError):
        return -1, ""
    return proc.returncode, proc.stdout


def _config(root: Path) -> dict[str, list[str | None]] | None:
    """Effective config as {normalized key: values}, one git call; None when unreadable.

    Section and variable names are case-insensitive (lower-cased here); a subsection such
    as the remote name keeps its case. A value-less key (`[push] followTags`) is None.
    """
    rc, out = _git(root, "config", "--list", "-z")
    if rc != 0:
        return None
    values: dict[str, list[str | None]] = {}
    for entry in out.split("\0"):
        if not entry:
            continue
        key, newline, value = entry.partition("\n")
        section, _, rest = key.partition(".")
        sub, _, var = rest.rpartition(".")
        norm = f"{section.lower()}.{sub}.{var.lower()}" if sub else f"{section.lower()}.{var.lower()}"
        values.setdefault(norm, []).append(value if newline else None)
    return values


def _config_true(values: list[str | None]) -> bool:
    last = values[-1] if values else "false"
    return last is None or last.strip().lower() in ("true", "yes", "on", "1")


def _strong_refs(root: Path, name: str) -> list[str] | None:
    """Local refs `name` strongly matches under git's count_refspec_match, or None on error."""
    candidates = [f"refs/{name}", f"refs/tags/{name}", f"refs/heads/{name}"]
    if name.startswith("refs/"):
        candidates.insert(0, name)
    rc, out = _git(root, "for-each-ref", "--format=%(refname)", *candidates)
    if rc != 0:
        return None
    existing = set(out.split())
    return [c for c in dict.fromkeys(candidates) if c in existing]


def _oid(root: Path, rev: str) -> str | None:
    rc, out = _git(root, "rev-parse", "--verify", "--quiet", "--end-of-options", rev)
    value = out.strip()
    return value if rc == 0 and _HEX_OID.fullmatch(value) else None


def _source(root: Path, src: str) -> tuple[str | None, str]:
    """The object a refspec source pushes (match_explicit: unique ref first, then any rev)."""
    refs = _strong_refs(root, src)
    if refs is None:
        return None, "git for-each-ref failed"
    if len(refs) > 1:
        return None, f"source {src!r} matches more than one ref ({', '.join(refs)})"
    oid = _oid(root, refs[0] if refs else src)
    return (oid, "") if oid else (None, f"source {src!r} does not resolve to an object")


def _colonless(root: Path, spec: str) -> tuple[str | None, str | None, str]:
    """(destination, oid, reason) for a refspec without `:` — the destination is the source ref."""
    if spec == "HEAD":
        rc, out = _git(root, "symbolic-ref", "-q", "HEAD")
        full = out.strip()
        if rc != 0 or not full.startswith("refs/heads/"):
            return None, None, "HEAD is detached or unreadable; name the source and destination"
    else:
        refs = _strong_refs(root, spec)
        if refs is None:
            return None, None, "git for-each-ref failed"
        if len(refs) != 1:
            return None, None, (f"{spec!r} matches {len(refs)} local refs; use "
                                f"<source>:refs/heads/<branch>")
        full = refs[0]
    oid = _oid(root, full)
    return (full, oid, "") if oid else (None, None, f"{full} does not resolve")


def resolve_command_updates(command: str, root: Path | None) -> Resolution:
    """(canonical updates, "") the command would perform, or (None, reason) — fail closed."""
    if root is None:
        return None, "repository root unknown"
    if not _PLAIN_PUSH.fullmatch(command or ""):
        return None, ("not a single plain `git push <remote> <refspec>...` invocation "
                      "(chained, quoted or expanded shell text can change what is pushed)")
    tokens = command.split()[2:]
    delete_all, follow_tags, positional = False, None, []
    for tok in tokens:
        if tok.startswith(("+", "~")):
            return None, f"{tok!r}: forced or tilde-expanded refspecs are not bindable"
        if tok in _DRY_RUN_OPTIONS:
            return None, (f"{tok} performs no update, so it cannot authorize one: the pre-push "
                          f"boundary sees the same refs for a dry run as for the real push. "
                          f"Inspect with `git log <remote>/<branch>..<branch>` instead")
        if tok in ("-d", "--delete"):
            delete_all = True
        elif tok == "--no-follow-tags":
            follow_tags = False
        elif tok.startswith("-"):
            if tok not in _NEUTRAL_OPTIONS:
                return None, f"option {tok} is not supported for a bound push"
        else:
            positional.append(tok)
    if len(positional) < 2:
        return None, "name the remote and every refspec explicitly (git push <remote> <refspec>...)"
    remote, specs = positional[0], positional[1:]

    rc, out = _git(root, "remote")
    if rc != 0:
        return None, "git remote failed"
    if remote not in out.split():
        return None, f"{remote!r} is not a configured remote; push to a named remote"
    cfg = _config(root)
    if cfg is None:
        return None, "git config could not be read"
    last = {k: (v[-1] or "").strip().lower() for k, v in cfg.items() if v}
    remaps = [
        (_config_true(cfg.get(f"remote.{remote}.mirror", [])), f"remote.{remote}.mirror"),
        (last.get("push.recursesubmodules") in ("on-demand", "only"), "push.recurseSubmodules"),
        (follow_tags is None and _config_true(cfg.get("push.followtags", [])), "push.followTags"),
    ]
    if any(":" not in s for s in specs) and not delete_all:
        remaps.append((bool(cfg.get(f"remote.{remote}.push")), f"remote.{remote}.push"))
        remaps.append((last.get("push.default") in ("upstream", "tracking"), "push.default"))
    for hit, label in remaps:
        if hit:
            return None, f"{label} adds or remaps pushed refs; use <source>:refs/<full destination>"

    rc, out = _git(root, "remote", "get-url", "--push", "--all", remote)
    urls = [u for u in out.splitlines() if u.strip()] if rc == 0 else []
    if not urls:
        return None, f"push URL of {remote!r} could not be read"
    endpoints = [canonical_endpoint(u) for u in urls]
    if any(e is None for e in endpoints):
        return None, "a push URL carries a query/fragment or is unusable as an endpoint identity"

    refs: list[tuple[str, str | None, str]] = []
    for spec in specs:
        if delete_all or spec.startswith(":"):
            dst = spec[1:] if spec.startswith(":") else spec
            if ":" in dst or not valid_destination_ref(dst):
                return None, f"deleted ref {dst!r} must be fully qualified (refs/heads/<name>)"
            refs.append((dst, None, "delete"))
        elif ":" in spec:
            src, dst = spec.split(":", 1)
            if not src or not valid_destination_ref(dst):
                return None, f"destination {dst!r} must be fully qualified (refs/heads/<name>)"
            oid, why = _source(root, src)
            if oid is None:
                return None, why
            refs.append((dst, oid, "update"))
        else:
            dst, oid, why = _colonless(root, spec)
            if dst is None:
                return None, why
            refs.append((dst, oid, "update"))
    if len({r[0] for r in refs}) != len(refs):
        return None, "two refspecs update the same destination"
    entries = [{"push_endpoint": e, "destination_ref": d, "source_oid": o, "operation": op}
               for e in dict.fromkeys(endpoints) for d, o, op in refs]
    updates = canonical_updates(entries)
    return (updates, "") if updates else (None, "resolved updates failed validation")


def boundary_updates(url: str, lines: list[str]) -> Resolution:
    """(canonical updates, "") from pre-push stdin lines for one endpoint, or (None, reason).

    Line = `<local ref> SP <local oid> SP <remote ref> SP <remote oid>`; a deletion carries
    the all-zero local oid. An empty list is a push with nothing to update (all up to date).
    """
    endpoint = canonical_endpoint(url)
    if endpoint is None:
        return None, "the push URL is unusable as an endpoint identity"
    entries = []
    for line in lines:
        parts = line.strip().split(" ")
        if not line.strip():
            continue
        if len(parts) != 4 or not _HEX_OID.fullmatch(parts[1]):
            return None, "unreadable pre-push update line"
        delete = bool(_ZERO_OID.fullmatch(parts[1]))
        entries.append({"push_endpoint": endpoint, "destination_ref": parts[2],
                        "source_oid": None if delete else parts[1],
                        "operation": "delete" if delete else "update"})
    if not entries:
        return (), ""
    updates = canonical_updates(entries)
    return (updates, "") if updates else (None, "pre-push updates failed validation")
