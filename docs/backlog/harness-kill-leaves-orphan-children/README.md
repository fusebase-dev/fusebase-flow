# harness-kill-leaves-orphan-children

**Status:** CLOSED at T4 (2026-09-12, `2f03652`+) — shipped, 10/10 on MSYS, zero surviving
descendants across five outer-wall kills and zero fixture leftovers on a clean run, all verified by
process inspection. B5/B6 stay accepted (§ 2026-08-07)
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

**R1 is INCOMPLETE as written, and that is what kept the field discriminator red until T4.** It
names the topology but not the HANDLE. Measured at `2f03652` (full `ps` + `/proc` capture): the
identity the harness PUBLISHES is `_bpid`, its own backgrounded capture subshell in
`_ffhc_tempfile_capture` — and a background job of a non-interactive shell keeps the SHELL's
process group. The published pid therefore always resolved to the HARNESS's group, which
`ffor_reap` must refuse; `timeout` creates the reapable group one level BELOW it:

```
harness   1044675  pgid 1044651   <- the harness's own group
  +- _bpid 1044717  pgid 1044651  <- PUBLISHED; same group as the harness => unreapable
       +- timeout   1044726  pgid 1044726  <- the reapable group leader
            +- bash phase       1044728  pgid 1044726
                 +- bash grandchild 1044740  pgid 1044726
```

`hooks/local/lib/run-with-timeout.sh` also probed `ffhc_pgid_of "$_bpid"` and published it as the
record's pgid field. By construction that value can only ever be the harness's own group, so it
was a fork per phase for a number no consumer could act on. Retired at T4: the field is now `-`
and the READER resolves the live group (`ffor_resolve_phase`).

**Therefore no harness-side cleanup can be relied on** — not an EXIT trap, not a signal trap. R2
stands as originally written. R3 stands: `taskkill //F //T` reports SUCCESS and still leaves the
descendants alive.

**The shipped mechanism is an out-of-band sentinel** (`hooks/tests/lib/orphan-sentinel.sh`),
started once per run under its own `timeout` process group so it is immune to the group signal
that kills the harness and carries a hard cap so it can never outlive the run. It polls the
harness; when the harness dies with a phase still in flight, it revalidates the recorded identity
tuple and terminates **that process group only** — the handle is the shallowest self-led group
BELOW the published pid that is neither the harness's nor its own (`ffor_resolve_phase`). It never signals its
own group, the harness's group, an ancestor, a name-wide set, or an unverified pid, so
`bounded-run-msys-collateral-kill` stays closed.

**The guards live in `hooks/tests/lib/orphan-reap.sh`, which the harness's EXIT path sources too**
— one guard set for both teardown paths. The EXIT path runs the reap FIRST and disarms the
sentinel LAST **and only when the phase group is CONFIRMED gone** (`ffor_group_gone`); ordering
alone was not enough, see § 2026-09-12. Every guard fails CLOSED:
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

## 2026-09-12 — T4 shipped: the handle, the disarm race, and the proof

Two defects, both measured, both required to leave zero descendants.

| # | Defect | Measured at `2f03652` | Fix |
|---|---|---|---|
| D1 | The published identity (`_bpid`) shares the harness's process group, so every guard correctly refused to act and the reap killed NOTHING | `signal-reap` 7/8; `launch-window-signal-still-reaps` FAIL with `child_gone=-1 grandchild_gone=-1` (alive at 8s) | `ffor_resolve_phase` in `hooks/tests/lib/orphan-reap.sh`: BFS one level down the live `ps` parent links to the shallowest self-led group that is neither the harness's nor the caller's own. Fails CLOSED (no snapshot / unresolvable own pgid / no such group => kill nothing) |
| D2 | `_ff_exit_reap` disarmed the sentinel UNCONDITIONALLY after a reap it cannot finish inside the outer `-k 5s` grace — the grace loop alone is ~8s on MSYS (a `sleep` is a 0.64s spawn), so `kill -KILL -pgid` never landed and the only mechanism that could finish was then killed | 1 of 5 outer-wall kills left `timeout` + its phase child alive 60s after the harness died | harness-side reap uses grace 0 (TERM+KILL back to back, no wait it cannot afford); `_ff_exit_reap` disarms the sentinel ONLY when `ffor_group_gone` CONFIRMS the group is empty. Unconfirmable => the sentinel stays armed and finishes out-of-band |

