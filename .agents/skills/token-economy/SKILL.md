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
| **TE-01 · Read-scoped** — read the slice that answers the question (offset/limit, grep→targeted read), not the whole file for one fact | Scoped reads are FACT-FINDING; before an EDIT, read enough surrounding context to hold the file's invariants — never grep-and-edit blind | — |
| **TE-02 · No re-reads of unchanged in-context files** — a file already in context is not read again | Re-read REQUIRED after invalidation events: your own Edit/Write, hooks/formatters, parallel/delegated agents, git operations, a failed Edit match, context compaction. Uncertain whether it changed → re-read is the CORRECT spend | — |
| **TE-03 · Generated/vendored restraint** — never read large generated, vendored, lock, build, cache, or compiled outputs | Unless the generated artifact is itself the subject of the task. Shared definition of generated/vendored = `policies/module-size.yml: exempt_globs` | — |
| **TE-04 · Pre-cached identifiers** — never re-derive IDs the handoff already carries; verify (one quick read), don't re-discover | Stale-looking ID → verify, then surface; don't silently re-derive | POINTER → `templates/handoff-implement.md` § Pre-cached identifiers |
| **TE-05 · Two-strike rule** — the same failing approach is not attempted a third time | "Same approach" = same action, same inputs, expecting a different result. NOT strikes: FR-10 3/3 reproduction runs, test reruns after a real change, bounded labeled flaky-external retries. On 2 strikes → diagnose via `zoom-out` (FR-20) + `validation-and-qa` (FR-10) | — |
| **TE-06 · Targeted edits over whole-file rewrites** — patch the changed region; don't regenerate the file | FR-18 supersede rewrites are MANDATED, not waste | — |
| **TE-07 · Pointers over reprints / reference-once** — in chat and handoffs cite the artifact path, don't repaste its body; once a large body (big tool result, log, JSON, file region) is in context, later turns refer to it by its retrieval handle (path+window, request ID, report path, test name) instead of re-sending it | A fresh first inclusion, or a deliberately re-run command's NEW output, is not a re-send; never drop a decision, ID, or evidence the next step needs. Doc-side rule is FR-23 (pointers over restatement) | `flow-skills/documentation-budget/SKILL.md` |
| **TE-08 · Record-then-read** — read durable evidence once after the run instead of agent-side polling | Sole exception (first live drive of fresh code) is bounded | POINTER → `flow-skills/smoke-testing/SKILL.md` § Verification cost discipline |
| **TE-09 · Delegation economics** — delegate only when the sub-agent's context floor costs less than the tokens the split saves | Bounded, disjoint slices only | `flow-skills/task-delegation/SKILL.md` |

## Context compression discipline

Extends FR-26 to **large context and large output** — when the input or a tool result is big enough that loading it whole is itself the waste. This is read-time and reasoning-time routing, **not a budget**: it slices and points to large artifacts and keeps compressed context honest. It never authorizes skipping a needed read or thinning verification — the Guardrail still governs.

| Rule | Guard / what it must never become |
|---|---|
| **TE-10 · Content-route before consuming** — classify a large input (code, log, JSON, test output, diff, markdown, prose, transcript, generated/vendored output, binary/asset metadata) before deciding how much of it to read | Routing decides depth, never whether to verify; an authoritative artifact still gets read in full when the task needs its invariants |
| **TE-11 · Extract before reasoning** — for large logs, test output, JSON, traces, transcripts, and search results, pull the relevant slice or a summary first instead of loading the whole body into reasoning context | The slice is for triage; if it is ambiguous or the decision is load-bearing, widen it or open the source |
| **TE-12 · Preserve the retrieval path** — every summary or compressed note carries a handle to reopen the original: source path, command, report path, line/window pointer, request ID, or test name | A note with no retrieval handle is a dead end — you must always be able to get back to ground truth |
| **TE-13 · Original-before-edit** — before editing code, changing product logic, approving acceptance criteria, deciding security / billing / permissions / client-data, or closing verification, reopen and read the authoritative source | A summary may point you AT the change; it never substitutes for reading the file you are about to edit or approve |
| **TE-14 · Summary is not authority** — compressed/summarized context is for exploration and triage | NEVER the sole basis for implementation, security, permissions, billing, migrations, compliance, public API contracts, client-data access, or acceptance criteria — those decide against the original |
| **TE-15 · Stable context floor** — don't rewrite always-on rules, agent files, command files, handoffs, or governance docs just to improve phrasing | A small, stable instruction surface is cheaper every session than a "better-worded" one; governance edits are explicit, reviewed, diff-based tickets — never an optimization side effect |
| **TE-16 · Cross-agent dedupe** — handoffs between PO, AI Developer, Architect, Deploy, QA, and other roles carry decisions, IDs, paths, and pointers, not duplicated full artifacts | Dedupe never drops a decision or an ID the next role needs; every pointer must resolve |
| **TE-17 · Large-output hygiene (anticipate, then narrow)** — when a command's output is plausibly large or unbounded (full logs, whole-tree listings, unfiltered queries/dumps), scope the FIRST invocation — limit/offset, tail, grep/jq, targeted test, shorter traceback, or write-to-report-then-read — rather than running it wide and narrowing only on the rerun | Scoping serves the question; never scope so tight that needed evidence is excluded, and an estimated size is never a hard cap or a reason to skip a needed read |
| **TE-18 · Compression is not verification** — never use compression/summarization to skip reproduction, skip smoke tests, thin acceptance evidence, or hide uncertainty | **Quality outranks tokens** — on any conflict the correctness/safety floor wins, exactly as in the Guardrail |

