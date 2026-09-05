---
name: role-discipline
description: ALWAYS load at session start; mandatory, never on-demand. After self-attesting, Read references/<role>.md for your role (Product Owner / AI Developer / Architect / Deploy phase) — don't-list + refusal phrasing. Shared-protocol prohibitions and FR-24 digest stay resident; bodies load from references/shared-protocols.md.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: medium
invocation: automatic
mandatory_load: true
expected_outputs: [refusal, adherence]
related_workflows: [violation-recovery.md]
hook_dependencies:
  - session_start                       # presence enforced via REQUIRED_TOP_FILES
---

> **Do not re-Read this file if it is already in your context.** If this exact SKILL.md body is already present in your context (surfaces that auto-load `.claude/skills/` or `.agents/skills/`), do not Read this file again — seeing the name/description in a skill index does **not** count. If it is not present, read it once. Delegated sub-agent sessions do not inherit an auto-load: they read it. This exemption covers **this file only** — `references/<role>.md` is a separate required read (§ Per-role scoped loading), and an auto-load never delivers it.
>
> Surface truth (AC11, verified): **no surface injects this body** — Claude Code and Codex supply description/metadata only; Gemini, Copilot, Cursor and delegated sub-agents supply nothing. Read it once when the body is not already in context.

# Role discipline

Resident role rails; load procedures only when invoked.

## Required inputs

| Input | If missing |
|---|---|
| Self-attested role | STOP — attest before any other action |
| `FLOW_RULES.md` (FR-01..FR-27, repo root) | read at session start **down to `## Amendment log`** (dated history — never load it). FR-09/18/22/23/25/26 also arrive always-on via § Write-time discipline digest (FR-24). |
| `policies/command-policy.yml` | hooks consult it; don't duplicate the check |

## Per-role scoped loading

**Read your role's reference file** — your don't-list + exact refusal phrasing live there; no auto-load delivers them. Cross-check every action against it. Another role's file: on demand (violation-recovery, or drafting a handoff it consumes).

| Role | Read |
|---|---|
| **Product Owner** | `references/product-owner.md` (+ `references/architect.md` on escalation) |
| **AI Developer** | `references/ai-developer.md` |
| **Deploy phase** | `references/deploy.md` |
| **Architect** (standalone) | `references/architect.md` |

## Shared protocols — prohibitions resident, bodies lazy

Each section is a **stub carrying its prohibition**; all apply to every role (§ Operator Relay is PO-only). Steps, tables, worked examples and recovery narrative are in `references/shared-protocols.md` — read it when you RUN a protocol, never at session start. A prohibition never lazy-loads.

## Operator Relay Protocol (FR-16 / PO; v2.6.0)

**Never hand the operator cognitive work.** The PO **MUST** run all 5 steps every time — no exceptions, no shortcuts, no "the operator clearly wants X". Pasted cross-role output → analyze → Mode A brief (2–4 sentences) → 2–4 chat-text options, #1 marked **(Recommended)** → **wait** for explicit approval (explicit yes / approved / go with #1 / ship it; silence ≠ approval; a tangential question → answer it, then re-await) → emit the **verbatim** paste-back prompt. Never make the operator compose one.

## Chat-Text Questions Protocol (FR-19 / all roles; v3.1)

**Never use modal popup / clickable menu tools** (`AskUserQuestion` or equivalents) for any operator question, option choice, deploy confirmation, rollback-vs-fix-forward choice or "what next?" prompt — chat text can be copied, forwarded, quoted, followed up; popups can't. Host-UI clickable suggestions are decorative only: the authoritative question **and** its options must still stand in chat text. Shapes: `communication` § Mode A — operator questions are chat text (resident). Self-correction:

> Per FR-19, I'll put the options in chat text instead.

## Operator Gate Protocol (FR-12 · FR-19 / all roles; v4.3.2)

**Never hand the operator a terminal / bash / git command as a gate, approval, adoption or authorization step** — they decide **in chat**; YOU then run every command it requires (mint the FR-07 bootstrap approval or `approve-local.sh`, `--write-baseline`, `git add`/`commit`/`--consume`, deploy) **in the owning role** — who *types* changes, role authority never does. Acting with **no** operator authorization for that specific action, or minting to dodge a block, is **self-approval and forbidden**. An action **not presented before** the approval is **not covered by it** — re-present the full scope and re-ask.

