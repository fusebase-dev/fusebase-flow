# release-gate-flaky-job-probe

**Status:** active — reproduction first
**Found:** 2026-08-11, during the v4.8.0 publication

## Root cause — identified 2026-08-12 (occurrence 3)

`ffhc_job_available` (`hooks/local/lib/run-with-timeout.sh:376-390`) probes Windows Job Object
support by running `powershell.exe -NoProfile` under `run_with_timeout 15`, then:

```sh
case "$out" in *ASSIGN-OK*) FFHC_JOB_PROBE_RESULT="ok"; return 0 ;;
              *)            FFHC_JOB_PROBE_RESULT="no"; return 1 ;;
esac
```

**Any** non-`ASSIGN-OK` outcome is recorded as "unavailable" — including a 15s timeout. A PowerShell
cold start on a loaded hosted runner can exceed that, so *the probe timed out* and *this host lacks
job objects* are the same verdict, and the result is cached for the process.

That is the defect class this repository keeps finding: a mechanism reporting a conclusion it has not
established. The assertion is right to demand availability; the probe is wrong to infer absence from
silence.

**Fix direction (do NOT simply raise the bound** — a rounded-up observation is what
`gate-bounds-lack-headroom` warns against): distinguish a timeout from a definite negative. On
timeout, retry once — the cold start is one-time, so a second call is warm — and only then conclude
unavailable. Keep the final verdict strict; only stop converting "no answer yet" into "no".

Do not relax `ws2hard-probe-gating`: `test-msys-tree-cleanup.sh:376` deliberately fails loudly when
the mechanism cannot run, and that refusal is correct.

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

## Required first step — reproduction, not a fix

Do not "stabilize" the assertion by relaxing it: an unavailable job object is a real condition the
mechanism smoke depends on (`test-msys-tree-cleanup.sh:376` already fails loudly when the
mechanism cannot run, deliberately refusing to skip). Establish first:

1. Whether the probe has a timeout/cold-start dependency on `powershell.exe` under runner load.
2. Whether `FFHC_JOB_PROBE_RESULT` caching or a prior phase's residue can influence it.
3. Whether the failure correlates with runner class, concurrent phases, or elapsed suite position.

Then decide: bound and retry the probe with an explicit budget, or make unavailability a
distinguishable *reported* state rather than a bare rc, so a transient probe failure is
attributable instead of indistinguishable from a genuine capability gap.

## Provenance

v4.8.0 published on attempt 2 of run `31459937396` after exactly one sanctioned re-run, with
positive evidence of transience (same SHA green minutes earlier). One re-run, recorded — not a
pattern to normalize.
