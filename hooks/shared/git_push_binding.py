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
    PROFILE_GIT_PUSH, Update, bindable_endpoint, canonical_updates, has_record_separator,
    valid_destination_ref,
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
    """(rc, stdout). rc -1 when git could not be run at all — callers fail closed.

    TRIPWIRE: decoding is BYTE-PRESERVING (`surrogateescape`), never `errors="replace"`.
    Replacement rewrites an undecodable byte into U+FFFD, which is a transformation of an
    identity: two different remotes could decode to the same stored endpoint. Surrogates are
    refused downstream by has_record_separator, so such a remote cannot be bound at all.
    """
    try:
        proc = subprocess.run(["git", *args], cwd=str(root), capture_output=True,
                              timeout=_GIT_TIMEOUT)
    except (OSError, subprocess.SubprocessError, ValueError):
        return -1, ""
    return proc.returncode, proc.stdout.decode("utf-8", "surrogateescape")


def _one_line(out: str) -> str | None:
    """The single value git printed, or None when its output is not exactly one record.

    TRIPWIRE - THIS IS THE ONLY WAY GIT OUTPUT BECOMES A VALUE HERE, and it is not a split:
    the output must end with exactly one LF and contain no other LF, so a value carrying a
    separator FAILS instead of being trimmed or divided. Every enumerate-and-parse read was
    deleted (`git remote`, `for-each-ref`, `get-url --all`) because each review round found a
    new way to forge or lose one of their records: `%(refname)%00` turned out to emit NUL AND
    LF, and dropping empty fields let a changed URL keep a matching count. Ask git one
    question, take one answer or an error; never reconstruct git's own selection rules.
    """
    if not out.endswith("\n") or out.count("\n") != 1:
        return None
    return out[:-1]


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


#: git's own spellings for `push.default` (config.c compares them with strcmp, so this is
#: case-SENSITIVE and untrimmed). `upstream`/`tracking` remap a colon-less destination; the
#: rest leave it alone. Anything else is a value git itself rejects -> refuse.
_PUSH_DEFAULT_SAFE = ("nothing", "current", "simple", "matching")
_PUSH_DEFAULT_REMAPS = ("upstream", "tracking")


def _present(cfg: dict, key: str) -> bool:
    """TRIPWIRE: PRESENCE, not interpretation. Reading a config value means deciding what git
    would do with it, and two rounds of review were spent on boolean spellings (`off`, `0`, ``
    are valid false; `"false\n"` is not a boolean at all). A key that can add or remap pushed
    refs therefore refuses when it is set AT ALL, and the denial names how to proceed. Same
    move as refusing a path that merely CARRIES a filter attribute instead of interpreting it.
    """
    return bool(cfg.get(key))


def _oid(root: Path, rev: str) -> str | None:
    """The object `rev` names, asked as ONE question with one answer or an error."""
    rc, out = _git(root, "rev-parse", "--verify", "--quiet", "--end-of-options", rev)
    value = _one_line(out) if rc == 0 else None
    return value if value and _HEX_OID.fullmatch(value) else None


def _named_ref(root: Path, name: str) -> tuple[str | None, str]:
    """(the one local ref `name` names, "") or (None, reason) — ambiguity REFUSES.

    git's own rule: `refs/heads/<name>` and `refs/tags/<name>` are both strong matches, and it
    refuses a push whose source matches more than one ("src refspec … matches more than one").
    Each candidate is probed by EXACT full name, so nothing enumerates refs and nothing
    reconstructs git's disambiguation order; a weak match (refs/remotes/…) is not resolved here
    at all, which is the conservative direction.
    """
    if name.startswith("refs/"):
        return (name, "") if _oid(root, name) else (None, f"{name!r} is not a local ref")
    found = [full for full in (f"refs/heads/{name}", f"refs/tags/{name}") if _oid(root, full)]
    if len(found) > 1:
        return None, (f"{name!r} names both a branch and a tag; git refuses that push as "
                      f"ambiguous — use <source>:refs/heads/<branch>")
    return (found[0], "") if found else (None, "")


