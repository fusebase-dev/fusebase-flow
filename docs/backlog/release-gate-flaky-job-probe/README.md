# release-gate-flaky-job-probe

**Status:** CLOSED — cause established by measurement, bound raised, confirmed on three hosted runs
**Found:** 2026-08-11, during the v4.8.0 publication
**Diagnosed:** 2026-08-14, from run `31753213227` (occurrence 5)
**Confirmed:** 2026-08-14, three consecutive green `verify-windows-msys` runs on three different SHAs

## CONFIRMATION — three hosted Windows runs, zero probe diagnostics

The bound landed. Every one of these emitted **no `[ffhc-job-probe]` line at all**, meaning every
probe returned `ok` on its first attempt — and the diagnostic fires on any rc≠0, so silence here is
positive evidence, not absence of instrumentation.

| Run | SHA | Result |
|---|---|---|
| `31832137608` | `3999a4a` | 1037/1037, mechanism rows exercised |
| `31834351442` | `c329931` | the **v4.9.2 release run** — `publish` succeeded |
| (N3 re-verify) | `29e621a` | 1043/1043 |

`ws2hard-probe-gating` and `ws2hard-job-mechanism-must-run-here` both passed in each, so the
mechanism ran rather than being skipped — the failure mode this ticket existed to prevent.

Before the fix this row failed roughly every other Windows run and blocked publication twice
(`v4.9.0`, `v4.9.1`). A 271ms overrun of a clean-host-sized bound held a release for two versions.

## CAUSE — ESTABLISHED (occurrence 5, run `31753213227`, 2026-08-13)

Not a hypothesis. The instrumented probe named its own cause on the first hosted failure after
instrumentation, verbatim:

```
[ffhc-job-probe] result=timeout-or-error rc=124 elapsed_ms=15271 helper=ok marker=absent attempt=1/2 cache=unknown detail=
```

| Field | Reads as |
|---|---|
| `rc=124` | the 15s watchdog killed it — not a PowerShell exit code, not a script error |
| `elapsed_ms=15271` | PowerShell startup on a loaded hosted runner exceeds 15s. Previously "plausible but unproven"; now measured, 271ms over the bound |
| `helper=ok` | `_ffhc_job_helper_path` succeeded |
| `marker=absent` + `detail=` empty | PowerShell produced NO output on stdout OR stderr — it never got far enough to fail at anything |

**Cause:** the probe's 15s bound was sized to a clean-host observation, and a loaded hosted runner's
PowerShell cold start crosses it. The gate's verdict was therefore decided by runner load. The
shipped hook code was never implicated in any of the five occurrences.

**Fix:** bound raised 15s -> **46s**, ~3x the 15271ms loaded-host worst case, per
`docs/backlog/gate-bounds-lack-headroom` (a bound is a liveness backstop, not a performance
assertion; deliberate 2-3x headroom over a LOADED-host worst case, never a rounded-up clean-host
observation). Deliberately NOT 20s: that backlog records `cli-flow-recovery` crossing its bound
four times (240 -> 480 -> 900s) because each bump was rounded up from the last observation. The
measurement, its run id, its date and the multiple are recorded in a tripwire at the call site
(`hooks/local/lib/job-fence.sh`). Worst case a wedged PowerShell can now add is 3 x 46s = 138s
against the 1800s phase bound; a genuinely hung PowerShell is still killed (verified locally at
46.9s, rc 124).

### EXCLUDED by this measurement

| Theory | Killed by |
|---|---|
| `_ffhc_job_helper_path` fails on first call | `helper=ok` |
| Partial-write TOCTOU on the create-once helper (`cat > $p` behind an existence test) — a concurrent probe executing a half-written `.ps1` | `marker=absent` with `detail=` EMPTY. A truncated script produces a PowerShell parse error on stderr, which the instrumented probe captures. There was no output at all |
| PowerShell exited on its own (execution policy, `Add-Type` failure, exception) | `rc=124` is the watchdog's own code, and the helper's own failure paths all print `ASSIGN-FAIL` |

The TOCTOU race was **real and is fixed** (atomic same-directory temp + sentinel validation +
rename, `hooks/local/lib/job-fence.sh`) — but it is **correct-but-unrelated** to this ticket's
failures. Leaving it unfixed during the instrumented run was deliberate: fixing it would have been
a guess, and would have destroyed the evidence had it been the cause.

### Consequence filed separately

The two consecutive RED Windows runs this flake caused (v4.9.0 and v4.9.1) are what exposed
`fingerprint-row-driven-by-publish-not-tag`: the post-tag fingerprint-row step ran only after a
SUCCESSFUL publish, so two reds in a row dropped `v4.9.1`'s row from `v4.9.2`'s permanent tree
(consumer finding N3). Fixing this probe removes the TRIGGER, not that defect — it is now
enforced independently by `hooks/local/preflight.sh`.

### Still open (not causal here, worth knowing)

- `_ffhc_job_fence`'s bash-side ASSIGN-OK confirm loop still allows only ~3s for PowerShell to
  start. On a runner slow enough to produce this ticket's 15s cold start, the fence would fall back
  to WS2-core rather than fence. That is SAFE (the taskkill reap still applies) and was out of
  scope here — but it is the same clean-host sizing mistake one layer down.

