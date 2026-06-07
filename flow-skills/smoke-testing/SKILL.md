---
name: smoke-testing
description: Use when Product Owner defines smoke prompts or deploy handoffs, and when AI Developer / Deploy phase executes post-deploy smoke. Do NOT use for pre-deploy unit/integration/source gates alone; smoke means proving the operator-visible outcome on the deployed surface with ground-truth diagnostics.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: high
invocation: automatic
expected_outputs:
  - outcome-based smoke prompts in docs/specs/<slug>/verification-gate.md
  - deploy-handoff smoke contract in docs/tmp/handoff/<date>-<slug>-deploy.md
  - smoke evidence in docs/tmp/handoff/<date>-<slug>-smoke/
  - smoke result table in deploy report
related_workflows:
  - smoke-verification.md
  - greenlight-deploy.md
  - live-user-verification.md
hook_dependencies:
  - none
---

# Smoke Testing

> **Style:** Mode-B-lite. Outcome-first smoke discipline for Product Owner definition and AI Developer execution.

## Purpose

Prevent pre-outcome signals from being mislabeled as smoke success. A smoke test passes only when the operator-visible action works on the deployed surface and the system's ground-truth diagnostics show no hidden failure.

## When to invoke

- Product Owner drafts `verification-gate.md` for a user-facing or operator-facing change.
- Product Owner drafts `docs/tmp/handoff/<date>-<slug>-deploy.md` and includes S1..Sn smoke prompts.
- AI Developer / Deploy phase runs post-deploy smoke prompts.
- A previous smoke missed a production bug and the smoke method must be corrected.
- Operator asks whether smoke evidence is sufficient.

## Do not invoke when

- The task is only pre-deploy source validation: lint, typecheck, unit tests, static bundle checks, file hash checks.
- No deployed or runtime behavior exists to exercise.
- A live user session is required but consent/session handling is not available; invoke `workflows/live-user-verification.md` first.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Operator-visible success criterion | `verification-gate.md` smoke section | PO must write it before designing checks |
| Smoke prompts S1..Sn | `docs/specs/<slug>/verification-gate.md` | Stop; smoke cannot be improvised after deploy |
| Deployed surface / base URL / command | deploy handoff | Stop; ask PO to amend handoff |
| Ground-truth diagnostic surface | smoke prompt field: logs, request dumps, DB row, rendered UI, response body | Stop; PO must define it or explicitly mark unknown |
| Existing smoke harness | `docs/specs/<slug>/smoke.spec.ts`, script path, curl command, or manual steps | Use if present; do not substitute weaker checks silently |
| UI / browser plan, if applicable | S<n> fields or `templates/smoke-test-playwright.md` | Require route, viewport, primary action, stable locators, auth plan, unique test data, expected outcome, diagnostics |
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Continue only if smoke can name another ground-truth diagnostic surface |
| Evidence directory | `docs/tmp/handoff/<date>-<slug>-smoke/` | Create before execution |

## Procedure

### Product Owner: define the smoke contract

1. Write the success-criterion sentence first. It must describe the operator-visible outcome, not an implementation signal.
   - Bad: `spawn exits 0`
   - Good: `operator chat reply renders TemplateListCard with the 8 real templates`
2. Identify the ground-truth diagnostic surface for each S<n>. Examples: request dump JSON, app error log, server log, rendered DOM, response body, database row, job trace.
3. For Fusebase Apps smoke, use `docs/fusebase-cli-edition.md` to pick supporting CLI diagnostics such as `remote-logs`, `dev-debug-logs`, `fusebase-cli`, `fusebase-dashboards`, or `fusebase-gate`.
4. Separate supporting checks from smoke checks. File hashes, symbol presence, service active, exit code 0, and HTTP auth sanity are supporting checks only; they cannot satisfy smoke by themselves.
5. For UI smoke, include at least one real primary interaction when the ticket creates or changes one: navigate, submit, save, send, search, filter, authenticate, or complete the main workflow. A screenshot-only check is visual evidence, not sufficient smoke for an interactive feature.
6. For UI smoke, name stable selectors or accessible locators for interactive controls and meaningful dynamic output. Prefer selectors tied to purpose/state, not styling or layout.
7. For browser-driven smoke, define route/navigation, viewport coverage, auth/session plan, setup data, unique test values, and cleanup responsibility. Do not rely on existing shared data counts or empty states unless the smoke prepares that state.
8. For UI actions that cross backend boundaries, name both evidence surfaces: browser-visible result and backend/log/API diagnostic. Browser success alone is insufficient if server logs show errors.
9. Add at least one adversarial/falsification probe: "what would still be broken if the static checks passed?"
10. Define S1..Sn with these fields: scenario, route/navigation, steps, expected operator-visible outcome, pass criterion, ground-truth diagnostic to inspect, stable selectors/locators if UI-facing, auth/test data plan, viewport if browser-facing, adversarial check, evidence required, insufficient substitutes.
11. If the real end-to-end action needs operator credentials or a live session, use `workflows/live-user-verification.md`. If that is not available now, mark the deploy state `SHIPPED-pending-operator-smoke`, leave spec DRAFT, and provide the exact operator smoke prompt.
12. When drafting deploy handoff, copy the smoke contract verbatim. Do not compress S1..Sn to "run smoke" or "verify feature works."

### AI Developer / Deploy phase: execute the smoke

