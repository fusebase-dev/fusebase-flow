# Comment policy — tripwire + pointer only (FR-22 reference)

This is the rationale, evidence, and per-project audit prompt behind **FR-22** (the always-on rule lives in `FLOW_RULES.md`; the carve-out config lives in `policies/comment-policy.yml`; enforcement lives in the `code-review` skill). Cross-project validated 2026-06-04.

## Why

In a Flow workflow, source files are read by **AI agents**, not humans line-by-line — a human asks an agent to explain rather than opening the file. So inline prose written for a human reviewer (changelog history, incident rationale, re-explained diagnosis, WHAT-restating) serves an audience that isn't there, and is paid for in context budget on every load.

Two framework-level root causes the rule fixes:

1. **The "match surrounding comment density" instruction is a one-directional ratchet** — density only matches-or-exceeds, never trims. FR-22 ships the explicit override.
2. **No feedback penalty** — every Stop-hook gate (typecheck/lint) is comment-blind. Wrong code fails a gate; a useless comment fails nothing, so the habit is invisible to the loop. Enforcement therefore moves to write-time (FR-22) + review-time (`code-review`).

(A third driver, model mimicry, is addressed indirectly by giving the agent an explicit policy.)

## The rule (summary — full text in FLOW_RULES.md FR-22)

Write only two kinds of comment; remove everything else.

- **Tripwire** — a constraint an editing agent could violate without realizing and that isn't obvious from local code (`empirical floor — don't lower below X`; `additive — editing breaks back-compat`; an auth/platform/concurrency quirk). One line by default; ≤~4 lines only for security/auth/concurrency/platform-quirk.
- **Retrieval pointer** — a ≤1-line tag naming the external WHY-home (`(decision B2)`, `backlog 156`).

Remove: WHAT-restating comments; rationale already in a decision/ticket/memory (→ pointer); changelog/history (→ git). Do **not** match surrounding density upward.

## Two subtleties (do not over-simplify)

- **Storage ≠ retrieval → the pointer is NOT a duplicate.** When an agent opens a file, the decision/backlog records are not in its context (SessionStart injects a fixed path set; commit bodies are often empty). The one-line pointer is the only in-context trigger to that external record. A naive "never restate — the why lives elsewhere" rule wrongly deletes it and *orphans* the record. Kill the prose; keep the pointer.
- **Architecture-dependent → carve-outs are project-configurable.** Whether a *separate instruction layer* is read **instead of** source (a generated substrate/prompt/RAG/codegen the authoring agent consumes, never the engine source) was SUPPORTED in one audited project and REFUTED in another (one agent reads the real files). So the trust-critical carve-out set is **project-settable** in `policies/comment-policy.yml: trust_critical_globs` — never hardcoded. Run the audit prompt below in each project to derive its set before adopting.

## Content gate forbidden — artifact-level checks encouraged

The "no gate" decision is scoped to comment **content**, not to process **artifacts**. Conflating the two over-generalized "no content gate" into "build nothing" — including the safe artifact-level checks that give FR-22 a delivery guarantee.

| Layer | Inspects | Verdict | Why |
|---|---|---|---|
| Comment CONTENT (tripwire vs WHAT-restate) | the words inside a comment | **FORBIDDEN as a gate** | tripwire-vs-restate is semantic, not pattern-matchable; a regex/lint gate trains agents to write worse comments to satisfy it. Enforced write-time (FR-22) + review-time (`code-review`). |
| Process ARTIFACTS (handoff-contains-block; review-ran signal) | whether the implement handoff carries the FR-22 push block; whether the agent emitted the review-ran marker | **ENCOURAGED** | inspects process artifacts, never comment semantics → fully FR-22-safe. Makes the rule present-by-construction (template) and visible to the loop (`comment_policy_review_applied`, warn-only, in `policies/required-artifacts.yml`; detected by `stop.py`). |

Maintainers/agents must not read "FR-22 forbids a gate" as "no enforcement machinery at all." Content gates are out; artifact-level checks are in. (The `FLOW_RULES.md` FR-22 rule row is unchanged — this distinction lives here + in the `comment-policy` skill.)

## Cross-project evidence (2026-06-04)

| Claim | Project A | Project B |
|---|---|---|
| WHAT-restating comments redundant | holds | holds (e.g. a comment restating a `.filter()` line-for-line) |
| Why already homed elsewhere → inline prose is a duplicate | holds for prose | PARTIAL — prose duplicated verbatim in code + `decisions.md`, but the inline tag is a retrieval index |
| A separate instruction layer is read **instead of** source | SUPPORTED (substrate; authoring agent never sees engine source) | REFUTED (one agent reads the real files; comments are in its context) |
| Root cause: density-ratchet + no penalty | SUPPORTED | SUPPORTED |

**Measured (trust-critical auth-core files, Project B):** comment/code ratio ~0.17 aggregate, but **0.53 in the trust-critical resolver vs 0.07 in CRUD** — waste is localized. Of ~30 auth-core comments: ~30% tripwire (keep), ~25% restate-WHAT + ~20% duplicate-prose (~45% removable), rest mixed. Headline: **for ~every 2 lines of comment, ~1 is redundant**, concentrated in a few hot engine/auth files; CRUD is already lean.

## Reusable independent-audit prompt

Drop this into any repo and point an independent agent at it; it tests the claims against *that* project's architecture and is told to argue the other side. Kept verbatim so results are comparable across projects. Its output (rule fit + exact carve-out globs) populates `policies/comment-policy.yml: trust_critical_globs`.

```
INDEPENDENT AUDIT — code-comment policy: are inline comments serving any real reader?

