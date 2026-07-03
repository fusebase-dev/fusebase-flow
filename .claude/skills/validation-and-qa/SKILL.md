---
name: validation-and-qa
description: Use when code changes need a gate report, operator asks "is this ready?", or a single observed failure needs reproducibility check; runs lint/typecheck/tests, smoke, probes, reproducibility-before-fix. Do NOT approve deploy (that's release-deploy-reporting).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: medium
invocation: automatic
expected_outputs:
  - gate report (chat or docs/verification/<slug>-gate.md)
  - smoke report (docs/tmp/handoff/<date>-<slug>-smoke/)
  - reproduction notes (when applicable)
related_workflows:
  - verification-gate.md
  - smoke-verification.md
hook_dependencies:
  - stop
---

# Validation and QA

## Purpose

Validate changed behavior with deterministic checks before a deploy is approved. Five sub-modes: (a) verification gate after implementation; (b) smoke prompt verification post-deploy; (c) reproducibility-before-fix when a single observed failure is reported; (d) test-data hygiene cleanup; (e) **Lightweight-lane live-proof** (FR-21) — the compressed gate for a Lightweight ticket.

## When to invoke

- Active phase is `Verify` (per FLOW_RULES state announcement)
- AI Developer has reported a gate from `greenlight-implement` and the operator pasted it back
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
| AI Developer gate report | chat paste from AI Developer session | Stop; ask operator to paste report |
| Lint / typecheck / test commands | project-specific section of `AGENTS.md` or `package.json`/`pyproject.toml` | Stop; ask operator to provide commands |
| Worker-undisturbed list | `policies/protected-paths.yml` | Stop; gate cannot complete without protected-path verification |
| UI / E2E test context, if applicable | `verification-gate.md`, `templates/smoke-test-playwright.md`, route/component files, API/backend paths | Require route, primary action, stable locator, auth plan, test data, expected outcome, diagnostic surfaces |
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Continue with Flow-only validation, but mark app-domain probe coverage unknown |

## Procedure

### Sub-mode A — Verification gate

1. Read `verification-gate.md` to learn the contract (smoke prompts, probe list); required gate-report fields are canonical in `policies/gate-contracts.yml: gate_report` (producer template: `templates/gate-report.md`).
2. Verify completeness of the pasted gate report against that field schema.
3. If any field missing, redirect implementer: "Gate report missing <field>. Per FR-05, complete reports only. Re-run."
4. Run cross-artifact consistency check (every AC exercised in tasks; every locked decision cited where applied; no TODO/FIXME/WIP markers; spec status still DRAFT).
5. **Apply the 3-question test for empirical coverage** to each AC:
   1. *Did this AC actually run on a real input?* (or only in unit tests with mocks?)
   2. *Was the observed output compared to the expected output?* (or did the test only assert "no exception"?)
   3. *Could a reader reproduce the run from the gate report alone?* (commands + inputs + outputs visible?)

   If any answer is "no" for any AC, the gate is incomplete. Redirect implementer to add the missing evidence, even if all the unit tests pass. Mock-only tests + green CI do NOT prove the AC works against real inputs.

   **Self-recording systems (FR-23):** if the system under test has durable evidence surfaces (journals, run records, logs, snapshots), report fields carry POINTERS to them — transcribe only what no system records; redirect a report that re-transcribes system-recorded events.
6. For UI / E2E evidence, verify the test plan is specific enough to reproduce:
   - Route/navigation path to the feature.
   - Stable selectors or accessible locators for controls and meaningful outputs.
   - Primary action under test and expected user-visible result.
   - Auth/session plan, including whether synthetic test data or live-user verification is required.
   - Test data setup using unique values; no exact-count assumptions against shared state unless the test created the records.
   - Browser-visible evidence plus backend/log/API diagnostic evidence when the feature spans frontend and backend.
7. If passes, output approval to operator with explicit phrase "Gate verified. Phase advances to Deploy."

**Gate scoping (FF_ONLY) — the final gate MUST be full/unscoped.** `bash hooks/tests/run-tests.sh` supports `FF_ONLY="tag1,tag2"` to run a SUBSET of phases for implement-loop iteration speed. FF_ONLY is implement-loop only: the FINAL pre-commit / pre-deploy gate MUST be a full **unscoped** run, and a gate report may cite ONLY `state/audit/hook-test-results.md` — **never** `hook-test-results-scoped.md`. A scoped run is fail-closed by construction (its summary line is deliberately not the strict `[run-tests] N/N PASS` shape, so `ffhc_run_tests_pass_ok` / `ffhc_count_pass_lines` read it as NOT a clean full pass; its rows go to the separate scoped file). If a pasted gate report cites the scoped file or a `(SCOPED FF_ONLY=…)` summary, redirect the implementer to re-run the full gate. `FF_LIST=1` prints the canonical tag list without running.

### Sub-mode E — Lightweight-lane live-proof (FR-21)

For a Lightweight-lane ticket there is no `verification-gate.md` and no long-form gate report — but the **live proof is never skipped** (it is the safety floor). Compress, don't drop:

1. Run the change on a **real input** (not a mock) and **compare observed to expected** — the first two of the 3-question test, applied to the one acceptance criterion in the change-note.
2. Make it **reproducible from the change-note alone** (command + input + observed output in 1–3 lines) — the third question.
3. Confirm the FR-07 protected-path re-check is clean (`git diff` against `policies/protected-paths.yml`).
4. Report in **1–3 lines**: `<what changed> · observed <X>, expected <Y> ✓ · FR-07 clean`. That is the LL gate.

If the live proof can't be produced (no real input reachable, outcome not measurable), the ticket is **not** Lightweight-eligible per condition 3 — promote to Full (`flow-skills/lightweight-lane/SKILL.md`).

### Sub-mode B — Smoke prompt verification (post-deploy)

1. Invoke `flow-skills/smoke-testing/SKILL.md` — the canonical smoke contract (outcome-first sufficiency, UI/browser plan, shared-state discipline, dual-surface evidence) — and run S1..Sn from `verification-gate.md` per `workflows/smoke-verification.md` mechanics.
2. Persist evidence to `docs/tmp/handoff/<date>-<slug>-smoke/`; compute the pass ratio and verify it against the threshold in the gate contract.
3. If below threshold, or if end-to-end smoke is not feasible, do NOT mark spec DONE. Report failure or `PENDING-OPERATOR-SMOKE` with concrete `Sn observed Y, expected Z` / missing prerequisite.

### Sub-mode C — Reproducibility before fix

1. Operator reports single observed failure ("the system did X").
2. Reproduce 3 times under the same conditions.
3. Outcomes:
   - **3/3 reproduce** → systemic; invoke `requirements-specification` to draft fix spec
   - **1/3 or 2/3** → likely model variance / non-determinism; document and recommend no-op close
   - **0/3** → close ticket as no-op-needed
4. Document attempts in chat with concrete commands, inputs, observed outputs.

### Sub-mode D — Test-data hygiene cleanup

Run BEFORE marking the spec DONE. Smoke runs and reproducibility attempts often write throwaway artifacts (probe payloads, screenshots, temp database rows, mock response captures). These must be cleaned up so they don't pollute the next session or leak into commits.

1. **Inventory test artifacts created during this ticket:**
   - Files written under `docs/tmp/handoff/<date>-<slug>-smoke/` (KEEP — evidence)
   - Files written under `tmp/`, `/tmp/`, project root with random names (DELETE)
   - Database rows tagged with test slugs / fixture IDs (DELETE if scoped to this ticket; keep if shared fixture)
   - Mock response captures left in feature directories (DELETE)
   - Screenshots / response bodies that captured operator session content during live-user verification (REDACT or DELETE per `workflows/live-user-verification.md` Step 6)
   - External-service test objects, notifications, webhooks, or payment-like side effects (CLEAN UP or document as intentionally retained with approval)
2. **Run cleanup commands** with explicit before/after counts. Example:
   ```
   # Before: list what will be removed
   find tmp/ -type f -name '<slug>-*' | wc -l    # → 7
   # Cleanup
   find tmp/ -type f -name '<slug>-*' -delete
   # After: confirm zero remain
   find tmp/ -type f -name '<slug>-*' | wc -l    # → 0
   ```
3. **Verify no test data slipped into git:** `git status` after cleanup; if anything is staged that looks like test artifact, unstage and delete (or move to `docs/tmp/handoff/<date>-<slug>-smoke/` if it is genuine evidence).
4. **Document in the gate report:** one-line "Test-data hygiene: <N> ephemeral artifacts cleaned; 0 remaining; git status clean."

Skip this sub-mode only if no test data was written during the ticket (rare — even pure typecheck tickets often leave `node_modules/` / `__pycache__/` churn that should be ignored, not deleted).

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Gate verdict | chat output to operator | Mode A |
| Smoke evidence | `docs/tmp/handoff/<date>-<slug>-smoke/` | Mode B (full) |
| Reproduction notes | chat output + optionally `docs/specs/<slug>/spec.md` audit-log | Mode A + Mode B |

## Verification cost

For any verification that spans wall-clock time (deploys, jobs, agent runs): record-then-read by default — see `flow-skills/smoke-testing` § Verification cost discipline (polling is the bounded exception, not the default).

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Lint/typecheck failed in implementer gate report | report shows "lint: errors" or "typecheck: errors" | Redirect implementer to fix; do not advance phase |
| Worker-undisturbed file diffed unexpectedly | `git diff` against `protected-paths.yml` shows non-empty | Stop; redirect to check FR-07 + filed exception artifact |
| UI / E2E plan is vague | no route, locator, primary action, test data, auth plan, or expected outcome | Mark gate incomplete; require a reproducible browser test plan |
| Shared-state assumption | asserts exact counts or empty state without creating/isolating data | Revise test to create unique data or isolate state before claiming PASS |
| Smoke S<n> failed | screenshot or log shows divergence from expected | Document `Sn observed Y, expected Z`; do NOT mark spec DONE; surface to operator with rollback/fix-forward options |
| Browser PASS but backend diagnostic shows error | console/UI looks right while server log/request dump/job row shows failure | Smoke FAIL; attach both evidence surfaces |
| Reproduce attempt fails 0/3 or partially | 1 or 2 of 3 attempts reproduce | Document model variance; recommend no-op close per FR-10 |

## Escalation path

- Smoke threshold not met → operator decides rollback (`git revert`) or fix-forward via follow-up task; surface options, don't decide
- Test infrastructure broken → file infra ticket; gate cannot proceed; do not weaken gate to "skip tests"
- Reproduction needs operator session credentials → propose via `workflows/architect-escalation.md` (live-user verification with explicit consent)
- External-service side effects needed for verification → require explicit approval or use a sandbox/test-mode path before execution

## Anti-patterns

- Do NOT approve deploy from this skill (that's `release-deploy-reporting`)
- Do NOT weaken gate criteria mid-flight ("just this once skip lint")
- Do NOT print or persist session keys / cookies if a live-user verification is in play; mask in output
- Do NOT auto-fix lint or typecheck errors without operator approval — surface them
- Do NOT skip reproducibility-before-fix when a single failure is reported (FR-10)
- Do NOT use browser automation for API-only, unit-only, load, or performance testing when a lighter deterministic probe is sufficient
- Do NOT claim UI/E2E coverage from a test plan with placeholders, uncreated data, brittle selectors, or unspecified auth state
- Do NOT allow external-service smoke to send real notifications, charges, or customer-visible messages without an approval path

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
