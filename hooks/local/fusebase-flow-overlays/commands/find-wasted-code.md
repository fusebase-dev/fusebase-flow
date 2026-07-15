---
description: Run the find-wasted-code audit — the code-per-friction sibling of /token-waste-audit and /find-wasted-effort. Statically scans this repo for dead-end tool calls, broken links, missing helpers, footgun configs, and a silent-push-through baseline, then writes a TRACKED report to docs/wasted-code/report.md. Manual-trigger only; read-only except the one report write; findings are review candidates, never auto-fixes. (FuseBase Flow)
---

# /find-wasted-code

Invoke the **find-wasted-code** skill (`flow-skills/find-wasted-code/SKILL.md`).

1. Run `python hooks/local/find-wasted-code.py` (if `python` is missing, run `python3 hooks/local/find-wasted-code.py`). Optional args: `--print` (summary only, no write), `--date YYYY-MM-DD` (deterministic in-report date), `--root PATH`. Self-check: `--selftest` runs the per-rule golden fixtures (adversarial slug corpus, W5 baseline, scope exclusions, output containment, secret-scanner coexistence).
2. Read the report it wrote (`docs/wasted-code/report.md`) — per-rule findings (W1 dead-end refs, W2 broken links, W3 missing helpers, W4 footgun config), each labelled **broken/confirmed** (provable from repo state) or **candidate/inconclusive** (needs human judgment), plus the **Coverage** section (W5 swallowed-error baseline, unresolved references, skipped inputs). Silence is auditable, not proof of cleanliness.
3. Interpret every finding as a review CANDIDATE, never a verdict or an auto-fix — check it against the false-positive classes (`flow-skills/find-wasted-code/references/false-positive-examples.md`). Ambiguous references live under Coverage → Unresolved, never as defects. The W5 baseline is a count for review, not a finding list; annotate an intentional swallow with `find-wasted-code: ignore W5 — <reason>`.
4. Output a Mode A summary in chat: per-rule totals by severity, the W5 baseline counts, and the top confirmed `broken` items with their `file:line`. Do not paste raw file contents. This audit is read-only to the project — it writes only the tracked `docs/wasted-code/report.md` (containment-checked, sentinel-guarded, redaction-safe so it never trips the pre-commit secret scan). Fixes are the operator/PO's call.
5. For a confirmed `broken` finding, recommend the concrete fix the report suggests (fix the path, restore the file/handler, or correct the anchor). Point token/ceremony questions at the sibling audits: `/token-waste-audit` (tokens) and `/find-wasted-effort` (process ceremony).

Non-Claude surfaces (Codex/Cursor/Copilot/Gemini): invoke the `find-wasted-code` skill by name and run the analyzer directly (`python hooks/local/find-wasted-code.py`); it is stdlib-only and surface-independent.
