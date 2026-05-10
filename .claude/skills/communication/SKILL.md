---
name: communication
description: ALWAYS apply on every chat output (Mode A — visual, concrete, brief) and on every internal-artifact write (Mode B — dense, tabular, front-loaded; no narrative padding). Mandatory at session start; not on-demand. Contains the full ASCII pattern library and the 12 Mode B principles with concrete anti-patterns.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: low
invocation: automatic
mandatory_load: true
expected_outputs:
  - Mode A — operator chat output that uses ASCII visuals when state has spatial relationships
  - Mode B — internal artifact files that are dense, tabular, front-loaded, with concrete identifiers
related_workflows:
  - session-initiation.md
  - eight-phase-flow.md
hook_dependencies:
  - session_start
---

# Communication

> **Style:** Mode-B-lite (this file). It contains ASCII visual examples by design — those are the reference patterns that operators see in chat. They are NOT visuals embedded in other Mode-B files.

## Purpose

Two communication modes that every Fusebase Flow session must follow consistently. The audiences differ, so the format differs:

- **Mode A — Operator chat.** Output the operator reads in real time. Visual, concrete, brief. ASCII diagrams when state has spatial relationships; tight status announcements when it doesn't. Operators scan; they don't read.
- **Mode B — Internal artifacts.** Files the next AI session will load (`docs/specs/`, `docs/decisions/`, `docs/handoff/`, `docs/problem-catalog/`, `docs/backlog/`, plus other framework files at root). Written for an AI consumer, not a human reader. Dense, tabular, front-loaded, no narrative padding.

This skill is mandatory because both modes affect quality continuously: operator clarity (Mode A) and AI context-budget efficiency (Mode B). Drift on either degrades the flow.

## When to invoke

Always. Concretely:

- **Mode A** activates every time you write to the operator (chat output: status announcements, decision presentations, gate-report acknowledgments, deploy summaries, end-of-session recaps).
- **Mode B** activates every time you write content into a file in the AI-consumed list below.
- Self-attestation at session bootstrap names this skill explicitly so drift surfaces at the first response.

## Do not invoke when

There is no scenario where this skill doesn't apply. It is mandatory at all times.

## File classification

### Mode B applies (write AI-optimized; do NOT add prose padding or visuals)

```
docs/specs/<slug>/spec.md
docs/specs/<slug>/decisions.md
docs/specs/<slug>/tasks.md
docs/specs/<slug>/verification-gate.md
docs/specs/<slug>/research.md          (optional artifact)
docs/specs/<slug>/data-model.md        (optional artifact)
docs/specs/<slug>/clarify-conversation.md
docs/backlog/<slug>/README.md
docs/backlog/index.md
docs/handoff/<YYYY-MM-DD>-<slug>-<stage>.md
docs/problem-catalog/<slug>/problem.md
docs/problem-catalog/README.md
docs/skills/<slug>/SKILL.md            (project-internal skills)
docs/skills/README.md
```

### Mode B-lite (concise, structured, trigger-oriented, AI-consumable; this skill follows this tier)

```
skills/*/SKILL.md
workflows/*.md
docs/compatibility.md
docs/hook-coverage.md
docs/rail-mapping.md
audit/README.md
```

### Mode B does NOT apply (keep human-readable; humans onboard or amend these)

```
README.md
AGENTS.md
CLAUDE.md
GEMINI.md
PUBLISHING.md
LICENSE
FLOW_RULES.md
docs/framework.md
docs/clean-room.md
docs/source-map.md
.github/copilot-instructions.md
.github/instructions/*.instructions.md
```

If a file's mode is unclear, default to Mode B (AI-optimized). The carve-out list above is the explicit human-facing set.

---

# Mode A — Operator chat (visual, concrete, brief)

## Critical rule

ASCII visuals go in CHAT MESSAGES the agent sends to the operator. They do NOT go in `docs/specs/`, `docs/decisions/`, `docs/handoff/`, `docs/problem-catalog/`, `docs/backlog/`, or any other Mode-B file.

Why:

- Mode-B files are read by AI agents on bootstrap or on-demand. Visual bloat increases token consumption.
- Visuals communicate transient state (current roadmap, current options). State changes; file visuals go stale.
- Chat is ephemeral. Visuals consumed by the operator don't persist into future-session context.

**This skill** is itself the canonical reference for the patterns — the visuals below are the library, used as templates in chat.

## Why visuals (in chat)

Operators scan. They don't read prose carefully when checking status. A 5-line ASCII roadmap with status icons communicates more in 2 seconds than a 30-word paragraph in 10.

Three benefits when used in chat:

