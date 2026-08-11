# Backlog — local-gate-misses-manifest-freshness

**Status:** re-scoped to the maintainer lane (2026-08-06, T1). The CI/local discrepancy is REAL and is not closed; only its placement in the consumer default gate was wrong. It must not become another shipped gate phase — see the 2026-08-05 attempt below.
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

## 2026-08-05 — attempted, reverted; belongs in the maintainer pack, not the default gate

An attempt (a `manifest-freshness` phase + `hook_manifest.py stamp --out`) was **reverted** after adversarial review. The defect is REAL and was reconfirmed: at `cb0ff8b` the manifest recorded `bbe6f454…` for `run-tests.sh` while the blob hashed to `72cbcfd8…`. But three things must change before a retry.

**1. Placement, not correctness, is the problem.** CI already detects this drift. A local check saves a *maintainer* a push-retry cycle and buys an ordinary consumer nothing, while adding a phase to the shipped full gate. Under the locked North Star that is maintainer tooling in the default product. It belongs in the **maintainer-governance pack (roadmap S9)**, and it should not land before S2/C0 fix the gate contract.

**2. `--out` has a Windows bug.** The guard used `Path(out).is_absolute()`, which is **False** for an MSYS-style `/c/tmp/x` on Windows Python, so the path is root-anchored and the manifest is written to `C:\c\tmp\x` while the tool reports the requested path. The sibling `managed_content_manifest.py` (`out_path = root / out_rel`) has the same hazard. Linux is unaffected. Any retry must convert to a native path explicitly, and its own test must do the same — the attempt's passing Windows result depended on a conveniently native `TMPDIR`.

**3. The red arm must not touch the tree.** The attempt appended a newline to a real tracked file and restored it under an `EXIT` trap. That trap does not survive SIGKILL, cannot run on a read-only checkout, and two concurrent runs can restore each other's backups and leave the tree dirty. A gate test must not mutate the tree it judges — use a scratch worktree or a synthetic root.

Also worth keeping: `verify` and `stamp`+compare catch **different** things. `verify` names modified/missing paths but reported `extra=0` for a newly added collected file; only the restamp-compare saw it. A retry needs both arms.

## Notes

Related: `docs/problem-catalog/docs-only-commit-broke-content-derived-gate/problem.md` (same family — local green that did not cover what CI enforces). The durable guardrail from that entry — *the gate must run on the tree you actually push* — is necessary but not sufficient while the local gate is narrower than CI.
