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
| **TE-05 · Two-strike rule** — the same failing approach is not attempted a third time | "Same approach" = same action, same inputs, expecting a different result. NOT strikes: FR-10 3/3 reproduction runs, test reruns after a real change, bounded labeled flaky-external retries, a delegate re-dispatch inside the bounded delegate-retry envelope (`flow-skills/liveness-discipline`) — the approach was never executed. On 2 strikes → diagnose via `zoom-out` (FR-20) + `validation-and-qa` (FR-10) | — |
| **TE-06 · Targeted edits over whole-file rewrites** — patch the changed region; don't regenerate the file. This holds for an FR-18 supersede too: supersede replaces stale *semantics*, not the file — targeted `Edit` when most sections are unchanged | A full `Write` is the CORRECT primitive (not waste) for structure/mode/ticket changes or when most sections changed — FR-18 mandates the replaced semantics, never the rewrite tool | `flow-skills/role-discipline/SKILL.md` § Supersede Convention |
| **TE-07 · Pointers over reprints / reference-once** — in chat and handoffs cite the artifact path, don't repaste its body; once a large body (big tool result, log, JSON, file region) is in context, later turns refer to it by its retrieval handle (path+window, request ID, report path, test name) instead of re-sending it | A fresh first inclusion, or a deliberately re-run command's NEW output, is not a re-send; never drop a decision, ID, or evidence the next step needs. Doc-side rule is FR-23 (pointers over restatement) | `flow-skills/documentation-budget/SKILL.md` |
| **TE-08 · Record-then-read** — read durable evidence once after the run instead of agent-side polling | Exactly two bounded, labeled exceptions: the first live drive of fresh code, and delegate-PROGRESS polling under the bounded delegate-retry envelope (3 attempts / 5 min / one progress read per interval — a delegate that never started leaves no record to read) | POINTER → `flow-skills/smoke-testing/SKILL.md` § Verification cost discipline · `flow-skills/liveness-discipline/SKILL.md` § Bounded delegate-retry envelope |
| **TE-09 · Delegation economics** — delegate only when the sub-agent's context floor costs less than the tokens the split saves. Floor: ~40–80k tokens on its first request (platform prompt, tools, skill listing, instructions; p10–p90, 2026-10) plus what it must re-read. A reused worker re-reads nothing but pays its whole context on every request: at ~300k a fresh successor is cheaper once the remaining work exceeds ~30 requests, at ~500k ~13 | Bounded, disjoint slices only; the reuse bound is `task-delegation` § Correction ownership | `flow-skills/task-delegation/SKILL.md` |

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

## Residency and cache lifetime

Every request re-reads the agent's whole context, so cost grows with context × requests; a context idle past its cache lifetime is re-written in full on the next request. Like § Context compression discipline this is routing, not a budget — the Guardrail governs.

| Rule | Guard / what it must never become |
|---|---|
| **TE-19 · Bounded residency** — plan each delegated slice to finish in about 50 tool calls or fewer (sub-agent context passes ~300k near 50 tool uses and ~500k near 65–90; three consumer runs, 2026-10); split larger work into sequential task groups, each a fresh worker that resumes from records (`task-delegation` successor contract); the main session offers rotation at milestones (FR-17) | A size is a plan-time split and a rotation point, never truncation: a worker past it finishes its slice and the NEXT group starts fresh. Never split below one coherent, independently verifiable task. Sizing applies to work already eligible for delegation (`task-delegation` §§1–4) — it is never a reason to delegate |

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