## Occurrence 4 — 2026-08-12, `16ec277` (v4.9.1 pre-tag) — **NOT transient; escalate**

This one breaks the pattern and is the most informative so far. Run `31647388965`:

| | Occurrences 1-3 | **Occurrence 4** |
|---|---|---|
| Failing rows | 1 (`ws2hard-probe-gating`) | **2** (+ `ws2hard-job-mechanism-must-run-here`) |
| Suite total | 1028/1029 | **1022/1024** — total DROPPED by 5 |
| Later parent-shell probe | succeeded | **also failed** |

`ws2hard-job-mechanism-must-run-here` (`test-msys-tree-cleanup.sh:376`) fires only when the host is
MSYS, has `powershell.exe`, and `ffhc_job_available` still returns false. It is the deliberate
refusal to skip. Its firing means the probe failed at the parent-shell call too, not just in the
first subshell — so the mechanism rows never ran, which is why the denominator fell from 1029 to
1024.

**This invalidates the transient-first-call inference for THIS run.** Occurrences 1-3 were consistent
with a first-call failure recovering immediately; occurrence 4 is a persistent failure within the
same run.

**Runner-image change is EXCLUDED.** Checked immediately rather than left as speculation: occurrence
3 (one row, recovered) and occurrence 4 (two rows, persistent) both ran on runner `2.336.0`, image
provisioner `20260729.566` — identical. The environment did not change between them, so the same
image produces both outcomes. That points at a load- or timing-dependent failure that can take out
both probe calls when the host is busy enough, not at a changed platform.

**Do not re-run to get a green.** With a persistent failure a re-run is no longer a sanctioned
transient remedy; it would be manufacturing a pass. The release is blocked here until the probe is
instrumented per the steps below.

## Pre-diagnosis analysis (occurrences 1-4) — superseded by the CAUSE section above

Kept because the defect-shape findings drove the instrumentation that produced the diagnosis. The
probe lives in `hooks/local/lib/job-fence.sh` since the FR-25 extraction.

| Finding | Evidence | Now |
|---|---|---|
| Watchdog rc preserved | `run_with_timeout` preserves rc 124/137 | still true — and is what made `rc=124` readable |
| Probe rc discarded | classification used only `ASSIGN-OK`; `$?` was never saved | FIXED: `ok` requires rc 0 + `ASSIGN-OK` + `PROBE-DONE`; a no-answer is never cached as absence |
| Timeout classification marker-dependent | a timeout with no marker became `no`; with the marker it returned success | FIXED (same change); a marker-then-kill is `timeout-or-error` |
| Deadline waste | `DeadlineSecs=1` became 30 × 100 ms via a `+20` tick pad | FIXED; `WinPid=0` now exits right after create+setinfo |
| Failure shape (occ. 1-3) | a later parent-shell probe succeeded right after a subshell probe failed | consistent with load-dependent startup: same host, different moment |
| `FFHC_TIMEOUT_BIN` absence | the test supplies it | EXCLUDED, unchanged |
| Cache interaction between gating calls | each gating call runs in its own subshell | EXCLUDED, unchanged |
| Runner-image change | occ. 3 and 4 ran on identical runner `2.336.0` / image `20260729.566` | EXCLUDED, unchanged — and consistent with a LOAD-dependent cause |
| PowerShell cold start > 15s | "plausible but unproven" | **ESTABLISHED** — measured at 15271ms, see the CAUSE section |
| `_ffhc_job_helper_path` fails on first call | open | **EXCLUDED by measurement** (`helper=ok`) |

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

## Prescribed steps — DONE

`ws2hard-probe-gating` and `ws2hard-job-mechanism-must-run-here` were never relaxed; both still
fail loudly, and that refusal to skip is what kept the ticket honest.

| # | Step | State |
|---|---|---|
| 1 | Capture watchdog rc, elapsed, `_ffhc_job_helper_path` outcome, `ASSIGN-OK` seen | DONE — and it is what produced the diagnosis |
| 2 | Classify `ok \| definite-negative \| timeout-or-error`; never cache `timeout-or-error` as absence | DONE; `ok` additionally requires rc 0 + `PROBE-DONE` (review finding: rc must decide the verdict, not just the log) |
| 3 | `WinPid=0` exits immediately after create/setinfo | DONE |
| 4 | Remove the `+20` tick inflation | DONE — note it also shortened the real fence's internal deadline; margin over the reap cap is now 1s, tripwired at the `dl` assignment |
| 5 | Collect evidence, then decide whether retry is justified | **Retry NOT added, and not needed.** The cause is a bound sized to a clean host, so the fix is headroom on the bound. Retrying a probe that needs 15s under a 15s bound would have masked the cause and normalised re-running until green |

**Do not re-run to get a green** still stands for any future occurrence.

## Provenance

v4.8.0 published on attempt 2 of run `31459937396` after exactly one sanctioned re-run, with
positive evidence of transience (same SHA green minutes earlier). One re-run, recorded — not a
pattern to normalize.
