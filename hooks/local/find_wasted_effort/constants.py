"""Shared constants + the prevents:-marker parse regex (single source of truth
for the find-wasted-effort analyzer). The regex is kept byte-identical to
policies/ratchet-governance.yml: annotation_marker.parse_regex so the analyzer
and the policy describe the same grammar (FR-22: the WHY lives in the taxonomy,
the marker is the retrieval pointer)."""

import re

DEFAULT_WINDOW = 20          # rounds/commits to consider
DUP_BLOCK_MIN = 3            # rule 3: verbatim block in >= N artifacts
UNUSED_GATE_MIN = 3          # rule 1: N rounds, every deviation approved
FULL_SUITE_MAX = 2           # rule 2: baseline + end is the non-waste norm

CONFIRMED, DISMISSED, INCONCLUSIVE = "confirmed", "dismissed", "inconclusive"

# Reused from the token-economy substrate (token-waste-audit.py) — do not diverge.
FALSE_POSITIVE_HEADER = (
    "Findings below are review CANDIDATES that MAY indicate outcome-neutral "
    "ceremony — not verdicts, and never remove instructions (the PO owns "
    "subtraction; policies/ratchet-governance.yml). A clean observation window "
    "is NOT proof a control is waste: a gate stop can be low-frequency / "
    "high-severity (catastrophic-low-frequency). Each finding states the "
    "contrary evidence that dismisses it; absence of contrary evidence in a "
    "short window is INCONCLUSIVE, never confirmed. Known false-positive "
    "classes per rule: flow-skills/find-wasted-effort/references/"
    "false-positive-examples.md."
)

# Parse regex shared with policies/ratchet-governance.yml: annotation_marker.parse_regex
# Captures the comma-separated class list; terminates at the comment close, '#',
# em-dash (pointer note), or EOL. Inline per-class parentheticals / severity tags
# are stripped per-class by PAREN_STRIP_RE.
PREVENTS_RE = re.compile(r"prevents:\s*([a-z0-9][a-z0-9 ,\-()/]*?)\s*(?:-->|#|—|$)")
PAREN_STRIP_RE = re.compile(r"\s*\([^)]*\)\s*")


def parse_prevents_classes(line):
    """Return the set of incident-classes named by a `prevents:` marker on `line`
    (empty set if none). Per-class parentheticals / severity tags are stripped."""
    out = set()
    m = PREVENTS_RE.search(line)
    if m:
        for c in m.group(1).split(","):
            c = PAREN_STRIP_RE.sub(" ", c).strip()
            if c:
                out.add(c)
    return out
