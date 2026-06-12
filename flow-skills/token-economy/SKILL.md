---
name: token-economy
description: Use when implementing, debugging, or running long tool-using work sessions, or when the operator asks about "token waste", "session cost", "why is this so expensive", or runs "/token-waste-audit" — delivers FR-26's execution-time economy rules (scoped reads, no re-reads of unchanged in-context files, two-strike retry rule, targeted edits) with their quality guards, plus the measurement path. Do NOT use for app-decomposition token economy (product-apps-decomposition owns that), verification polling economics (smoke-testing § Verification cost discipline owns that), doc budgets (documentation-budget owns that), or to justify skipping needed reads / thinning verification — quality outranks tokens.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: "3.20"
risk_level: low
invocation: automatic
expected_outputs:
  - execution-time behavior matching the FR-26 rules table (redundant consumption eliminated; quality guards honored)
  - /token-waste-audit report interpreted as candidates mapped to FR-26 rules (Claude Code), or the explicit repo-side fallback on other surfaces
related_workflows:
  - greenlight-implement.md
  - lightweight-lane.md
hook_dependencies:
  - none
---

# Token Economy (FR-26)

## Guardrail first (the rule's first clause)

**Quality outranks tokens.** These rules eliminate **REDUNDANT** consumption only — never skip a needed first-read, never thin verification, never truncate reasoning. On any conflict, the correctness/safety floor wins (same floor language as FR-21: ceremony drops, safety never). Citing FR-26 to avoid a read or a verification step inverts the rule.

## Rules (each with its quality guard)

| Rule | Guard / carve-out | Canonical home (if pointer) |
|---|---|---|
| **Read-scoped** — read the slice that answers the question (offset/limit, grep→targeted read), not the whole file for one fact | Scoped reads are FACT-FINDING; before an EDIT, read enough surrounding context to hold the file's invariants — never grep-and-edit blind | — |
| **No re-reads of unchanged in-context files** — a file already in context is not read again | Re-read REQUIRED after invalidation events: your own Edit/Write, hooks/formatters, parallel/delegated agents, git operations, a failed Edit match, context compaction. Uncertain whether it changed → re-read is the CORRECT spend | — |
| **Never read generated/vendored/lock files** | Unless the generated output is itself the subject of the task. Shared definition of generated/vendored = `policies/module-size.yml: exempt_globs` | — |
| **Pre-cached identifiers** — never re-derive IDs the handoff already carries; verify (one quick read), don't re-discover | Stale-looking ID → verify, then surface; don't silently re-derive | POINTER → `templates/handoff-implement.md` § Pre-cached identifiers |
| **Two-strike rule** — the same failing approach is not attempted a third time | "Same approach" = same action, same inputs, expecting a different result. NOT strikes: FR-10 3/3 reproduction runs, test reruns after a real change, bounded labeled flaky-external retries. On 2 strikes → diagnose via `zoom-out` (FR-20) + `validation-and-qa` (FR-10) | — |
| **Targeted edits over whole-file rewrites** — patch the changed region; don't regenerate the file | FR-18 supersede rewrites are MANDATED, not waste | — |
| **Pointers over reprints** — in chat and handoffs, cite the artifact path; don't repaste its body | Doc-side rule is FR-23 (pointers over restatement) | `flow-skills/documentation-budget/SKILL.md` |
| **Record-then-read** — read durable evidence once after the run instead of agent-side polling | Sole exception (first live drive of fresh code) is bounded | POINTER → `flow-skills/smoke-testing/SKILL.md` § Verification cost discipline |
| **Delegation economics** — delegate only when the sub-agent's context floor costs less than the tokens the split saves | Bounded, disjoint slices only | `flow-skills/task-delegation/SKILL.md` |

## Measure it

- **Claude Code:** run `/token-waste-audit` (command file `.claude/commands/token-waste-audit.md`) or directly `python hooks/local/token-waste-audit.py [--last N] [--dir PATH]`. Deterministic stdlib-only parser over this project's transcripts: requestId-deduped per-session totals (requests, output tokens, cache read/creation, tool-result size estimates) + leak signatures (identical-window Reads ≥3×, polling-shaped Bash repeats, top-10 largest tool results, large rewrites of pre-existing paths). Findings are **candidates that MAY indicate** an FR-26 rule — the report header lists the known false-positive classes. Report → `state/audit/token-waste-audit-<date>.md` (gitignored).
- **Other surfaces (Codex / Cursor / Copilot / Gemini):** transcript metrics are unavailable — say so explicitly ("transcript metrics unavailable on this surface") and degrade to the repo-side summary the parser also produces: largest tracked source files, `docs/tmp/handoff.md` size, optional `bash hooks/local/check-module-size.sh --all`. Never fabricate transcript numbers.

## Growth rule

A waste pattern that recurs across audits and matches no row above → add one rule row (with its quality guard) via `skill-authoring`. Project-specific waste patterns stay in project docs/skills, not here.

## Anti-patterns

- Citing FR-26 to skip a needed first-read, a reproduction run, or a verification step — that inverts the guardrail; the correctness/safety floor wins.
- Treating audit findings as verdicts. They are candidates: FR-18 supersede rewrites, mirror regeneration, and deliberate FR-10 reproduction look identical to waste in the metrics.
- Hard token budgets, caps, or gates on token counts — a budget gate trains truncation (intelligence damage); FR-26 is deliberately write-time discipline + retrospective audit only.
- Grep-and-edit blind: editing a file whose invariants you never read because "scoped reads are cheaper".

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
