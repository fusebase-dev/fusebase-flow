# Mode B — worked detail (lazy-loaded reference, v4.5.0+)

> **Load on demand.** NOT loaded at session start. The resident `flow-skills/communication/SKILL.md` carries the mode definitions, the file classification, the visual triggers, the FR-19 question shapes, and all 12 Mode-B principle names — everything that tells you *what not to do*. This file carries the ❌/✅ worked examples, the anti-pattern catalog, the pitfalls, and the failure/escalation tables. Read it when a specific artifact write needs the example, or when reviewing an artifact for Mode-B drift.

## B1–B12 worked examples

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

Use `Status: DONE`, `Owner: PO`, `Lock status: LOCKED` — not free-text descriptions like "This is currently done by the PO and locked".

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

You're following the skill if:

- **Mode A:** every operator chat output has either a visual element (when state warrants it) OR a tight status announcement. No long prose paragraphs explaining state.
- **Mode B:** every internal artifact opens with the answer/payload, not a preamble. Tables and bullet lists outweigh prose paragraphs. File:line cross-references where applicable. No "as discussed above", "the earlier change", or other vague pointers.
- **Self-attestation** at session bootstrap explicitly names "communication skill — Mode A and Mode B" so drift surfaces immediately at first response.

Quick check: open any `spec.md` / `decisions.md` / `tasks.md` you've drafted. Count paragraph words vs table-cell words. If paragraphs dominate, Mode B is being violated.

## Common pitfalls

- **Writing spec.md as if onboarding a human reader.** README.md is the human onboarding doc; spec.md is for AI. Move narrative-style content out and replace with tables / tagged fields.
- **Putting visuals in Mode-B files** (spec.md, decisions.md, tasks.md). Bloats AI context every load. Visuals go in chat, or in `references/patterns.md` as library entries.
- **Restating constitution / spec content inside decisions.md.** Adjacent files are already loaded. Reference, don't restate.
- **Free-form decision write-ups** with hedging and narrative. Use the decisions.md template's letter-prefixed table form.
- **Inconsistent vocabulary** ("task" vs "T-number" vs "item"; "deploy" vs "ship" vs "release"). Use project-defined terms verbatim.
- **Long preambles** ("This document captures..."). Open with the answer.

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Operator chat output (visual when warranted, tight status otherwise) | chat | Mode A |
| Internal artifacts (spec/decisions/tasks/handoff/problem-catalog/backlog) | files in the classification list in `../SKILL.md` | Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Operator output is paragraph-heavy when state has spatial relationships | Long prose where a roadmap/tree would clarify | Self-correct: "switching to Mode A — visual roadmap." Output the visual. |
| Mode-B file contains an ASCII visual | Pre-commit code-review or operator review | Move the visual to chat next time the file is referenced; replace inline with tabular form. |
| Mode-B file opens with multi-paragraph preamble | First paragraph is "This document captures..." narrative | Self-correct on next write: open with payload (status + linked decisions or first table). |
| Vague cross-references | Phrases like "see above" / "the earlier commit" / "as discussed" | Replace with concrete identifier (`spec.md:42`, sha:`abc1234`, T-number). |

## Escalation path

- Recurring Mode B violations across 3+ tickets → propose adding a new principle or anti-pattern to this file + a one-liner row in `../SKILL.md` (operator decides).
- Operator wants to add a 9th visual pattern → propose addition to `references/patterns.md`, not any per-ticket file.
