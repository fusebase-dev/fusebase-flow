# Playwright smoke test template

> **Use when:** the ticket touches user-facing UI and `verification-gate.md` defines smoke prompts S1..Sn that benefit from browser automation.

> **Style:** Mode B (per-ticket smoke spec is an internal artifact).

> **Discipline:** follow `skills/smoke-testing/SKILL.md`. Playwright must exercise the real primary interaction for interactive UI changes; screenshots/DOM assertions alone are not enough. Still inspect any ground-truth diagnostic named by S<n> (request dump, app error log, job row, etc.).

## When Playwright is overkill

Playwright is heavy. Don't reach for it when a lighter tool suffices.

| Smoke type | Use instead of Playwright |
|---|---|
| API surface only (no UI) | `curl` / `httpie` script with response-body assertions |
| Background job verification | tail application logs + grep for expected log line |
| CLI behavior | shell script that runs the CLI and asserts on stdout / exit code |
| Single-page render check | `curl` for HTTP 200 + grep for an expected page-title string |
| Static asset deploy | `curl -I` for HTTP 200 + content-length range check |

Playwright pays off when smoke needs DOM interaction (clicking buttons, filling forms, asserting on rendered text after JS execution). For everything else, the lighter tool is faster to write, faster to run, and produces evidence that's easier to grep.

For interactive UI tickets, at least one Playwright smoke should complete the real workflow named in the gate: submit, save, send, authenticate, search/filter, or another primary action. Pure render checks belong in probes, not smoke PASS evidence.

Selector guidance: use stable selectors or accessible locators named in `verification-gate.md`. Prefer purpose/state selectors and role/name locators over styling, layout, generated class names, or incidental text.

## Test plan contract

Before writing a Playwright smoke, fill these fields from `verification-gate.md` S<n>. If a field is unknown, amend the gate/handoff before execution.

| Field | Required content |
|---|---|
| User flow | one journey only: route, start state, primary action, expected result |
| Viewport | desktop/mobile dimensions or "project default" |
| Locators | stable selectors or accessible locators for controls and dynamic output |
| Test data | unique values to create; existing records allowed; cleanup responsibility |
| Auth/session | no-auth, synthetic account, test account, or live-user workflow |
| Backend diagnostic | server log, request dump, API response, DB row, job trace, or N/A |
| External side effects | sandbox/test-mode path, explicit approval, or forbidden |

Shared-state rule: do not assert exact counts or empty states for data the smoke did not create. Generate unique names/ids for records created during the run, and record them in the evidence log for cleanup.

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
const RUN_ID = `smoke-${Date.now()}`;

test.describe('<slug> smoke', () => {

  test('S1: <scenario one-liner>', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });

    await page.goto(`${BASE_URL}/<feature route>`);

    // Steps from verification-gate.md S1
    await page.getByTestId('<stable-action-selector>').click();
    await page.getByTestId('<stable-input-selector>').fill(`${RUN_ID}-<value>`);
    await page.getByTestId('<stable-submit-selector>').click();

    // Pass criterion
    await expect(page.getByTestId('<stable-output-selector>')).toHaveText('<expected>');
    expect(consoleErrors).toEqual([]);

    // Evidence
    await page.screenshot({ path: 'docs/handoff/<date>-<slug>-smoke/screenshots/S1.png' });
    // Also inspect the backend/log/API diagnostic named in verification-gate.md S1.
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
| Test data note | `docs/handoff/<date>-<slug>-smoke/test-data.md` |
| Backend diagnostic excerpt | `docs/handoff/<date>-<slug>-smoke/S<n>-diagnostic.log` |
| Pass/fail summary | embedded in deploy report |

## Pass / fail interpretation

- All tests PASS, output `<n>/<n> PASS` matches gate threshold → continue with single docs commit (FR-14)
- Any test FAIL → do NOT mark spec DONE; surface to operator with concrete `S<n> observed Y, expected Z`; rollback or fix-forward per operator decision
- Browser assertions pass but console/network/backend diagnostics show an error → FAIL; attach both browser and diagnostic evidence

## Anti-patterns

- Do not skip smoke "because tests passed" — smoke verifies post-deploy behavior, not pre-deploy
- Do not rely on screenshot-only evidence for an interactive UI change
- Do not use brittle selectors tied to styling, layout, generated classes, or incidental copy
- Do not assert exact counts, first-row assumptions, or empty states unless this smoke created or isolated the data
- Do not use placeholder values that can collide with previous runs; create unique values and document them
- Do not commit screenshots to git — keep them in `docs/handoff/<date>-<slug>-smoke/` (which is committed for audit; rotate with deploy ticket retention)
- Do not embed deploy URL or session credentials in the spec file — read from env vars
- Do not trigger real notifications, charges, or customer-visible external-service actions without an explicit approval or sandbox path
- Do not over-instrument — smoke tests are end-to-end happy-path checks, not exhaustive regression suites

## Trade-offs vs Chrome DevTools Protocol (CDP)

Playwright wraps CDP under a higher-level API. The trade-off:

| Concern | Playwright | Raw CDP |
|---|---|---|
| Authoring friction | low — `page.click`, `page.fill`, etc. | high — manual `Runtime.evaluate` / `Input.dispatchKeyEvent` |
| Cross-browser | yes (Chromium / Firefox / WebKit) | Chromium-only |
| IDE integration | excellent (`@playwright/test` extension for VS Code, codegen, debug) | minimal |
| Trace + screenshot | first-class (`trace: 'on-first-retry'`, `screenshot: 'only-on-failure'`) | manual capture and persistence |
| Headless / headed switch | flag in config | manual `Browser.launch` plumbing |
| Fits the smoke-prompt cadence | yes — per-ticket `smoke.spec.ts` is small and disposable | no — too much boilerplate per ticket |
| Useful when CDP is direct-needed | (Playwright exposes CDP via `page.context().newCDPSession()` if you need it) | when you specifically need CDP-level control beyond what Playwright wraps |

Default: Playwright. Drop to raw CDP only when a specific smoke needs direct CDP access (e.g., capturing performance traces, network throttling beyond Playwright's API). Note this in the per-ticket `smoke.spec.ts` file's header comment so the next maintainer knows why.

## Related

- `workflows/smoke-verification.md` — when and how smoke runs
- `workflows/greenlight-deploy.md` — deploy procedure that invokes smoke
- `templates/verification-gate.md` — defines the S1..Sn prompts this spec automates