| D3 | **`/proc/<pid>/stat` field 20 is a PRE-EXEC value on MSYS.** It changes exactly once after a pid appears — 0.45-0.97 s later on an idle host, **4.1 s** under gate load (recorded `239157481` -> `239161590`). Every identity bound to a token captured at spawn time therefore stopped matching, and each guard correctly declined to kill | 12 fixture siblings (`while :; do sleep 1; done`, 2 processes each) survived CLEAN runs and were still burning CPU; one from 2026-09-09 22:25 was alive three days later | Two exact proofs replace the one unreliable one. Fixture: `ff_kill_verified` accepts the start token OR "still THIS shell's own child with this comm" — not a loosening, since an unreaped child's pid cannot be recycled. Shipped sentinel: it REFRESHES the leader token every poll tick from the live leader (one `/proc` read), which is sound because a live process still leading its own pgid is by definition the same process. A "wait for the token to settle" heuristic was tried and REJECTED: the stale value holds for an unbounded number of consecutive reads under load |

Also closed: the sentinel now removes its own state file when it reaps, so a SIGKILLed gate stops
leaving one `ffhc-sentinel.*` per run in `TMPDIR` (23 had accumulated on the measuring host).

**This contradicts the ticket's own "What is NOT the defect" section, which said the reaper works on
a clean exit.** It did for the phase tree; it did not for the suite's own fixture processes, and
nothing measured that until T4 counted the process table before and after a run.

### Evidence

