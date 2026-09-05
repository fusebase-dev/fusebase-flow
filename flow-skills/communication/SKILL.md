---
name: communication
description: ALWAYS apply — Mode A on operator chat output (visual, concrete, brief), Mode B on internal-artifact writes (dense, tabular, front-loaded). Mandatory at session start, never on-demand; rules stay resident, examples lazy-load from references/.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: low
invocation: automatic
mandatory_load: true
expected_outputs:
  - Mode A operator chat
  - Mode B internal artifacts
related_workflows:
  - session-initiation.md
  - eight-phase-flow.md
hook_dependencies:
  - session_start
---

> **Do not re-Read this file if it is already in your context.** A name/description is not the body. No supported surface guarantees this body; read it once unless the exact body is present. Delegated sub-agents read it.

# Communication

**Mode A — operator chat (FR-08).** Visual, concrete, brief: ASCII when state is spatial, tight status otherwise. Operators scan; they don't read.
**Mode B — internal artifacts (FR-09).** What a later AI session loads: dense, tabular, front-loaded, concrete identifiers; no narrative padding or preamble.
Both apply in every session — no exemption, never downgraded to on-demand.

**Prohibition — visuals never in Mode-B files.** ASCII goes in chat only, never in any file on the Mode-B list below: visuals cost tokens on every load and freeze transient state. `references/patterns.md` is the library — not a licence to embed visuals elsewhere.

## File classification

**Mode B applies** (AI-optimized; no prose padding, no visuals):

```
docs/specs/<slug>/{spec,decisions,tasks,verification-gate,research,data-model,clarify-conversation}.md
docs/backlog/<slug>/README.md · docs/backlog/index.md
docs/tmp/handoff.md   (active continuity; superseded each session — FR-18 / FR-23 Tier 2)
docs/tmp/handoff/<date>-<slug>-{implement,deploy,architect}.md   (formal relays)
docs/problem-catalog/{<slug>/problem.md,README.md} · docs/skills/{<slug>/SKILL.md,README.md}
```

**Mode B-lite** (this file's tier): `flow-skills/*/SKILL.md` · `workflows/*.md` · `docs/{compatibility,hook-coverage,rail-mapping}.md` · `audit/README.md`

**Not Mode B** (human-readable): `{README,AGENTS,CLAUDE,GEMINI,PUBLISHING,FLOW_RULES}.md` · `LICENSE` · `docs/{framework,clean-room,source-map}.md` · `.github/copilot-instructions.md` · `.github/instructions/*.instructions.md`

Unclear → default Mode B. Whether an artifact should exist **at all** is FR-23 (`documentation-budget`); this governs only HOW. Active continuity is `docs/tmp/handoff.md` alone, never the `docs/tmp/handoff/` subtree (relays, `-smoke/` dirs, `archive/`).

## Mode A

Use one when: 3+ phases with tickets → roadmap · multiple tickets with progress → status table · options A/B/C → decision tree or comparison table · X blocks Y → dependency graph · ticket through the 8 phases → state diagram · when things shipped → timeline · trade-offs → side-by-side · architecture → box-and-arrow.

Don't when: a sentence suffices · data is naturally tabular · wider than ~100 chars · decorative. Test: *"whiteboard in person?"* — if no, prose or table. A box around prose is worse than no diagram.

**Width + decoration (applies whenever you do emit a visual):** keep diagrams under 80 characters where possible, **never over-decorate** (a box around every element is noise), and verify alignment in monospace before output.

## Mode A — operator questions are chat text (FR-19)

Operator questions are chat text, never popup/clickable menu tools.

| Question type | Mode A shape |
|---|---|
| Decision with options | Table `Option / What happens / Trade-off`; mark **(Recommended)** |
| Narrow confirm | Exact typed phrase in backticks + what happens on any other reply |
| Clarify | One concise question, then 2-3 concrete options if useful |
| Relay prompt | Copy-ready code block or quote block |

## Mode B — resident principles

| # | Principle — rule |
|---|---|
| B1 | Front-load the answer — first sentence or cell IS the answer |
| B2 | Tables over prose for structured data — 3+ comparable rows |
| B3 | Bullet lists over paragraphs for enumerables — 3+ items of one kind → bullets; never "First X, then Y, finally Z" prose |
| B4 | Concrete over abstract — `T17`, commit `3b1bfaa`, `repository.ts:42-58`; never "the earlier change" / "the recent commit" |
| B5 | Predictable section names — the template's exact headers verbatim; never paraphrase a heading (AI navigates by heading) |
| B6 | No narrative storytelling — never "I considered X, then thought Y, and decided Z"; write decision + alternatives + reason in tag form |
| B7 | Cross-references precise — `spec.md:42-58`, `decisions.md G2`, `repository.ts:42`; never "see above" / "the earlier decision" |
| B8 | No restatement of context — adjacent loaded files (`FLOW_RULES.md`, `spec.md`, `decisions.md`) are already in context: cite them, never re-explain or restate the constitution |
| B9 | Status fields explicit and tag-style |
| B10 | Avoid hedging unless genuinely uncertain — real doubt → clarify item |
| B11 | Consistent vocabulary — project terms verbatim; never switch synonyms within or across files |
| B12 | No human-onboarding preamble — never open with "This document captures…"; open with the payload (or one ≤15-word summary line) |

Details and failure examples: `references/mode-b-detail.md`. Visual patterns: `references/patterns.md`. Load either only when needed.

## Procedure

1. Classify the output surface using the table above.
2. Apply Mode A or Mode B and the resident constraints.
3. Load a reference only when its examples resolve a live formatting choice.

## Worked example

Input: a gate report result for the operator and the saved report file. Chat uses two concrete sentences plus the state footer. The report uses template headings, a check table, exact SHAs/paths, and no diagram. No reference loads unless a diagram or Mode-B edge case is actually needed.

Clean-room original; no third-party content copied. See `docs/source-map.md`.
