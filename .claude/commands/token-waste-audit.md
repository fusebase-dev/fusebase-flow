---
description: Run the FR-26 token-waste audit — parse this project's Claude Code transcripts deterministically (requestId-deduped totals + leak-signature candidates, incl. large-output), map findings to FR-26 rules, and report concrete fixes. Read-only; report goes to state/audit/ (gitignored). (FuseBase Flow)
---

# /token-waste-audit

Invoke the **token-economy** skill's measurement path (`flow-skills/token-economy/SKILL.md` § Measure it).

1. Run `python hooks/local/token-waste-audit.py` (if `python` is missing, run `python3 hooks/local/token-waste-audit.py`). Optional args: `--last N` (sessions to audit), `--dir PATH` (transcript dir override).
2. Read the report it wrote (`state/audit/token-waste-audit-<date>.md`) — per-session deduped totals, top tool-result sinks, leak-signature candidates. This includes **large-output compression candidates** (tool results ≥20k chars from any output-producing tool — built-in or MCP — whose size suggests scoped reads, narrower commands, report files, jq/grep/filtering, targeted tests, shorter tracebacks, or pointer-backed summaries before reasoning over the content) and **repeat-output candidates** (the same large body re-sent across turns, matched by a one-way fingerprint — never the content — that should be referenced by its handle instead of re-pasted).
3. Interpret every finding as a CANDIDATE that MAY indicate the cited FR-26 rule. Confirm or dismiss each one against the report header's false-positive classes before calling it waste — for `large-output` that includes an intentional first read of a large file (to hold its invariants), FR-18 supersede rewrites / mirror regeneration, generated output that is itself the task's subject, deliberate FR-10 reproduction evidence, and a one-time large diagnostic report written then read once.
4. Output a Mode A summary in chat: totals table, top sinks, confirmed-vs-dismissed candidates (by class, incl. large-output). Do not paste raw tool-result text (the report never contains it; keep it that way).
5. Recommend concrete fixes, each citing the FR-26 rule row it applies — scoped reads, re-read only after invalidation, two-strike diagnose via `zoom-out`, record-then-read per `smoke-testing` § Verification cost discipline (`flow-skills/token-economy/SKILL.md` § Rules); map `large-output` and `repeat-output` candidates to `flow-skills/token-economy/SKILL.md` § Context compression discipline (extract/scope/filter; reference an in-context body by its handle instead of re-sending it; pointer-backed summaries with a retrieval handle).

Non-Claude surfaces (Codex/Cursor/Copilot/Gemini): transcript metrics are unavailable — invoke the `token-economy` skill and use its repo-side fallback (the parser prints it and exits 0).
