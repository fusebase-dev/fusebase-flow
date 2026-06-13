---
description: Run the A2 find-wasted-effort audit — the process-per-outcome (ceremony) sibling of /token-waste-audit. Parses Flow artifacts on disk (gate/deploy reports, handoffs, approval artifacts, git log, prevents: annotations) for ceremony that bought no safety outcome. Read-only; report goes to state/audit/ (gitignored). Findings are review candidates, never auto-prune.
---

# /find-wasted-effort

Invoke the **find-wasted-effort** skill (`flow-skills/find-wasted-effort/SKILL.md`).

1. Run `python hooks/local/find-wasted-effort.py` (if `python` is missing, run `python3 hooks/local/find-wasted-effort.py`). Optional args: `--window N` (commits/rounds to consider), `--root PATH`. Self-check: `--selftest` runs the synthetic per-rule fixtures.
2. Read the report it wrote (`state/audit/find-wasted-effort-<date>.md`) — per-rule findings (rules 1,2,3,5,6,7; rule 4 is CUT), each labelled **confirmed / dismissed / inconclusive** with the contrary evidence searched, plus the coverage section (D5 — which `prevents:`-annotated controls were in scope).
3. Interpret every finding as a review CANDIDATE, never a verdict or a remove instruction — check it against the false-positive classes (`flow-skills/find-wasted-effort/references/false-positive-examples.md`). A clean window is NOT proof a control is waste (`catastrophic-low-frequency` controls are expected to sit idle).
4. Output a Mode A summary in chat: per-rule verdict table, coverage, totals. This audit is read-only in Phase 1 — do not remove any ceremony element, edit memory/overlays, or reclassify a lane; pruning is the PO's call via the `policies/ratchet-governance.yml` prune protocol.
5. For ceremony that is genuinely outcome-neutral, recommend the PO open a review (A3), citing named incident-class + window + negative examples. Point context-rebuild questions at `/token-waste-audit`'s cross-session aggregate (rule 4 is covered there, not here).

Non-Claude surfaces (Codex/Cursor/Copilot/Gemini): invoke the `find-wasted-effort` skill by name and run the analyzer directly (`python hooks/local/find-wasted-effort.py`); it is stdlib-only and surface-independent.