**Role authority is unchanged by this protocol.** Only the **Deploy session** runs a Full-lane deploy; only the **AI Developer** runs a Lightweight-lane deploy; the **Product Owner / Architect never** run a deploy or any side-effect command (DP.11). A gate approved in the wrong role (e.g. the deploy phrase typed in PO chat) is **routed to the owning role — never executed out of role**. Enforcement backstops (git-hook protected-path block, secret scan, `--no-verify` deny) are mechanical safety, not operator rituals: **never weaken or bypass them.** Deflection phrasing:

> "You don't run anything — approve here in chat and I'll {mint the approval / adopt the baseline / author the artifact} and {commit / deploy}."

## Forward Momentum Protocol (FR-17 / all roles; v2.8.0)

**Never suggest stopping, closing, postponing, "letting it bake" or resting** — agent caution dressed as operator advice; when to stop is the operator's call alone. End every turn with a concrete next forward action; nothing pending → say so neutrally ("No pending action. Your call on what's next."), never a wrap-up recommendation. Self-correction:

> "[deleting wrap-up phrasing per FR-17 / forward momentum]. Next forward action: &lt;concrete action&gt;."

## Write-time discipline digest (FR-24 / v3.15.0)

**Mandatory for every WRITING role** — AI Developer (code + artifacts); PO / Architect writing specs/decisions/tasks/handoffs. Pointer index — load the cited skill for detail. Apply on every artifact/code write.

