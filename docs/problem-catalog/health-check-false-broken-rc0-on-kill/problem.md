# Problem: health-check reads a healthy install as BROKEN on Ovation (rc0-on-kill)

**Slug:** `health-check-false-broken-rc0-on-kill`
**Filed:** 2026-07-01
**Severity:** high
**Status:** resolved
**Filed by:** PO per FR-15 (consumer field report — Ovation, Windows MINGW64)

## Symptom

On Ovation, a HEALTHY install reported BROKEN: the bounded hook-test run was killed at the deadline but the wrapper returned rc0, so the `rc0 + no FAIL: + no PASS ⇒ BROKEN` branch fired.

## Root cause

The MSYS wrapper returned rc0 on a taskkill (see `bounded-run-msys-collateral-kill`). The verdict logic correctly treats `rc0 + no PASS + no FAIL` as a genuine no-run crash ⇒ BROKEN — but a killed-at-deadline run was reaching that branch with rc0 instead of a timeout rc, so a timeout was misclassified as a crash.

## Why it matters

- A healthy install told the operator it was broken → false alarm, wasted recovery effort, lost trust in the verdict.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v3.30.3 — WS2-core is the ROOT fix (wrapper returns a true 124 on kill), after which the existing `124⇒PARTIAL` path handles it; WS4 is the DEFENSIVE guard. CRITICAL: the `rc0 + no-PASS + no-FAIL ⇒ BROKEN` guard for a GENUINE no-run crash is PRESERVED (HT8–HT11) — do NOT blindly reclassify all rc0 |

## Recurrence triggers (so future sessions recognize this)

- Health-check reports BROKEN on an install that passes `run-tests` when run by hand.
- A bounded run's rc0 is about to be reinterpreted — check whether it is a real no-run crash vs a masked timeout.

## Guardrail (the lesson)

Fix false-BROKEN at the ROOT (true-124-on-kill), not by relaxing the verdict — the `rc0-no-run ⇒ BROKEN` guard is fail-closed and must NOT regress. Distinguish a masked timeout from a genuine crash by the wrapper's rc contract, never by widening the verdict's rc0 tolerance.

## Related

- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — the rc0-on-kill source this depends on.
- `hooks/tests/test-health-check-timeout.sh` — HT8–HT11 lock the fail-closed guard.