1. **Fast scanning** — operator sees state at a glance.
2. **Spatial relationships** — dependencies, sequences, hierarchies become visible.
3. **Reduced ambiguity** — "Phase 2 is in progress" is less precise than 🟡 next to slice 04.

## When to use a visual

| Scenario | Visual type |
|---|---|
| Multi-phase project status (3+ phases, multiple tickets each) | Roadmap |
| Multiple tickets with progress | Status table or roadmap |
| Decision points with options (A vs B vs C) | Decision tree or comparison table |
| Dependencies between tickets (X blocks Y) | Dependency graph |
| Lifecycle state (e.g., ticket moves through 8 phases) | State diagram |
| Timeline of events (when things shipped) | Timeline |
| Trade-off analysis | Side-by-side comparison |
| Architecture overview | Box-and-arrow diagram |

## When NOT to use a visual

- A single sentence is sufficient ("ticket X shipped, deploy hash Y")
- The information is naturally tabular (markdown table beats ASCII)
- The diagram would be too wide for the chat / editor pane (>100 chars)
- The visual is decorative without adding clarity

Heuristic: **"Would I reach for a whiteboard if explaining this in person?"** If yes, ASCII. If no, prose or table.

## Pattern library

### Pattern 1 — Project roadmap (phases + slices/tickets + status)

```
Phase 1 — Operator experience polish (3 slices)        ✅ COMPLETE
   ├── 01 Agent executionMode mismatch                  ✅
   ├── 02 Run management via AI Studio                  ✅
   └── 03 NL dashboard destination discovery (PATH B)   ✅

Phase 2 — Expand authoring capabilities (~6-10 slices)  🟡 IN PROGRESS
   ├── 04 Composition foundation (invoke_workflow)      🟡 in Codex now
   ├── 05 Router workflow shape (Brief 02 cont)         ⏸
   ├── 06 SPA composition authoring                     ⏸
   ├── 07 Audit + nested-run rendering                  ⏸
   ├── 08 Wait/delay step type                          ⏸
   └── 09 Scheduled triggers                            ⏸

Phase 3 — External integrations (~11-17 slices)         ⏸ NOT STARTED
   └── ...

Phase 4 — DEFERRED (out of this run's scope)
   └── ...
```

Status icons:

- ✅ Complete (deployed, DRAFT → DONE)
- 🟡 In progress (currently being worked on)
- ⏸ Pending / not started
- 🚧 Blocked (waiting on dependency or external)
- ❌ Failed / cancelled
- 🔄 Re-do / re-investigation needed

### Pattern 2 — Status snapshot at session bootstrap

```
Product Owner ready. Project state:

📋 Backlog (5 tickets parked)
🚧 In-flight (2 specs DRAFT)
📨 Recent handoffs: 2026-05-08-priority-fix-deploy.md (most recent)
📦 Recent commits: 33 today

📅 Roadmap status:

Phase A — Foundation (3 tickets)              ✅ COMPLETE
Phase B — Operator features (5 tickets)       🟡 IN PROGRESS (3/5)
   ├── retry-failed-classifications           ✅
   ├── profile-not-found-classification       ✅
   ├── tiktok-profile-avatar-caching          ✅
   ├── skip-already-fetched-fields            🟡 Tier 1+2 done; Tier 3 pending
   └── native-influencer-creation             ⏸
Phase C — External integrations (TBD)         ⏸ NOT STARTED

What's on your mind?
```

### Pattern 3 — Decision tree (in chat, NOT in decisions.md)

```
Operator submits Custom enrichment with archiveOptions
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
     lookbackDays set?           lookbackDays unset?
            │                         │
            ▼                         ▼
   ┌────────────────┐         ┌──────────────────┐
   │ Apply early-   │         │ Full grid scroll │
   │ exit at N=10   │         │ up to 1000-cap   │
   │ consecutive    │         │ (today's behavior│
   │ too-old videos │         │  preserved)      │
   └────────┬───────┘         └────────┬─────────┘
            ▼                          ▼
     ┌──────────────────────────────────────┐
     │ Backend defensive filter on          │
     │ source_videos.published_at           │
     │ before enqueue                       │
     └──────────────────────────────────────┘
```

### Pattern 4 — Dependency graph (which ticket blocks which)

```
   priority-fix
        │
        ▼
   ┌────────────────────────────────────────┐
   │  archive-lookback-days   queue-cohort- │
   │  (independent)           inventory     │
   │                          (independent) │
   └────────────────────────────────────────┘
                    │
                    ▼
   ┌────────────────────────────────────────┐
   │  queue-recency-ordering                │
   │  (depends on priority-fix shipped)     │
   └────────────────────────────────────────┘
                    │
                    ▼
   ┌────────────────────────────────────────┐
   │  creator-selection-recency             │
   │  (sibling to queue-recency-ordering)   │
   └────────────────────────────────────────┘
```

