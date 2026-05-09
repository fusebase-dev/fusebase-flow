---
name: validation-and-qa
description: Use when code changes need a gate report, operator asks "is this ready?", or a single observed failure needs reproducibility check; runs lint/typecheck/tests, smoke, probes, reproducibility-before-fix. Do NOT approve deploy (that's release-deploy-reporting).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 0.1
risk_level: medium
invocation: automatic
expected_outputs:
  - gate report (chat or docs/verification/<slug>-gate.md)
  - smoke report (docs/handoff/<date>-<slug>-smoke/)
  - reproduction notes (when applicable)
related_workflows:
  - verification-gate.md
  - smoke-verification.md
hook_dependencies:
  - stop
---

# Validation and QA

## Purpose

Validate changed behavior with deterministic checks before a deploy is approved. Three sub-modes: (a) verification gate after implementation; (b) smoke prompt verification post-deploy; (c) reproducibility-before-fix when a single observed failure is reported.

## When to invoke

- Active phase is `Verify` (per FLOW_RULES state announcement)
- Implementer has reported a gate from `greenlight-implement` and the operator pasted it back
- Operator asks "is this ready?" / "did it pass?" / "validate this change"
- Operator describes a single observed failure: "the system did X, that's wrong" → run reproducibility-before-fix sub-mode (FR-10)
- Post-deploy: smoke-prompt verification when `verification-gate.md` specified numbered smoke prompts

## Do not invoke when

- Operator wants deploy approval — invoke `release-deploy-reporting` instead
- No code change exists yet (the gate runs against actual implementation, not a plan)
- Spec is still in DRAFT with unresolved clarifies — gate cannot pass an incomplete spec

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Verification-gate contract | `docs/specs/<slug>/verification-gate.md` | Stop; gate without contract is meaningless |
| Implementer gate report | chat paste from Implementer session | Stop; ask operator to paste report |
| Lint / typecheck / test commands | project-specific section of `AGENTS.md` or `package.json`/`pyproject.toml` | Stop; ask operator to provide commands |
| Worker-undisturbed list | `policies/protected-paths.yml` | Stop; gate cannot complete without protected-path verification |

## Procedure

### Sub-mode A — Verification gate

1. Read `verification-gate.md` to learn the contract (required fields, smoke prompts, probe list).
2. Verify completeness of pasted gate report against contract:
   - Every T-task has a SHA
   - Test counts (before / after / delta per layer)
   - Lint + typecheck status
   - Worker-undisturbed git diff confirmation
   - Manifest version (if applicable)
3. If any field missing, redirect implementer: "Gate report missing <field>. Per FR-05, complete reports only. Re-run."
4. If complete, run cross-artifact consistency check (every AC exercised in tasks; every locked decision cited where applied; no TODO/FIXME/WIP markers; spec status still DRAFT).
5. If passes, output approval to operator with explicit phrase "Gate verified. Phase advances to Deploy."

### Sub-mode B — Smoke prompt verification (post-deploy)

1. Run numbered smoke prompts S1..Sn from `verification-gate.md`. Persist evidence (screenshots, response excerpts, log lines) to `docs/handoff/<date>-<slug>-smoke/`.
2. Compute pass ratio (e.g., 4/4 PASS).
3. If below threshold defined in gate contract, do NOT mark spec DONE. Report failure with concrete `Sn observed Y, expected Z`.

### Sub-mode C — Reproducibility before fix

1. Operator reports single observed failure ("the system did X").
2. Reproduce 3 times under the same conditions.
3. Outcomes:
   - **3/3 reproduce** → systemic; invoke `requirements-specification` to draft fix spec
   - **1/3 or 2/3** → likely model variance / non-determinism; document and recommend no-op close
   - **0/3** → close ticket as no-op-needed
4. Document attempts in chat with concrete commands, inputs, observed outputs.

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Gate verdict | chat output to operator | Mode A |
| Smoke evidence | `docs/handoff/<date>-<slug>-smoke/` | Mode B (full) |
| Reproduction notes | chat output + optionally `docs/specs/<slug>/spec.md` audit-log | Mode A + Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Lint/typecheck failed in implementer gate report | report shows "lint: errors" or "typecheck: errors" | Redirect implementer to fix; do not advance phase |
| Worker-undisturbed file diffed unexpectedly | `git diff` against `protected-paths.yml` shows non-empty | Stop; redirect to check FR-07 + filed exception artifact |
| Smoke S<n> failed | screenshot or log shows divergence from expected | Document `Sn observed Y, expected Z`; do NOT mark spec DONE; surface to operator with rollback/fix-forward options |
| Reproduce attempt fails 0/3 or partially | 1 or 2 of 3 attempts reproduce | Document model variance; recommend no-op close per FR-10 |

## Escalation path

- Smoke threshold not met → operator decides rollback (`git revert`) or fix-forward via follow-up task; surface options, don't decide
- Test infrastructure broken → file infra ticket; gate cannot proceed; do not weaken gate to "skip tests"
- Reproduction needs operator session credentials → propose via `workflows/architect-escalation.md` (live-user verification with explicit consent)

## Anti-patterns

- Do NOT approve deploy from this skill (that's `release-deploy-reporting`)
- Do NOT weaken gate criteria mid-flight ("just this once skip lint")
- Do NOT print or persist session keys / cookies if a live-user verification is in play; mask in output
- Do NOT auto-fix lint or typecheck errors without operator approval — surface them
- Do NOT skip reproducibility-before-fix when a single failure is reported (FR-10)

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
