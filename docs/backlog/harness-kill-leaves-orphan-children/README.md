# harness-kill-leaves-orphan-children

**Status:** parked — observed, not reasoned
**Filed:** 2026-08-06
**Severity:** medium-high — silently corrupts the timings of every subsequent run, and presents as flaky tests
**Surface:** `hooks/tests/run-tests.sh:102-116` (`_ff_exit_reap` / `trap _ff_exit_reap EXIT`)

## Observed

A full gate was launched under an outer wall (`timeout 6000 bash hooks/tests/run-tests.sh`). The outer wall fired at 100 min while `cli-flow-recovery` was in flight. The harness died; **its children did not.**

Alive **38 minutes** after the parent's death, verified via Win32 `CommandLine`:

```
387624  timeout.exe  "…/usr/bin/timeout.exe" -k 5s 900 bash "…/hooks/tests/test-cli-flow-recovery.sh"
400012  bash.exe     "…/hooks/tests/test-cli-flow-recovery.sh"
46672   bash.exe     "…/hooks/tests/test-cli-flow-recovery.sh"     <- created AFTER the parent died
```

PID 46672 was created at the exact moment the child's own 900s bound would have fired, i.e. the abandoned watchdog was still escalating with no parent to report to.

## Why it matters

This repo's operating notes already say: *before diagnosing a timing FAIL, check for a competing suite — a competing suite on this machine has caused one.* **This is how that competing suite gets created.** A killed gate seeds the next run with live CPU-consuming children, so the next run's phase timings are inflated by an invisible cause. The observable symptom is a flaky timing test; the actual cause is a previous run that never died.

Compounding: `gate-bounds-lack-headroom` is diagnosed from phase wall times. Any timing collected after a killed run is suspect, which means this defect can corrupt the evidence used to fix that one.

## What is NOT the defect

The reaper works on a **clean** exit. Verified the same day: a full gate that ran to completion (`GATE_RC=0`, 768/768) left zero test processes and zero temp captures. The gap is specific to the harness being **signalled from outside** while a bounded phase is in flight — which is exactly the case `_ff_exit_reap` says it exists to cover:

> "if the harness is signaled while a bounded phase is still in flight, taskkill ONLY that phase's own recorded child winpid"

So this is a gap in a guard that exists, not an absent guard. Root cause is undiagnosed — candidates: the EXIT trap not running on SIGTERM under MSYS, `FFHC_LAST_WINPID` not being set/visible at that moment, or the taskkill resolving to nothing because the recorded winpid had already been re-parented.

## Acceptance

- A full gate killed by an external `timeout` (SIGTERM) leaves **zero** `hooks/tests/*` processes within the `-k` grace window.
- The same holds for SIGINT (operator Ctrl-C), which is the more common real case.
- The existing clean-exit behaviour is unchanged (no new kills on a normal run).
- A red arm proves it: launch under a short outer wall, let it fire mid-phase, assert no surviving children. Without a red arm this cannot be distinguished from "it happened not to leak this time."

## Related

- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — same family, different trigger: that entry is the bounded-run kill firing on its OWN deadline (over- and under-killing). This is the harness's parent dying to an EXTERNAL signal.
- `docs/problem-catalog/health-check-false-broken-rc0-on-kill/problem.md` — the rc-on-kill sibling.
- `docs/backlog/gate-bounds-lack-headroom/README.md` — the evidence this defect can corrupt.
- FR-27 liveness: a task that cannot signal its own completion-or-death must never be launched bare. Here the child outlived the observer entirely.
