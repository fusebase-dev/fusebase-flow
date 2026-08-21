# Decisions — N6, the half-apply self-seals

## N6-D1 — the base must not record entries the run did not earn — **LOCKED**

**Decision.** The new managed-content base must **not** contain entries for paths this run preserved
as `unknown-base`. Apply as today; write the base as today; **omit those paths from it.**

**Status:** LOCKED, 2026-08-20. Supersedes nothing. Reverses no prior decision.

### Context

A consumer with no base manifest runs the ordinary upgrade. Differing pre-existing paths classify
`unknown-base` and are preserved; genuinely new paths are `upstream-added` and auto-copied; the base
manifest is excluded from classification and then unconditionally appended as the final copy
operation. The run therefore records **upstream's current bytes** as the consumer's base for paths it
just admitted it could not classify.

One release later those paths read `consumer-only` — *"YOU changed these"* — or `changed-by-both`,
and the run aborts. Reproduced live against the v4.12.0 engine: `hooks/local/control.sh`, a file the
consumer never touched, was preserved as `unknown-base`, recorded with upstream's bytes, and then
blamed on the consumer and used to abort the next upgrade.

### Why not the refusal the spec originally proposed (T1-A)

The spec's S3 said: refuse to advance base and VERSION when *"classification lacked a trustworthy
historical base"*. Operationally that is `FFSB_REASON ∈ {no-git, no-tag, no-module, extract-failed,
stamp-failed}` — **synthesis failed** — which is a **cause**.

`docs/specs/n5-upgrade-silent-no-op/decisions.md` § N3, *Alternatives considered*, rejects exactly
that, verbatim:

> *Trigger on synthesis failure — rejected: strands the forked consumer who still received files.
> The refusal must key on outcome, not on cause.*

N2 protects the same population for the same reason: *"adopting it would also punish the forked
consumer, for whom no tag can ever resolve and who is least able to recover."* And the shipped oracle
`test-upgrade-delivers-or-refuses.sh :: n2-forked-still-proceeds` asserts rc 0, VERSION advanced, and
no refusal on precisely that shape — 6/6 green today. T1-A would require inverting all three
assertions, which is a consumer-visible behaviour reversal for the forked, no-tag and tarball
populations.

Adding S3's second clause (*"and ambiguous paths were preserved"*) narrows the domain but does not
change the keying: it still fires on cause, plus evidence the cause mattered.

**The K9 reading in the spec does hold.** A run-level refusal to commit state is genuinely a
different shape from K9 Option A's per-path abort — Option A stops a run for any `unknown-base` path
even when the consumer has a good base, whereas a precondition-driven refusal is self-limiting. That
reasoning was tested and survived. It rescues T1 from K9 and then walks it straight into N3, which
neither the spec nor the handoff cited.

### Why N6-D1 instead

It keys on **outcome** — what this run actually delivered — which is N3's stated rule rather than its
rejected alternative.

| Property | T1-A (refuse) | **N6-D1 (truthful base)** |
|---|---|---|
| Keys on | cause — N3's rejected alternative | **outcome — N3's stated rule** |
| Forked consumer (N2) | refused, receives nothing | **proceeds, receives files, VERSION advances** |
| `n2-forked-still-proceeds` | must be inverted | **stays green, unchanged** |
| Stops the sealing | yes | **yes** |
| Decision cost | reverses N3's alternatives + N2 | **reverses nothing** |

A path omitted from the base classifies `unknown-base` on the next run: K9's designed safe residue —
preserve **and report, every run**. A path recorded with bytes the run did not earn classifies
`consumer-only` and is silently frozen. **A missing entry is recoverable and visible; a false entry
is neither.**

### Consequences, stated plainly

- Affected paths stay **stale but visible**. The consumer keeps seeing them reported every run rather
  than being told they authored them. That is worse than a clean upgrade and strictly better than
  today.
- `verify` will report those paths `extra` rather than `modified`. Both are DRIFT; the wording
  changes.
- This does **not** rescue installs already poisoned — their base already contains false entries.
  Those are reached by the advisory (`docs/ADVISORY-2026-08-20-missing-base-upgrade.md`, shipped
  `17c2533`) and by N6-D2's recovery path.
- It does not touch base seeding, source attestation, or fresh installs, so it does not trigger the
  spec's own standing wasted-work risk (removing base seeding and recreating the missing-base state).

## N6-D2 — no local signal identifies a poisoned tree; do not guess — **LOCKED**

**Decision.** The health check must **not** attempt to classify an existing tree as poisoned. It may
positively detect the missing-base state (base absent → `verify` ABSENT, rc 4) and route to
`bootstrap-upgrade.sh`. For `base present + DRIFT` it emits a **conditional pointer** to the advisory,
never a verdict.

**Status:** LOCKED, 2026-08-20.

### Evidence

Two trees driven through the v4.12.0 engine — one poisoned, one healthy with a genuine consumer edit
— produce an **identical signature**: base present, self-hash valid, `verify` DRIFT/`modified`, base
byte-identical to a published upstream manifest, rc 0, VERSION advanced, and the same backup
artifacts.

Each candidate discriminator was tested and failed:

- **Fingerprint-row match** — non-discriminating *by design*: K13b installs the source tree's
  manifest as the new base after **every** successful upgrade, so a healthy tree's base also matches
  a published row.
- **VERSION advanced relative to content** — true of both; that is what `consumer-only` means.
- **Backup artifacts** — identical sets. `audit/managed-content-manifest.json` gets no backup twin at
  all (`upgrade.sh:554-556` twins top-level files only; `audit/` is not in `list-managed --dirs`), so
  nothing in the tree records whether a base existed before the run.

The distinguishing fact is **history** — did a base exist before the run that wrote this one — and it
is recorded nowhere.

### Consequence

- **Forward-only fix:** the engine stamps provenance into the base it installs (`prior_base:
  present|absent|synthesized`, `prior_version`, `preserved_unclassified: N`), so a poisoned base
  self-identifies with certainty from the next upgrade onward. This reaches **zero** already-affected
  installs; the output must say so rather than implying coverage.
- **Recovery (N6-D3 scope):** automatic repair is offered only where the operator supplies external
  ground truth — `VERSION.pre-upgrade-*`, `docs/release-fingerprints.md`, and a source clone carrying
  the tags. A tree without those inputs **cannot** be repaired automatically, and the procedure must
  say that rather than guessing a baseline.

### Why this is not a cop-out

A check that guesses which state an operator is in would send half of them down a path that makes the
tree worse — the advisory already tells the poisoned population that deleting the base or
bootstrapping blindly recreates the poison. A wrong verdict here is actively harmful, not merely
unhelpful.
