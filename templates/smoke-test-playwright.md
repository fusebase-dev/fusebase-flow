# Playwright smoke test template

> **Use when:** the ticket touches user-facing UI and `verification-gate.md` defines smoke prompts S1..Sn that benefit from browser automation.

> **Style:** Mode B (per-ticket smoke spec is an internal artifact).

## When PlayWright is overkill

PlayWright is heavy. Don't reach for it when a lighter tool suffices.

| Smoke type | Use instead of PlayWright |
|---|---|
| API surface only (no UI) | `curl` / `httpie` script with response-body assertions |
| Background job verification | tail application logs + grep for expected log line |
| CLI behavior | shell script that runs the CLI and asserts on stdout / exit code |
| Single-page render check | `curl` for HTTP 200 + grep for an expected page-title string |
| Static asset deploy | `curl -I` for HTTP 200 + content-length range check |

PlayWright pays off when smoke needs DOM interaction (clicking buttons, filling forms, asserting on rendered text after JS execution). For everything else, the lighter tool is faster to write, faster to run, and produces evidence that's easier to grep.

## Setup (one-time per project)

```bash
# Install Playwright + the browser binaries (only browsers actually used in smoke tests)
npm install --save-dev @playwright/test
npx playwright install chromium

# Add a minimal playwright.config.ts at project root if not already present:
# (skip if your project already has Playwright configured)
```

Minimal `playwright.config.ts`:

```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './docs/specs',                  // smoke specs live alongside their tickets
  testMatch: '**/smoke.spec.ts',            // only files explicitly named smoke.spec.ts
  reporter: [['line'], ['html', { open: 'never' }]],
  use: {
    headless: true,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
});
```

The setup is once-per-project; per-ticket smoke specs reuse it.

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

## Trade-offs vs Chrome DevTools Protocol (CDP)

PlayWright wraps CDP under a higher-level API. The trade-off:

| Concern | PlayWright | Raw CDP |
|---|---|---|
| Authoring friction | low — `page.click`, `page.fill`, etc. | high — manual `Runtime.evaluate` / `Input.dispatchKeyEvent` |
| Cross-browser | yes (Chromium / Firefox / WebKit) | Chromium-only |
| IDE integration | excellent (`@playwright/test` extension for VS Code, codegen, debug) | minimal |
| Trace + screenshot | first-class (`trace: 'on-first-retry'`, `screenshot: 'only-on-failure'`) | manual capture and persistence |
| Headless / headed switch | flag in config | manual `Browser.launch` plumbing |
| Fits the smoke-prompt cadence | yes — per-ticket `smoke.spec.ts` is small and disposable | no — too much boilerplate per ticket |
| Useful when CDP is direct-needed | (PlayWright exposes CDP via `page.context().newCDPSession()` if you need it) | when you specifically need CDP-level control beyond what PlayWright wraps |

Default: PlayWright. Drop to raw CDP only when a specific smoke needs direct CDP access (e.g., capturing performance traces, network throttling beyond PlayWright's API). Note this in the per-ticket `smoke.spec.ts` file's header comment so the next maintainer knows why.

## Related

- `workflows/smoke-verification.md` — when and how smoke runs
- `workflows/greenlight-deploy.md` — deploy procedure that invokes smoke
- `templates/verification-gate.md` — defines the S1..Sn prompts this spec automates
