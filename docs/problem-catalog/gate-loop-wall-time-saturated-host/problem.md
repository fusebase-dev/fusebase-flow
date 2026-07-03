# Problem: the full gate is ~90% of session wall time on a CPU-saturated host

**Slug:** `gate-loop-wall-time-saturated-host`
**Filed:** 2026-07-03
**Severity:** medium
**Status:** resolved (mitigated — implement-loop only; final gate stays full)
**Filed by:** PO per FR-15 (autonomous roadmap runs — repeated observation across v3.30.3..v3.30.6)

## Symptom

On the saturated Windows/MSYS host, running the full `run-tests.sh` + preflight between every implement task dominated session wall-clock (~90%); the actual code changes were a small minority of the time. The health-check's default preflight budget (60s) also intermittently timed out, yielding a `PARTIAL_UNVERIFIED` verdict on a genuinely healthy install.

## Root cause

Two compounding costs, both structural, not behavioral:

- The implement loop re-ran the ENTIRE gate suite after every task even when a task touched one narrow surface — no way to scope a fast inner-loop check while keeping the full gate authoritative.
- Preflight mirror-hashing spawned ~270 per-file `sha256sum` processes (one per mirror file). Process spawn is expensive under MSYS + CPU saturation, so preflight blew its own health-check budget.

## Why it matters

- Gate wall-time is the single largest consumer of autonomous-run wall-clock on the target platform; it throttles roadmap throughput and inflates every session's cost.
- A false `PARTIAL_UNVERIFIED` on preflight timeout erodes trust in the health verdict.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v3.30.6 F2 — `FF_ONLY` opt-in scoped gates in `run-tests.sh`: run only named suites in the implement loop. Unset ⇒ byte-identical full gate. Scoped ⇒ fail-closed-by-construction (deliberately fails the strict `N/N PASS` classifier, writes a separate results file, exits 2 on an unknown/empty tag) so a scoped run can NEVER be mistaken for a clean full pass |
| Shipped | v3.30.6 F4 — preflight mirror-hashing batched to one `sha256sum` per root (~6.7× faster; repairs the default health-check preflight budget; byte-identical drift/missing detection) |
| Shipped | v3.30.6 F5/F3 — spawn micro-cuts in the fixture hot loop (builtin reads + metadata pre-pass) and an adaptive sub-second poll in the MSYS reap loop (deadline preserved as a hard FLOOR, verbatim `sleep 1` fallback) |

## The load-bearing invariant

`FF_ONLY` is an INNER-LOOP accelerator only. The FINAL pre-commit and pre-deploy gate MUST be a full, unscoped `run-tests.sh` — a scoped run is fail-closed by construction so it can never satisfy the release classifier. Scoping the release gate would be a coverage regression, not an optimization.

## Recurrence triggers (so future sessions recognize this)

- Operator/agent observes "the gates take forever" / "most of the run is testing" on a loaded Windows box.
- Health-check reports `preflight: UNVERIFIED — timed out` while `bash hooks/local/preflight.sh` run directly is 0/0 (preflight 0/0 is the ground truth; the `?` is only a budget timeout).

## Guardrail (the lesson)

Scope the inner loop, never the release gate. Batch process spawns (one `sha256sum` per root, not per file) — spawn cost dominates under MSYS + saturation. On a saturated host, preflight run directly (0/0) is ground truth; the health-check's timeout `?` is benign, not a failure.

## Related

- `docs/tmp/handoff/2026-07-03-v3306-fable-optimization-spec.md` — the v3.30.6 optimization spec.
- `hooks/tests/run-tests.sh` — `FF_ONLY` scoped-gate implementation + `test-ff-only.sh`.
- `hooks/local/preflight.sh` — batched mirror-hashing (§5/§5b).
- `docs/problem-catalog/run-tests-never-completes-msys/problem.md` — the prior MSYS gate-completion defect this builds on.
