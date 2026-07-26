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

> **Do not re-Read this file if it is already in your context.** If this exact SKILL.md body is already present in your context (surfaces that auto-load `.claude/skills/` or `.agents/skills/`), do not Read this file again — seeing the name/description in a skill index does **not** count. If it is not present, read it once. Delegated sub-agent sessions do not inherit an auto-load: they read it.
>
> Surface truth (AC11, verified): **no surface injects this body.** Claude Code (`.claude/skills/`) and Codex (`.agents/skills/`, optional `skills_dir`) supply the description/metadata only; Gemini, Copilot, Cursor and delegated sub-agents supply nothing. Read it once when the body is not already in your context.

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

## Mode A — visual triggers

Use one when: 3+ phases with tickets → roadmap · multiple tickets with progress → status table · options A/B/C → decision tree or comparison table · X blocks Y → dependency graph · ticket through the 8 phases → state diagram · when things shipped → timeline · trade-offs → side-by-side · architecture → box-and-arrow.

Don't when: a sentence suffices · data is naturally tabular · wider than ~100 chars · decorative. Test: *"whiteboard in person?"* — if no, prose or table. A box around prose is worse than no diagram.

**Lazy-load:** the 8 patterns + character/width discipline are in `references/patterns.md` — do NOT preload; read it only when a reply will carry a visual. The state-announcement footer is text, never a visual.

## Mode A — operator questions are chat text (FR-19)

Choose / clarify / confirm / approve → full question as chat text. Never popup or clickable menu tools (`AskUserQuestion` etc.): chat text can be copied, forwarded, quoted, and followed up across sessions; popups can't.

| Question type | Mode A shape |
|---|---|
| Decision with options | Table `Option / What happens / Trade-off`; mark **(Recommended)** |
| Narrow confirm | Exact typed phrase in backticks + what happens on any other reply |
| Clarify | One concise question, then 2-3 concrete options if useful |
| Relay prompt | Copy-ready code block or quote block |

## Mode B — the 12 principles

| # | Principle — rule |
|---|---|
| B1 | Front-load the answer — first sentence or cell IS the answer |
| B2 | Tables over prose for structured data — 3+ comparable rows |
| B3 | Bullet lists over paragraphs for enumerables |
| B4 | Concrete over abstract — `T17`, `repository.ts:42-58` |
| B5 | Predictable section names — the template's exact headers |
| B6 | No narrative storytelling |
| B7 | Cross-references precise — never "see above" |
| B8 | No restatement of context |
| B9 | Status fields explicit and tag-style |
| B10 | Avoid hedging unless genuinely uncertain — real doubt → clarify item |
| B11 | Consistent vocabulary |
| B12 | No human-onboarding preamble |

**Lazy-load:** ❌/✅ examples, anti-patterns, pitfalls, verification, and failure cases are in `references/mode-b-detail.md` — read it when a write or review needs an example; the rules above stand without it.

## Skill-level constraints

Definitions, classification, prohibitions, and the 12 principle **names** stay resident — only elaboration moves to `references/`; a prohibition that loads only when you already remembered it is worthless. Never restate this skill as `FLOW_RULES.md` rules.

Clean-room original; no third-party content copied. See `docs/source-map.md`.
