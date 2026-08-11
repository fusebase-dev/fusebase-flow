# Problem: `run-tests.sh` never reaches exit 0 on any MSYS/MINGW64 box

**Slug:** `run-tests-never-completes-msys`
**Filed:** 2026-07-01
**Severity:** high
**Status:** resolved
**Filed by:** PO per FR-15 (consumer field reports — Cummings/WorkHub/Ovation/Start-page/troubleshooter, all Windows MINGW64)

## Symptom

`bash hooks/tests/run-tests.sh` never printed `Total:`/exit 0 on ANY of the 5 consumer boxes — the universal, highest-leverage v3.30.2 defect. A phase appeared frozen for minutes.

## Root cause

The harness did NOT reuse the v3.30.2 bounded-run engine reap: raw `$(...)` captures block until every write-end closes, and an MSYS native grandchild survives POSIX `timeout` and holds the pipe open forever. No `trap … EXIT` reaper; `test-cli-flow-recovery.sh` ran UNBOUNDED; per-phase output only echoed after `$(...)` returned, so a slow phase looked like a hang.

## Why it matters

- The suite that gates every release could not complete on the target platform — consumers could not self-verify an install/upgrade.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v3.30.3 G2 (WS3) — harness sources the bounded core, replaces `$(...)` with `ffhc_run_bounded` (tempfile capture + strict-scoped reap), adds an EXIT-trap reaping ONLY its own recorded child winpid, bounds `test-cli-flow-recovery` (INCONCLUSIVE on bound-hit), flushes per-phase progress |
| Shipped | v4.2.0 (`hook-manifest-verify`) — DEEPER fix. The bounded-run above stopped the HANG, but the suite was still too SLOW on MSYS (fork-per-case, ~100× MSYS spawn cost) to COMPLETE the health check's hook-tests critical — so a full **HEALTHY** verdict was structurally UNREACHABLE on Windows (capped at `PARTIAL_UNVERIFIED`/exit 4 forever, on every install + upgrade). v4.2.0 DECOUPLED the health verdict from the suite: the hook-tests critical is now a fast content-hash **manifest verify** (`audit/hook-layer-manifest.json`; full HEALTHY in ~31s on Win11/Git-Bash, and it also catches local tampering), plus a single-process fixture runner (fork-loop → one process; parity-proven) and a platform-adaptive `--run-hook-tests`. See [[ci-red-invisible-no-release-gate]] + [[ci-linux-msys-test-divergence]]. |

## Residual CLOSED — external-signal orphans (T3 reproduced, T4/T4a fixed, 2026-08-07)

| Status | Detail |
|---|---|
| Shipped | `hooks/tests/lib/orphan-sentinel.sh` + `hooks/tests/lib/orphan-reap.sh`. An out-of-band sentinel runs in its OWN process group (so the group signal that kills the harness cannot reach it), polls the harness, and on the harness's death revalidates the recorded identity tuple and terminates ONLY that phase's process group. `run-tests.sh`'s EXIT path runs the SAME guarded reap FIRST and disarms the sentinel LAST, so an in-flight guard is never cleared before cleanup completes. Regression arm: `hooks/tests/test-run-tests-signal-reap.sh` (tag `signal-reap`), whose rows are labelled DISCRIMINATOR vs CONTROL and whose skips are counted separately from passes |
| Fail-closed rules that make it safe | An unresolvable own/harness pgid, a leader start-token mismatch, an occupied-but-unverifiable leader pid, an ancestor on this process's parent chain, or no process table at all all mean **kill nothing**. Group ownership is bound by the leader's `/proc` start token, so a recycled pid or pgid can never be reaped |
| Known open (design decision, not a defect in this fix) | The harness's own exit status is 143 on TERM but the harness never acts on an untrapped **INT** at all. Adding `trap … INT` does not fix it: bash does not deliver a trap while `_ffhc_nap`'s blocking FIFO `read` is in flight, so the trap would defer past the outer `-k` SIGKILL. Closing INT means changing the nap primitive. The regression arm reports this row `INCONCLUSIVE` rather than asserting it |
| Platform cost that shaped the design | On MSYS one `/proc/<pid>/stat` read costs ~500ms while one whole-table `ps` costs ~350ms (measured). A per-pid `/proc` walk spent the entire `-k` grace window before it could signal anything, so the guards take ONE `ps` snapshot and read `/proc` only for start tokens |

### What T3 originally measured (kept — it is why the fix is out-of-band)

The v3.30.3 WS3 fix above added `trap _ff_exit_reap EXIT` "so a harness signalled mid-phase reaps its recorded child". T3 reproduced the case that clause names and found the guard inert there:

| Measured | Detail |
|---|---|
| The EXIT trap never runs | The harness is polling inside `ffhc_msys_wait_reap` (`run-with-timeout.sh:519-564`), not blocked in a foreground command. A direct TERM is acted on late or not at all (>=12s unacted-on measured), so an outer `timeout -k 5s` SIGKILLs it first |
| The phase subtree is signal-insulated | GNU `timeout` puts it in its OWN process group, so the group signal that kills the harness cannot reach the phase child or grandchild |
| The reap would not close it anyway | `taskkill //F //T` on the recorded winpid kills only the inner `timeout`; child + grandchild survive |

So this entry's HANG fix (tempfile capture) is intact and unaffected; the ORPHAN case on external teardown is what the sentinel above closes. Tracked as `docs/backlog/harness-kill-leaves-orphan-children/`; regression arm `hooks/tests/test-run-tests-signal-reap.sh`; evidence `state/audit/run-tests-signal-reap/<full-head>/topology-<tree>-<run-id>.tsv`.

## Recurrence triggers (so future sessions recognize this)

- A shell harness uses `$(...)` to capture a subprocess that may spawn a native (non-MSYS) grandchild.
- Operator says "run-tests hangs" / "it never finishes" / "a phase looks frozen" on Windows.

## Guardrail (the lesson)

On MSYS, `$(...)` capture of anything that can spawn a native grandchild is a hang waiting to happen — capture to a tempfile under a bounded wrapper (`ffhc_run_bounded`) and reap the recorded child winpid. Flush per-phase progress so a slow phase is never mistaken for a freeze (FR-27).

## Related

- `hooks/local/lib/run-with-timeout.sh` — the bounded-run engine + strict winpid scoping.
- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — the engine-side kill defect WS3 depends on.
- `docs/backlog/harness-kill-leaves-orphan-children/README.md` — the external-signal orphan case the EXIT-trap reaper does not cover.
