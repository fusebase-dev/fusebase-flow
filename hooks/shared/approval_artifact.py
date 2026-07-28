"""Fusebase Flow — approval_artifact: the single canonical approval-artifact reader.

Owns every artifact-reading concern that used to be duplicated across
command_policy.py, path_policy.py and hooks/local/lib/active-approvals.sh:
load, schema detection, expiry parsing, action agreement, binding checks.

Contract (decision K17): a Verdict is artifact STATE only. Acceptability is the
separate predicate is_acceptable(verdict, strict=...), so each carrier declares
its own pass-set and the loader never needs to know who called it.
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

_WS = re.compile(r"\s+")


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


#: Verdicts each carrier accepts, by strictness (decision K17's table).
_ACCEPT_STRICT = frozenset({Verdict.VALID})
_ACCEPT_COMPAT = frozenset({Verdict.VALID, Verdict.MISSING_EXPIRY})

SCHEMA_VERSION = 2
_KNOWN_SCHEMAS = (1, 2)


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
    """sha256 over the hook-received command after whitespace collapse ONLY (K6).

    TRIPWIRE (decision K6): collapse runs of whitespace and trim — normalize NOTHING
    else. Every "smarter" normalization (stripping env prefixes, resolving executable
    paths, unquoting, reordering flags) WIDENS what one artifact authorizes and can
    make two semantically different commands collide. A false negative costs one
    re-approval; a false positive costs an unapproved production deploy.
    """
    canonical = _WS.sub(" ", command or "").strip()
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
    "Artifact", "SCHEMA_VERSION", "Verdict", "binding_state", "compute_command_digest",
    "compute_repo_id", "evaluate_artifact", "evaluate_file", "expiry_state",
    "filename_action", "is_acceptable", "load", "now_utc", "parse_expiry",
]
