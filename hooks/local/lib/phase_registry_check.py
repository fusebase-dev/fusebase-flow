#!/usr/bin/env python3
"""Every registered FF_TAGS phase must name its gating route, in exactly one doc table.

WHY-home: docs/backlog/phase-classification-ratchet/README.md.

docs/maintainer-testing.md already says in prose that "registration alone leaves the outcome
incomplete". A prose rule that lives only in the file it protects is a comment, not a control
(problem-catalog/ci-linux-msys-test-divergence §8): it was written 2026-09-07 and two controls
still shipped gated nowhere three days later (v4.16.0 -> v4.16.2). This makes it closed-world.

The rejected shapes are listed once, in docs/maintainer-testing.md; do not restate them here.

Registry-only by design: it cannot see a control that is neither a registered FF_TAGS phase nor
a named workflow step. Stated, not hidden.

Usage: phase_registry_check.py <run-tests.sh> <maintainer-testing.md> [<verify-workflow.yml>]
Prints `ERROR <msg>` / `NOTE <msg>` lines; exit code = ERROR count (99 = internal failure).
"""
from __future__ import annotations

import re
import sys

# The ratchet: the unreviewed count must EQUAL this. Lowered by the commit that reviews a row.
# Seeded 2026-09-10 at 28 of 77 registered phases (measured, not guessed).
FF_UNREVIEWED_BASELINE = 28

REL_HEADER = "| Release responsibility | Existing required tags |"
OPTIN_HEADER = "| Tag | Why opt-in | Required protection retained |"
UNROUTED_HEADER = "| Tag | Classification | Reason |"

TABLE_LABEL = {
    REL_HEADER: "release table",
    OPTIN_HEADER: "Diagnostic-exclusions table",
    UNROUTED_HEADER: "'Registered, not in the release profile' table",
}

UNREVIEWED_RE = re.compile(r"^unreviewed \(pre-ratchet, \d{4}-\d{2}-\d{2}\)$")
TICKED = re.compile(r"`([^`]+)`")

errors: list[str] = []
notes: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def note(msg: str) -> None:
    notes.append(msg)


def parse_array(src: str, name: str, path: str) -> list[str]:
    """Read a top-level `NAME=(...)` bash array. Refuses to return an empty list quietly."""
    m = re.search(r"(?m)^%s=\(" % re.escape(name), src)
    if not m:
        err("could not find %s in %s - refusing to read an unparsed runner as 'no phases'"
            % (name, path))
        return []
    close = src.find(")", m.end())
    if close < 0:
        err("%s in %s is not closed - refusing to read a malformed array" % (name, path))
        return []
    tags = src[m.end():close].replace("\\", " ").split()
    if not tags:
        err("%s in %s parsed to zero tags - refusing to read that as 'no phases'" % (name, path))
    return tags


def parse_tables(doc_lines: list[str], doc_path: str) -> dict:
    """Rows (as cell lists) per known header. A missing or empty table is loud, never green."""
    tables: dict = {}
    for i, raw in enumerate(doc_lines):
        header = raw.rstrip()
        if header not in TABLE_LABEL:
            continue
        rows: list = []
        for body in doc_lines[i + 2:]:          # +2 skips the |---|---| separator
            body = body.rstrip()
            if not body.startswith("|"):
                break
            cells = [c.strip() for c in body.strip("|").split("|")]
            rows.append(cells)
        tables[header] = rows
    for header, label in TABLE_LABEL.items():
        if header not in tables:
            err("%s has no '%s' table header - the registry cannot be parsed, and an empty "
                "parse would read as 'every phase is classified'" % (doc_path, header))
        elif not tables[header]:
            err("%s: the %s has no rows - refusing to read an empty table as 'nothing to "
                "classify'" % (doc_path, label))
    return tables


def collect(tables: dict, header: str, doc_path: str, first_cell_only: bool) -> dict:
    """tag -> row cells, for one table. A duplicate row inside one table is an error."""
    found: dict = {}
    for cells in tables.get(header, []):
        if not cells:
            continue
        scope = cells[0] if first_cell_only else " ".join(cells[1:])
        tags = TICKED.findall(scope)
        if not tags:
            err("%s: a %s row carries no backticked tag: %s"
                % (doc_path, TABLE_LABEL[header], " | ".join(cells)[:120]))
            continue
        if first_cell_only and len(tags) != 1:
            err("%s: a %s row names %d tags in its Tag cell (%s) - one row per phase"
                % (doc_path, TABLE_LABEL[header], len(tags), ", ".join(tags)))
            continue
        for tag in tags:
            if tag in found:
                err("%s: the %s lists '%s' twice" % (doc_path, TABLE_LABEL[header], tag))
            found[tag] = cells
    return found


def compare(doc_tags, array_tags, table_label: str, array_name: str) -> None:
    """Doc <-> runner must agree in BOTH directions; each disagreement names its tag."""
    for tag in sorted(set(doc_tags) - set(array_tags)):
        err("the %s lists '%s' but %s does not contain it - the doc and the runner must agree"
            % (table_label, tag, array_name))
    for tag in sorted(set(array_tags) - set(doc_tags)):
        err("%s contains '%s' but the %s does not list it - the doc and the runner must agree"
            % (array_name, tag, table_label))


