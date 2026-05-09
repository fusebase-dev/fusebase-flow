"""Fusebase Flow — audit_logger.

Append-only JSONL audit log at state/audit.log.jsonl. Every hook
handler logs its decision so operators can audit retroactively.

Concurrency note: line-oriented append + atomic file open with O_APPEND is safe
across processes on POSIX. On Windows, the runtime serializes appends sufficiently
for v0.1 (single-operator, single-IDE assumption). Heavy concurrency moves to a
SQLite log in v0.2 if needed.
"""
from __future__ import annotations

import json
import os
import time
import uuid
from pathlib import Path
from typing import Any

from .policy_loader import find_git_root


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
    """Append one audit event. Returns the event_id."""
    event_id = uuid.uuid4().hex
    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "event_id": event_id,
        "event": event,
        "decision": decision,
        "reason": reason,
        "rule_id": rule_id,
        "session_id": os.environ.get("FUSEBASE_FLOW_SESSION_ID"),
        "host_tool": os.environ.get("FUSEBASE_FLOW_HOST_TOOL"),
        **(extra or {}),
    }
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


__all__ = ["emit", "audit_log_path", "redact"]
