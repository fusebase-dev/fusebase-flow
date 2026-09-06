"""Temporal linkage for window-honest ceremony evidence."""

import re
import subprocess

from find_wasted_effort.conclusion_link import linked_commit, parse_conclusions


SHA_RE = re.compile(r"(?<![0-9a-f])([0-9a-f]{7,40})(?![0-9a-f])", re.IGNORECASE)


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


def _path_clean(root, rel):
    return not _git(root, "status", "--porcelain=v1", "--", rel)


def _matched_refs(text, shas):
    matches = set()
    for raw in SHA_RE.findall(text):
        ref = raw.lower()
        candidates = [sha for sha in shas if sha.startswith(ref)]
        if len(candidates) == 1:
            matches.add(candidates[0])
    return matches


def partition_artifacts(root, artifacts, commits):
    shas = {sha.lower() for sha, _ in commits}
    linked = []
    historical = []
    rows = []
    for rel, body in artifacts:
        last = _last_commit(root, rel).lower()
        records = parse_conclusions(body)
        if not records:
            legacy_link = last if last in shas and _path_clean(root, rel) else None
            (linked if legacy_link else historical).append((rel, body))
            rows.append({"file": rel, "status": "linked-legacy" if legacy_link else "historical/unlinked",
                         "commits": [legacy_link] if legacy_link else [],
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
    shas = {sha.lower() for sha, _ in commits}
    linked = []
    historical = []
    rows = []
    for approval in approvals:
        rel = approval["file"]
        try:
            body = (root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            body = ""
        links = _matched_refs(body, shas)
        target = linked if links else historical
        target.append(approval)
        rows.append({"file": rel, "status": "linked" if links else "historical/unlinked",
                     "commits": sorted(links)})
    return linked, historical, rows