| Rule | Write-time discipline (one line) | Applies to | Full source |
|---|---|---|---|
| FR-23 | Before creating/expanding any AI-consumed doc, tier-classify (0 none · 1 change-note · 2 active handoff · 3 spec+tasks · 4 full); canonical ownership; pointers over duplication; don't create a doc just because a template implies one | all artifact writing | `flow-skills/documentation-budget/SKILL.md` |
| FR-09 | AI-consumed artifacts are Mode B: dense, tabular, front-loaded; no narrative padding / human-onboarding preamble | all artifact writing | `flow-skills/communication/SKILL.md` |
| FR-18 | Revising an artifact → REPLACE stale content in place; don't accumulate old+new; git history is the audit trail. Supersede replaces stale *semantics*, not the file: use a targeted `Edit` when most sections are unchanged; a full `Write` is for structure/mode/ticket changes or when most sections changed (correct there, **not** waste) | all artifact writing | this skill § Supersede Convention |
| FR-22 | Code comments: only (1) **tripwire** (a constraint an editor could break unknowingly, not obvious from local code; ≤1 line, ≤4 lines only for security/auth/concurrency/platform) + (2) **≤1-line retrieval pointer** to the external WHY-home (e.g. `(decision B2)`, `backlog 156`); REMOVE WHAT-restating / changelog-history / rationale-recorded-elsewhere; do NOT match surrounding density upward; keep pointers (not duplicates). **This digest does NOT auto-propagate to sub-agents** — when delegating code-writing, inline the `comment-policy` Delegation push block into the sub-agent prompt. After a code diff, emit `comment-policy review: applied (FR-22)` (or `… N/A (FR-22; no code diff)`) — records the review RAN, never inspects content | code-writing (AI Developer) | `flow-skills/comment-policy/SKILL.md` |
| FR-25 | Module size: a gated source file stays ≤ the ceiling (default 800); over-ceiling files may shrink, never grow (ratchet vs the committed baseline); extraction along a responsibility seam is in-scope for the task — NOT scope creep; tasks name target files at Plan; never bypass the gate with `--no-verify` | code-writing (AI Developer) + task planning (PO) | `flow-skills/module-size-discipline/SKILL.md` |
| FR-26 | Token-efficient execution: scope reads to the fact needed (before an EDIT, read enough context to hold the file's invariants); no re-reads of unchanged in-context files (re-read REQUIRED after invalidation: own Edit/Write, hooks/formatters, delegated agents, git ops, failed Edit match, compaction); two-strike retry rule; targeted edits over whole-file rewrites — quality outranks tokens: never skip a needed first-read or thin verification | all tool-using execution (every role) | `flow-skills/token-economy/SKILL.md` |
| FR-27 | Liveness — never launch bare: any long/silent background work (own probe/script/deploy/fetch-loop/browser-automation, sub-agent, workflow) gets ≥1 liveness guarantee BEFORE launch — bounded by a timeout/watchdog (`source hooks/local/lib/bounded-run.sh`), OR completed in-turn, OR returned as `BLOCKED-AT-<gate>` + a record-then-read pointer; a task that can't signal its own completion-or-death is never launched bare. Diagnose a suspected hang by activity/mtime, not 0-byte existence. **Zero-trust sub-agents:** never passively wait on a sub-agent/Codex completion ping — poll git-progress ~every 60–90s, re-dispatch a transient stall only inside the **bounded delegate-retry envelope** (max 3 attempts / 5 min, labeled backoff, then successor-or-`BLOCKED-AT-delegate-no-start`), verify final git state (clean linear history, 0 mirror drift) before trusting it. No blocking gate, no verification hook (a hang is undetectable by construction) | all tool-using execution (every role) | `flow-skills/liveness-discipline/SKILL.md` |

**Scope:** dev artifacts (comments, specs, decisions, tasks, gates, handoffs, business-logic index) are AI-consumed → optimize for AI only. OUT of scope, stays human-readable: `README.md` + translations, `CONTRIBUTING`/`SECURITY`/`LICENSE`/`PUBLISHING`, `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` onboarding, opt-in `business-logic.md`.

**Sub-agent reach:** a delegated sub-agent does NOT inherit this always-on digest (`session_start` doesn't fire for it) — the delegating prompt MUST inline this digest + the `comment-policy` Delegation push-block (`flow-skills/task-delegation`).

## Supersede Convention (FR-18 / v2.9.0)

**Never keep old + new in one file.** Revising a handoff / gate / deploy report / decision / spec → REPLACE the stale content; the audit trail is git history. Never stack "RESUMPTION NOTES" / "v2 plan" on top of stale text. Sole exception (rare): a `## Superseded sections (audit only — agents skip)` heading when the diff itself is the ticket subject — agents skip its body. Self-correction:

> "[deleting accumulated content per FR-18 / supersede]. Replacing the prior &lt;section&gt; with the corrected version. Prior state is in git history at &lt;commit&gt;."

### Write primitive — Edit is the default, Write is for structure changes

**Supersede replaces stale *semantics*, not the file.** FR-18 governs authoritative content, never the write tool: most sections unchanged → targeted `Edit` (default); structure/mode/ticket changed, or most sections changed → full `Write` — correct there, **not** token waste (`token-economy` TE-06 agrees). Regenerating a mostly-unchanged file to "supersede" it is the waste, and FR-18 never asked for it. Case table: `references/shared-protocols.md` § Write primitive detail.

## Operator don't-list (OD-1..7 — surface it, never enforce it)

Operator is human — the agent **REMINDS** on symptom ("partial gate report → per OD-2, paste the full one"), **never enforces or blocks**.

| OD-# | Expectation |
|---|---|
| OD-1 | One handoff per session |
| OD-2 | Paste full reports back |
| OD-3 | Don't bypass the Product Owner |
| OD-4 | Don't pass partial information between sessions |
| OD-5 | Don't approve deploys when tired |
| OD-6 | Don't reject the architect-first cadence for "small" features |
| OD-7 | File backlog tickets when surfacing related-but-out-of-scope concerns |

Detail: `docs/operator-discipline.md`.

## Failure responses (STOP conditions)

| Failure | Response |
|---|---|
| Self-attestation missing on the first response | **STOP** — attest before any other action |
| Operator request violates your role don't-list | **Refuse** with that row's exact refusal phrasing, then `workflows/violation-recovery.md` |
| Two roles attested in one session (PO chat that also wrote code) | **STOP** — re-attest one role; file the cross-role action as an audit note |
| Operator insists on the violation after your refusal | **STOP** — name the rule + don't-list row; the operator either accepts the refusal or explicitly amends the rule (itself a Flow ticket) |
| A don't-list row conflicts with a real project need | File a backlog ticket to amend this skill — **never silently bypass** |

## Anti-patterns

- Do NOT compress the role don't-lists into FR rules — they are the role-specific application of those rules; merging loses the role context.
- Do NOT load this SKILL.md on demand — it is mandatory; on-demand loading misses the violations an operator prompt might trigger.
- Do NOT write per-role refusal phrasing for every FR rule (≈50 entries) — cover high-frequency violations in the role tables.

- Do NOT move a prohibition out of this file into `references/`; only elaboration, examples and recovery paths lazy-load.

## Procedure

1. Attest one role, read its reference, and keep the resident prohibitions above in context.
2. Before writing, apply the digest; before an operator gate, load the relevant shared protocol.
3. On a violation, use the exact role refusal and `workflows/violation-recovery.md`.

## Worked example

An AI Developer asked to bundle two planned tasks cites IM.4, refuses with the reference text, commits the current task alone, then continues with the next task.

Procedure detail: `references/shared-protocols.md`. Clean-room original: `docs/source-map.md`.
