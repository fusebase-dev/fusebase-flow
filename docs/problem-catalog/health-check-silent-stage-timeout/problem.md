# Problem: health check can exhaust the caller wall without an interim verdict

**Slug:** `health-check-silent-stage-timeout`  
**Severity:** medium  
**Status:** resolved (stage observability); runtime optimization not justified by the measured run

## Signal

`fusebase-flow-health-check.sh --no-upstream` emitted no verdict before a 120s caller watchdog stopped it on an MSYS consumer fixture.

## Root cause

The report is assembled on stdout only after all checks finish. Default MSYS `--no-upstream` bounded children can consume 160s sequentially (`preflight=60`, `manifest=60`, `conflict=30`, `CLI-version=10`) before inline work and timeout termination grace. No enforced total wall exists, so a 120s caller bound can expire without naming the active stage.

## Fix

- Every existing health stage emits a flushed stderr `START`/`END` pair with elapsed time, child rc, and declared budget when bounded.
- Stdout report, conflict JSON capture, verdict precedence, and exit codes are unchanged.
- `--help` declares exact bounded-child defaults and states that sequential inline work and timeout termination grace prevent an enforced total-wall guarantee. Optional upstream and deep-run budgets are additive.

## Evidence

| Probe | Result |
|---|---|
| Focused delayed preflight | live `START`; timeout `END` rc 124/137 in 3s with 1s child budget plus kill/scheduling grace; `PARTIAL_UNVERIFIED`, exit 4; progress absent from stdout |
| Disposable v4.15.0 fixture, one bounded run | completed before its 180s caller watchdog; preflight 27s/120s rc1, manifest 6s/60s rc1, conflict 4s/30s rc1, CLI-version 4s/10s rc0; no bounded-stage overrun |
| Inline-stage visibility | active approvals 12s; local inventory 22s; CLI version 4s; partial-upgrade 13s |

The fixture carried `FFHC_PREFLIGHT_TIMEOUT=120` and `FFHC_TESTS_TIMEOUT=300`; the former raised its `--no-upstream` bounded-child sum to 220s even though the optional deep run was not selected. Its final `BROKEN` verdict came from pre-existing preflight/fixture drift plus the deliberately copied unstamped health candidate. The timing evidence supports observability only; it does not isolate a safe runtime correction.

## Retrieval pointers

- `hooks/local/fusebase-flow-health-check.sh`
- `hooks/local/lib/health-stage-progress.sh`
- `hooks/tests/test-health-check-timeout.sh --only t57`