You are an adversarial, independent auditor. Read-only. Test a claim and a proposed rule
against THIS codebase's actual architecture; argue the opposing side before agreeing.
Assume the proposal is wrong until the code proves it right. Cite file:line.

CLAIMS: (1) the real reader of source is an AI coding agent, not a human, so WHAT-restating
comments are redundant; (2) WHY-comments are load-bearing only if the comment is the SOLE
home — where disciplined external records exist (commits/issues/docs/memory) the inline
prose is a duplicate; (3) a separate instruction layer may be consumed INSTEAD of the source
(generated prompt/substrate/RAG/codegen) — if so the agent reads that, not the code; (4)
root cause = mimicry + no feedback penalty on comments + a "match surrounding density" ratchet.

PROPOSED RULE: comment ONLY (a) a one-line TRIPWIRE (a constraint an editing agent could
violate, not obvious locally, ~4 lines max for security/concurrency) and (b) a ≤1-line
RETRIEVAL POINTER to the external WHY-home. Remove WHAT-restating, duplicated-rationale, and
changelog comments. Never match density upward.

INVESTIGATE (verify, don't assume): (A) who/what actually reads these files? (B) does a
separate instruction layer exist that an AI consumes instead of source, or does any comment
reach a model via RAG/codegen/doc-gen? (C) are the external WHY-homes real/disciplined or
thin (if thin, inline WHY may be the sole record)? (D) sample recent hunks: comment/code
ratio + classify each comment restate-WHAT / explain-WHY / tripwire / duplicate-of-record.

ARGUE THE OTHER SIDE: find comments that are the sole home of intent; files humans demonstrably
read; cases where stripping a comment lowers an editing AI's precision; domains (crypto,
concurrency, perf, hardware) needing dense local rationale. List what the rule would BREAK.

OUTPUT: verdict SUPPORTED/PARTIAL/REFUTED per claim with file:line; rule fit
adopt/adopt-with-carve-outs/reject + exact carve-outs (globs/domains); the 3 measurements
from (D) with numbers; the single strongest argument AGAINST. Read-only, no code changes.
```

## Adopting in a project

1. Run the audit prompt above; capture the carve-out globs it returns.
2. Set them in `policies/comment-policy.yml: trust_critical_globs` (uncomment + customize the defaults).
3. The policy is now in force at write-time (FR-22) and review-time (`code-review` flags WHAT-restating / duplicated / changelog comments and verifies tripwires + pointers were retained).
4. Existing files are cleaned only via an explicit **Lightweight** pass (FR-21) — comments strip from build output, so cleanups need no deploy.
