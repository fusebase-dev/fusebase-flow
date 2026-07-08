# Workflow: smoke-verification

> **Style:** Mode-B-lite. Session mechanics for running post-deploy smoke prompts (evidence dir, pass ratio, reporting). The smoke **contract** — prompt shape, outcome-first criteria, sufficiency rules, adversarial checks — is canonical in `flow-skills/smoke-testing/SKILL.md`; execute under that skill.

## When to run

- Spec includes user-facing behavior change AND `docs/specs/<slug>/verification-gate.md` defines smoke prompts S1..Sn
- After deploy command succeeds and probes pass
- Before flipping spec.md DRAFT → DONE

## Pass threshold

`verification-gate.md` specifies the threshold (e.g., `4/4 PASS`). The threshold is part of the gate contract; a deploy report with smoke ratio below threshold means do NOT mark spec DONE.

## Procedure

1. Read smoke prompts S1..Sn from `docs/specs/<slug>/verification-gate.md`; restate each success criterion + ground-truth diagnostic per `flow-skills/smoke-testing/SKILL.md`.
2. Create evidence dir: `mkdir -p docs/tmp/handoff/<date>-<slug>-smoke/screenshots/`.
3. For each S<n>: execute the steps, capture operator-visible outcome evidence, inspect the ground-truth diagnostic surface, and record PASS / FAIL — all sufficiency rules (supporting-checks-insufficient, UI/browser plan, shared-state discipline, test-data cleanup) per the smoke-testing skill.
4. Save evidence: `docs/tmp/handoff/<date>-<slug>-smoke/S<n>-<scenario>.{png,md,log}`.
5. Compute pass ratio: `<n_pass>/<n_total>`.
6. Append summary to deploy report:
   ```
   Smoke results: <n_pass>/<n_total> PASS
   - S1: PASS — evidence at docs/tmp/handoff/<date>-<slug>-smoke/S1-*.png
   - S2: PASS — evidence at docs/tmp/handoff/<date>-<slug>-smoke/S2-*.md
   - S3: FAIL — observed Y, expected Z; evidence at docs/tmp/handoff/<date>-<slug>-smoke/S3-*.png
   ```

## Pass

If ratio meets threshold from gate contract: continue with single docs commit (FR-14) and spec.md DRAFT → DONE.

## Fail

If ratio below threshold:
- Do NOT mark spec DONE
- Surface failure in chat (Mode A) with concrete `S<n> observed Y, expected Z` and evidence path
- Recovery options: **Rollback** per the handoff's rollback-surface plan (`git revert <deploy hash>` + redeploy for code-only; else the surface-appropriate steps — `flow-skills/release-deploy-reporting/SKILL.md` § Rollback-surface classification) or **Fix-forward** (file follow-up task; spec stays DRAFT)
- Operator decides

## Automation surfaces

UI flow → Playwright (`templates/smoke-test-playwright.md`; screenshot + DOM snapshot) · API surface → curl/httpie (response body + status) · Background job → application logs (log line excerpt). The AI Developer or Deploy session executes; evidence is captured to `docs/tmp/handoff/<date>-<slug>-smoke/`.

## Outputs

| Artifact | Path |
|---|---|
| Per-prompt evidence | `docs/tmp/handoff/<date>-<slug>-smoke/S<n>-*.{png,md,log}` |
| Summary | embedded in deploy report |
| Failure flag (if applicable) | chat surfacing + spec stays DRAFT |

## Related

- `flow-skills/smoke-testing/SKILL.md` — canonical smoke contract (definition + execution discipline)
- `workflows/verification-gate.md` — gate contract that includes smoke threshold
- `workflows/greenlight-deploy.md` — deploy flow that includes this workflow
- `templates/smoke-test-playwright.md` — Playwright spec template
- `flow-skills/validation-and-qa/SKILL.md` — sub-mode B (smoke verification)
- `flow-skills/release-deploy-reporting/SKILL.md` — captures smoke results in deploy report
