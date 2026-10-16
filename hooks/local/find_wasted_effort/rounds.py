"""Round ids claimed by recorded gate reports for the commits their own tables resolve."""

import re

from .conclusion_link import linked_report, parse_template_report
from .evidence import artifact_kind, artifact_slug

TASK_RANGE_LINE = re.compile(r"\*\*Task range:\*\*\s*(.+)$", re.MULTILINE | re.IGNORECASE)
TASK_SPAN = re.compile(r"\bT(\d+)(?:\s*(?:\.\.|–|-)\s*T?(\d+))?\b")


def task_spans(text):
    spans = []
    for line in TASK_RANGE_LINE.finditer(text):
        for span in TASK_SPAN.finditer(line.group(1)):
            first = int(span.group(1))
            last = int(span.group(2) or first)
            if first <= last:
                spans.append((first, last))
    return spans


def round_claims(artifacts, commits):
    owners = {}
    for rel, text in artifacts:
        # Must equal artifact_slug(rel): suite-run and lane pairing match rounds by slug.
        slug = artifact_slug(rel)
        if not slug or artifact_kind(rel, text) != "gate-report":
            continue
        spans = task_spans(text)
        for task, sha in linked_report(parse_template_report(rel, text), commits):
            if any(first <= int(task[1:]) <= last for first, last in spans):
                owners.setdefault(sha, set()).add(slug)
    return {sha: slugs.pop() for sha, slugs in owners.items() if len(slugs) == 1}
