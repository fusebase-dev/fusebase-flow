#!/usr/bin/env python3
"""Advisory structural check of a report file against one policies/gate-contracts.yml contract.

Enum values are checked only where the report states `<field name>: <value>`; the template
carries lint/typecheck as pasted output, so lint presence comes from the `label` hint.
Unwired by design (decision A4, v5.11 O7): the gate verdict is the Product Owner side's.

Usage: gate_contract_check.py <report-file> <contract-name> <policy-file>
Exit: 0 valid, 1 missing field or invalid value, 2 usage / unknown contract / unreadable policy.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PREFIX = "[verify-gate]"
ENUM_SPEC = re.compile(r"^enum\s*\[(.*)\]$")
PLACEHOLDER = re.compile(r"^(?:-*|—|–|<[^>]*>)$")
SEPARATOR_ROW = re.compile(r"^\|?[\s:|-]*-[\s:|-]*$")
UNESCAPED_PIPE = re.compile(r"(?<!\\)\|")


def name_pattern(field: str) -> str:
    return r"[ _-]?".join(re.escape(part) for part in field.split("_"))


def heading_re(section: str) -> re.Pattern:
    return re.compile(r"^#+\s*(?:\d+[a-z]?\.\s*)?" + re.escape(section) + r"\b", re.IGNORECASE)


def is_present(field: str, spec: dict, text: str) -> bool:
    section = spec.get("section")
    if section:
        return any(heading_re(section).match(line) for line in text.splitlines())
    if re.search(name_pattern(field), text, re.IGNORECASE):
        return True
    label = spec.get("label")
    return bool(label) and label.lower() in text.lower()


def enum_values(spec) -> list:
    m = ENUM_SPEC.match(spec.strip()) if isinstance(spec, str) else None
    return [v.strip() for v in m.group(1).split(",")] if m else []


def cells(row: str) -> list:
    body = row.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") and not body.endswith("\\|") else body
    return [c.strip().replace("\\|", "|") for c in UNESCAPED_PIPE.split(body)]


def section_table(text: str, section: str):
    lines = text.splitlines()
    match = heading_re(section)
    start = next((i for i, line in enumerate(lines) if match.match(line)), None)
    if start is None:
        return None
    level = len(lines[start]) - len(lines[start].lstrip("#"))
    table = []
    for line in lines[start + 1:]:
        s = line.strip()
        if re.match(r"^#{1,%d}\s" % level, s):
            break
        if s.startswith("|"):
            table.append(s)
        elif table:
            break
    return table


def check_section_rows(field: str, spec: dict, text: str) -> list:
    section = spec["section"]
    table = section_table(text, section)
    if table is None:
        return []
    if not table:
        return ["%s: no table under '%s'" % (field.replace("_", " "), section)]
    header = [h.lower() for h in cells(table[0])]
    rows = [cells(r) for r in table[1:] if not SEPARATOR_ROW.match(r)]
    shape = spec.get("item_shape") or {}
    allowed = enum_values(shape.get("status"))
    need_evidence = set(spec.get("evidence_required_for") or [])
    status_col = next((j for j, h in enumerate(header) if "status" in h), None)
    evidence_col = next((j for j, h in enumerate(header) if "evidence" in h), None)
    problems = []
    if allowed and status_col is None:
        problems.append("'%s' table has no Status column (columns: %s)"
                        % (section, ", ".join(cells(table[0]))))
    if need_evidence and evidence_col is None:
        problems.append("'%s' table has no Evidence column (columns: %s)"
                        % (section, ", ".join(cells(table[0]))))
    if problems:
        return problems
    for n, row in enumerate(rows, 1):
        criterion = row[0] if row else ""
        status = row[status_col].strip("` ") if status_col is not None and status_col < len(row) else ""
        if allowed and status not in allowed:
            problems.append("row %d: status '%s' is not %s (%s)"
                            % (n, status, " or ".join(allowed), criterion))
            continue
        if status in need_evidence:
            evidence = row[evidence_col].strip("` ") if evidence_col < len(row) else ""
            if PLACEHOLDER.match(evidence):
                problems.append("row %d: %s without evidence ('%s') (%s)"
                                % (n, status, evidence, criterion))
    minimum = int(spec.get("min_items") or 0)
    if len(rows) < minimum:
        problems.append("%d rows under '%s'; at least %d required" % (len(rows), section, minimum))
    return problems


def check_values(fields: dict, text: str) -> list:
    problems = []
    for field, spec in fields.items():
        spec = spec if isinstance(spec, dict) else {}
        if spec.get("type") == "enum" and spec.get("values"):
            allowed = [str(v).lower() for v in spec["values"]]
            stated = re.compile(r"(?im)" + name_pattern(field)
                                + r"[ \t*_`]*[:=][ \t*_`]*([A-Za-z][\w-]*)")
            for m in stated.finditer(text):
                if m.group(1).lower() not in allowed:
                    problems.append("%s: stated value '%s' is not one of %s"
                                    % (field.replace("_", " "), m.group(1), ", ".join(allowed)))
        if spec.get("type") == "list" and spec.get("section"):
            problems += check_section_rows(field, spec, text)
    return problems


def main(argv: list) -> int:
    if len(argv) != 4:
        print("usage: gate_contract_check.py <report-file> <contract-name> <policy-file>",
              file=sys.stderr)
        return 2
    report, name, policy_path = Path(argv[1]), argv[2], Path(argv[3])
    try:
        import yaml
    except ImportError:
        print("%s PyYAML is not importable (hooks/requirements.txt)" % PREFIX, file=sys.stderr)
        return 2
    try:
        policy = yaml.safe_load(policy_path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        print("%s cannot read %s: %s" % (PREFIX, policy_path, exc), file=sys.stderr)
        return 2
    contract = policy.get(name) if isinstance(policy, dict) else None
    if not isinstance(contract, dict):
        print("%s unknown contract: %s" % (PREFIX, name), file=sys.stderr)
        return 2
    text = report.read_text(encoding="utf-8")
    fields = contract.get("required_fields") or {}
    missing = []
    for field, spec in fields.items():
        spec = spec if isinstance(spec, dict) else {}
        if not spec.get("optional") and not is_present(field, spec, text):
            where = " (section '%s')" % spec["section"] if spec.get("section") else ""
            missing.append(field.replace("_", " ") + where)
    problems = check_values(fields, text)
    if missing:
        print("%s %s INCOMPLETE — missing: %s" % (PREFIX, name, ", ".join(missing)))
    for problem in problems:
        print("%s %s %s" % (PREFIX, name, problem))
    if missing or problems:
        return 1
    print("%s %s: required fields present, stated values valid (advisory structural check; "
          "the verdict is the Product Owner side's, via validation-and-qa)" % (PREFIX, name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
