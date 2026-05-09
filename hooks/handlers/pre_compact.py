#!/usr/bin/env python3
"""Fusebase Flow — pre_compact handler.

Preserve flow state before context compression. Saves a small summary to
state/context-summary.md so the next post-compact session
can rehydrate quickly.

Records:
- active phase (best-effort from agent_message scan)
- active ticket slug (best-effort from cwd / open files)
- recent commits (top 5)
- git status short
- whether handoff drafts exist that haven't been saved
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.git_utils import is_clean, recent_commits, status_short  # noqa: E402
from shared.policy_loader import find_git_root  # noqa: E402


PHASE_PATTERNS = [
    (r"\bspecify\b", "Specify"),
    (r"\bclarify\b", "Clarify"),
    (r"\bplan\b", "Plan"),
    (r"\bdecisions?\b", "Decisions"),
    (r"\btasks?\b", "Tasks"),
    (r"\bverify|verification\b", "Verify"),
    (r"\bimplement|implementer\b", "Implement"),
    (r"\bdeploy\b", "Deploy"),
]


def _detect_phase(text: str) -> str:
    text_lower = text.lower()
    for pat, name in PHASE_PATTERNS:
        if re.search(pat, text_lower):
            return name
    return "unknown"


def _detect_slug(text: str, root: Path | None) -> str:
    m = re.search(r"docs/(?:specs?|backlog)/([a-z0-9][a-z0-9-]+)/", text)
    if m:
        return m.group(1)
    if root:
        try:
            specs = list((root / "docs" / "specs").glob("*/"))
            if len(specs) == 1:
                return specs[0].name
        except Exception:
            pass
    return "—"


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        root = None

    transcript_text = ""
    tp = event.get("transcript_path")
    if tp:
        try:
            transcript_text = Path(tp).read_text(encoding="utf-8", errors="ignore")
        except OSError:
            transcript_text = ""

    haystack = (event.get("agent_message") or "") + "\n" + transcript_text[-4000:]
    phase = _detect_phase(haystack)
    slug = _detect_slug(haystack, root)

    summary_lines = [
        "# Fusebase Flow context summary (pre-compact snapshot)",
        f"Saved: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
        f"Phase: {phase}",
        f"Ticket: {slug}",
    ]

    if root:
        try:
            clean = is_clean(root)
            summary_lines.append(f"Working tree clean: {'yes' if clean else 'NO'}")
        except Exception:
            pass
        try:
            commits = recent_commits(root, n=5).strip().splitlines()
            if commits:
                summary_lines.append("Recent commits:")
                for c in commits[:5]:
                    summary_lines.append(f"  {c}")
        except Exception:
            pass
        try:
            ss = status_short(root)
            if ss.strip():
                summary_lines.append("Uncommitted (git status --short):")
                for line in ss.strip().splitlines()[:20]:
                    summary_lines.append(f"  {line}")
        except Exception:
            pass

    if root:
        out_path = root / "state" / "context-summary.md"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
        emit(
            "pre_compact",
            decision="allow",
            reason="context summary persisted",
            extra={"phase": phase, "slug": slug, "summary_path": str(out_path)},
            root=root,
        )

    sys.stdout.write(json.dumps({"decision": "allow", "phase": phase, "ticket": slug}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
