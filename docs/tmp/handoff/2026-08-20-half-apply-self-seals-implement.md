# AI Developer handoff — N6, the half-apply self-seals

**Spec (authoritative — it carries the premise review's corrections):** `docs/specs/half-apply-self-seals/spec.md`
**Consumer escalation:** `c:/Users/Pavel/projects/WorkHub Managed/docs/_shared/fusebase-flow-escalations/2026-08-20-v4.12.0-escalation.md`
**Branch:** create `fix/half-apply-self-seals` off `main` (`17c2533`)

The premise review ran **before** any code and changed four of five slices. Build what the spec says,
not what the consumer's report says where they differ — their mechanism text has three terminology
errors the spec corrects, though their severity call is right.

FR-03: one task = one commit. Stop at the gate (IM.8). Do not push, tag, or bump VERSION.

## The root cause — build around this, not around manifest membership

> The transaction advances the base and VERSION after classification, without a trustworthy
> historical base, even though ambiguous paths were preserved.

## Build scope

| Slice | Call |
|---|---|
| **T1 — transactional base/VERSION advancement** | **BUILD FIRST** — this is the root fix |
| **T2 — two-state detection + routing in `/fusebase-health`** | BUILD |
| **T3 — recovery procedure for the poisoned state** | BUILD |
| T4 — F2 regression test only | BUILD (test, no engine change) |
| T5 — N4 publisher-only scoping | BUILD LAST, separable |
| S2 advisory | **already DONE** — `17c2533`, both release notes, both GitHub release bodies |

## T1 — the transactional invariant, and the design question you must answer first

**Do not start coding until you have reasoned about this and recorded a decision.**

`lib/upgrade-delivery-guard.sh` (N5, v4.11.0) refuses to advance VERSION when three conditions hold:
VERSION would change **and** nothing was applied or removed **and** at least one path classified
`unknown-base`.

**N6 slips through that guard precisely because files WERE applied** — the `upstream-added` ones are
auto-copied, so `ff_applied > 0` and the guard never fires. That is the gap.

The invariant needs broadening to: refuse to commit the new base and VERSION when classification
**lacked a trustworthy historical base** AND **ambiguous paths were preserved** — regardless of how
many other files were successfully applied.

The tension you must resolve deliberately, not by reflex:

- Broadening this way means a no-base upgrade now **refuses** rather than half-applying. That is
  arguably correct — it is the "couldn't tell what to do" case — but it is a behaviour change for
  every no-base consumer, and K9 Option A ("abort on `unknown-base`") was **already rejected** as
  *"unusable first adoption"*. Read `decisions.md` on K9 and K13a/K13b before deciding.
- The distinction that may save it: K9 rejected aborting on a per-path *classification*; this is a
  run-level refusal to **commit state** that the run did not earn. N5's guard already establishes
  that shape and was accepted. But establish that reading from the decision record — do not assume it.
- Whatever you decide, the refusal must route (see T2), not merely stop. A refusal with no way
  forward recreates the "unusable first adoption" objection K9 was protecting against.

**FR-25:** `upgrade.sh` is pinned at its module-size baseline and must not grow. New logic goes in a
lib. Note raw copies happen at `upgrade.sh:552-558` and `:576-580`, so call-site edits must be
size-neutral.

## T2 — two states in `/fusebase-health`, and one honest limit

**State 1 — clean missing-base, pre-exposure** (VERSION still truthfully names the installed
baseline): route to `bootstrap-upgrade.sh`, which stages the new engine first and works from this
state (`bootstrap-upgrade.sh:683-708,714-750`).

**State 2 — poisoned / already half-applied:** hard stop. Bootstrap CANNOT repair it —
`synthesize-base.sh:46-49` trusts an existing base without validating it, and deleting the base makes
synthesis key off the now-advanced VERSION (`:57-75`, advanced at `upgrade.sh:674-681`) and rebuild
the same poison. Tell the operator to preserve `*.pre-upgrade-*`, the source clone, VERSION backups
and logs, and route to T3.

**Distinguishing the two is the hard part.** A poisoned tree has a base that is present and
self-consistent — it is upstream's real manifest — so verification passes. Establish a signal that
actually separates them and say what it is. Candidates worth testing, none endorsed: base content
matching a *published* upstream fingerprint row exactly (the consumer's own forensic tell), VERSION
advanced relative to observable content, backup artifacts from a prior run. If you cannot find a
sound discriminator, say so — a check that guesses is worse than one that does not exist.

**State it plainly in the output and the spec:** the health-check script is itself among the frozen
files, so this check cannot reach installs already affected. It protects the not-yet-exposed. The
already-affected are reached by the advisory, out-of-band. Do not imply otherwise.

## T3 — the recovery procedure

A poisoned tree is frozen under the ordinary path but **not** unrecoverable. Build a procedure that
establishes the **last truthful version** before rebuilding anything — that is the ordering the
review insists on, because every shortcut that skips it reconstructs the same wrong base.

Inputs available: `*.pre-upgrade-*` backups, the source clone, VERSION backups,
`docs/release-fingerprints.md` (which maps every released tree to its manifest fingerprint — the
consumer used exactly this to prove the copy). Whether that is sufficient is yours to establish.

If the honest answer is that some poisoned trees cannot be recovered automatically, say that and
scope the procedure to those that can. Do not invent a repair that silently guesses the baseline.

## T4 — F2: regression test only, no engine change

v4.12.0 already materializes incoming git content from git **objects** with LF forced
(`materialize-managed-source.sh:4-7,64-78`), and ordinary `upgrade.sh` invokes that boundary
(`upgrade.sh:218-239`). The consumer's F2 is most plausibly **downstream of N6** — their old engine
never ran that boundary. Reproduce it through the v4.12 engine and add a regression test. Do **not**
add normalize-on-copy: it would create a second canonicalization authority after the existing
boundary.

## T5 — N4: publisher-only scoping

Lock the ownership check to publisher repos. Do **not** add the three plugin manifests to the managed
set — `managed_content_manifest.py:38-44` records why they are publisher-only: adoption lets an
upgrade overwrite a consumer's own plugin manifest. A publisher-context check that misses enforcement
fails visibly; managed adoption corrupts ownership silently.

## Gate report must include

Per task: SHA, RED-then-GREEN with the actual failing output, the T1 decision and the K9/K13b reading
that supports it, the T2 discriminator you established (or your statement that none is sound), and
preflight + relevant phase results. Re-stamp manifests LAST. If an oracle cannot be made to fail
first, say so rather than reporting a green you cannot account for.
