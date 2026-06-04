# Spec — FR-22 code-comment policy (tripwire + retrieval-pointer)

**Status:** DONE (shipped v3.10.0)
**Lane:** Full (new always-on rule every Flow agent inherits; multi-surface)
**Target version:** 3.10.0
**Source:** downstream proposal `docs/fusebase-flow-proposals/2026-06-04-comment-policy-tripwire-and-pointer.md` (paperclip+hermes-v1), cross-project validated (paperclip+hermes + AssetWatch Prod).

## Problem

Flow agents generate code with heavy human-oriented comments — changelog history, incident rationale, re-explained diagnosis, and WHAT-restating prose. In a Flow workflow source files are read by **AI agents**, not humans (a human asks an agent to explain rather than opening the file), so much of that text serves an absent audience and is pure token/context cost. Measured ~45% of comments removable in trust-critical files across two independent projects, concentrated in the densest engine/auth files (CRUD is already lean).

Two framework-level root causes:
1. The base harness instruction **"match surrounding comment density"** is a one-directional ratchet — density only ever increases. Flow must ship an explicit override.
2. **No feedback penalty** — every Stop-hook gate (typecheck/lint) is comment-blind, so over-commenting is invisible to the loop. Wrong code fails a gate; a useless comment fails nothing.

## The rule (FR-22)

Write only two kinds of comment; remove everything else:

1. **Tripwire** — a constraint an editing agent could violate without realizing and that isn't obvious from local code ("empirical floor — don't lower below X"; "additive — editing breaks back-compat"). One line by default; ≤~4 lines only for security/auth/concurrency/platform-quirk.
2. **Retrieval pointer** — a ≤1-line tag naming the external WHY-home (`(decision B2)`, `backlog 156`).

Remove WHAT-restating comments, rationale already recorded in a decision/ticket/memory (→ pointer), and changelog/history (→ git). **Explicitly override "match density upward."** Carve-out: trust-critical paths keep multi-line tripwires.

## Two subtleties the framework MUST preserve

- **Storage ≠ retrieval → the pointer is NOT a duplicate.** When an agent opens a file, the decision/backlog records are not in its context (SessionStart injects a fixed path set; commit bodies were empty in both audited repos). The one-line pointer is the only in-context trigger to the external record. A rule that says "never restate, the why lives elsewhere" wrongly deletes it and orphans the record. Keep the pointer; kill only the prose.
- **Architecture-dependent → carve-outs are project-configurable.** Whether a separate instruction layer is read instead of source was SUPPORTED in one project and REFUTED in another. Ship a project-settable trust-critical glob list; let each project run the audit prompt to confirm fit. Do not hardcode one carve-out set.

## Where it lands (the four integration points)

1. **FLOW_RULES.md FR-22** — primary home; always-on code-writing invariant; includes the density-override clause.
2. **`code-review` skill** — review dimension flagging WHAT-restating / duplicated-rationale / changelog comments AND verifying tripwires + pointers were retained (catch over-trimming). This is the real enforcement.
3. **AI Developer handoff (`templates/handoff-implement.md`)** — one-line reminder the policy is in force.
4. **Project-config (`policies/comment-policy.yml`)** — declarative `trust_critical_globs`.

Plus `docs/comment-policy.md` (framework reference): rationale, cross-project evidence, and the reusable independent-audit prompt (generalized — no plugin-specific clause).

## Non-negotiables

1. **Not a regex/lint hook.** Distinguishing a tripwire from a restate-WHAT comment is semantic, not pattern-matchable. A regex gate trains agents to write worse comments to satisfy it. Enforce at write-time (FR-22) + review-time (code-review), never via a gate.
2. **Pointer preserved.** The code-review dimension must catch over-trimming (a deleted pointer/tripwire), not only over-commenting.
3. **Carve-outs declarative + project-settable**, not hardcoded; default set opt-in (commented) like `protected-paths.yml`.
4. **Not retroactive.** Existing files are cleaned only via an explicit Lightweight pass; comments strip from build output, so cleanups never need a deploy.

## Acceptance

- FR-22 present in FLOW_RULES.md (row + implication + amendment log); self-attestation range reads FR-01..FR-22 across adapters (auto-synced).
- code-review skill has an explicit comment-policy dimension + failure-case + over-trim anti-pattern.
- handoff-implement carries the one-line reminder + pre-commit checklist item.
- `policies/comment-policy.yml` + `docs/comment-policy.md` exist; audit prompt generalized.
- preflight 0/0; run-tests 16/16; recovery sim PASS; health HEALTHY; plugin valid. VERSION 3.9.0 → 3.10.0.
