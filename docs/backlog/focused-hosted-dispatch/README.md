# focused-hosted-dispatch

**Status:** done (T141, 2026-10-13). **Filed:** 2026-10-13 (v5.10 time review, `docs/changes/2026-10-13-v510-time-review.md`). **Severity:** medium (release latency). **Surface:** `.github/workflows/fusebase-flow-maintainer.yml`.

## Observed

`docs/maintainer-testing.md` § Execution and completion asks for changed platform-dependent cases on Linux and MSYS before tagging. The only hosted route that can run an arbitrary group is a full `fusebase-flow-verify` dispatch (~27 min, the same profile the tagged gate repeats). `fusebase-flow-maintainer.yml` runs on both platforms in ~2 min but with a fixed `FF_ONLY` list and no input. Without local Linux, a change to a platform-dependent case outside that list can only be proven before tagging by the full profile — which the process forbids as a default — so it either waits for the tagged gate or needs an operator exception (v5.9 and v5.10 both took that exception, 54 min of hosted time).

## Resolution

Optional `groups` uses the env-only `FF_DISPATCH_GROUPS` path with shell validation; empty retains fixed contracts, dispatch concurrency uses the run ID, and feedback cannot publish or count as release evidence.
Guard rows: `maintainer-dispatch-groups`, `maintainer-no-expression-in-run`, `maintainer-groups-behavior`, `maintainer-dispatch-concurrency`, each with a negative mutation in `release-authority`.
