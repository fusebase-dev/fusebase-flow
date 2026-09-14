# Karpathy Guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

> **Attribution:** imported from [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) `skills/karpathy-guidelines/SKILL.md` at commit `2c606141936f1eeef17fa3043a72095b4765b9c2` (body lines 7-67, verbatim except the clauses marked *Flow:*). License: MIT, as declared upstream in that file's frontmatter (`license: MIT`), `.claude-plugin/plugin.json` (`"license": "MIT"`) and `README.md` § License (`MIT`); upstream ships no LICENSE file and names no copyright holder. Provenance: `docs/source-map.md#karpathy-guidelines`.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken. *Flow:* Exception: the minimum responsibility-seam extraction required for this task by FR-25 remains in scope; see `flow-skills/module-size-discipline/SKILL.md`.
- Match existing style, even if you'd do it differently. *Flow:* For comments introduced or necessarily changed by this task, FR-22's tripwire/retrieval-pointer policy overrides surrounding comment density (`flow-skills/comment-policy/SKILL.md`).
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass" *Flow:* Apply Flow's reproduction classification in `flow-skills/validation-and-qa/SKILL.md` § Sub-mode C; for maintenance of Fusebase Flow itself, `docs/maintainer-execution.md` overrides mandatory repeat counts.
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification. *Flow:* Stay within the authorized task and approval gates; retries follow `flow-skills/token-economy/SKILL.md` TE-05 and applicable liveness bounds (`flow-skills/liveness-discipline/SKILL.md`).
