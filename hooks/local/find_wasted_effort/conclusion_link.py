"""Parse outcome/task/commit-scoped conclusion records."""

import re


HEADING = re.compile(r"^## Conclusion:\s*(.+?)\s*$", re.MULTILINE)
FIELD = re.compile(r"^(Outcome|Task|Commit):\s*(.+?)\s*$", re.MULTILINE | re.IGNORECASE)
SHA = re.compile(r"[0-9a-f]{7,40}", re.IGNORECASE)
TASK = re.compile(r"T\d+", re.IGNORECASE)


def parse_conclusions(text):
    matches = list(HEADING.finditer(text))
    records = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.start():end]
        fields = {key.lower(): value.strip(" `") for key, value in FIELD.findall(body)}
        records.append({"name": match.group(1), "body": body, **fields})
    return records


def resolve_commit(commit, task, selected):
    if not isinstance(commit, str) or not SHA.fullmatch(commit):
        return None
    if not isinstance(task, str) or not TASK.fullmatch(task):
        return None
    commit = commit.lower()
    matches = [sha for sha, subject in selected
               if sha.lower().startswith(commit)
               and re.search(rf"\b{re.escape(task)}\b", subject, re.IGNORECASE)]
    return matches[0] if len(matches) == 1 else None


def linked_commit(record, selected):
    if not record.get("outcome"):
        return None
    return resolve_commit(record.get("commit"), record.get("task"), selected)


def linked_approval(record, expected_action, selected):
    if not isinstance(record, dict) or record.get("action") != expected_action:
        return None
    commit = record.get("commit", record.get("commit_sha"))
    return resolve_commit(commit, record.get("task"), selected)
