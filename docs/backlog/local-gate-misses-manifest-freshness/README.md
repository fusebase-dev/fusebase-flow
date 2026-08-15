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

## 2026-08-15 — retried in `cli-0298-compatibility`; point 3 UPHELD and fixed, point 1 CONTESTED by new evidence

The phase shipped as `hooks/tests/test-manifest-freshness.sh` (tag `manifest-fresh`). Status of the three objections above:

| Objection | Outcome |
|---|---|
| **2 — `--out` Windows bug** | N/A. The retry never used `stamp --out`; the bug is untouched and still stands as written for any future attempt that does. |
| **3 — the red arm must not touch the tree** | **UPHELD, and it caught a live defect in the retry.** The first version of the retry did exactly what this objection forbids: it snapshotted the real manifests, stamped over them, created a real file under `hooks/tests/`, and restored under an `EXIT` trap. That is now rewritten — every arm is either read-only against the judged tree, or executed inside a disposable `git worktree`. The judged working tree is never written to. This objection was correct and is the reason the rewrite exists. |
| **1 — placement: "buys an ordinary consumer nothing"** | **CONTESTED — the premise is falsified by measurement.** See below. Not overridden; reopened. |

### Why point 1's premise no longer holds

On its **first hosted run**, `manifest-fresh` caught `audit/hook-layer-manifest.json` recording `4145ce9c…` for `hooks/local/check-vendored-rendered.sh` while the committed blob hashes `b084434258f3970e`. Three files were `i/lf` + `w/crlf`: created with CRLF, normalized to LF in the index by `.gitattributes`, never re-checked-out. The stampers hash **working-tree bytes**, so the manifest described bytes that never ship.

That is not a maintainer push-retry cycle. It is:

- a **shipped, consumer-facing integrity artifact making a false claim** — `audit/hook-layer-manifest.json` is published, and
- the **input to the tamper-detection property** the health check's integrity critical depends on (`fusebase-flow-health-check/SKILL.md`: *"catches local tampering, which re-running tests does NOT"*). A manifest keyed to bytes that never ship weakens exactly that check for every adopter.

It is also invisible to every other local signal **by construction**: the stamper and the verifier read the same wrong bytes and agree with each other. `verify-*.sh` reports MATCH. Only a stamp of a **clean checkout** — i.e. the bytes git materializes per `.gitattributes` — disagrees.

Evidence: hosted verify RED on **both** platforms at `22873d6` (linux 1076/1080, windows 1087/1091), identical rows, deterministic. Fixed in `b57c62f`. Reproducible locally against the pre-fix commit: `FFMF_REF=22873d6 bash hooks/tests/test-manifest-freshness.sh` fails the two stamp-compare rows.

### Open operator decision — NOT settled by this retry

Whether this phase belongs in the **shipped default gate** or the **S9 maintainer-governance pack** is now an open call for the operator. It is deliberately **not** in `FF_FAST_TAGS` (full tier only) so that promoting it does not pre-empt the ruling; an earlier version of the retry did promote it, and that escalation is withdrawn.

- **For the shipped gate:** the class it catches is a consumer-facing artifact defect, not a maintainer convenience — which is the specific claim point 1 rested on.
- **For S9:** the North-Star argument about maintainer tooling in the default product is unchanged in principle; only its factual premise moved.
- **Asymmetry worth weighing:** moving a full-tier phase into the maintainer pack later is a small change; re-adding a deleted check after a further occurrence costs more.

Also confirmed during the retry, re-verifying this entry's own note that `verify` and stamp-compare catch different things: an extra file planted in `hooks/tests/` leaves `verify-hook-manifest.sh` reporting **MATCH** (`extra=0`) while `verify-managed-content-manifest.sh` reports `extra:`. The stamp-compare arm is load-bearing; a read-only-verify-only design has a hole.

## Notes

Related: `docs/problem-catalog/docs-only-commit-broke-content-derived-gate/problem.md` (same family — local green that did not cover what CI enforces). The durable guardrail from that entry — *the gate must run on the tree you actually push* — is necessary but not sufficient while the local gate is narrower than CI.

Related: `docs/backlog/stamper-hashes-worktree-not-artifact/README.md` — the root-cause option (hash committed content instead of working-tree bytes), filed separately because it is a **trade-off**, not a free improvement.
