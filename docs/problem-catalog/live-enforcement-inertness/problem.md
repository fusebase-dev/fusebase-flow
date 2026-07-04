# Problem: live enforcement hooks were INERT — handlers read a Flow-schema event field the host never sends

**Slug:** `live-enforcement-inertness`
**Filed:** 2026-07-04
**Severity:** critical
**Status:** resolved
**Filed by:** Deploy phase per FR-15 (highest-value Phase C finding; operator standing directive to catalog audit lessons)

## Symptom

The `UserPromptSubmit` + `Stop` hook handlers were GREEN in the test suite yet did NOTHING in a live Claude Code session. The FR-12 pasted-secret warning, bypass detection, the `/product-owner` activation reminder, and the FR-04/05/14 done/deploy-complete deny gate never fired on real prompts. The enforcement existed, was tested, and shipped — but was structurally inert in production.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Paste a prompt containing a secret in a real Claude Code session (pre-S1 handler) | No FR-12 warning — handler read `user_prompt`; host sent `prompt` |
| 2 | Emit a "done"/"deploy complete" claim in a real session (pre-S1 handler) | No deny — handler read `agent_message`; host sends `transcript_path` (final assistant message must be parsed from it) |
| 3 | Run the hook test suite | GREEN — fixtures injected the Flow-schema keys (`user_prompt`/`agent_message`), so the synthetic input matched the handler's read and the logic ran |

Reproduces: deterministic — the handler read a key the runtime never sends, so the guarded branch was unreachable live while every schema-shaped fixture stayed green.

## Root cause

The handlers read normalized/Flow-schema event fields (`user_prompt`, `agent_message`) with NO normalization shim from the host's native event shape. The Claude Code runtime sends `prompt` (UserPromptSubmit) and `transcript_path` (Stop — the final assistant message must be extracted from the transcript file), not the internal names. Because the test fixtures fabricated the internal schema shape, the suite exercised the deny/warn logic against inputs that never occur in production. A "green hook suite" proved the LOGIC, not that the hook FIRES on a real event. This is a synthetic-only coverage gap: storage-shape (internal schema) diverged from wire-shape (host native), and nothing tested the wire boundary.

## Why it matters

- Every enforcement wired to these two events was silently off in production while presenting as tested-and-shipped — the worst failure class (false confidence in a safety control).
- The gap is invisible to happy-path AND to schema-shaped adversarial tests; only a native-shape fixture (or a live drive) surfaces it.

## Mitigation / workaround

S1 fix (`4acb535`): handlers read the native shapes — dual-key `prompt` (UserPromptSubmit) and parse the final assistant message from `transcript_path` (Stop); warns surface via `hookSpecificOutput.additionalContext`, denies via stderr. The deny/warn LOGIC is unchanged — only the input source was fixed, so no gate was weakened. New native-shape fixtures close the synthetic-only coverage gap. S1b (`9790c90`) then hard-closed the transcript-extraction edge: when the transcript is corrupt/wrong-shape/format-drifted and the final assistant message can't be extracted, `stop.py` now FAILS CLOSED (deny "could not verify — unverifiable transcript") rather than falling open.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | S1 `4acb535` + S1b `9790c90` (release v3.30.7, commit `aabbadc`) · tag v3.30.7 · 2026-07-04 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- Writing or modifying a hook handler that reads event input (`hooks/handlers/*.py`)
- Adding a hook test fixture — verify it uses the HOST's native event shape, not just the internal schema
- A hook that "passes its tests" but doesn't visibly act in a live session
- Any read of a normalized/internal field name where the host emits a different wire key

## Guardrail (the lesson)

A hook handler that reads a normalized/Flow-schema event field the host runtime never sends is INERT in production while its schema-shaped tests stay green — a synthetic-only coverage gap. Test hooks with the HOST's NATIVE event shape (fixture the real `prompt` / `transcript_path`), not just the internal schema. A "green hook suite" does not prove the hook fires live — it proves the logic runs on the fixture shape. Test the WIRE boundary, not only the storage shape.

## Related

- `docs/problem-catalog/security-check-fail-open-class/problem.md` — sibling fail-open class (S1b's transcript edge is a fail-open closed to fail-closed)
- Phase C audit: independent Fable whole-system audit (9 subsystems → 40 findings → 6 fix slices S1/S2/S4/S5/S6 + S1b), released as v3.30.7

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-04 | filed + resolved | release v3.30.7 (`aabbadc`); S1 `4acb535` + S1b `9790c90` |
