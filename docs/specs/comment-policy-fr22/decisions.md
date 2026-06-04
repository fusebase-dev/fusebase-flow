# Decisions — FR-22 code-comment policy

## D1 — New always-on rule = FR-22

Max existing rule is FR-21; the comment policy is FR-22. It's a code-writing invariant (like the type-safety rule that lives in `AGENTS.md`) — always-on, every role, every IDE.

## D2 — Rule text in FLOW_RULES.md; detail in a reference doc; NO new skill

The operator's proposal named four integration points (FR rule, code-review, handoff, project-config) and deliberately did **not** ask for a skill. The rule is compact enough to live as an FR-22 row + implication paragraph (its stated primary home), so adding a `flow-skills/` skill would churn the skill count (24→25) and ~8 enumerated name-lists for no enforcement benefit (enforcement is code-review, not a description-matched skill). Detail + the reusable audit prompt + cross-project evidence go in `docs/comment-policy.md` (framework reference), mirroring how the downstream proposal doc works. Skill count stays 24.

## D3 — Project-config: `policies/comment-policy.yml`

`schema_version: 1` + `trust_critical_globs` (default set commented/opt-in like `protected-paths.yml`: auth/identity/session/gate, DB migrations) + `local_override_file: policies/comment-policy.local.yml`. Declarative, project-settable; FR-22 and code-review read it as the carve-out source. Not consumed by a hook (the policy is semantic, not gate-enforced) — it's the canonical declaration of which paths keep multi-line tripwires.

## D4 — Enforcement = write-time (FR-22) + review-time (code-review). NEVER a gate.

Per the proposal's explicit "what NOT to do": no regex/lint hook. The `code-review` dimension flags WHAT-restating / duplicated-rationale / changelog comments as findings AND verifies tripwires + pointers were retained (the over-trim failure mode), so the policy can't be satisfied by deleting load-bearing pointers.

## D5 — Generalize the plugin-specific clause

The downstream rule's "AWM authoring agent reads WFO `chat-substrate/`" carve-out becomes the generic "storage ≠ retrieval / separate-instruction-layer" guidance + the project-settable `trust_critical_globs`. No downstream/plugin names ship in the framework.

## D6 — Density-override is explicit

FR-22 states "do NOT match surrounding comment density upward — trim toward this policy even in comment-heavy files." This is the clause that breaks the harness ratchet; without it the policy is silently overridden.

## D7 — Version 3.10.0

New always-on FR rule + new reference doc + new policy + review-dimension = a framework feature → minor bump (FR-21 shipped as 3.7.0 minor). Not retroactive to existing code.
