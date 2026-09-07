"""Temporal linkage for window-honest ceremony evidence."""

import json
import subprocess

from find_wasted_effort.conclusion_link import linked_approval, linked_commit, parse_conclusions


def _git(root, *args):
    try:
        result = subprocess.run(
            ["git", *args], cwd=str(root), capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=30,
        )
    except Exception:
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def _last_commit(root, rel):
    return _git(root, "log", "-1", "--format=%H", "--", rel)


def partition_artifacts(root, artifacts, commits):
    linked = []
    historical = []
    rows = []
    for rel, body in artifacts:
        last = _last_commit(root, rel).lower()
        records = parse_conclusions(body)
        if not records:
            historical.append((rel, body))
            rows.append({"file": rel, "status": "historical/unlinked",
                         "commits": [],
                         "last_commit": last or None, "reason": "no structured conclusions"})
            continue
        for index, record in enumerate(records, 1):
            sha = linked_commit(record, commits)
            target = linked if sha else historical
            fragment = f"{rel}#conclusion-{index}"
            target.append((rel, record["body"]))
            rows.append({"file": fragment, "status": "linked" if sha else "historical/unlinked",
                         "commits": [sha] if sha else [], "last_commit": last or None,
                         "task": record.get("task"), "outcome": record.get("outcome")})
    return linked, historical, rows


def partition_approvals(root, approvals, commits):
    linked = []
    historical = []
    rows = []
    for approval in approvals:
        rel = approval["file"]
        try:
            body = (root / rel).read_text(encoding="utf-8", errors="replace")
            record = json.loads(body)
        except (OSError, json.JSONDecodeError):
            record = None
        sha = linked_approval(record, approval["kind"], commits)
        target = linked if sha else historical
        target.append(approval)
        rows.append({"file": rel, "status": "linked" if sha else "historical/unlinked",
                     "commits": [sha] if sha else []})
    return linked, historical, rows
