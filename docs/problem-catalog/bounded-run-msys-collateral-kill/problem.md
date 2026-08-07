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

## Scope boundary — DEADLINE reap vs EXTERNAL teardown (T3, 2026-08-06)

This entry is the **deadline** reap: the bounded run hitting its OWN timeout and killing its recorded child. It is NOT the external-signal case (`harness-kill-leaves-orphan-children` / S2), where the harness is TERM/INT-ed from outside mid-phase. T3 measured two facts that bound any future work here:

| Fact | Consequence |
|---|---|
| `taskkill //F //T //PID <recorded child winpid>` reports `SUCCESS` but kills ONLY the inner `timeout` — the phase bash and its grandchild survive | `//T` is not a descendant guarantee on MSYS: exec/fork emulation breaks the Win32 parent link the tree walk follows. Do not treat a `SUCCESS` from `//T` as proof the subtree is gone |
| The strict identity guard holds: a recorded winpid whose child pid no longer matches kills NOTHING | The 255-collateral fix is intact and must stay intact — the S2 fix may NOT widen to a bare `taskkill //T` on an ancestor to compensate for the gap above |

Evidence: `state/audit/run-tests-signal-reap/<full-head>/summary.md` (F6, F7).

## How the S2 fix stayed inside this boundary (T4a, 2026-08-07)

The external-signal fix reaps by POSIX **process group**, not by a Win32 tree walk, so it never
widens `//T`. Every rule below exists because of THIS entry's 255-collateral incident, and each is
covered by a named row in `hooks/tests/test-run-tests-signal-reap.sh`:

| Rule in `hooks/tests/lib/orphan-reap.sh` | Regression row |
|---|---|
| The target group is bound by the group LEADER's `/proc` start token, so a recycled pid or pgid is refused | `group-identity-mismatch-kills-nothing` |
| An unresolvable own-group or harness-group lookup kills NOTHING (the first version failed OPEN here) | `failed-pgid-lookup-kills-nothing` |
| Never the caller's own group, the harness's group, or any group on the caller's parent chain — the ancestry walk is implemented, not asserted in a comment | `never-signals-own-group` |
| The native `taskkill` sweep is per-winpid, never `//T`, and every target is revalidated against a FRESH process-table observation taken after the group kill (pgid AND winpid must still match) | `sibling-survives` / `int-sibling-survives` / `launch-window-sibling-survives` / `wrapper-death-sibling-survives` |
| The strict deadline-path guard from this entry is unchanged and still exercised directly | `pid-reuse-mismatch-kills-nothing` |

The collateral controls are an independently launched, SAME-EXECUTABLE `bash` sibling outside the
target tree; it survives every capture in every scenario.

## Related

- `docs/problem-catalog/health-check-false-broken-rc0-on-kill/problem.md` — the verdict false-BROKEN this rc0 masking caused.
- `docs/problem-catalog/run-tests-never-completes-msys/problem.md` — the harness reap that depends on this strict scoping.
- `docs/backlog/harness-kill-leaves-orphan-children/README.md` — the EXTERNAL-signal sibling defect (S2); same kill primitive, different trigger.
