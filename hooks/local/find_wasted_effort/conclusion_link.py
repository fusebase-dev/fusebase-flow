"""Parse outcome/task/commit-scoped conclusion records and gate-report template tables."""

import re

from .evidence import RECORDED_REPORT_KINDS, artifact_kind, recorded_outcome_text


HEADING = re.compile(r"^## Conclusion:\s*(.+?)\s*$", re.MULTILINE)
FIELD = re.compile(r"^(Outcome|Task|Commit):\s*(.+?)\s*$", re.MULTILINE | re.IGNORECASE)
SHA = re.compile(r"[0-9a-f]{7,40}", re.IGNORECASE)
TASK = re.compile(r"T\d+", re.IGNORECASE)
STATUS_LINE = re.compile(r"^\*\*Status:\*\*[ \t]*\S", re.MULTILINE)
TABLE_SEPARATOR = re.compile(r"^\|?[\s:|-]*-[\s:|-]*$")


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


def _section(text, title):
    heading = re.compile(r"^(#+)\s*(?:\d+[a-z]?\.\s*)?" + re.escape(title) + r"\b", re.IGNORECASE)
    lines = [line.strip() for line in text.splitlines()]
    start = next((i for i, line in enumerate(lines) if heading.match(line)), None)
    if start is None:
        return []
    level = len(heading.match(lines[start]).group(1))
    section = []
    for line in lines[start + 1:]:
        if re.match(r"^#{1,%d}\s" % level, line):
            break
        section.append(line)
    return section


def _section_table(text, title):
    table = []
    for line in _section(text, title):
        if line.startswith("|"):
            if not TABLE_SEPARATOR.match(line):
                table.append([cell.strip(" *`") for cell in line.strip("|").split("|")])
        elif table:
            break
    return table


def _column(header, pattern):
    return next((j for j, cell in enumerate(header) if re.search(pattern, cell, re.IGNORECASE)), None)


def parse_template_report(rel, text):
    # Status line is a presence check only (the template's value is constant); §6 and §7 carry the outcome.
    if artifact_kind(rel, text) not in RECORDED_REPORT_KINDS or not STATUS_LINE.search(text):
        return None
    table = _section_table(text, "Per-task commit table")
    task_col = _column(table[0], r"^task$") if table else None
    sha_col = _column(table[0], r"\bsha\b") if table else None
    if task_col is None or sha_col is None:
        return None
    rows = [(row[task_col], row[sha_col]) for row in table[1:]
            if max(task_col, sha_col) < len(row)
            and TASK.fullmatch(row[task_col]) and SHA.fullmatch(row[sha_col])]
    gate = _section_table(text, "Gate satisfaction")
    status_col = _column(gate[0], r"^status$") if gate else None
    marks = [row[status_col].upper() for row in gate[1:]
             if status_col is not None and status_col < len(row)]
    outcome = ("%d PASS / %d FAIL" % (marks.count("PASS"), marks.count("FAIL"))
               if {"PASS", "FAIL"} & set(marks) else None)
    deviations = recorded_outcome_text("\n".join(_section(text, "Deviations")))
    return {"outcome": outcome, "rows": rows, "fails": marks.count("FAIL"), "deviations": deviations}


def linked_report(record, selected):
    if not record:
        return []
    resolved = [(task, resolve_commit(sha, task, selected)) for task, sha in record["rows"]]
    return [(task, sha) for task, sha in resolved if sha]
