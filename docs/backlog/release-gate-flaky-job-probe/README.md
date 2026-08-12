# release-gate-flaky-job-probe

**Status:** active — reproduction first
**Found:** 2026-08-11, during the v4.8.0 publication

## HYPOTHESIS — not established (occurrence 3)

`ffhc_job_available` (`hooks/local/lib/run-with-timeout.sh:376-390`) probes Windows Job Object
support by running `powershell.exe -NoProfile` under `run_with_timeout 15`.

### Established

| Finding | Evidence |
|---|---|
| Watchdog rc preserved | `run_with_timeout` preserves rc 124/137 (`run-with-timeout.sh:17,65`). |
| Probe rc discarded | `ffhc_job_available` captures stdout but never saves `$?`; classification uses only `ASSIGN-OK` (`run-with-timeout.sh:376-390`). |
| Timeout classification is marker-dependent | A timeout with no captured `ASSIGN-OK` becomes `no`; if the marker reached captured stdout before termination, the same rc 124 can return success. |
| Deadline waste | `DeadlineSecs=1` becomes 30 × 100 ms because both polling loops add 20 ticks (`run-with-timeout.sh:313,349`), imposing an unnecessary ~3s wait. |
| Failure shape | Only one row failed; the later parent-shell probe (`test-msys-tree-cleanup.sh:279`) succeeded immediately after the subshell probe failed. This proves a transient first-call failure, not its cause. |

### Excluded

- `FFHC_TIMEOUT_BIN` absence: the test supplies it (`test-msys-tree-cleanup.sh:253`).
- Cache interaction between gating calls: each call deliberately runs in its own subshell
  (`test-msys-tree-cleanup.sh:267`).

### Still open

- PowerShell cold start exceeding 15s is plausible but unproven.
- `_ffhc_job_helper_path` may fail on its first call (`run-with-timeout.sh:306`).
- Runner load, helper creation, and process startup remain candidate causes.

## Occurrence 3 — 2026-08-12, pre-tag `f4795ab`

Run `31635696002`, 1028/1029, identical text. Linux green on the same SHA.

**Three hosted occurrences in one day**, all Windows, all a single row failing an otherwise-green
suite: the v4.8.0 release run, `main` at `59668e1`, and this pre-tag verification. It is blocking
roughly every other Windows run, not occasionally flaking. Priority should rise accordingly.

## Occurrence 2 — 2026-08-12, main `59668e1`

Same row, same shape: `probe gating wrong (knob=1 rc=1 expect 0; …)` on `verify-windows-msys`,
1028/1029, in run `31611434833`. A local Windows full run on the same content was 1029/1029.

Two hosted occurrences now, both on Windows, both a single row deciding a whole gate, and both with
a green local run on the same content. This is no longer "it happened once" — the reproduction step
below has a second data point and should be scheduled rather than left open.

## Symptom

`msys-tree-cleanup ws2hard-probe-gating` failed on `verify-windows-msys` for SHA `20fd707`
(release run `31459937396`, attempt 1) and PASSED on the **same SHA** in run `31459050444`
~40 minutes earlier, and again on attempt 2 of the same release run. 928/929 both times — one row
decided publication.

Failure text: `probe gating wrong (knob=1 rc=1 expect 0; unset rc=1 expect !=0; forced-fail rc=1 expect !=0)`.
Only the first clause failed: with `FFHC_USE_JOB_OBJECT=1`, `ffhc_job_available` returned
unavailable on a host where the test requires available. The assertion is
`hooks/tests/test-msys-tree-cleanup.sh:270-276`; the probe shells out to `powershell.exe`.

## Why this matters more than one red run

The release gate is **non-deterministic**. A flaky test in a publication gate is worse than a
failing one: the documented remedy for a transient failure is a re-run (`PUBLISHING.md:255`), so
the observable habit becomes "re-run until green" — which is exactly how a real failure gets waved
through. Publication is the one gate where that cost is unbounded.

This is the third recorded instance of the gate's verdict being decided by ambient host conditions
rather than by the code:

| Item | Nature |
|---|---|
| `gate-bounds-lack-headroom` | phases within 0.5% of their watchdog walls; exit 124 with zero assertion failures |
| `harness-kill-leaves-orphan-children` | survivors inflate the next run's timings |
| **this** | a powershell-backed capability probe returns a different answer for the same SHA |

## Required first step — instrument before retry policy

Do not relax `ws2hard-probe-gating`; `test-msys-tree-cleanup.sh:376` correctly fails when the
mechanism cannot run. Instrument the probe before choosing retry behavior:

1. Capture watchdog rc, elapsed time, `_ffhc_job_helper_path` outcome, and whether `ASSIGN-OK`
   reached captured output.
2. Represent the result as `ok | definite-negative | timeout-or-error`; never cache
   `timeout-or-error` as capability absence.
3. When create/setinfo returns `WinPid=0`, exit immediately instead of entering the polling wait.
4. Remove the `+20` tick inflation from the one-second create/setinfo deadlines.
5. Collect first-call and immediate-follow-up evidence, then decide whether retry is justified.

Retry-once is not yet prescribed: the evidence proves transience but does not establish PowerShell
cold start, helper-path initialization, or any other root cause.

## Provenance

v4.8.0 published on attempt 2 of run `31459937396` after exactly one sanctioned re-run, with
positive evidence of transience (same SHA green minutes earlier). One re-run, recorded — not a
pattern to normalize.
