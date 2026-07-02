# Problem: tests passed green while `set -e` was OFF — a real optional-step abort bug hid behind them

**Slug:** `tests-ran-without-set-e`
**Filed:** 2026-07-02
**Severity:** medium
**Status:** resolved
**Filed by:** PO per FR-15 (v3.30.4 WS5 adversarial-review lesson)

## Symptom

A WS5 optional-step abort bug (an optional upgrade step failure/timeout aborted the whole run instead of warn-and-continue) passed the test suite GREEN. Codex adversarial review flagged it as a BLOCKER on the corrected diff; the tests had not been exercising the abort path because the sourced test lib ran without `set -e` — the failing branch's nonzero return was swallowed, so the bug was invisible to the harness.

## Root cause

The bug lived in a `set -e`-sensitive control path (an optional step's nonzero return should warn+continue, but under `set -e` it aborts the script). The test that "covered" it sourced the library WITHOUT `set -e`, so the exact runtime condition that triggers the bug was never reproduced by the test. Green tests attested coverage that did not exist: the assertion ran, but not under the shell option that makes the bug fire.

## Why it matters

- A green suite is only as trustworthy as the runtime conditions it reproduces — `set -e` / `pipefail` / `nounset` change control flow, so a test that sources a lib under different shell options is testing a DIFFERENT program.
- The bug was production-relevant (WS5 upgrade engine bounded exit): under `set -e` a single optional-step hiccup would abort a real consumer's `upgrade.sh --auto-yes`.
- Only an independent adversarial review (Codex) caught it — the self gate-report trusted the green tests. Reinforces the "adversarial-review implementations before deploy" memory.

## Mitigation / workaround

1. Test `set -e`-sensitive code UNDER `set -e` (source the lib with the same shell options the real caller uses, or run the branch in a `set -e` subshell).
2. When a fix touches control flow that depends on a shell option (`set -e`/`pipefail`/`nounset`), assert the branch under that exact option — a bare return-code assertion is insufficient.
3. Run an independent adversarial review of the actual diff before deploy; self gate-reports trust green tests and miss condition-not-reproduced blind spots.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `37da04f` (v3.30.4) — WS5 `set -e` optional-step abort fix, now tested under `set -e` (T22); adversarial-review BLOCKER folded |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- A fix touches a `set -e` / `pipefail` / `nounset`-sensitive branch (optional-vs-critical step handling, sourced-lib return codes).
- A test sources the code-under-test WITHOUT the shell options the real caller uses.
- A green suite attests a path that the adversarial reviewer says is broken — suspect condition-not-reproduced, not reviewer error.

## Related

- `docs/problem-catalog/truncated-manifest-on-bound-hit/problem.md` — sibling "verify against ground truth, don't trust the plausible signal" lesson.
- `docs/specs/windows-msys-hardening/roadmap.md` — § Post-deploy closeout — v3.30.4 (WS5).
- Memory: `adversarial-review-implementation-before-deploy` — independent Codex review of the actual code before deploy.

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-02 | filed + resolved | v3.30.4 release `37da04f` (WS5 T22) |
