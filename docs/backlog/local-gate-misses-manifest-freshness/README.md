# Backlog — local-gate-misses-manifest-freshness

**Status:** DONE 2026-08-05 (Lightweight lane — [`docs/changes/2026-08-05-local-gate-manifest-freshness.md`](../../changes/2026-08-05-local-gate-manifest-freshness.md)). New `manifest-freshness` phase replays both CI steps for both manifests against the actual tree; `hook_manifest.py stamp --out` keeps it non-mutating (AC2). AC1/AC2/AC3 all met — red arm 3/7, green arm 7/7, harness 15/15.

> The red arm did not need planting: the immediately preceding commit `cb0ff8b` had itself left both manifests stale (two collected files modified, no re-stamp) while passing the local gate and the pre-commit hook. The gap reproduced on the next commit after this ticket was read.

**Status was:** parked
**Filed:** 2026-07-27 (during the `rule-inventory-version-literal-noise` publication)
**Owner:** unassigned
**Lane guess:** Lightweight (one assertion + its red arm)

## Problem

The local full suite and CI **disagree** about hook-layer manifest freshness, and the local one is the weaker.

`.github/workflows/fusebase-flow-verify.yml` runs a dedicated step — `stamp-hook-manifest.sh`, then fail if the working tree moved. `bash hooks/tests/run-tests.sh` has no equivalent assertion: its `hook-manifest` tag exercises the stamping *mechanism*, not the *current tree's* freshness.

Consequence: a change to any manifest-collected file (`hooks/local/*.sh`, `hooks/tests/*`, `hooks/{handlers,shared,git}/**`) that forgets `stamp-hook-manifest.sh` passes the full local suite and **fails CI**.

## Observed

`eca925b` (2026-07-27) turned `main` red on exactly this. The local suite had reported **625/625 PASS** on that tree; `verify-hook-manifest.sh` reported drift on the two files the change touched:

```
[hook-manifest] verify: DRIFT (listed=121 matched=119 modified=2 missing=0 extra=0)
  modified: hooks/local/rule-inventory.sh
  modified: hooks/tests/test-rule-inventory.sh
```

Fixed by `a14e923` (restamp only). The implementer had run the full suite on the exact pushed tree — the discipline was right; the local gate simply does not cover this.

This is the **second** red-main incident in two days whose root cause is a local signal that does not match what CI enforces. The first was `docs-only-commit-broke-content-derived-gate`; both share the shape *"the local green did not mean what the pusher thought it meant."*

## Proposed fix

Add a `manifest-freshness` assertion to `run-tests.sh` that replays the CI step: stamp into a scratch copy (or stamp and compare, restoring on mismatch — it must not mutate the tree as a side effect of testing) and fail when the committed manifest differs.

## Acceptance criteria

- **AC1** — Touching a manifest-collected file without re-stamping makes the local full suite **FAIL**, with the offending path named.
- **AC2** — A clean tree passes, and the assertion does not itself modify `audit/hook-layer-manifest.json` (a test that stamps as a side effect would mask the very drift it checks).
- **AC3** — Red arm proven by planting a whitespace edit in a collected file; green arm proven on the unmodified tree.

## Notes

Related: `docs/problem-catalog/docs-only-commit-broke-content-derived-gate/problem.md` (same family — local green that did not cover what CI enforces). The durable guardrail from that entry — *the gate must run on the tree you actually push* — is necessary but not sufficient while the local gate is narrower than CI.
