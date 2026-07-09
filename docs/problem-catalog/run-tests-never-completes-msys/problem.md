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

## Recurrence triggers (so future sessions recognize this)

- A shell harness uses `$(...)` to capture a subprocess that may spawn a native (non-MSYS) grandchild.
- Operator says "run-tests hangs" / "it never finishes" / "a phase looks frozen" on Windows.

## Guardrail (the lesson)

On MSYS, `$(...)` capture of anything that can spawn a native grandchild is a hang waiting to happen — capture to a tempfile under a bounded wrapper (`ffhc_run_bounded`) and reap the recorded child winpid. Flush per-phase progress so a slow phase is never mistaken for a freeze (FR-27).

## Related

- `hooks/local/lib/run-with-timeout.sh` — the bounded-run engine + strict winpid scoping.
- `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` — the engine-side kill defect WS3 depends on.