1. Read every S<n> before starting. Restate the success criterion and ground-truth diagnostic in the deploy log/report.
2. For Fusebase Apps smoke, load the supporting CLI diagnostics named by `docs/fusebase-cli-edition.md` or the smoke contract. Use them to inspect logs, deployed behavior, and app quality evidence after the operator-visible action runs.
3. Use the named harness if one exists. If a script was created for live smoke, run that script or explain why it is impossible; do not replace it with static checks.
4. Execute the operator-visible action. Capture outcome evidence: screenshot, response excerpt, rendered card text, produced artifact, or job result.
5. For browser smoke, run one user flow at a time, preferably in a fresh browser context. Use unique test data and record any created IDs/names for cleanup.
6. Inspect the ground-truth diagnostic after the action, including any delayed dump/log written after process exit. Use a wait window when the system writes diagnostics asynchronously.
7. For UI/backend flows, inspect browser console/network evidence and the backend/log/API diagnostic named in S<n>. Treat either surface showing an error as smoke FAIL.
8. Treat exit code 0, service active, hash match, deployed symbol, and non-401 auth response as necessary-but-insufficient preconditions.
9. For errors shaped like `'X' object is not Y`, `NoneType`, `undefined is not`, or equivalent type/iteration failures, get the full traceback first. Do not bisect from guesses.
10. If smoke fails, list at least three candidate causes before selecting the next probe. Design a probe that distinguishes them.
11. If end-to-end execution is not feasible, report `PENDING-OPERATOR-SMOKE` with the missing prerequisite and exact operator steps. Do not claim PASS, DONE, or SHIPPED.
12. Persist evidence under `docs/tmp/handoff/<date>-<slug>-smoke/` and include exact paths in the deploy report.
13. Clean up or document test data and external-service side effects before DONE. Keep evidence files; remove throwaway data not needed for audit.
14. If a smoke missed a bug, update future smoke methodology immediately: add the missed outcome or diagnostic surface to the next gate/handoff.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Smoke contract | `docs/specs/<slug>/verification-gate.md` | Mode B |
| Deploy smoke instructions | `docs/tmp/handoff/<date>-<slug>-deploy.md` | Mode B |
| Evidence files | `docs/tmp/handoff/<date>-<slug>-smoke/S<n>-*.{md,log,png,json}` | Mode B |
| Smoke result matrix | `templates/deploy-report.md` section 4 | Mode B |
| Pending operator smoke prompt | deploy report + PO chat relay block | Mode A + Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Pre-outcome signal claimed as smoke | evidence is only exit code/hash/service/curl auth | Mark smoke incomplete; require operator-visible outcome + ground-truth diagnostic |
| Ground-truth diagnostic missing | S<n> has no log/dump/artifact/DOM/row to inspect | PO amends smoke contract before deploy |
| Harness exists but was skipped | deploy report uses weaker manual/static check | Mark smoke incomplete; run harness or report pending operator smoke |
| UI smoke only checks render/screenshot | primary interaction not exercised | Mark incomplete; run the real interaction or document pending operator smoke |
| UI smoke relies on brittle selectors | selectors are CSS/layout/text fragments likely to drift | Add stable purpose/state selectors or accessible locators before claiming PASS |
| Browser smoke plan is incomplete | missing route, viewport, auth plan, unique data, expected outcome, or cleanup | Mark incomplete; amend S<n> before execution |
| Shared-state assumption | test expects exact counts or empty state from data it did not create | Create unique data or isolate state; otherwise smoke cannot prove the outcome |
| Browser and backend disagree | UI appears correct but console/network/server diagnostics show errors | Smoke FAIL; attach both evidence surfaces |
| End-to-end unavailable | missing live cookie/session/API credential | Use live-user workflow or mark `PENDING-OPERATOR-SMOKE`; spec stays DRAFT |
| Smoke fail after deploy | S<n> observed != expected or diagnostic shows error | Do not mark DONE; surface rollback vs fix-forward options |
| Hidden delayed failure | process exits 0 but later dump/log contains exception | Smoke FAIL; attach dump/log evidence |

## Escalation path

- Missing smoke contract -> Product Owner amends `verification-gate.md`.
- Live account required -> follow `workflows/live-user-verification.md`.
- Smoke threshold not met -> operator chooses rollback or fix-forward in chat text (FR-19).
- Repeated escaped smoke bug -> add/update `docs/problem-catalog/<slug>/problem.md` and amend this skill or project smoke references.

## Anti-patterns

- Do not call static deployment checks "smoke."
- Do not declare PASS from exit code 0 alone.
- Do not declare PASS from file hashes, symbol presence, service active, tick latency, or auth transport alone.
- Do not substitute an easier probe for the sufficient end-to-end probe without marking the result partial.
- Do not use screenshots alone as PASS evidence for an interactive UI change.
- Do not rely on brittle layout/style selectors when stable purpose/state selectors or accessible locators can be provided.
- Do not rely on exact shared-data counts, preexisting records, or empty states unless the smoke creates or isolates the data.
- Do not run browser automation for API-only, unit-only, load, or performance checks when a lighter deterministic probe proves the same outcome.
- Do not trigger real customer-visible external-service side effects without an approval/sandbox plan.
- Do not mark spec DONE when smoke is failed or pending operator execution.
- Do not hide missing credentials behind a green status.

## Clean-room note

Original Fusebase Flow content. Derived from operator-provided retrospective patterns and generalized into repo-local workflow discipline; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
