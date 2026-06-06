---
name: comment-policy
description: Use when writing or editing code, adding/changing comments, or before committing a code diff — delivers FR-22's tripwire + retrieval-pointer comment policy at write time. Do NOT use for prose/doc edits, non-code tickets, or as a review gate (that's `code-review`).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.11
risk_level: low
invocation: automatic
expected_outputs:
  - Code diffs whose comments are tripwire-only or retrieval-pointer-only
  - WHAT-restating / recorded-elsewhere / changelog comments removed at write time
related_workflows:
  - greenlight-implement.md
  - eight-phase-flow.md
hook_dependencies:
  - none
---

# Comment policy (FR-22 write-time carrier)

> **Style:** Mode-B-lite. The write-time home of FR-22. Loads for code-writing agents (and their sub-agents) so the rule reaches the writer's context at the moment comments are written — not just at review. Rule body aligns with `FLOW_RULES.md:68`; rationale + evidence live in `docs/comment-policy.md`.

## Purpose

Flow source is read by AI agents, not humans line-by-line. WHAT-restating prose, rationale already homed in a decision/ticket/memory, and changelog comments serve an absent audience and cost context budget on every load. The base "match surrounding comment density" instruction is a one-directional ratchet and every Stop-hook gate is comment-blind, so over-commenting is invisible to the loop. This skill delivers the explicit override at write time.

## When to invoke

- Writing or editing code in any language.
- Adding, changing, or reviewing your own comments before a commit.
- About to commit a code diff (final comment pass).
- A handoff or task involves implementation, refactor, or scaffold.

## Do not invoke when

- Editing prose / docs / specs / decisions / handoffs (these are human-or-AI-read narrative, not code).
- The ticket is non-code (config-only rename, doc-only change with no source edit).
- You want review-time enforcement — that is `code-review` (the review dimension), not this write-time carrier.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| The code diff being written | working tree | nothing to apply the policy to — skip |
| Trust-critical carve-out set | `policies/comment-policy.yml: trust_critical_globs` | treat all paths as routine (carve-outs are opt-in per project) |
| Rationale / audit prompt | `docs/comment-policy.md` (framework-dev) · `references/audit-prompt.md` (consumer-reachable) | proceed from the two-kinds rule below |

## Procedure

Write only two kinds of comment; remove everything else.

### 1. Tripwire (keep)

A constraint an editing agent could violate without realizing, that is **not obvious from local code**. One line by default; ≤~4 lines **only** for security / auth / concurrency / platform-quirk.

```
# empirical floor — don't lower below 0.82 (decision B2)
threshold = 0.82
```

```
# additive — reordering breaks back-compat with serialized v1 payloads
FIELDS = (...)
```

### 2. Retrieval pointer (keep)

A ≤1-line tag naming the external WHY-home so an agent whose context is just the open file knows where the rationale lives.

```
COOLDOWN_S = 30        # (backlog 156)
```

### 3. Remove (everything else)

| Remove | Why | Replace with |
|---|---|---|
| WHAT-restating prose (`# loop over users`) | the code already says it; the reader is an agent | nothing |
| Rationale/diagnosis already in a decision/ticket/memory | duplicate of an external record | the ≤1-line pointer |
| Changelog / history (`# changed 2026-06-04: was X`) | the change is in git | nothing |

## Delegation push block (for code-writing sub-agents)

When you delegate any code-writing/implementation slice to a sub-agent, paste this block into its prompt (push — sub-agents do not reliably auto-load this skill):

```
COMMENT POLICY (FR-22) — applies to all code you write:
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision B2)" or "backlog 156".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```

## Two subtleties (do not over-simplify)

- **Do NOT "match surrounding comment density" upward.** Trim toward this policy even in comment-heavy files. This clause is what breaks the harness density-ratchet — without it the policy is silently overridden.
- **Storage ≠ retrieval — the pointer is NOT a duplicate.** When an agent opens a file the external records aren't in its context, so deleting the one-line pointer orphans a correct record the agent now has no trigger to open. Kill the prose; keep the pointer.

## Carve-out (trust-critical paths)

Trust-critical paths — auth / identity / session / gate code, DB migrations, and anything in `policies/comment-policy.yml: trust_critical_globs` — keep their multi-line tripwires. Apply the rule fully to CRUD / routine code. The set is **project-settable** (architecture-dependent: whether a separate instruction layer is read *instead of* source varies by project). Run `references/audit-prompt.md` against a project to derive its set before adopting.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Comment-policy-compliant code diff | working tree | (behavioral; no separate artifact) |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Diff carries WHAT-restate / changelog / duplicate-rationale comments | self-review before commit; `code-review` at review-time | strip the prose; keep tripwires + pointers |
| A pointer was deleted as a "duplicate" | external record now has no in-context trigger | restore the ≤1-line pointer |
| Tempted to add a regex/lint comment gate | this skill or a hook proposes pattern-matching comments | refuse — FR-22 forbids it; enforcement is write-time + `code-review`, never a gate |

## Escalation path

- Carve-out set unknown for this project → run `references/audit-prompt.md`; ask the operator in chat text (FR-19) which globs to set in `policies/comment-policy.yml`.
- Cleaning existing over-commented files → a separate explicit Lightweight pass (FR-21); not retroactive, comments strip from build output so no deploy.

## Anti-patterns

- Do not become a regex/lint/gate comment-matcher — tripwire-vs-restate is semantic, not pattern-matchable (FR-22).
- Do not match surrounding comment density upward.
- Do not strip a retrieval pointer as if it were a duplicate.
- Do not apply to prose/doc files — this is the code carrier.
- Do not retroactively rewrite existing files outside an explicit Lightweight pass.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
