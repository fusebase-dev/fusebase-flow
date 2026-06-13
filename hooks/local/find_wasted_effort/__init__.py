"""find_wasted_effort — per-rule evaluators + evidence collectors for the A2
ceremony audit. Extracted from hooks/local/find-wasted-effort.py along the
per-rule seam (FR-25 module-size: keep the CLI orchestrator under the 800-line
ceiling without a mechanical split). The CLI entrypoint stays at
hooks/local/find-wasted-effort.py; this package holds the load-bearing logic so
each surface (evidence, rules, selftest) stays single-pass readable.

READ-ONLY (Phase 1 / D4): nothing here writes outside the analyzer's own
gitignored state/audit/ report. No memory/overlay/spec edits, no prune/reclassify.
"""

from .constants import (  # noqa: F401
    CONFIRMED,
    DISMISSED,
    INCONCLUSIVE,
    DEFAULT_WINDOW,
    DUP_BLOCK_MIN,
    UNUSED_GATE_MIN,
    FULL_SUITE_MAX,
    FALSE_POSITIVE_HEADER,
    PREVENTS_RE,
    PAREN_STRIP_RE,
)

__all__ = [
    "CONFIRMED",
    "DISMISSED",
    "INCONCLUSIVE",
    "DEFAULT_WINDOW",
    "DUP_BLOCK_MIN",
    "UNUSED_GATE_MIN",
    "FULL_SUITE_MAX",
    "FALSE_POSITIVE_HEADER",
    "PREVENTS_RE",
    "PAREN_STRIP_RE",
]
