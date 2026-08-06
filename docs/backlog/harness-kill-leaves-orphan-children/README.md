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

**Consequences for the fix (T4) — CORRECTED 2026-08-06 after an independent second measurement.**

The first draft of this section said "a trap-based fix is ruled out … the mechanism must be
child-side (parent-death detection) or a supervisor." **That was wrong**, and it was the sentence
that would have steered T4 into building unnecessary machinery.

R2 measured an **untrapped** signal. Bash defers an untrapped TERM to a command boundary, which is
the ≥12s figure. A **trapped** signal is delivered at the next builtin boundary, and the poll loop
hits one constantly. Measured independently, twice, in the identical poll-loop context:

```
trap '…' TERM installed  →  trap ran 0.9s after the signal  →  harness exit 143
```

So **R2 rules out the trap's PAYLOAD, not the trap.** R3 stands: `taskkill //F //T //PID <recorded
winpid>` reports SUCCESS and still leaves child + grandchild alive, because MSYS fork/exec breaks
the Win32 parent link `//T` walks (the phase's Win32 `ParentProcessId` is a dead intermediate, not
the recorded pid).

**The mechanism R1 implies is a guarded POSIX process-group kill**, not a supervisor. R1's own
topology already contains it: wrapper, phase child and grandchild share one `pgid` equal to the
recorded `FFHC_LAST_CHILD_PID`, and the harness is in a different group. Demonstrated on a live
orphan tree that had just survived `taskkill`:

```
taskkill //F //T //PID 406884   → "SUCCESS"   … phase + grandchild STILL ALIVE
kill -TERM -1002613             → both gone, immediately
```

T4 therefore is: fire from `trap … TERM/INT`; revalidate identity
(`ffhc_msys_winpid(pid) == FFHC_LAST_WINPID`); guard scope with `pgid(pid) == pid` (own group
leader) **and** `pgid != pgid($$)`, so a mismatch kills nothing; `kill -TERM -$pgid`, wait
`FFHC_TIMEOUT_KILL_GRACE`, then `kill -KILL -$pgid`; keep `ffhc_msys_taskkill_winpid` as the
Windows backstop. The same-executable sibling sits in another process group and survives by
construction, and the two pgid guards exclude the caller shell — so
`bounded-run-msys-collateral-kill` is not reopened.

**Ruled out:** the "bash defers the EXIT trap behind a foreground command" theory (E9). The bounded
phase is backgrounded and polled (`run-with-timeout.sh:519-564`); a `bash -x` trace shows the live
poll loop. A minimal bash with an EXIT trap DOES die promptly on TERM, so this is not a general
property of EXIT traps.

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
- Signal-correct exit status: `143` for TERM, `130` for INT.

## Related

- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — same family, different trigger: that entry is the bounded-run kill firing on its OWN deadline (over- and under-killing). This is the harness's parent dying to an EXTERNAL signal.
- `docs/problem-catalog/health-check-false-broken-rc0-on-kill/problem.md` — the rc-on-kill sibling.
- `docs/backlog/gate-bounds-lack-headroom/README.md` — the evidence this defect can corrupt.
- FR-27 liveness: a task that cannot signal its own completion-or-death must never be launched bare. Here the child outlived the observer entirely.
