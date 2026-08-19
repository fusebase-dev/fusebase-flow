# Backlog — manifest-drift-attribution

**Status:** filed, NOT built — deliberately excluded from default `verify` by premise review (2026-08-18)
**Filed:** 2026-08-19, from `health-check-enforcement-blind-spot` S3b
**Source:** paperclip+hermes-v1 escalation `2026-08-17-health-check-enforcement-blind-spot-and-manifest-stamp-discipline.md` § 3.2
**Lane guess:** Full — placement and degradation semantics are the ticket; the git plumbing is easy

## Why this is filed instead of built

`DRIFT` names files; the operator reconstructs *why* by hand. The forensic value is real and measured (below). But `verify` is a deterministic membership/hash check with a stable four-exit contract (`0 MATCH / 1 DRIFT / 2 BROKEN / 4 ABSENT`) consumed by health, preflight, CI and upgrade gates. Git history is read-only, so attribution breaks no mutation contract — what it changes is **dependency, cost and failure semantics**:

| Property | Effect of putting attribution in default `verify` |
|---|---|
| Dependency | a non-Git tree currently falls back and can still verify bytes; attribution cannot run there at all |
| Correctness | shallow history makes *"no post-stamp commit"* **FALSE**, not unknown |
| Anchor validity | an **uncommitted** manifest makes the *"last commit touching the manifest"* anchor wrong |
| Cost | one `git log` per drifted file scales badly on a wide drift |

## The consumer's forensic evidence (the case for building it later)

Preserved because it is the whole argument for the feature, and it is not reproducible from this repo:

- their 9 modified files spanned attribution across **five** later commits, not the one assumed;
- **2 files had no post-stamp commit at all** — the manifest had recorded CRLF bytes, so those files were a *correct hold*, not a wrong re-stamp.

That distinction — correct hold vs wrong re-stamp — is exactly what an operator cannot get from a file list, and it is what makes the feature worth a flag.

## Where it may land

Behind `verify --explain`, as a standalone drift-diagnostic command, or as a health recommendation offered **after** a DRIFT verdict. Never in the default `verify` path.

## Hard requirements wherever it lands

| # | Requirement |
|---|---|
| R1 | Batch **all** drifted paths into **one** history query. Not one `git log` per file |
| R2 | **Never** change the integrity verdict or the exit code when attribution is unavailable. Attribution is commentary on a verdict already reached |
| R3 | **Never** emit *"byte-level divergence"* unless all three hold: the manifest is **tracked and clean**, the anchor commit **exists**, and history is **known complete** (not shallow). Otherwise say the attribution is unavailable and why |

## Standing risk — the wasted-work prediction, recorded before any code

**If this is built into the critical verifier, it is removed within three months.** One atypical consumer's forensics placed in a critical path, producing unreliable attribution in shallow and non-Git trees, carrying maintenance cost, with no measured ordinary-consumer demand. Recorded so that a future implementer who finds it behind a flag understands the flag is the point, and a future implementer tempted to promote it to the default path has the prediction in front of them.

## Notes

Related: `docs/backlog/stamper-hashes-worktree-not-artifact/README.md` (the CRLF class that produced the 2 no-post-stamp-commit files; its S3a stamp-time guard now refuses to create that manifest in the first place) · `docs/specs/health-check-enforcement-blind-spot/spec.md` § S3b.
