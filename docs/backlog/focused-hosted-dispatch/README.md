# focused-hosted-dispatch

**Status:** open — not scheduled. **Filed:** 2026-10-13 (v5.10 time review, `docs/changes/2026-10-13-v510-time-review.md`). **Severity:** medium (release latency). **Surface:** `.github/workflows/fusebase-flow-maintainer.yml`.

## Observed

`docs/maintainer-testing.md` § Execution and completion asks for changed platform-dependent cases on Linux and MSYS before tagging. The only hosted route that can run an arbitrary group is a full `fusebase-flow-verify` dispatch (~27 min, the same profile the tagged gate repeats). `fusebase-flow-maintainer.yml` runs on both platforms in ~2 min but with a fixed `FF_ONLY` list and no input. Without local Linux, a change to a platform-dependent case outside that list can only be proven before tagging by the full profile — which the process forbids as a default — so it either waits for the tagged gate or needs an operator exception (v5.9 and v5.10 both took that exception, 54 min of hosted time).

## Ask

Add a `groups` input to the maintainer workflow's `workflow_dispatch` (default: the current fixed list; validated against the runner's registered tags; unknown groups fail as `FF_ONLY` already does), keep push/PR behavior and the consumer opt-in condition unchanged, and keep it unable to publish or count as release evidence. Then reword the `maintainer-testing.md` sentence to name the route. Check `hooks/tests/lib/workflow_graph_check.py` and `release-authority` for maintainer-graph assertions.