| Claude Code measurement | Contract |
|---|---|
| Invocation | `/token-waste-audit` (`.claude/commands/token-waste-audit.md`) or `python hooks/local/token-waste-audit.py [--last N] [--dir PATH] [--main-only]`; stdlib-only |
| Scope | `--last N` selects top-level sessions by modification time; each brings `<sid>/subagents/agent-*.jsonl` and `<sid>/subagents/workflows/wf_*/agent-*.jsonl`; `journal.jsonl` excluded. `--main-only` reproduces the old main-session scope |
| Totals | Last usage per `requestId`; main row + sub-agent aggregate (agents, workflows, requests, output, cache read/creation); top-10 agents by cache read, with workflow id; findings run per transcript and name the originating agent |
| Cost attribution (first) | Main/sub-agent × cache read, cache write 5m/1h, uncached input, output; each request uses its `message.model` and the dated rate table in `hooks/local/token_waste_audit/costing.py`. List-price estimate (rates as of 2026-10); subscription billing differs. Unknown/`<synthetic>` models remain in tokens, excluded from USD with an unpriced-request line; unsplit creation priced at 5m |
| Context residency | Context = cache read + cache creation + input per request; peak/average/requests + compactions (`compact_boundary` only); top-10 transcripts by cache-read cost. One session-level `context-residency` signal when transcripts peaking ≥500k hold ≥50% of session cache-read cost; maps to TE-19 (bounded task groups) and FR-17 rotation |
| Cache rewrite / polling cost | `cache-rewrite`: start-to-start gap in the same transcript > explicit creation TTL (1h if its split >0, otherwise 5m if >0; unknown skipped) and creation ≥100k. Full count/tokens/USD split main/sub-agents. Polling: distinct requests issuing the repeated command, context sum × each request's cache-read rate |
| Ranking / session cap | Live rows sorted by estimated USD (unpriced last); text/image payload estimates use request input rates, rewrite payload estimates use output rates. Estimates overlap and are not avoidable-spend totals. `large-output`, `repeat-output`, `cache-rewrite`: top 10 each across main + agents per session, with "N more suppressed (session cap)"; other classes retained in full |
| Text findings | Identical-window Reads ≥3×; polling-shaped Bash repeats; large rewrites of pre-existing paths; `large-output` ≥20k text chars from output-producing built-in/MCP tools (write tools excluded); `repeat-output` identical large text bodies ≥2×; top-10 text results |
| Images | Separate image count and token **estimate**: PNG IHDR / JPEG SOFn dimensions, long edge scaled to ≤1568 px, ≈width×height/750; unknown dimensions = 1600. Base64 excluded from text sizes, `large-output` and `repeat-output` |
| `image-reread` | Identical image bytes ≥2× in one transcript → TE-02 candidate; same path with changed bytes = re-capture, not image re-read |
| Privacy / interpretation | No message/thinking/tool-result text, image data or hook output in reports; attachment lines excluded. Paths keep head…tail; commands keep head truncation. Candidates MAY indicate the cited TE rule; report header lists false positives. `context-residency` / `cache-rewrite` are cost signals, not proof that the work was unnecessary |
| Output | `state/audit/token-waste-audit-<date>.md` (gitignored) |

- **Auto-classification is labeled, never silent** (`--probe-command CMD` adds this ticket's documented gate probes, repeatable). Two conjunctive rules only: `growing-source-tail` (same full read key **and** monotonic growth or all-differing digests **and** no contradictory event — an intervening write to that path, a compaction between the reads, or an error-shaped result keeps it live; a size-difference-only re-read stays live) and `possible-FR-10-triple` (exactly-3 runs are **labeled**; dismissed only when the command is probe-shaped — a test runner, `--dry-run`, or a health/status/version verb — because three failed retries and three polls are count-identical to a reproduction triple; the count is runs *since the last write*, not truly consecutive). Every dismissal prints the rule that fired **and** its evidence, and is counted in a section **separate** from live findings. The run names one of four terminal states in words — candidates found · all auto-classified · no candidates above thresholds · no transcripts/parse failure. **Silence is never proof of cleanliness.**
- **Other surfaces (Codex / Cursor / Copilot / Gemini):** transcript metrics are unavailable — say so explicitly ("transcript metrics unavailable on this surface") and degrade to the repo-side summary the parser also produces: largest tracked source files, `docs/tmp/handoff.md` size, optional `bash hooks/local/check-module-size.sh --all`. Never fabricate transcript numbers.

## Growth rule

A waste pattern that recurs across audits and matches no row above → add one rule row (with its quality guard and the next free TE-xx ID — IDs are append-only, never renumbered: audit reports and problem-catalog entries cite them) via `skill-authoring`. This includes recurring large-output / large-context patterns surfaced by the `large-output` audit class — add the row **clean-room and dependency-free** (never reach for a third-party compression tool). Project-specific waste patterns stay in project docs/skills, not here unless they generalize across Flow use cases.

## Anti-patterns

- Citing FR-26 to skip a needed first-read, a reproduction run, or a verification step — that inverts the guardrail; the correctness/safety floor wins.
- Treating audit findings as verdicts. They are candidates: a warranted FR-18 full-`Write` supersede (structure/mode/ticket change, or most sections changed), mirror regeneration, and deliberate FR-10 reproduction look identical to waste in the metrics.
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