def _source(root: Path, src: str) -> tuple[str | None, str]:
    """The object a refspec source pushes (match_explicit: unique ref first, then any rev)."""
    full, why = _named_ref(root, src)
    if why:
        return None, why
    oid = _oid(root, full or src)
    return (oid, "") if oid else (None, f"source {src!r} does not resolve to an object")


def _colonless(root: Path, spec: str) -> tuple[str | None, str | None, str]:
    """(destination, oid, reason) for a refspec without `:` — the destination is the source ref."""
    if spec == "HEAD":
        rc, out = _git(root, "symbolic-ref", "-q", "HEAD")
        full = _one_line(out) if rc == 0 else None
        if not full or not full.startswith("refs/heads/") or not valid_destination_ref(full):
            return None, None, "HEAD is detached or unreadable; name the source and destination"
    else:
        full, why = _named_ref(root, spec)
        if full is None:
            return None, None, why or (f"{spec!r} is not a local ref; use "
                                       f"<source>:refs/heads/<branch>")
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

    cfg = _config(root)
    if cfg is None:
        return None, "git config could not be read"
    # Membership comes from the NUL-framed config, not from parsing `git remote` output:
    # config records cannot be forged by a value, and a name list cannot carry its own framing.
    if not any(k.startswith(f"remote.{remote}.") for k in cfg):
        return None, (f"{remote!r} is not a configured remote (or is defined in a legacy "
                      f".git/remotes file, which cannot be bound); push to a named remote")
    set_keys = [f"remote.{remote}.mirror", "push.recursesubmodules"]
    if follow_tags is None:                # --no-follow-tags already settles that question
        set_keys.append("push.followtags")
    if any(":" not in spec for spec in specs) and not delete_all:
        set_keys.append(f"remote.{remote}.push")
    for key in set_keys:
        if _present(cfg, key):
            return None, (f"{key} is set; it can add or remap the refs a push updates, and this "
                          f"gate does not interpret its value. Unset it for this push, or use "
                          f"<source>:refs/<full destination>")
    if any(":" not in spec for spec in specs) and not delete_all:
        value = (cfg.get("push.default") or [None])[-1]
        if value is not None and value not in _PUSH_DEFAULT_SAFE:
            reason = ("remaps a colon-less destination to its upstream"
                      if value in _PUSH_DEFAULT_REMAPS
                      else "holds a value git itself rejects")
            return None, (f"push.default {reason}; use <source>:refs/<full destination>")

    # ONE destination per approval. A multi-URL remote pushes to several repositories in one
    # command, and picking from a list is exactly the enumeration every round found a way to
    # forge — so it refuses and names the remedy. The count comes from NUL-framed config
    # (unforgeable); the URL itself comes from a single-value read with a trailing-LF contract.
    raw = cfg.get(f"remote.{remote}.pushurl") or cfg.get(f"remote.{remote}.url") or []
    if not raw:
        return None, f"{remote!r} has no configured URL to bind"
    if len(raw) > 1:
        return None, (f"{remote!r} has {len(raw)} push URLs, so one push updates several "
                      f"repositories; approve each destination separately through a "
                      f"single-URL remote")
    if raw[0] is None or has_record_separator(raw[0]):
        return None, (f"the configured URL of {remote!r} contains a line or record separator; "
                      f"an endpoint is compared byte-exact and cannot carry one")
    rc, out = _git(root, "remote", "get-url", "--push", remote)
    url = _one_line(out) if rc == 0 else None
    if url is None:
        return None, (f"push URL of {remote!r} could not be read as exactly one value "
                      f"(a URL carrying a line separator is refused, never trimmed)")
    endpoints = [bindable_endpoint(url)]
    if endpoints[0] is None:
        return None, "the push URL is not a bindable endpoint form"

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
    endpoint = bindable_endpoint(url)
    if endpoint is None:
        return None, "the push URL is unusable as an endpoint identity"
    entries = []
    for line in lines:
        if not line:
            continue
        # Fields are separated by exactly one space and nothing is trimmed: a ref name may
        # carry other line-ish characters, and trimming would bind a neighbouring identity.
        parts = line.split(" ")
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
