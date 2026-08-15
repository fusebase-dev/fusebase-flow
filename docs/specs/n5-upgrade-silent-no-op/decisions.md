# Decisions — N5 upgrade silent no-op

Prefix `N`. Two of the three questions were already decided elsewhere and are applied, not reopened; only N3 is new.

| ID | Decision | Rests on | Lock status |
|---|---|---|---|
| N1 | Port K13a synthesis to `upgrade.sh` via a shared lib — extract, never copy | K13a, K14 | LOCKED |
| N2 | `unknown-base` remains preserve+report; no abort | K9 (unchanged) | LOCKED |
| N3 | A run that refreshed nothing must not bump VERSION and must not exit 0 | new | LOCKED |

---

## N1. Complete K13a on the ordinary upgrade path, by extraction

**Decision:** move `ff_synthesize_base` from `bootstrap-upgrade.sh` into a shared lib under `hooks/local/lib/`, sourced by both engines. Call it from `upgrade.sh` before classification.

**Reasoning:** K13a is LOCKED and states its invariant unconditionally — *"A consumer with no `audit/managed-content-manifest.json` does not get a tree full of `unknown-base`"*. It names `bootstrap-upgrade.sh` because that was the adoption path in scope, not because the invariant is scoped to it. The exposed population arrives via `upgrade.sh`. So this **completes** a locked decision; it does not amend one, and no decision needs reopening.

Extraction rather than duplication follows K14's one-home principle, and here it is load-bearing rather than stylistic: the function's M1 line-ending block is annotated *"VERIFIED, do not 'simplify' this away"*, and a 2026-07-28 review's contrary claim was disproved by reproducing whole-tree misclassification. A second copy is a second chance to lose that.

**Alternatives considered:**

- **Copy the function into `upgrade.sh`** — rejected: two copies of a block whose comments say not to simplify it, in the two scripts that must agree about what a consumer edit is.
- **Call `bootstrap-upgrade.sh` from `upgrade.sh`** — rejected: bootstrap is the pre-boundary engine and `exec`s a handoff; invoking it mid-upgrade inverts the source-boundary contract (M1).

**Lock status:** LOCKED

---

## N2. `unknown-base` stays preserve + report

**Decision:** unchanged from K9. Only `changed-by-both` stops an unattended run.

**Reasoning:** the consumer's preferred fix (abort on `unknown-base`) is K9's **Option A, rejected verbatim** as *"unusable first adoption"* (`approval-binding-and-upgrade-classification/decisions.md:193`). Their preference is reasonable from where they sit — they cannot see K9 — but adopting it would also punish the forked consumer, for whom no tag can ever resolve and who is least able to recover. With N1 in place the ambiguity that made abort tempting is mostly gone: `unknown-base` becomes the residue of genuinely unresolvable VERSIONs rather than the default state of the fleet.

**Lock status:** LOCKED (inherited)

---

## N3. A run that delivered nothing must say so — refuse the bump AND fail

**Decision:** when **all three** hold —

```
VERSION would change   AND   ff_applied == 0 AND ff_removed == 0   AND   >=1 path classified unknown-base
```

— do not write VERSION, exit non-zero with a verdict distinguishable from both a clean run and a `changed-by-both` abort, name the recovery (`docs/release-fingerprints.md` identifies the tag to seed from; `bootstrap-upgrade.sh` synthesizes the base), and surface the same condition in the dry run.

**Reasoning:** this is a **run-level** rule and touches no per-path verdict, so it does not disturb K9. `upgrade.sh:12` already claims *"VERSION as the LAST step — so VERSION can never advance ahead of content"*; N5 proves that ordering alone does not deliver the guarantee the header asserts — with every path kept, VERSION advances ahead of content semantically while the ordering rule is satisfied. N3 enforces that same claim by outcome instead of sequence.

The third clause is what makes the trigger correct rather than merely strict: a current tree and a docs-only release both refresh zero paths and must not trip. Only the N5 shape has `unknown-base` present with zero applied.

Exiting non-zero is not decoration. N5's complaint is not only that VERSION advanced — it is that *the run reported success* and *the dry run showed no conflicts*, so nothing downstream could notice. Refusing the bump while still exiting 0 would rebuild the same defect one layer in.

**Alternatives considered:**

- **Warn-only for one release** — rejected: `preflight.sh:301` already warns on a missing base and did not stop this (preflight is maintainer-side; the consumer never runs it). A second advisory is the third soft signal on one failure. *"A warning is what N5 already effectively was."*
- **Refuse the bump but exit 0** — rejected: keeps the silence that made N5 undetectable.
- **Trigger on zero-refreshed alone** — rejected: false-positives a legitimately current tree and a docs-only release.
- **Trigger on synthesis failure** — rejected: strands the forked consumer who still received files. The refusal must key on outcome, not on cause.

**Lock status:** LOCKED
