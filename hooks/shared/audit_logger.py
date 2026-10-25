"""Fusebase Flow — audit_logger.

Append-only JSONL audit log at state/audit.log.jsonl. Every hook
handler logs its decision so operators can audit retroactively.

Concurrency note: line-oriented append + atomic file open with O_APPEND is safe
across processes on POSIX. On Windows, the runtime serializes appends sufficiently
for v0.1 (single-operator, single-IDE assumption). Heavy concurrency moves to a
SQLite log in v0.2 if needed.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from .policy_loader import find_git_root

# A URL's userinfo (`user`, or `user` and a password after a colon) follows its scheme and ends at an `@`: it runs to
# the last `@` before the host's end (/, ?, # or space).
_USERINFO = re.compile(r"([A-Za-z][A-Za-z0-9+.\-]*://)[^/?#\s]*@")


def strip_userinfo(value: Any) -> Any:
    """Every URL in every string, inside lists and dicts too, keeps scheme://host/path and loses its user[:password]@:
    a push URL can carry a token (review r1-43)."""
    if isinstance(value, str):
        return _USERINFO.sub(r"\1", value)
    if isinstance(value, dict):
        return {k: strip_userinfo(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [strip_userinfo(v) for v in value]
    return value


def stdin_text() -> str:
    """The hook event's JSON as text: its bytes decoded as UTF-8. Claude Code (Node's JSON.stringify) and Codex send
    non-ASCII unescaped; Windows' default stdin code page (cp1252) misread it, and pre_tool_use's hash then raised
    on it, which T371 turned into a deny of the call (6.0.0-m8, re-check B HOLD a)."""
    stream = sys.stdin
    if stream is None:
        return ""
    return stream.buffer.read().decode("utf-8", "replace") if hasattr(stream, "buffer") else stream.read()


def cmd_sha256(command: str) -> str:
    """The command's hash on the pre and post audit lines, one definition so a command's two lines match: the
    whitespace-collapsed form; a lone surrogate (from a JSON escape) is hashed as its code point, never raised on."""
    return hashlib.sha256(" ".join(command.split()).encode("utf-8", "surrogatepass")).hexdigest()


def event_root(event: dict, handler_dir: Path) -> Path | None:
    """The git work tree of the event's cwd; for a call from outside any (`cd <your-project>` from the folder above it)
    the project the handler belongs to (TRIPWIRE, 6.0.0-m8 fix: a failed lookup denied every such call, and in
    post_tool_use raised on every call, audit #10); None when neither is in one."""
    for start in (Path(event.get("cwd") or "."), handler_dir):
        try:
            return find_git_root(start)
        except (FileNotFoundError, OSError, ValueError):
            continue
    return None


def audit_log_path(root: Path | None = None) -> Path:
    return (root or find_git_root()) / "state" / "audit.log.jsonl"


def emit(
    event: str,
    *,
    decision: str,
    reason: str = "",
    rule_id: str | None = None,
    extra: dict[str, Any] | None = None,
    root: Path | None = None,
) -> str:
    """Append one audit event, with no URL userinfo in any string (strip_userinfo). Returns the event_id."""
    event_id = uuid.uuid4().hex
    record = strip_userinfo({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "event_id": event_id,
        "event": event,
        "decision": decision,
        "reason": reason,
        "rule_id": rule_id,
        "session_id": os.environ.get("FUSEBASE_FLOW_SESSION_ID"),
        "host_tool": os.environ.get("FUSEBASE_FLOW_HOST_TOOL"),
        **(extra or {}),
    })
    path = audit_log_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
    return event_id


def redact(value: str, *, keep_chars: int = 4) -> str:
    """Redaction helper for secrets. Keeps the first `keep_chars` for triage,
    masks the rest."""
    if not value:
        return ""
    if len(value) <= keep_chars:
        return "*" * len(value)
    return value[:keep_chars] + "*" * max(8, len(value) - keep_chars)


__all__ = ["emit", "audit_log_path", "redact", "strip_userinfo", "stdin_text", "cmd_sha256", "event_root"]
