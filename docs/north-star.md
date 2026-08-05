# North Star — Fusebase Flow

**Locked:** 2026-08-05 by the operator. **Status:** authoritative — every roadmap decision is checked against this.

## Who Flow is for

**Solo builders and small teams who want low friction.**

Not regulated teams buying auditability. Not primarily a maintainer framework for building Flow itself. When a change would serve one of those audiences at the cost of the primary one, the primary one wins.

## What that means, concretely

| Principle | Consequence |
|---|---|
| **One human decision per ordinary change** | If a change asks the operator to decide, approve, or read more than once, that is a defect in Flow, not diligence |
| **Lightweight is the default lane** | Full lane is an escalation with explicit triggers, not the safe-by-default choice. "In doubt → Full" is what turned uncertainty into ceremony and must be replaced with observable triggers |
| **Advanced governance is opt-in** | Evidence artifacts, multi-phase lifecycles and role separation are available for teams that want them, never imposed on a solo builder |
| **Mechanism over prose** | A guarantee is worth its cost only if something enforces it. A rule that exists only as instruction text is a documentation claim, and this project has repeatedly shipped those as if they were controls |
| **Cost is a first-class defect class** | Time the operator spends on ceremony that prevented no defect is a bug, tracked like any other |

## What this rules out

- Adding a rule because one incident happened once. Twelve of twenty-seven always-on rules arrived in ~46 days, mostly that way.
- Shipping a control whose enforcement is opt-in while documenting it as enforced (`approval_authors`, `live-enforcement-inertness`).
- Artifacts produced because a template implies them rather than because a later reader needs them.

## What it does NOT rule out

The safety kernel stays, because it is what a low-friction default is *allowed* to rest on:

- Independent adversarial review on security, upgrade, data and release surfaces — it has repeatedly found defects that green suites missed (7 BLOCKERs / 6 MAJORs after a 649/649 pass).
- Release publication structurally dependent on verification, gated on the exact published SHA.
- FR-06 destructive-operation protection, FR-07 protected paths, fail-closed secret scanning.
- Per-file three-way upgrade classification and verified source materialization.
- The problem catalog — the clearest evidence surface in the repo.

Low friction is not less safety. It is less *ceremony* per unit of safety.

## Known gap this locks against

Before this file existed, the same evidence supported opposite conclusions: under "auditability for regulated teams" the artifacts *are* the product; under "maintainer framework" the meta-skills are the valuable part. A simplification roadmap was drafted and could not be validated because there was nothing to check it against. That is the failure this file prevents.

## Measurement gap, still open

No **ordinary** consumer has been measured. Both reporting consumers are atypical — one a flagship multi-app install, one running a custom security overlay. Flow's value/cost ratio for its actual target audience is currently **unknown**, and claims about it must say so until measured.

## Related

`docs/constitution.md` · `docs/maintainer-execution.md` (maintainer-side, not product) · `docs/tmp/handoff/2026-08-05-product-review-proposal.md` (hypothesis, now checkable against this)