def check_classifications(rows: dict, workflow_src, workflow_path: str) -> int:
    unreviewed = 0
    for tag, cells in sorted(rows.items()):
        cls = cells[1] if len(cells) > 1 else ""
        if cls.startswith("step-gated"):
            steps = TICKED.findall(cls)
            if len(steps) != 1:
                err("'%s' is classified step-gated but its cell does not name exactly one "
                    "backticked workflow step: %s" % (tag, cls[:120]))
                continue
            if workflow_src is None:
                err("'%s' claims step-gated on '%s' but %s is absent - the claim cannot be "
                    "verified, so it is not accepted" % (tag, steps[0], workflow_path))
            elif steps[0] not in workflow_src:
                err("'%s' claims step-gated on '%s' but no step of that name exists in %s"
                    % (tag, steps[0], workflow_path))
        elif cls == "deferred":
            if len(cells) < 3 or not cells[2]:
                err("'%s' is deferred with no reason - a deferral must name its measurement" % tag)
        elif UNREVIEWED_RE.match(cls):
            unreviewed += 1
        else:
            err("'%s' has classification '%s' - must be `step-gated` naming a workflow step, "
                "`deferred`, or `unreviewed (pre-ratchet, YYYY-MM-DD)`" % (tag, cls[:80]))
    return unreviewed


def main(argv: list) -> int:
    if len(argv) < 3:
        print("ERROR usage: phase_registry_check.py <run-tests.sh> <maintainer-testing.md> "
              "[<verify-workflow.yml>]")
        return 99
    runner_path, doc_path = argv[1], argv[2]
    workflow_path = argv[3] if len(argv) > 3 else ""
    with open(runner_path, encoding="utf-8") as fh:
        runner_src = fh.read()
    with open(doc_path, encoding="utf-8") as fh:
        doc_lines = fh.read().splitlines()
    workflow_src = None
    if workflow_path:
        try:
            with open(workflow_path, encoding="utf-8") as fh:
                workflow_src = fh.read()
        except OSError:
            workflow_src = None

    registered = parse_array(runner_src, "FF_TAGS", runner_path)
    release = parse_array(runner_src, "FF_RELEASE_TAGS", runner_path)
    optin = parse_array(runner_src, "FF_OPTIN_TAGS", runner_path)
    tables = parse_tables(doc_lines, doc_path)

    rel_rows = collect(tables, REL_HEADER, doc_path, first_cell_only=False)
    optin_rows = collect(tables, OPTIN_HEADER, doc_path, first_cell_only=True)
    unrouted_rows = collect(tables, UNROUTED_HEADER, doc_path, first_cell_only=True)

    compare(rel_rows, release, TABLE_LABEL[REL_HEADER], "FF_RELEASE_TAGS")
    compare(optin_rows, optin, TABLE_LABEL[OPTIN_HEADER], "FF_OPTIN_TAGS")

    # Exactly one classification per phase, and no registered phase left unclassified.
    where: dict = {}
    for header, rows in ((REL_HEADER, rel_rows), (OPTIN_HEADER, optin_rows),
                         (UNROUTED_HEADER, unrouted_rows)):
        for tag in rows:
            where.setdefault(tag, []).append(TABLE_LABEL[header])
    for tag, labels in sorted(where.items()):
        if len(labels) > 1:
            err("'%s' appears in %d tables (%s) - exactly one classification per phase"
                % (tag, len(labels), ", ".join(labels)))
        if tag not in registered:
            err("%s classifies '%s' in the %s but FF_TAGS does not register it - stale row; "
                "remove it or re-register the phase" % (doc_path, tag, labels[0]))
    for tag in registered:
        if tag not in where:
            err("FF_TAGS registers '%s' but no table in %s classifies it - a phase that gates "
                "nothing is an incomplete outcome. Add it to the release table (and "
                "FF_RELEASE_TAGS), the Diagnostic-exclusions table (and FF_OPTIN_TAGS), or "
                "'Registered, not in the release profile' with a classification"
                % (tag, doc_path))

    unreviewed = check_classifications(
        unrouted_rows, workflow_src, workflow_path or "(no workflow path given)")
    if unreviewed > FF_UNREVIEWED_BASELINE:
        err("%d rows are classified `unreviewed`, above the shrink-only baseline of %d "
            "(FF_UNREVIEWED_BASELINE in hooks/local/lib/phase_registry_check.py). A NEW phase "
            "may not be parked as unreviewed - classify it, or gate it."
            % (unreviewed, FF_UNREVIEWED_BASELINE))
    elif unreviewed < FF_UNREVIEWED_BASELINE:
        # TRIPWIRE: below-baseline is RED, not a note. A reviewed row that leaves the constant
        # high frees a slot a later unreviewed row can silently take - a loosening nobody decided.
        err("%d rows are classified `unreviewed`, below the baseline of %d. Lower "
            "FF_UNREVIEWED_BASELINE in hooks/local/lib/phase_registry_check.py to %d in this "
            "commit - the ratchet moves down with every reviewed row, never later"
            % (unreviewed, FF_UNREVIEWED_BASELINE, unreviewed))
    else:
        note("phase registry: %d registered, %d release, %d opt-in, %d unreviewed (baseline %d)"
             % (len(registered), len(release), len(optin), unreviewed, FF_UNREVIEWED_BASELINE))

    for msg in notes:
        print("NOTE " + msg)
    for msg in errors:
        print("ERROR " + msg)
    return min(len(errors), 98)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:                      # never a silent green
        print("ERROR phase registry check crashed: %r" % (exc,))
        sys.exit(99)
