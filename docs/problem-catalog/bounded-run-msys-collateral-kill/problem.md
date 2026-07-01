# Problem: MSYS bounded-run kill is over-broad (collateral) and returns rc0-on-kill

**Slug:** `bounded-run-msys-collateral-kill`
**Filed:** 2026-07-01
**Severity:** high
**Status:** resolved (core, v3.30.3) · hardening tracked (v3.30.4)
**Filed by:** PO per FR-15 (consumer field reports — Cummings, WorkHub, Ovation)

## Symptom

The MSYS `taskkill` path was unreliable in BOTH directions: it OVER-killed (255-reaped the caller shell, the `run-tests` harness, and unrelated `bash.exe` in OTHER sessions — WorkHub) AND UNDER-killed on some hosts (Cummings: SIGKILL grace didn't fire → rc124≠137; a native descendant blocked past the deadline). It also returned rc0 on an MSYS kill, masking the timeout.

## Root cause

`taskkill /T /PID <winpid>` resolved to an ANCESTOR and/or hit Windows PID reuse under churn (MSYS pid↔winpid mis-resolution), so `//T` reaped the whole tree rooted above the intended child. `wait` after a taskkill returned a non-timeout rc (0/other) instead of 124/137.

## Why it matters

- 255-collateral kills the harness/caller/other sessions → the suite can never complete and unrelated work dies.
- rc0-on-kill routes the health-check to a false BROKEN (see `health-check-false-broken-rc0-on-kill`).

## Permanent fix

| Status | Detail |
|---|---|
| Shipped (core) | v3.30.3 G1 (WS2-core) — scope the kill STRICTLY to the spawned child's own recorded winpid subtree; capture the winpid at launch while alive; re-verify the winpid still maps to OUR child before killing (guards PID reuse); normalize a deadline-reap to a true 124 |
| Tracked | v3.30.4 (WS2-hard) — Windows Job Object wrap + Cummings-class ac3d/deadline reliability |

## Recurrence triggers (so future sessions recognize this)

- A bounded run on MSYS kills the caller/harness/other sessions (255 collateral), or a bounded run returns rc0 despite timing out.
- Operator says "the whole terminal died" / "it killed my other session".

## Guardrail (the lesson)

Never `taskkill //T` a winpid you have not re-verified maps to YOUR recorded child at kill-time (ancestor + PID-reuse hazard). Capture the winpid at launch while the process is alive (`/proc/<pid>/winpid` vanishes on exit). A deadline-reap must normalize to a true 124/137, never rc0.

## Related

- `docs/problem-catalog/health-check-false-broken-rc0-on-kill/problem.md` — the verdict false-BROKEN this rc0 masking caused.
- `docs/problem-catalog/run-tests-never-completes-msys/problem.md` — the harness reap that depends on this strict scoping.