### Pattern 5 — Comparison table for decision-making

```
┌─ Option A: D1 (sequence column) ────────┐  ┌─ Option B: D2 (timestamp hack) ────┐
│                                         │  │                                    │
│  ✅ Clean schema (priority_seq column)  │  │  ✅ No migration                   │
│  ✅ Sortable independent of timestamp   │  │  ✅ Faster to implement            │
│  ❌ Migration required                  │  │  ❌ Hacky enqueued_at semantics    │
│  ❌ Risk: platform apply blocker        │  │  ✅ No platform-blocker risk       │
│                                         │  │                                    │
│  Effort: ~half day                      │  │  Effort: ~3 hours                  │
│  Risk: Medium (new schema)              │  │  Risk: Low (formula change only)   │
└─────────────────────────────────────────┘  └────────────────────────────────────┘

Recommendation: Option B (D2) due to platform blocker.
```

### Pattern 6 — Timeline of events

```
2026-05-08 timeline:

08:00 ━━━ Phase 1 retry-failed-classifications      shipped (deploy wnmzsiqn)
08:30 ━━━ Phase 1 profile-not-found-classification  shipped (deploy jcgy8mj4)
09:15 ━━━ Phase 2 tiktok-profile-avatar-caching     shipped (deploy xj6gwwyy)
10:30 ━━━ Phase 3 skip-already-fetched-fields T1+2  shipped (deploy skiu4d9v)
12:00 ━━━ Phase 4 Path 1 native-influencer-creation shipped (deploy gg8jxjoi)
14:30 ━━━ priority-fix D2                           shipped (deploy hsq0zy6d)

Total: 6 shipped phases
```

### Pattern 7 — State diagram (lifecycle of one entity)

```
┌──────────────┐
│ Investigating│   ← user files backlog ticket
└──────┬───────┘
       │
       ▼ user decides to ship
┌──────────────┐
│ Promoting    │   ← PO drafts spec.md (status DRAFT)
└──────┬───────┘
       │
       ▼ user locks decisions
┌──────────────┐
│ Implementing │   ← AI Developer executes T1, T2, ...
└──────┬───────┘
       │
       ▼ implementer reports gate
┌──────────────┐
│ Verifying    │   ← PO runs consistency checker
└──────┬───────┘
       │
       ▼ PO approves deploy
┌──────────────┐
│ Deploying    │   ← Deploy phase runs deploy + probes
└──────┬───────┘
       │
       ▼ all probes pass
┌──────────────┐
│ Done         │   ← spec.md DRAFT → DONE
└──────────────┘
```

### Pattern 8 — Box-and-arrow architecture

```
┌───────────┐       POST           ┌───────────────┐
│  Browser  │  ───────────────►    │   Backend     │
│ (operator)│                      │   (Hono)      │
└───────────┘                      └───────┬───────┘
                                            │
                                            ▼
                                    ┌────────────────┐
                                    │  Postgres      │
                                    │  (isolated     │
                                    │   store)       │
                                    └────────────────┘
                                            ▲
                                            │
┌───────────┐       claim          ┌───────┴───────┐
│  Worker   │  ───────────────►    │  Worker auth  │
│ (Browser) │                      │  middleware   │
└───────────┘                      └───────────────┘
```

## Mode A — character + width discipline

| Element | Character | Notes |
|---|---|---|
| Box corners | `┌ ┐ └ ┘` | Single-line boxes |
| Box edges | `─ │` | Horizontal and vertical |
| Tee joints | `├ ┤ ┬ ┴ ┼` | Trees and intersections |
| Heavy corners | `╔ ╗ ╚ ╝` | Double-line for emphasis |
| Heavy edges | `═ ║` | Double-line emphasis |
| Arrows | `→ ←  ↑ ↓ ▶ ◀ ▲ ▼` | Direction indicators |
| Status emoji | `✅ 🟡 ⏸ 🚧 ❌ 🔄 📋 📨 📦 📅` | Status communication |
| Tree branches | `├── └──` | List hierarchy |

Width: keep diagrams under 80 characters when possible. Don't over-decorate (a box around every element is noise). Test alignment in monospace before output.

## Mode A integration with state announcements

The mandatory state announcement at every output is short text, NOT a visual:

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

Visuals are for the BODY of the message when the body benefits from spatial layout. Single-decision or single-status updates use prose.

