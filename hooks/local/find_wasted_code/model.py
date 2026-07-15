"""Finding + Coverage value objects. Pure data; deterministic ordering."""
from __future__ import annotations

from .constants import finding_id


class Finding:
    __slots__ = ("rule", "tier", "verdict", "severity", "path", "line",
                 "evidence", "fix", "fp_note")

    def __init__(self, rule, tier, verdict, severity, path, line, evidence, fix, fp_note):
        self.rule = rule
        self.tier = tier
        self.verdict = verdict
        self.severity = severity
        self.path = path
        self.line = line
        self.evidence = evidence
        self.fix = fix
        self.fp_note = fp_note

    @property
    def id(self):
        return finding_id(self.rule, self.path, self.line, self.evidence)

    def sort_key(self):
        return (self.rule, self.path, self.line, self.evidence)


class Coverage:
    """Everything the run touched but did NOT confirm as a defect — so silence is
    auditable (an un-scanned file or an unresolved ref is visible, not invisible)."""

    def __init__(self):
        self.scanned = 0
        self.skipped = []          # (path, reason_code)
        self.unresolved = []       # (rule, path, line, why) — could not prove
        self.dismissed = []        # (rule, path, line, "ignore-directive")
        self.w5_py = []            # (path, line) swallow baseline
        self.w5_sh = []            # (path, line) swallow baseline
        self.rules_run = set()

    def skip(self, path, reason):
        self.skipped.append((path, reason))

    def unresolve(self, rule, path, line, why):
        self.unresolved.append((rule, path, line, why))

    def dismiss(self, rule, path, line):
        self.dismissed.append((rule, path, line))
