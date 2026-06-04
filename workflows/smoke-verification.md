# Workflow: smoke-verification

> **Style:** Mode-B-lite. Numbered smoke prompts run post-deploy with persisted evidence. Execute under `flow-skills/smoke-testing/SKILL.md`.

## Purpose

For user-facing tickets, smoke prompts (S1..Sn) verify behavior in production after deploy. Distinct from unit/integration tests (which run pre-deploy in the gate). Smoke prompts test end-to-end behavior on the deployed surface and inspect the system's ground-truth diagnostics.

## When to run

- Spec includes user-facing behavior change AND `verification-gate.md` defines smoke prompts S1..Sn
- After deploy command succeeds and probes pass
- Before flipping spec.md DRAFT → DONE

## Smoke prompt shape

Each smoke prompt (S<n>) in `docs/specs/<slug>/verification-gate.md`:

| Field | Required |
|---|---|
| Identifier | `S<n>` |
| Scenario | One-line description of the user behavior being tested |
| Route / surface | URL, command, page, or entry point |
| Steps | Numbered actions the smoke runner takes |
| Expected | What the user observes if it works |
| Evidence required | Screenshot / response excerpt / log line |
| Pass criterion | Specific condition |
| Ground-truth diagnostic | Log/dump/DOM/DB/job artifact that proves no hidden runtime failure |
| Stable selectors / locators | UI control/output selectors, or N/A |
| Auth / test data plan | no-auth, synthetic account, live-user workflow, unique values, cleanup |
| Adversarial check | Signal that would falsify the fix if the static/supporting checks passed |

Example:

```markdown
### S1: operator submits enrichment with skipFlags

Steps:
1. Open SPA at <feature URL>
2. Submit Custom enrichment with `skipFlags: { transcript: true }`
3. Watch extension console

Expected:
- Extension does NOT fetch transcripts for any video in the run
- Backend records skip in cache predicate

Evidence: extension console screenshot + backend log line `cache_branch_skip predicate=transcript`

Ground-truth diagnostic: backend request/job log for the submitted run shows no transcript fetch branch and no error entry for the run id.

Adversarial check: if static code landed but runtime still fetches transcripts, the extension log will show a transcript fetch attempt and smoke fails.

Pass criterion: 0 transcript fetch attempts in extension log + at least 1 cache_branch_skip in backend log
```

## Pass threshold

`verification-gate.md` specifies the threshold (e.g., `4/4 PASS`). The threshold is part of the gate contract; a deploy report with smoke ratio below threshold means do NOT mark spec DONE.

## Procedure

1. Read smoke prompts S1..Sn from `docs/specs/<slug>/verification-gate.md`.
2. Create evidence dir: `mkdir -p docs/handoff/<date>-<slug>-smoke/screenshots/`.
3. For each S<n>:
   - Execute the steps
   - Capture operator-visible evidence (screenshot, rendered output, response body, job result)
   - Inspect the ground-truth diagnostic surface (request dump, error log, server log, DB row, DOM state, etc.)
   - For browser smoke, use the route, viewport, stable selectors/locators, auth plan, and unique test data from S<n>
   - For UI/backend flows, inspect browser console/network evidence and backend/log/API diagnostics
   - Save evidence: `docs/handoff/<date>-<slug>-smoke/S<n>-<scenario>.{png,md,log}`
   - Compare against expected and pass criterion
   - Record verdict: PASS / FAIL
   - Treat exit code 0, service active, hash match, symbol presence, and auth sanity as supporting checks only
   - Record created test data and cleanup status when the smoke writes shared state or external-service objects
4. Compute pass ratio: `<n_pass>/<n_total>`.
5. Append summary to deploy report:
   ```
   Smoke results: <n_pass>/<n_total> PASS
   - S1: PASS — evidence at docs/handoff/<date>-<slug>-smoke/S1-*.png
   - S2: PASS — evidence at docs/handoff/<date>-<slug>-smoke/S2-*.md
   - S3: FAIL — observed Y, expected Z; evidence at docs/handoff/<date>-<slug>-smoke/S3-*.png
   - S4: PASS — evidence at docs/handoff/<date>-<slug>-smoke/S4-*.log
   ```

## Pass

If ratio meets threshold from gate contract: continue with single docs commit (FR-14) and spec.md DRAFT → DONE.

## Fail

If ratio below threshold:
- Do NOT mark spec DONE
- Surface failure in chat (Mode A) with concrete `S<n> observed Y, expected Z` and evidence path
- Recovery options:
  - **Rollback:** `git revert <deploy hash>` + redeploy
  - **Fix-forward:** file follow-up task; spec stays DRAFT
- Operator decides

## Smoke automation surfaces

Smoke prompts can be:

| Type | Tool | Evidence format |
|---|---|---|
| UI flow | Playwright (see `templates/smoke-test-playwright.md`) | screenshot + DOM snapshot |
| API surface | curl / httpie | response body + status code |
| Background job | application logs | log line excerpt |
| Mixed | combination | as appropriate |

The AI Developer or Deploy session executes; evidence is captured to `docs/handoff/<date>-<slug>-smoke/`.

## Outputs

| Artifact | Path |
|---|---|
| Per-prompt evidence | `docs/handoff/<date>-<slug>-smoke/S<n>-*.{png,md,log}` |
| Summary | embedded in deploy report |
| Failure flag (if applicable) | chat surfacing + spec stays DRAFT |

## Related

- `workflows/verification-gate.md` — gate contract that includes smoke threshold
- `workflows/greenlight-deploy.md` — deploy flow that includes this workflow
- `templates/smoke-test-playwright.md` — Playwright spec template
- `flow-skills/smoke-testing/SKILL.md` — role discipline for defining/executing outcome-based smoke
- `flow-skills/validation-and-qa/SKILL.md` — sub-mode B (smoke verification)
- `flow-skills/release-deploy-reporting/SKILL.md` — captures smoke results in deploy report
