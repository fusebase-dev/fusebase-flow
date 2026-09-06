"""Parse outcome/task/commit-scoped conclusion records."""

import re


HEADING = re.compile(r"^## Conclusion:\s*(.+?)\s*$", re.MULTILINE)
FIELD = re.compile(r"^(Outcome|Task|Commit):\s*(.+?)\s*$", re.MULTILINE | re.IGNORECASE)


def parse_conclusions(text):
    matches = list(HEADING.finditer(text))
    records = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.start():end]
        fields = {key.lower(): value.strip(" `") for key, value in FIELD.findall(body)}
        records.append({"name": match.group(1), "body": body, **fields})
    return records


def linked_commit(record, selected):
    task = record.get("task", "")
    outcome = record.get("outcome", "")
    commit = record.get("commit", "").lower()
    if not outcome or not re.fullmatch(r"T\d+", task, re.IGNORECASE):
        return None
    matches = [sha for sha, subject in selected
               if sha.lower().startswith(commit)
               and re.search(rf"\b{re.escape(task)}\b", subject, re.IGNORECASE)]
    return matches[0] if len(matches) == 1 else None
