"""Fusebase Flow — approval_artifact: the single canonical approval-artifact reader.

Owns every artifact-reading concern that used to be duplicated across
command_policy.py, path_policy.py and hooks/local/lib/active-approvals.sh:
load, schema detection, expiry parsing, action agreement, binding checks.

Contract (decision K17): a Verdict is artifact STATE only. Acceptability is the
separate predicate is_acceptable(verdict, strict=...), so each carrier declares
its own pass-set and the loader never needs to know who called it.

Two contracts live here. `evaluate_artifact` judges protected-path and deferral
artifacts (schema 1/2, binding enforced when present). `evaluate_command_approval`
judges COMMAND approvals: schema 3 only, every binding mandatory, VALID the only
acceptable verdict whatever `strict_approvals` says (docs/backlog/approval-binding-omits-head/).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any


class Verdict(str, Enum):
    # TRIPWIRE: state only — there is deliberately no LEGACY_OK/ACCEPTED member.
    # Mode resolution lives in is_acceptable(); adding a mode-dependent member here
    # makes the same artifact report different verdicts on different calls and breaks
    # the --inventory report (decision K17).
    VALID = "VALID"
    EXPIRED = "EXPIRED"
    MISSING_EXPIRY = "MISSING_EXPIRY"
    MALFORMED = "MALFORMED"
    ACTION_MISMATCH = "ACTION_MISMATCH"
    BINDING_MISMATCH = "BINDING_MISMATCH"
    LEGACY_SCHEMA = "LEGACY_SCHEMA"            # command approval predating schema 3
    PROFILE_MISMATCH = "PROFILE_MISMATCH"      # binding profile differs from the rule's
    UPDATE_MISMATCH = "UPDATE_MISMATCH"        # git_push_v1: different ref update(s)
    BINDING_UNRESOLVED = "BINDING_UNRESOLVED"  # the observed binding could not be resolved


#: Verdicts each carrier accepts, by strictness (decision K17's table).
_ACCEPT_STRICT = frozenset({Verdict.VALID})
_ACCEPT_COMPAT = frozenset({Verdict.VALID, Verdict.MISSING_EXPIRY})

SCHEMA_VERSION = 2
_KNOWN_SCHEMAS = (1, 2)

COMMAND_SCHEMA_VERSION = 3
PROFILE_COMMAND_ONLY = "command_only_v1"   # binds the command text + repository, NOT content
PROFILE_GIT_PUSH = "git_push_v1"           # also binds every ref update the push performs
BINDING_PROFILES = (PROFILE_COMMAND_ONLY, PROFILE_GIT_PUSH)   # weakest first: index = strength
UPDATE_KEYS = ("push_endpoint", "destination_ref", "source_oid", "operation")
#: Actions judged by their OWN carrier (path_policy, the health engine), never as command
#: approvals. Reporters fall back to "every other action is a command approval" when
#: command-policy cannot be read, so a path/deferral artifact is not hidden by that failure.
NON_COMMAND_ACTIONS = frozenset({"protected_path_edit", "health_check_deferral"})


class _NotObserved:
    def __repr__(self) -> str:
        return "NOT_OBSERVED"


#: TRIPWIRE: passing NOT_OBSERVED skips an equality check. Only a carrier that
#: structurally cannot see that input may pass it — the --inventory / health reports, and
#: the pre-push boundary for `command_digest` (git hands it ref updates, never the command).
#: The command gate always passes real observed values; None there means "unknown" and
#: fails closed.
NOT_OBSERVED: Any = _NotObserved()


@dataclass(frozen=True)
class Artifact:
    """One file under state/approvals/ plus whatever survived parsing.

    `data` is None when the file was unreadable, not JSON, or not a JSON object —
    evaluate_artifact turns each of those into MALFORMED rather than an exception.
    """
    path: Path
    filename_action: str
    data: dict[str, Any] | None

    @property
    def schema_version(self) -> Any:
        return (self.data or {}).get("schema_version")


def filename_action(path: Path | str) -> str:
    """The `<action>` prefix of `<action>-<slug>-<YYYYMMDD>.json`, or "" if unshaped."""
    stem = Path(path).name
    if not stem.endswith(".json"):
        return ""
    # TRIPWIRE: action names are snake_case and must never contain "-" — that is what
    # makes the first hyphen the unambiguous action/slug boundary when the slug itself
    # carries hyphens. Adding a hyphenated action name silently breaks every lookup.
    return stem[: -len(".json")].split("-", 1)[0]


def parse_expiry(value: Any) -> datetime | None:
    """Parse an ISO-8601 instant into an aware UTC datetime, or None if unusable.

    TRIPWIRE (decision K1): expiry is PARSED and compared as a datetime, never
    string-compared. The original defect was `if expires and expires < now` over raw
    strings — lexicographic ordering silently mis-ranks any format variation (offset
    forms, fractional seconds, a naive vs Z-suffixed stamp) and a missing/empty value
    read as "valid forever". Do not reintroduce a string comparison here.

    TRIPWIRE: the UTC CONVERSION is artifact content too and must stay inside the try —
    a valid extreme aware stamp (`9999-12-31T23:59:59-14:00`) parses fine and then
    OverflowErrors on astimezone(); that exception escaped evaluate_artifact() and the
    handler emitted no deny at all (AC3).
    """
    if isinstance(value, bool) or not isinstance(value, str):
        return None
    text = value.strip()
    if not text:
        return None
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
        return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)
    except (ValueError, TypeError, OverflowError, OSError):
        return None


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def compute_command_digest(command: str) -> str:
    """sha256 over the hook-received command, TRIMMED ONLY (decision K6, REVISED).

    TRIPWIRE (decision K6 revised): `.strip()` and nothing else. Do NOT collapse
    interior whitespace — inside a quoted argument it is data, not formatting, and
    collapsing it made `--app "safe  prod"` and `--app "safe prod"` hash identically,
    so one approval authorized a command targeting a different value. Every "smarter"
    normalization (env prefixes, executable paths, unquoting, flag order) WIDENS what
    one artifact authorizes. A false negative costs one re-approval; a false positive
    costs an unapproved production deploy.
    """
    canonical = (command or "").strip()
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def compute_repo_id(root: Path | str | None) -> str:
    """sha256 of the realpath of the repository root; "" when the root is unknown."""
    if root is None:
        return ""
    try:
        real = os.path.realpath(str(root))
    except (OSError, ValueError):
        return ""
    return hashlib.sha256(real.encode("utf-8")).hexdigest() if real else ""


def load(path: Path | str) -> Artifact | None:
    """Read one artifact. Returns None only when the file cannot be read at all.

    Never raises for ANY file content: unparseable JSON, a top-level array/number/
    string/null all yield an Artifact whose `data` is None (-> MALFORMED).
    """
    p = Path(path)
    try:
        raw = p.read_text(encoding="utf-8")
    except Exception:
        return None
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = None
    return Artifact(
        path=p,
        filename_action=filename_action(p),
        data=parsed if isinstance(parsed, dict) else None,
    )


def _binding_ok(recorded: Any, observed: str | None) -> bool:
    """A binding field the artifact carries must match the observed ambient fact.

    Fail-closed (decision K2): a bound artifact whose binding cannot be checked
    (observed is None/unknown) does NOT authorize — an unverifiable binding is a
    mismatch, never a waiver. Absent/empty recorded value => not bound => ok.
    """
    if recorded is None or (isinstance(recorded, str) and not recorded.strip()):
        return True
    if not isinstance(recorded, str):
        return False
    return bool(observed) and recorded.strip() == observed.strip()


def evaluate_artifact(
    data: Any,
    *,
    expected_action: str,
    command_digest: str | None = None,
    repo_id: str | None = None,
    now: datetime | None = None,
) -> Verdict:
    """Classify one artifact body. Mode-independent (decision K17).

    Precedence, most-specific first: MALFORMED > ACTION_MISMATCH > expiry state >
    BINDING_MISMATCH. Every field access happens after its own type check, so no
    artifact content can raise out of this function (the command_policy.py defect
    where JSON parsing was guarded but field access was not).
    """
    if not isinstance(data, dict):
        return Verdict.MALFORMED

    schema = data.get("schema_version")
    if schema is not None:
        if isinstance(schema, bool) or not isinstance(schema, int) or schema not in _KNOWN_SCHEMAS:
            return Verdict.MALFORMED

    body_action = data.get("action")
    if body_action is not None and not isinstance(body_action, str):
        return Verdict.MALFORMED
    claimed = (body_action or "").strip()
    if schema == SCHEMA_VERSION and not claimed:
        return Verdict.MALFORMED          # v2 mandates `action`; absence is malformed, not legacy
    if claimed and claimed != (expected_action or "").strip():
        return Verdict.ACTION_MISMATCH

    raw_expiry = data.get("expires_at")
    if raw_expiry is None or (isinstance(raw_expiry, str) and not raw_expiry.strip()):
        expiry_verdict: Verdict | None = Verdict.MISSING_EXPIRY
    elif not isinstance(raw_expiry, str) or isinstance(raw_expiry, bool):
        return Verdict.MALFORMED
    else:
        parsed = parse_expiry(raw_expiry)
        if parsed is None:
            return Verdict.MALFORMED
        expiry_verdict = Verdict.EXPIRED if parsed < (now or now_utc()) else None

    if not _binding_ok(data.get("repo_id"), repo_id):
        return Verdict.BINDING_MISMATCH
    if not _binding_ok(data.get("command_digest"), command_digest):
        return Verdict.BINDING_MISMATCH

    return expiry_verdict or Verdict.VALID


_HEX64 = re.compile(r"[0-9a-f]{64}")
_OID = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
_SCHEME_URL = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)(.*)", re.DOTALL)
_SCP_LIKE = re.compile(r"([^/:]{2,}):(.*)", re.DOTALL)
_SCP_AUTHORITY = re.compile(r"(?:([A-Za-z0-9._+-]+)@)?([A-Za-z0-9._-]+|\[[0-9A-Fa-f:.]+\])")
_REF_FORBIDDEN = re.compile(r"[\x00-\x20\x7f~^:?*\[\\]|\.\.|@\{|//")


def canonical_endpoint(url: Any) -> str | None:
    """Identity of a push endpoint, or None when it cannot be one.

    TRIPWIRE: writer, command gate and pre-push boundary all derive the endpoint through
    THIS function from the string git itself reports, so they cannot drift. Two rules pull
    in opposite directions and BOTH are load-bearing:

      * an HTTP(S)/git userinfo is authentication material (`https://<token>@host/x`), it
        never selects the repository — the path is absolute — so it is DROPPED, never stored;
      * an SSH login DOES select the repository: `alice@host:repo.git` and
        `bob@host:repo.git` are different users' repositories, and `~` expands per principal.
        Stripping it merged distinct destinations, so the login is KEPT (a login name is not
        a secret). A password-bearing SSH authority is refused rather than stored or dropped.

    Nothing else is normalized — every normalization widens what one approval binds.
    """
    if not isinstance(url, str):
        return None
    text = url.strip()
    if not text or any(ord(c) < 0x21 or ord(c) == 0x7F for c in text):
        return None
    m = _SCHEME_URL.fullmatch(text)
    if m:
        scheme, authority, rest = m.groups()
        if "?" in rest or "#" in rest:
            return None
        userinfo, at, host = authority.rpartition("@")
        if not host and scheme.lower() != "file":
            return None
        if at and scheme.lower().endswith("ssh"):
            if ":" in userinfo or not userinfo:
                return None                  # password material, or an empty principal
            return f"{scheme}://{userinfo}@{host}{rest}"
        return f"{scheme}://{host}{rest}"
    m = _SCP_LIKE.fullmatch(text)
    if m:                                    # [user@]host:path; a 1-char head is a drive
        head, path = m.groups()
        hm = _SCP_AUTHORITY.fullmatch(head)
        if not hm:
            return None
        user, host = hm.groups()
        # git's scp-like form carries no password; an `@` in the first path segment means the
        # string is not the [user@]host:path it parsed as, so refuse instead of guessing.
        if "@" in path.split("/", 1)[0]:
            return None
        return f"{user}@{host}:{path}" if user else f"{host}:{path}"
    return text                              # a local path


def valid_destination_ref(ref: Any) -> bool:
    """A fully qualified ref name under `git check-ref-format` rules (conservative)."""
    if not isinstance(ref, str) or not ref.startswith("refs/") or ref.endswith(("/", ".", ".lock")):
        return False
    if _REF_FORBIDDEN.search(ref):
        return False
    return all(part and not part.startswith(".") and not part.endswith(".lock")
               for part in ref.split("/"))


Update = tuple[str, str, "str | None", str]


def canonical_updates(value: Any) -> tuple[Update, ...] | None:
    """The `updates` binding as a sorted tuple, or None when any entry is malformed.

    Entry = {push_endpoint, destination_ref, source_oid, operation}, exactly those keys.
    `update` carries a full object id; `delete` carries source_oid null (a deletion has
    no source object). One destination per endpoint — a duplicate is ambiguous.
    """
    if not isinstance(value, list) or not value:
        return None
    out: list[Update] = []
    for entry in value:
        if not isinstance(entry, dict) or set(entry) != set(UPDATE_KEYS):
            return None
        endpoint, ref = entry["push_endpoint"], entry["destination_ref"]
        oid, op = entry["source_oid"], entry["operation"]
        if not isinstance(endpoint, str) or canonical_endpoint(endpoint) != endpoint:
            return None
        if not valid_destination_ref(ref):
            return None
        if op == "update":
            if not isinstance(oid, str) or not _OID.fullmatch(oid):
                return None
        elif op != "delete" or oid is not None:
            return None
        out.append((endpoint, ref, oid, op))
    if len({(e, r) for e, r, _o, _p in out}) != len(out):
        return None
    return tuple(sorted(out, key=lambda u: (u[0], u[1], u[2] or "", u[3])))


def updates_as_json(updates: tuple[Update, ...]) -> list[dict[str, Any]]:
    return [dict(zip(UPDATE_KEYS, u)) for u in updates]


def command_contract_problems(data: Any) -> tuple[Verdict | None, list[str]]:
    """(structural verdict or None when sound, human reasons) for a command approval.

    Shared by evaluate_command_approval and the --inventory "why" column, so the report
    can never give a reason the gate does not act on.
    """
    if not isinstance(data, dict):
        return Verdict.MALFORMED, ["not a JSON object"]
    schema = data.get("schema_version")
    legacy = schema is None or (isinstance(schema, int) and not isinstance(schema, bool)
                                and schema in _KNOWN_SCHEMAS)
    if legacy:
        missing = [k for k in ("action", "repo_id", "command_digest", "created_at",
                               "expires_at", "binding_profile")
                   if not (isinstance(data.get(k), str) and data[k].strip())]
        why = [f"schema_version {'absent' if schema is None else schema}; "
               f"command approvals require {COMMAND_SCHEMA_VERSION}"]
        if missing:
            why.append("missing " + ", ".join(missing))
        return Verdict.LEGACY_SCHEMA, why
    # TRIPWIRE: the type check comes FIRST — `3.0 == 3` is True in Python, so a float (or a
    # bool) would otherwise satisfy an integer-only schema contract.
    if not isinstance(schema, int) or isinstance(schema, bool) or schema != COMMAND_SCHEMA_VERSION:
        return Verdict.MALFORMED, [f"unknown schema_version {schema!r} (must be the integer "
                                   f"{COMMAND_SCHEMA_VERSION})"]
    why = []
    action = data.get("action")
    if not isinstance(action, str) or not action.strip():
        why.append("action missing or not a string")
    for key in ("repo_id", "command_digest"):
        if not isinstance(data.get(key), str) or not _HEX64.fullmatch(data[key]):
            why.append(f"{key} is not 64 lowercase hex")
    created, expires = parse_expiry(data.get("created_at")), parse_expiry(data.get("expires_at"))
    if created is None:
        why.append("created_at missing or unparseable")
    if expires is None:
        why.append("expires_at missing or unparseable")
    if created is not None and expires is not None and not created < expires:
        why.append("created_at is not before expires_at")
    profile = data.get("binding_profile")
    if profile not in BINDING_PROFILES:
        why.append(f"binding_profile {profile!r} is not one of {list(BINDING_PROFILES)}")
    elif profile == PROFILE_GIT_PUSH:
        if canonical_updates(data.get("updates")) is None:
            why.append("updates missing or malformed for git_push_v1")
    elif "updates" in data:
        why.append(f"updates is not a binding of {profile}")
    return (Verdict.MALFORMED, why) if why else (None, [])


def evaluate_command_approval(
    data: Any,
    *,
    expected_action: str,
    required_profile: Any,
    command_digest: Any,
    repo_id: Any,
    updates: Any = NOT_OBSERVED,
    updates_mode: str = "exact",
    now: datetime | None = None,
) -> Verdict:
    """Judge a command approval under schema 3. Mode-independent (K17).

    Precedence: MALFORMED/LEGACY_SCHEMA > ACTION_MISMATCH > EXPIRED > BINDING_MISMATCH
    (repo) > PROFILE_MISMATCH > BINDING_MISMATCH (command) > BINDING_UNRESOLVED /
    UPDATE_MISMATCH. `updates` is the observed canonical_updates tuple, None when
    resolution failed. `updates_mode="subset"` is the pre-push boundary's rule: git omits
    up-to-date refs and runs the hook once per push URL, so every observed update must be
    bound while a bound one may be absent. The command gate uses "exact".
    """
    structural, _why = command_contract_problems(data)
    if structural is not None:
        return structural
    if data["action"].strip() != (expected_action or "").strip():
        return Verdict.ACTION_MISMATCH
    if parse_expiry(data["expires_at"]) < (now or now_utc()):
        return Verdict.EXPIRED
    if repo_id is not NOT_OBSERVED and (not repo_id or data["repo_id"] != repo_id):
        return Verdict.BINDING_MISMATCH
    profile = data["binding_profile"]
    # A STRONGER profile satisfies a weaker requirement (git_push_v1 carries every
    # command_only_v1 binding); a weaker or unknown required profile never passes.
    if required_profile is not NOT_OBSERVED and (
            required_profile not in BINDING_PROFILES
            or BINDING_PROFILES.index(profile) < BINDING_PROFILES.index(required_profile)):
        return Verdict.PROFILE_MISMATCH
    if command_digest is not NOT_OBSERVED and (
            not command_digest or data["command_digest"] != command_digest):
        return Verdict.BINDING_MISMATCH
    if profile == PROFILE_GIT_PUSH and updates is not NOT_OBSERVED:
        if updates is None:
            return Verdict.BINDING_UNRESOLVED
        bound, observed = set(canonical_updates(data["updates"]) or ()), set(updates)
        if not (observed <= bound if updates_mode == "subset" else observed == bound):
            return Verdict.UPDATE_MISMATCH
    return Verdict.VALID


def evaluate_file(
    path: Path | str,
    *,
    expected_action: str,
    command_digest: str | None = None,
    repo_id: str | None = None,
    now: datetime | None = None,
) -> Verdict:
    """evaluate_artifact for a file on disk; an unreadable file is MALFORMED."""
    art = load(path)
    if art is None:
        return Verdict.MALFORMED
    return evaluate_artifact(
        art.data,
        expected_action=expected_action,
        command_digest=command_digest,
        repo_id=repo_id,
        now=now,
    )


def is_acceptable(verdict: Verdict, *, strict: bool) -> bool:
    """The ONLY place `strict` is consulted (decision K17)."""
    return verdict in (_ACCEPT_STRICT if strict else _ACCEPT_COMPAT)


def accept_with_audit(
    verdict: Verdict,
    *,
    strict: bool,
    carrier: str,
    artifact_path: Path | str | None = None,
    action: str = "",
    root: Path | None = None,
) -> bool:
    """is_acceptable + the K7 obligation that a COMPAT acceptance leaves a trace.

    TRIPWIRE: every carrier must accept through this, not bare is_acceptable — a
    compat-accepted expiry-less artifact that is accepted SILENTLY is the pre-fix
    behaviour, and the one release of warning (K7) only helps if it is greppable.
    """
    ok = is_acceptable(verdict, strict=strict)
    if ok and verdict is Verdict.MISSING_EXPIRY:
        name = Path(artifact_path).name if artifact_path else "<unknown>"
        try:
            from .audit_logger import emit
            emit(
                "approval_legacy_accepted",
                decision="allow",
                reason=(
                    f"K7 compat [{carrier}]: {name} has no parseable expires_at and was "
                    f"accepted. Strict mode (strict_approvals: true) will REJECT it — "
                    f"reissue with `bash hooks/local/approve-local.sh {action or '<action>'} "
                    f"<slug> --command '<exact command>'`."
                ),
                rule_id="FR-12",
                extra={"artifact": name, "action": action, "carrier": carrier,
                       "approval_verdict": Verdict.MISSING_EXPIRY.value},
                root=root,
            )
        except BaseException:                        # noqa: BLE001 — logging never gates
            pass
    return ok


def expiry_state(data: Any) -> str:
    """Human-facing expiry classification for the --inventory report (AC12)."""
    if not isinstance(data, dict):
        return "malformed"
    raw = data.get("expires_at")
    if raw is None or (isinstance(raw, str) and not raw.strip()):
        return "legacy-no-expiry"
    parsed = parse_expiry(raw)
    if parsed is None:
        return "unparseable"
    return "expired" if parsed < now_utc() else "active"


def binding_state(data: Any) -> str:
    """Which binding fields an artifact carries, for the --inventory report (AC12)."""
    if not isinstance(data, dict):
        return "none"
    carried = [k for k in ("command_digest", "repo_id")
               if isinstance(data.get(k), str) and data[k].strip()]
    return "+".join(carried) if carried else "none"


__all__ = [
    "Artifact", "BINDING_PROFILES", "COMMAND_SCHEMA_VERSION", "NON_COMMAND_ACTIONS", "NOT_OBSERVED",
    "PROFILE_COMMAND_ONLY", "PROFILE_GIT_PUSH", "SCHEMA_VERSION", "UPDATE_KEYS", "Verdict",
    "accept_with_audit", "binding_state", "canonical_endpoint", "canonical_updates",
    "command_contract_problems", "compute_command_digest", "compute_repo_id",
    "evaluate_artifact", "evaluate_command_approval", "evaluate_file", "expiry_state",
    "filename_action", "is_acceptable", "load", "now_utc", "parse_expiry", "updates_as_json",
    "valid_destination_ref",
]
