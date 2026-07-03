---
name: phase-audit
description: Use when a multi-slice phase has been implemented and the operator wants an independent audit of ALL slices before sign-off, or asks to "audit the phase", "review all slices", "independent check". Spawns a fresh sub-agent that examines every slice against the spec. Do NOT use for a single-diff review (use code-review), for security-only review (use security-permissions-review), or before a phase is implemented.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.3
risk_level: medium
invocation: automatic
expected_outputs:
  - per-slice audit verdict (consistent with spec/decisions; gaps; drift)
  - cross-slice consistency findings
  - consolidated audit report with blockers vs non-blockers
related_workflows:
  - eight-phase-flow.md
  - verification-gate.md
  - architect-escalation.md
hook_dependencies:
  - none
---

# Phase Audit

> **Style:** Mode-B-lite.

## Purpose

After a phase of multiple slices is implemented, run an **independent** audit (a fresh sub-agent with no implementation bias) over EVERY slice — verifying each against the spec/decisions and checking cross-slice consistency — before the phase is signed off. Catches drift that per-slice, in-session review misses.

## When to invoke

- A phase with 2+ slices is implemented and awaiting sign-off.
- Operator says "audit the phase", "review all slices", "independent audit", "did we miss anything across the phase".
- Before flipping a large spec DRAFT→DONE.

## Do not invoke when

- Single change / single diff → use `code-review`.
- Security-specific concern → use `security-permissions-review`.
- Phase not yet implemented (nothing to audit).
- A trivial one-slice phase (per-slice review suffices).

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Spec + decisions | `docs/specs/<slug>/` | stop; cannot audit without the target |
| Slice list + SHAs | `docs/specs/<slug>/tasks.md` | derive from git log of the phase range |
| Implemented diff | `git diff <phase-start>..HEAD` | stop |

## Procedure

1. **Scope.** Identify the phase's slices and their commit range from `tasks.md` / git log.
2. **Delegate (independent).** Per `flow-skills/task-delegation/SKILL.md`, spawn a fresh sub-agent (read-only) so the audit is unbiased by the implementing session.
3. **Per-slice audit.** For each slice: does the diff satisfy its acceptance criteria; cite file:line; flag gaps, scope creep, TODOs, missing tests.
4. **Cross-slice consistency.** Check slices don't contradict each other, duplicate logic, or leave a seam (shared types, interfaces, data shape).
5. **Drift vs spec/North Star.** Confirm the phase as a whole still matches the spec/decisions and `docs/north-star.md` if present.
6. **Consolidate.** Produce one report: per-slice verdicts + cross-slice findings, split into blockers vs non-blockers, each with file:line evidence.
7. **Adversarial pass (optional).** For high-risk phases, have the sub-agent try to refute its own "looks good" verdicts before reporting.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Phase audit report | chat + optional `docs/specs/<slug>/phase-audit.md` | Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Slice fails its AC | step 3 | blocker; return to AI Developer |
| Cross-slice contradiction | step 4 | blocker; reconcile before sign-off |
| Audit not independent (same session bias) | sub-agent not spawned | re-run via task-delegation |

## Escalation path

- Blockers found → return to AI Developer with the per-slice list.
- Cross-cutting design issue → `workflows/architect-escalation.md`.
- Ask operator in chat (FR-19) if scope of "the phase" is ambiguous.

## Anti-patterns

- Do not write fixes (audit only; like `code-review`, FR-01).
- Do not audit in the implementing session (defeats independence).
- Do not collapse to a single-diff review — every slice in scope.
- Do not pass a phase with unreconciled cross-slice contradictions.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
