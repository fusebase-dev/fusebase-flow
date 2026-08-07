# harness-kill-leaves-orphan-children

**Status:** active — S2, reproduced and root-caused at T3; fix is T4
**Filed:** 2026-08-06
**Severity:** medium-high — silently corrupts the timings of every subsequent run, and presents as flaky tests
**Surface:** `hooks/tests/run-tests.sh:108-122` (`_ff_exit_reap` / `trap _ff_exit_reap EXIT`) + `hooks/local/lib/run-with-timeout.sh:519-564` (the backgrounded, polled bounded phase)
**Red arm:** `hooks/tests/test-run-tests-signal-reap.sh` (tag `signal-reap`) · **Evidence:** `state/audit/run-tests-signal-reap/<full-head>/`

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

## Reproduced — T3 (2026-08-06, HEAD `1b28ee29`)

Miniature bounded phase (child bash + its own grandchild) driven through the real
`ffhc_run_bounded` path with a byte-copy of the shipped reaper, killed by an outer `timeout`
wall mid-flight. `4/8 PASS`: the four reap assertions FAIL, the four collateral/clean-exit
controls PASS. Full trace + provenance: `state/audit/run-tests-signal-reap/<full-head>/summary.md`.

**Root cause — two independent failures, both required to explain the field observation:**

| # | Failure | Evidence |
|---|---|---|
| R1 | GNU `timeout` puts the phase subtree in its OWN process group (`pgid` = inner-timeout pid), so the group signal that kills the harness structurally cannot reach the phase child or grandchild | topology capture: harness `pgid=1003505`; wrapper/child/grandchild `pgid=1003517` |
| R2 | The EXIT trap never runs. A direct SIGTERM to the harness — which is polling inside `ffhc_msys_wait_reap`, not blocked in a foreground command — is acted on late or not at all (>=12s unacted-on measured), so the outer `-k 5s` SIGKILL lands first | trap marker absent in every run; measured direct-signal latency |
| R3 | Even when the trap DOES run, its reap is insufficient: `taskkill //F //T //PID <recorded winpid>` returns `SUCCESS`, kills only the inner `timeout`, and leaves child + grandchild alive — MSYS exec/fork emulation breaks the Win32 parent link `//T` walks | trap's own kill executed directly against a live fixture |

**Consequences for the fix (T4) — settled after THREE measurements, two of which were wrong.**

The sequence matters, because two of these were confident and mistaken:

| # | Claim | Fixture | Verdict |
|---|---|---|---|
| 1 | "A trap is ruled out; trap never fired in 12s" | real harness, FIFO nap active | **correct** |
| 2 | "Trap fires in 0.9s, so a trap IS viable" | simplified `sleep 0.2` poll loop | **wrong — non-representative fixture** |
| 3 | "Trap never fires with the nap; fires in 1s with the nap forced off" | real harness, both arms | **correct, and explains 1 and 2** |

`_ffhc_nap` is `read -t SECS` on an RW-opened FIFO. Bash does not deliver the trap while that
blocking read is in flight, so with the nap active an explicit `trap … TERM INT` does **not** run
before the outer `timeout -k 5s` SIGKILLs the harness. Measurement 2 used an external `sleep`,
which bash interrupts cleanly — it measured a loop the harness does not have.

**Therefore no harness-side cleanup can be relied on** — not an EXIT trap, not a signal trap. R2
stands as originally written. R3 stands: `taskkill //F //T` reports SUCCESS and still leaves the
descendants alive.

**The shipped mechanism is an out-of-band sentinel** (`hooks/tests/lib/orphan-sentinel.sh`),
started once per run under its own `timeout` process group so it is immune to the group signal
that kills the harness and carries a hard cap so it can never outlive the run. It polls the
harness; when the harness dies with a phase still in flight, it revalidates the recorded identity
tuple and terminates **that process group only** — R1's topology (wrapper, child and grandchild
share one pgid; the harness is in a different group) is the handle it reaps. It never signals its
own group, the harness's group, an ancestor, a name-wide set, or an unverified pid, so
`bounded-run-msys-collateral-kill` stays closed.