| Check | Result |
|---|---|
| `FF_ONLY=signal-reap` on MSYS, at `2f03652` (baseline) | **7/8**, 306s — `launch-window-signal-still-reaps` FAIL |
| `FF_ONLY=signal-reap` on MSYS, after the fix | **10/10 rc=0**; 166s on a quiet 9-process host, 342s on a contaminated one |
| Process table across a clean MSYS run | **9 rows before, 9 rows after, 0 fixture leftovers** (was: 3 leaked siblings per run) |
| New row `phase-group-is-not-the-harness-group` [DISCRIMINATOR] | asserts the recorded pid resolves to the harness group AND that the phase child + grandchild are in a different group resolved below it; reports the old resolve's answer as an ERROR if the fixture stops reproducing that topology |
| New row `tracked-identity-survives-msys-exec` [DISCRIMINATOR] | asserts the suite's OWN identity-verified teardown actually kills what it tracked, by process table and not by `kill -0` (an unwaited zombie answers that); it runs FIRST because every row below depends on that teardown. Red at `2f03652` for D3 |
| Outer-wall field kills, `timeout -k 5s <wall> bash hooks/tests/run-tests.sh` with `FF_ONLY=cli-flow-recovery`, walls 120/135/145/150/165 s | **survivors=0** in all five, censused by Win32 `CommandLine` 25s after the wall (not by any trap's return code); two of them on the rc=137 arm, where GNU `timeout`'s `-k` SIGKILL reaches its own group and kills the harness outright |
| Pre-fix contrast, same census | child + grandchild ALIVE 8s after the harness died (fixture probe on shipped code); 1 of 5 outer-wall kills leaked `timeout` + phase child at +60s |
| Linux (`ff-gate:24.04`) | `signal-reap` correctly `N/A` (statically, off-MSYS); `liveness`, `msys-tree-cleanup`, `ws5-upgrade`, `job-probe`, `git-capture-guard`, `secret-scan-staged` green. The MSYS-only code paths are inert there |

**A live field instance was found and removed during this work**: a `bash -c 'while :; do sleep 1;
done'` fixture sibling created 2026-09-09 22:25 was still burning CPU three days later, orphaned by
an earlier killed `signal-reap` run. It predates the fix, so it does not trigger the B5/B6
reopen condition (a); it does confirm the leak was live, not theoretical.

### Release-profile classification

`signal-reap` moves from `unreviewed (pre-ratchet)` to **`deferred`** in `docs/maintainer-testing.md`
(`FF_UNREVIEWED_BASELINE` 28 -> 27). The red baseline that blocked promotion is closed and the COST
bar is now CLEARED: **166 s on a quiet MSYS host**, against `preboundary-consumed` excluded at 204 s
and `approval-schema3` carried at 184-286 s; Linux is statically N/A at 18 s.

It is still deferred, on ONE objective condition that is not cost: **it has never run green on
hosted Windows**, because it was red at every commit until now. Promoting it would make the next
tagged release gate its first hosted execution of a phase that kills live process trees — the shape
of risk that already cost this repo the `v4.16.3` cycle. Close it with one non-publishing
`.github/workflows/fusebase-flow-measure-windows.yml` run at this SHA, then promote: it is the only
oracle for the Process-lifecycle owned-child row, which has zero release tags today.

## Related

- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — same family, different trigger: that entry is the bounded-run kill firing on its OWN deadline (over- and under-killing). This is the harness's parent dying to an EXTERNAL signal.
- `docs/problem-catalog/health-check-false-broken-rc0-on-kill/problem.md` — the rc-on-kill sibling.
- `docs/backlog/gate-bounds-lack-headroom/README.md` — the evidence this defect can corrupt.
- FR-27 liveness: a task that cannot signal its own completion-or-death must never be launched bare. Here the child outlived the observer entirely.

## 2026-08-07 — B5/B6 ACCEPTED as known limitations (operator decision)

The S2 mechanism ships with two residual gaps, accepted deliberately rather than patched a third
time. They are unchanged by T4.

**SUPERSEDED (2026-09-12): "the field failure is closed" was NOT true on 2026-08-07.** That claim
rested on the three DIRECT-DRIVE guard discriminators, which were green. The one END-TO-END field
discriminator — `launch-window-signal-still-reaps` — was RED from the day it shipped and stayed
red at every commit through `2f03652`, because the guards were being handed an unreapable handle
(§ Reproduced — T3, R1 correction). The suite is now 9 rows, not 19; the 19-row suite was reduced
to 4 discriminators + 4 controls at T3 for the reason recorded in the phase header, and T4 adds
the ninth row. Read § 2026-09-12 for the state that is actually proven.

**What is NOT fixed, precisely.**

| # | Residual | Trigger | Consequence |
|---|---|---|---|
| B6 | The in-flight record is written by append+terminator, which DETECTS a torn record but does not PREVENT one. A torn first append reads as "nothing in flight"; a later tear leaves an older record authoritative; write failures are swallowed | The harness must be killed inside the window between launching a child and completing its first append | That one phase's descendants may survive, as before the fix |
| B5 | The delayed group SIGKILL is unconditional, and the native sweep revalidates against the same snapshot it captured from rather than against pre-kill identity | Group membership changes between snapshot and kill | A process that joined the target group after the snapshot could be signalled |

**Why accepted, not fixed.** The two correct fixes both cost more than the residual:

- *Atomic publication via temp+rename* — correct, but the harness has ~46 bounded phases, so two
  rename-backed publications per phase is ~92 additional MSYS `mv` spawns. Spawn cost in this
  engine is itself a catalogued defect; this trades a rare race for a guaranteed slowdown.
- *A persistent supervisor owning the child before launch* — correct and complete, but a
  substantially larger change with a new long-lived moving part, for a failure mode that has not
  been observed in the field.

The locked North Star treats process cost as a first-class defect and rules out building
machinery for incidents that happened once. This one has not happened at all — it is a race
found by inspection, not by an incident.

**Conditions of the acceptance.** If any of these becomes true, reopen and implement the
supervisor: (a) an orphan is observed in the field after this fix; (b) the launch-to-record window
widens for any reason; (c) a consumer reports flaky gate timings traceable to leftover processes.

The `launch-window-signal-still-reaps` test only delays the WinPID probe — it does not tear,
interrupt or fail the first append. A future implementer should not read it as covering B6.
