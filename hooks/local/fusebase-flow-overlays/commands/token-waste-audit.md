---
description: Run the FR-26 token-waste audit — parse this project's Claude Code transcripts deterministically (requestId-deduped totals + leak-signature candidates), map findings to FR-26 rules, and report concrete fixes. Read-only; report goes to state/audit/ (gitignored).
---

# /token-waste-audit

Invoke the **token-economy** skill's measurement path (`flow-skills/token-economy/SKILL.md` § Measure it).

1. Run `python hooks/local/token-waste-audit.py` (if `python` is missing, run `python3 hooks/local/token-waste-audit.py`). Optional args: `--last N` (sessions to audit), `--dir PATH` (transcript dir override).
2. Read the report it wrote (`state/audit/token-waste-audit-<date>.md`) — per-session deduped totals, top tool-result sinks, leak-signature candidates.
3. Interpret every finding as a CANDIDATE that MAY indicate the cited FR-26 rule — check it against the false-positive classes in the report header (FR-18 rewrites, mirror regeneration, deliberate FR-10 reproduction) before treating it as waste.
4. Output a Mode A summary in chat: totals table, top sinks, confirmed-vs-dismissed candidates. Do not paste raw tool-result text (the report never contains it; keep it that way).
5. Recommend concrete fixes, each citing the FR-26 rule row it applies (`flow-skills/token-economy/SKILL.md` § Rules) — e.g., scoped reads, re-read only after invalidation, two-strike diagnose via `zoom-out`, record-then-read per `smoke-testing` § Verification cost discipline.

Non-Claude surfaces (Codex/Cursor/Copilot/Gemini): transcript metrics are unavailable — invoke the `token-economy` skill and use its repo-side fallback (the parser prints it and exits 0).