## Mode A — don't fake it

If you're tempted to draw a diagram but the spatial relationships aren't actually meaningful — don't. A list of bullets is fine. Bad ASCII diagrams (boxes around prose) are worse than no diagram.

Test: **"Does the spatial arrangement convey information that prose can't?"** If yes, draw. If no, write.

---

# Mode B — Internal artifacts (AI-optimized, dense, structured)

> Files in the Mode-B list are read by AI sessions to execute work. They are not human onboarding documents. Optimize for AI context efficiency: front-load payload, prefer structured formats, eliminate narrative padding.

## Mode B principles

### B1. Front-load the answer

First sentence (or first table cell) IS the answer. Reasoning second. AI sessions scan; they don't read top-to-bottom.

❌ "After considering several options including the migration-based approach and the timestamp-based approach, weighing trade-offs around schema cleanliness and platform-blocker risk, the team has determined that..."
✅ "Decision: D2 (timestamp-based). Reason: avoids platform apply blocker. Alternatives: D1 (rejected — migration needed)."

### B2. Tables over prose for structured data

Decision matrices, task lists, status grids, criterion checks → tables. Three or more rows of comparable data is always tabular.

❌ "T1 covers the backend endpoint changes and depends on nothing. T2 covers the SPA card and depends on T1. T3 covers extension wiring and depends on T1..."
✅
```
| T# | Track | Scope | Depends-on |
|---|---|---|---|
| T1 | backend | endpoint + storage helper | — |
| T2 | spa | enrichment card | T1 |
| T3 | extension | content-script wiring | T1 |
```

### B3. Bullet lists over paragraphs for enumerables

Three or more items of the same kind → bullets. Don't write "First X, then Y, finally Z" prose.

### B4. Concrete over abstract

Use specific identifiers: `T17`, commit `3b1bfaa`, `repository.ts:42-58`, ticket slug `skip-already-fetched-fields`. Never "the earlier change", "the recent commit", "see above".

### B5. Predictable section names

Use the template's exact section headers. AI navigates by heading; deviation costs cycles. If the spec.md template says `## Acceptance criteria`, write that header — don't paraphrase to "What success looks like".

### B6. No narrative storytelling

Don't write "I considered X, then thought about Y, and decided Z." Write the decision + alternatives + reasoning in tag-form.

❌ "I think the right approach is probably X, since Y seems important, and Z might also matter — though we should consider that W could be a concern..."
✅
```
Decision: X
Reason: Y
Alternatives considered:
- Z (rejected: A)
- W (rejected: B — concern flagged but lower-priority)
```

### B7. Cross-references precise

`spec.md:42-58` not "see spec above". `decisions.md G2` not "the earlier decision". `repository.ts:42` not "the function in the repository file".

### B8. No restatement of context

Adjacent loaded files (`FLOW_RULES.md`, `spec.md`, `decisions.md`) are already in the AI's context. Reference them; don't re-explain.

❌ At top of `decisions.md`: "This ticket addresses the issue described in spec.md, where the system fails to..." (just cite `spec.md` and move on)
✅ "Decisions for {slug}. See spec.md for problem statement."

### B9. Status fields explicit and tag-style

Use `Status: DONE`, `Owner: PO`, `Locked: yes` — not free-text descriptions like "This is currently done by the PO and locked".

### B10. Avoid hedging unless genuinely uncertain

"May", "could", "might", "possibly" are AI-noise unless they encode real uncertainty. If uncertain, file it as a clarify item rather than embedding hedge language in the spec.

❌ "We might want to consider whether the cache could potentially become stale..."
✅ Either: "Cache becomes stale after 24h. Mitigation: TTL invalidation."
   Or: file as clarify Q: "Cache staleness — TTL? Manual invalidate? See clarify Q-A."

### B11. Consistent vocabulary

Use project-defined terms verbatim ("ticket", "task T-N", "deploy", "feature token", etc.). Don't switch synonyms within or across files.

### B12. No human-onboarding preamble

Don't open files with "This document captures the architectural plan for..." paragraphs. Open with the actual content (or a single ≤15-word summary line).

❌ "# Spec — skip-already-fetched-fields\n\nThis document describes the architectural plan for the skip-already-fetched-fields feature. The feature was identified as a need by the operator after observing that..."
✅ "# Spec — skip-already-fetched-fields\n\n**Status:** DRAFT\n\n## Problem\nEnrichment re-fetches fields already cached. Operator surfaced 2026-05-07."

## Mode B anti-patterns (with examples)

### Anti-pattern: prose-heavy spec.md

