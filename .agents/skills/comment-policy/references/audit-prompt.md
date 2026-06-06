# Independent-audit prompt — code-comment policy (FR-22)

Consumer-reachable copy of the generalized independent-audit prompt (rides the `comment-policy` skill into every mirror). Drop it into any repo and point an independent agent at it; it tests FR-22's claims against *that* project's architecture and is told to argue the other side. Kept verbatim so results are comparable across projects. Its output (rule fit + exact carve-out globs) populates `policies/comment-policy.yml: trust_critical_globs`. Framework-dev rationale + cross-project evidence live in `docs/comment-policy.md`.

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

## Using the result

1. Run the prompt above; capture the carve-out globs it returns.
2. Set them in `policies/comment-policy.yml: trust_critical_globs` (uncomment + customize the defaults).
3. The policy is now in force at write-time (FR-22 via the `comment-policy` skill) and review-time (`code-review`).
4. Existing files are cleaned only via an explicit Lightweight pass (FR-21) — comments strip from build output, so cleanups need no deploy.