Generated/vendored restraint and reference-once live in the Rules table as TE-03 / TE-07 — one canonical row each.

## Fusebase-CLI grounding — known large-output surfaces (TE-17 instances)

Pre-identified so the FIRST invocation is scoped — not the rerun. `/token-waste-audit`'s `large-output` class flags results ≥20k chars from these surfaces; cite the TE ID in fixes.

| Surface | Characteristic size | Scope the FIRST invocation |
|---|---|---|
| `fusebase remote-logs runtime <appId>` | up to 300 entries × long lines (default 100) | `--tail 50` first; add `--type system` / `--container <name>` when the symptom names a layer; widen only if the slice misses the event |
| `fusebase remote-logs build <appId>` | full cloud build log | fetch once, read tail-first for the failing step; grep the captured output rather than re-fetching |
| Local dev logs `<app-dir>/logs/dev-<timestamp>/` (dev-debug-logs) | one file per source, whole session | pick the ONE file the symptom maps to per the dev-debug-logs routing table, grep→targeted read; never cat the whole session dir |
| MCP dashboard payloads (`getDashboardViewData`, schema/prompt dumps — fusebase-dashboards) | full row sets / whole schema | pass filters + limits in the call; `prompts_search` with narrow `groups`; never pull all rows to answer a one-row question |
| Gate MCP discovery / org user listing (fusebase-gate) | full org/contract listings | scope to the user/contract in question; record-then-read (TE-08) for repeated checks |

Guard: scoping serves the question — never exclude the evidence the diagnosis needs (TE-17's guard governs). Surface names/flags track the vendored CLI provider skills; on a FuseBase CLI refresh, re-check this table against `remote-logs` / `dev-debug-logs` / `fusebase-dashboards` / `fusebase-gate` skills.

## Measure it

- **Claude Code:** run `/token-waste-audit` (command file `.claude/commands/token-waste-audit.md`) or directly `python hooks/local/token-waste-audit.py [--last N] [--dir PATH]`. Deterministic stdlib-only parser over this project's transcripts: requestId-deduped per-session totals (requests, output tokens, cache read/creation, tool-result size estimates) + leak signatures (identical-window Reads ≥3×, polling-shaped Bash repeats, top-10 largest tool results, large rewrites of pre-existing paths, **`large-output` candidates** — tool results ≥20k chars from any output-producing tool, built-in **or MCP** (write tools excluded) — and **`repeat-output` candidates** — the same large body re-sent across turns, fingerprinted by a one-way hash, never the content. All mapped to TE-xx rule IDs (§ Rules / § Context compression discipline)). Findings are **candidates that MAY indicate** an FR-26 rule — the report header lists the known false-positive classes. Report → `state/audit/token-waste-audit-<date>.md` (gitignored).
- **Other surfaces (Codex / Cursor / Copilot / Gemini):** transcript metrics are unavailable — say so explicitly ("transcript metrics unavailable on this surface") and degrade to the repo-side summary the parser also produces: largest tracked source files, `docs/tmp/handoff.md` size, optional `bash hooks/local/check-module-size.sh --all`. Never fabricate transcript numbers.

## Growth rule

A waste pattern that recurs across audits and matches no row above → add one rule row (with its quality guard and the next free TE-xx ID — IDs are append-only, never renumbered: audit reports and problem-catalog entries cite them) via `skill-authoring`. This includes recurring large-output / large-context patterns surfaced by the `large-output` audit class — add the row **clean-room and dependency-free** (never reach for a third-party compression tool). Project-specific waste patterns stay in project docs/skills, not here unless they generalize across Flow use cases.

## Anti-patterns

- Citing FR-26 to skip a needed first-read, a reproduction run, or a verification step — that inverts the guardrail; the correctness/safety floor wins.
- Treating audit findings as verdicts. They are candidates: FR-18 supersede rewrites, mirror regeneration, and deliberate FR-10 reproduction look identical to waste in the metrics.
- Hard token budgets, caps, or gates on token counts — a budget gate trains truncation (intelligence damage); FR-26 is deliberately write-time discipline + retrospective audit only.
- Grep-and-edit blind: editing a file whose invariants you never read because "scoped reads are cheaper".
- Treating a summary as the source of truth for a final edit or an approval — the original is reopened first (§ Context compression discipline).
- Compressing away the evidence verification needs — reproduction runs, smoke output, acceptance evidence, or a stated uncertainty.
- Using token economy as an excuse to avoid opening the authoritative file before deciding.
- Adding a third-party compression dependency to Flow core — FR-26 economy is behavioral discipline + a deterministic stdlib audit, not a tool to install.
- Copying a third-party compression implementation, prompt, or doc into Flow — canonical Flow content is clean-room original.
- Rewriting always-on / governance files for cosmetic phrasing under the banner of "optimization" — governance edits are explicit, reviewed, diff-based.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