❌
```
# Spec — priority-fix

This document captures the architectural plan for fixing the priority issue
that was observed in production on 2026-05-07. After significant
investigation, we determined that the queue ordering logic was the root
cause, and we considered several approaches before settling on the
timestamp-based approach (D2). The reasoning behind this choice is...
```

✅
```
# Spec — priority-fix

**Status:** DRAFT
**Created:** 2026-05-07
**Linked decisions:** D1, D2 (locked)

## Problem
Queue items not respecting priority order; backend formula uses unstable timestamp.

## Approach
D2 (timestamp-based). See decisions.md for D1 rejection rationale.

## Acceptance criteria
- AC1: Priority-1 items dequeue before priority-2 within same batch
- AC2: Worker-undisturbed: zero diff on connector.ts/sync.ts/repository.ts
- AC3: ...
```

### Anti-pattern: visual in Mode-B file

❌ Adding a Pattern-3 decision-tree ASCII diagram into `decisions.md` so future readers "can see the logic". This bloats AI context every time `decisions.md` loads.
✅ Put the visual in chat when presenting decisions for lock; `decisions.md` gets the locked outcomes in tabular form.

### Anti-pattern: restating constitution

❌ At top of spec.md: "Per project constitution, the worker-undisturbed list includes connector.ts, sync.ts, repository.ts. We must not modify these files. Mixed-fleet considerations require..."
✅ "Constitution invariants verified: zero diff on worker-undisturbed list; mixed-fleet safe (locked decision G3)."

### Anti-pattern: vague pointer

❌ "See the relevant file for the implementation."
✅ "See `src/features/enrichment/repository.ts:142-178`."

## Verification

You're following this skill if:

- **Mode A:** every operator chat output has either a visual element (when state warrants it) OR a tight status announcement. No long prose paragraphs explaining state.
- **Mode B:** every internal artifact opens with the answer/payload, not a preamble. Tables and bullet lists outweigh prose paragraphs. File:line cross-references where applicable. No "as discussed above", "the earlier change", or other vague pointers.
- **Self-attestation** at session bootstrap explicitly names "communication skill — Mode A and Mode B" so drift surfaces immediately at first response.

Quick check: open any `spec.md` / `decisions.md` / `tasks.md` you've drafted. Count paragraph words vs table-cell words. If paragraphs dominate, Mode B is being violated.

## Common pitfalls

- **Writing spec.md as if onboarding a human reader.** README.md is the human onboarding doc; spec.md is for AI. Move narrative-style content out and replace with tables / tagged fields.
- **Putting visuals in Mode-B files** (spec.md, decisions.md, tasks.md). Bloats AI context every load. Visuals go in chat or in this skill file.
- **Restating constitution / spec content inside decisions.md.** Adjacent files are already loaded. Reference, don't restate.
- **Free-form decision write-ups** with hedging and narrative. Use the decisions.md template's letter-prefixed table form.
- **Inconsistent vocabulary** ("task" vs "T-number" vs "item"; "deploy" vs "ship" vs "release"). Use project-defined terms verbatim.
- **Long preambles** ("This document captures..."). Open with the answer.

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Operator chat output (visual when warranted, tight status otherwise) | chat | Mode A |
| Internal artifacts (spec/decisions/tasks/handoff/problem-catalog/backlog) | files in classification list above | Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Operator output is paragraph-heavy when state has spatial relationships | Long prose where a roadmap/tree would clarify | Self-correct: "switching to Mode A — visual roadmap." Output the visual. |
| Mode-B file contains an ASCII visual | Pre-commit code-review or operator review | Move the visual to chat next time the file is referenced; replace inline with tabular form. |
| Mode-B file opens with multi-paragraph preamble | First paragraph is "This document captures..." narrative | Self-correct on next write: open with payload (status + linked decisions or first table). |
| Vague cross-references | Phrases like "see above" / "the earlier commit" / "as discussed" | Replace with concrete identifier (`spec.md:42`, sha:`abc1234`, T-number). |

## Escalation path

- Recurring Mode B violations across 3+ tickets → propose adding a new principle or anti-pattern to this skill (operator decides).
- Operator wants to add a 9th visual pattern → propose addition to the pattern library; lives here, not in any per-ticket file.

## Anti-patterns (skill-level, not artifact-level)

- Do NOT split this skill across multiple files. The pattern library + 12 principles + anti-patterns must stay in one place so a single skill load gives the full reference.
- Do NOT downgrade to "on-demand". This skill is mandatory at session start; communication discipline applies to every session.
- Do NOT rewrite as rules in `FLOW_RULES.md`. Rule statements that point at this skill are fine; the discipline content stays here.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