**The guards live in `hooks/tests/lib/orphan-reap.sh`, which the harness's EXIT path sources too**
— one guard set for both teardown paths, and the EXIT path runs the reap FIRST and disarms the
sentinel LAST, so an in-flight guard is never cleared before cleanup. Every guard fails CLOSED:
an unresolvable own/harness pgid, a leader start-token mismatch, an occupied-but-unverifiable
leader pid, an ancestor on the caller's parent chain, or no process table at all all mean **kill
nothing**. Group ownership is bound by the group LEADER's `/proc` start token, which is what makes
a recycled pid or pgid unreapable; reaping is by group MEMBERSHIP, so the leaked topology R3
recorded (leader dead, descendants alive) is covered rather than skipped.

**Cost constraint that shaped it:** on MSYS one `/proc/<pid>/stat` read costs ~500ms while one
whole-table `ps` costs ~350ms (measured). A per-pid `/proc` walk spent the entire outer `-k` grace
window before it could signal anything, so the guards take ONE `ps` snapshot and read `/proc` only
for start tokens.

**Method note worth keeping.** Measurement 2 was mine. I verified a claim against a fixture that
did not reproduce the condition under test, and used it to override a correct finding. The
fixture must contain the mechanism being questioned — here, the FIFO nap.

## What is NOT the defect

The reaper works on a **clean** exit. Verified the same day: a full gate that ran to completion (`GATE_RC=0`, 768/768) left zero test processes and zero temp captures. The gap is specific to the harness being **signalled from outside** while a bounded phase is in flight — which is exactly the case `_ff_exit_reap` says it exists to cover:

> "if the harness is signaled while a bounded phase is still in flight, taskkill ONLY that phase's own recorded child winpid"

So this is a gap in a guard that exists, not an absent guard. Root cause is now settled (R1-R3 above): of the three original candidates, "the EXIT trap not running" is confirmed (R2) and "the taskkill resolving to nothing useful" is confirmed in a stronger form than suspected — it resolves, reports SUCCESS, and still leaves the descendants alive (R3). `FFHC_LAST_WINPID` was correctly set and visible; that candidate is eliminated.

## Acceptance

- A full gate killed by an external `timeout` (SIGTERM) leaves **zero** `hooks/tests/*` processes within the `-k` grace window.
- The same holds for SIGINT (operator Ctrl-C), which is the more common real case.
- The existing clean-exit behaviour is unchanged (no new kills on a normal run).
- A red arm proves it: launch under a short outer wall, let it fire mid-phase, assert no surviving children. Without a red arm this cannot be distinguished from "it happened not to leak this time." — SHIPPED at T3 as `hooks/tests/test-run-tests-signal-reap.sh`.
- The collateral controls hold: an independently launched same-executable sibling outside the target tree survives, an identity (PID-reuse) mismatch kills nothing, and the caller shell survives.

## Known open — SIGINT exit status (design decision, not covered by this fix)

The harness's **own** exit status is 143 on TERM (measured on the harness, not on an enclosing
`timeout`). On **INT** it does not act on the signal at all and has to be SIGKILLed, so there is no
130. Adding `trap … INT` is not the fix: bash does not deliver a trap while `_ffhc_nap`'s blocking
FIFO `read` is in flight (measurement 3 above), so the handler would defer past the outer `-k`
SIGKILL and the status would become 137. Closing this means changing the nap primitive itself.
`hooks/tests/test-run-tests-signal-reap.sh` reports the row `INCONCLUSIVE` rather than asserting a
contract the code does not implement. **The orphan reap itself is unaffected** — the INT scenarios
reap child and grandchild within the grace window, because the sentinel does not depend on the
harness acting on the signal.
- Signal-correct exit status: `143` for TERM, `130` for INT.

## Related

- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — same family, different trigger: that entry is the bounded-run kill firing on its OWN deadline (over- and under-killing). This is the harness's parent dying to an EXTERNAL signal.
- `docs/problem-catalog/health-check-false-broken-rc0-on-kill/problem.md` — the rc-on-kill sibling.
- `docs/backlog/gate-bounds-lack-headroom/README.md` — the evidence this defect can corrupt.
- FR-27 liveness: a task that cannot signal its own completion-or-death must never be launched bare. Here the child outlived the observer entirely.
