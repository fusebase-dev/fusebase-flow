# Playwright smoke test template

> **Use when:** the ticket touches user-facing UI and `verification-gate.md` defines smoke prompts S1..Sn that benefit from browser automation.

> **Style:** Mode B (per-ticket smoke spec is an internal artifact).

## File location

```
docs/specs/<slug>/smoke.spec.ts
```

Or, if the project has a dedicated test dir:

```
tests/smoke/<slug>.spec.ts
```

## Skeleton

```ts
import { test, expect } from '@playwright/test';

const BASE_URL = process.env.SMOKE_BASE_URL ?? 'http://localhost:3000';

test.describe('<slug> smoke', () => {

  test('S1: <scenario one-liner>', async ({ page }) => {
    await page.goto(`${BASE_URL}/<feature route>`);

    // Steps from verification-gate.md S1
    await page.click('<selector>');
    await page.fill('<selector>', '<value>');
    await page.click('<selector>');

    // Pass criterion
    await expect(page.locator('<selector>')).toHaveText('<expected>');

    // Evidence
    await page.screenshot({ path: 'docs/handoff/<date>-<slug>-smoke/screenshots/S1.png' });
  });

  test('S2: <scenario one-liner>', async ({ page }) => {
    await page.goto(`${BASE_URL}/<feature route>`);
    // ...
    await page.screenshot({ path: 'docs/handoff/<date>-<slug>-smoke/screenshots/S2.png' });
  });

});
```

## Run command

```bash
mkdir -p docs/handoff/<date>-<slug>-smoke/screenshots
SMOKE_BASE_URL=<deployed url> npx playwright test docs/specs/<slug>/smoke.spec.ts \
  --reporter=line \
  --output=docs/handoff/<date>-<slug>-smoke/playwright-output \
  | tee docs/handoff/<date>-<slug>-smoke/playwright-run.log
```

## Evidence persistence

| Artifact | Path |
|---|---|
| Screenshot per S<n> | `docs/handoff/<date>-<slug>-smoke/screenshots/S<n>.png` |
| Playwright trace (failures) | `docs/handoff/<date>-<slug>-smoke/playwright-output/` |
| Run log | `docs/handoff/<date>-<slug>-smoke/playwright-run.log` |
| Pass/fail summary | embedded in deploy report |

## Pass / fail interpretation

- All tests PASS, output `<n>/<n> PASS` matches gate threshold → continue with single docs commit (FR-14)
- Any test FAIL → do NOT mark spec DONE; surface to operator with concrete `S<n> observed Y, expected Z`; rollback or fix-forward per operator decision

## Anti-patterns

- Do not skip smoke "because tests passed" — smoke verifies post-deploy behavior, not pre-deploy
- Do not commit screenshots to git — keep them in `docs/handoff/<date>-<slug>-smoke/` (which is committed for audit; rotate with deploy ticket retention)
- Do not embed deploy URL or session credentials in the spec file — read from env vars
- Do not over-instrument — smoke tests are end-to-end happy-path checks, not exhaustive regression suites

## Related

- `workflows/smoke-verification.md` — when and how smoke runs
- `workflows/greenlight-deploy.md` — deploy procedure that invokes smoke
- `templates/verification-gate.md` — defines the S1..Sn prompts this spec automates
