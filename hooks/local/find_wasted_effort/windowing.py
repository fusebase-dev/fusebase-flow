"""Temporal linkage for window-honest ceremony evidence."""

import re
import subprocess


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
        links = set()
        last = _last_commit(root, rel).lower()
        if last in shas and _path_clean(root, rel):
            links.add(last)
        links.update(_matched_refs(body, shas))
        target = linked if links else historical
        target.append((rel, body))
        rows.append({"file": rel, "status": "linked" if links else "historical/unlinked",
                     "commits": sorted(links), "last_commit": last or None})
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
