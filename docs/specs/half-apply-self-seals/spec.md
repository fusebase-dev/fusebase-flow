# N6 — the half-apply self-seals

**Status:** SPECIFIED — premise review complete (SOUND-WITH-FIXES); its corrections are applied below
**Opened:** 2026-08-20
**Source:** WorkHub Managed escalation `2026-08-20-v4.12.0-escalation.md` (committed `7f37f632`), finding N6, HIGH
**Severity rationale:** v4.11.0's N5 fix cannot reach the population it was written for, and one attempt to take it freezes the tree under the ordinary upgrade path.

## Root cause

The review's central finding — neither we nor the consumer had reached it, and every slice below is
framed around it:

> **The transaction advances the base and VERSION after classification, without a trustworthy
> historical base, even though ambiguous paths were preserved.**

Manifest membership is **not** the cause. The base being shipped, listed, or copied is how the
poison arrives; the poison *sticks* because the engine commits the new base and VERSION as if the
run had been fully applied when it knowingly preserved paths it could not classify.

## Verified locally before this spec was written

Two facts, both checked against this repo rather than taken on trust:

1. **`audit/managed-content-manifest.json` is listed by the managed set** —
   `managed_content_manifest.py list-managed --files` lists it, alongside
   `audit/hook-layer-manifest.json`. So when absent it is not synthesized; it is **copied from
   upstream**. (The review corrected the *mechanism* of that copy — see the table below — but the
   copy itself is real.)
2. **Their sandbox's poisoned base is byte-identical to our own published v4.11.0 fingerprint row** —
   `326 assets / c0bd8faad60785a62cadce5626e92baa606fbb09547e4352b5fa0ae67a667a82`, matching
   `docs/release-fingerprints.md`. That is proof the base was copied from upstream, not derived from
   the consumer's tree.

## The mechanism

The base is meant to record **what upstream last shipped this consumer**. The copy records **what
upstream ships now**. That substitution is how the defect presents; the root cause above is why it
sticks.

For a consumer with no base — the F1/N1 population, installs whose last upgrade ran a pre-4.7.0
engine:

| Step | Result |
|---|---|
| pre-existing files whose local bytes **equal** upstream classify `current` | refreshed normally — no freeze |
| pre-existing files whose local bytes **differ** classify `unknown-base` | preserved, **not refreshed** — `hooks/local/upgrade.sh` freezes only because it differs (`managed_content_manifest.py:284-291`) |
| genuinely new files with no local counterpart classify `upstream-added` | **auto-copied** (`managed_content_manifest.py:286-299,305-316`) |
| the absent base manifest is **not classified at all** | explicitly **excluded** from classification, then unconditionally appended as the final `copy` operation whenever the run does not abort (`managed_content_manifest.py:268-271,362-369`) |

So the N5 apparatus (`lib/synthesize-base.sh`, `lib/upgrade-delivery-guard.sh`, its test) lands while
**its only caller does not**. Their measurement: exit 0, VERSION 4.9.2 → 4.11.0, 30 files preserved,
and `grep -c ff_n5_nothing_delivered hooks/local/upgrade.sh` → **0**.

Then the copied base seals it. Base now equals upstream's current content, local differs, so the
classifier concludes the consumer edited them:

```
consumer-only (16) — YOU changed these; upstream did not — PRESERVED:
  - hooks/local/upgrade.sh          <- the file that would fix this
  - hooks/local/preflight.sh
  - hooks/local/fusebase-flow-health-check.sh
  - hooks/local/bootstrap-upgrade.sh
```

Across a release boundary it stops being merely stale: 11 still frozen, 5 `changed-by-both`,
**ABORTED, exit 3**. Hand-reconciling the conflicts does not help — `upgrade.sh` remains misfiled as
the consumer's own edit, so no future release can repair it through the ordinary path.

**What "permanent" means, honestly:** frozen under the ordinary upgrade path — **not**
mathematically unrecoverable. Backups or a purpose-built repair can restore the tree. That
distinction is exactly what the recovery half of S1 exists to deliver.

## Why this outranks an ordinary staleness bug

**It is K13b's error mirrored, and larger.** K13b rejects restamping the base from the consumer's
tree because that *"records their edits as upstream base; the next upstream change then overwrites
them."* N6 records **upstream's content as the consumer's base**. K13b's version loses edits at the
next change; N6 freezes the entire tree indefinitely **and presents it as consent** — harder to
notice, and harder to argue with, because the report says the consumer chose it.

**The repair cannot ship by the path that needs it.** The fix lives in `upgrade.sh`, and `upgrade.sh`
is precisely the file the affected consumer never receives. F1 was this same shape — *"upgrade.sh
cannot install its own release"* — and v4.7.1's honesty note already records that the in-memory run
finishes on the old engine. A fix placed in the engine cannot rescue a consumer whose engine will not
be replaced. v4.12.0 corrected the v4.7.0 notes for exactly this class.

## Slice calls

The premise review's ruling, applied throughout the slices below:

| Slice | Call |
|---|---|
| S1 | **REWRITE, THEN BUILD** — split clean missing-base from poisoned state; already-exposed installs are reached out-of-band, not by the shipped check |
| S2 | **DONE** — advisory shipped ahead of the fix (evidence in S2) |
| S3 | **REPLACED** — transactional base/VERSION advancement, not manifest-membership removal |
| S4 | **NO BUILD** — v4.12.0's source boundary already owns it; regression test only |
| S5 | **BUILD SEPARATELY** — publisher-only scoping, never managed adoption |

## Slices

Ordered by who they reach, not by elegance. That is the consumer's own ranking and it is right: the
root fix helps nobody already exposed.

### S1 — detect and route in `/fusebase-health` — REWRITE, THEN BUILD

The draft claimed one state and one route. There are **two states**, and only one of them is
bootstrap-shaped:

**State 1 — clean missing-base, pre-exposure.** VERSION still truthfully identifies the installed
baseline; the consumer has not yet run an ordinary upgrade from this state. Route to
`bootstrap-upgrade.sh`. This works: `bootstrap-upgrade.sh:683-708,714-750` reconstructs the base
from that tag and executes the **source** engine, staging the new engine first.

**State 2 — poisoned / already half-applied.** Bootstrap **cannot** repair this state:

- `synthesize-base.sh:46-49` trusts an existing base without validating it, so bootstrap hands the
  poisoned base straight through to the source engine.
- If the user deletes the base, synthesis keys off the now-**advanced** local VERSION
  (`synthesize-base.sh:57-75`; the advance happened at `upgrade.sh:674-681`) and reconstructs the
  same poison.

State 2 needs a **hard stop**, preservation of backups (`*.pre-upgrade-*`, the source clone, VERSION
backups, logs), and a dedicated recovery procedure that first establishes the **last truthful
version** before anything is rebuilt.

**Delivery paradox — state it, do not paper over it:** the health-check script is itself among the
frozen files, so a new health check cannot reach already-affected installs through the broken
upgrade path. The check protects installs not yet exposed and installs that still refresh; the
already-affected population is reached **out-of-band** — S2's advisory and pinned release notes.
Do not claim the shipped check reaches them.

### S2 — say it in the release notes — DONE

Shipped ahead of the fix:

- `docs/ADVISORY-2026-08-20-missing-base-upgrade.md`, committed `17c2533`.
- Advisory banner added to the v4.11.0 and v4.12.0 release notes — the releases whose fix is
  unreachable.
- The same banner prepended to **both** published GitHub release bodies via the API.

It carries the two-state instruction from S1, including the explicit language the review required
for the poisoned state: **do not rerun upgrade, do not delete / re-stamp the manifest, do not run
current bootstrap blindly; preserve backups.** `PUBLISHING.md` carries it forward so the next
engine-side upgrade fix states the same.

### S3 — make consumer-base advancement transactional — REPLACED (root fix, reaches nobody already exposed)

The draft's S3 — stop shipping the base manifest as content — is wrong twice over:

1. **It does not stop the poisoning.** Removing the base from `MANAGED_FILES` changes what
   `list-managed` reports, but `build_plan` **independently** appends the base copy as its final
   operation (`managed_content_manifest.py:362-369`). The copy survives the removal.
2. **It creates a genuine bootstrapping paradox.** The shipped manifest is required as the source
   attestation that verifies incoming content (`materialize-managed-source.sh:147-166`). If it
   stops shipping, a modern source is treated as unverified legacy — and a fresh install would have
   no base at all, which is the very state that causes N6.

The replacement targets the root cause directly:

> **Never write the new base or VERSION when classification lacked a trustworthy historical base
> AND ambiguous paths were preserved.** Fail closed before the writes; leave the tree and VERSION
> exactly as they were.

The review names the cleaner long-term option, recorded here for the eventual design: split
**"release source attestation"** (what verifies incoming content) from **"consumer's prior
baseline"** (what drives three-way classification) into distinct artifacts, so shipping one never
overwrites the other.

The draft's design question is answered — do not re-open it: `audit/hook-layer-manifest.json` is
**different**. It is ordinary upstream integrity content that does **not** control future three-way
classification (`managed_content_manifest.py:51-54,268-271`). Do not assume symmetry with the base
manifest.

### S4 — F2 residual — NO BUILD; regression test only

v4.12.0 already fixes this at a **stronger** boundary than normalize-on-copy would: incoming git
content is materialized from git **objects**, not the staging worktree, with LF forced
(`materialize-managed-source.sh:4-7,64-78`), and ordinary `upgrade.sh` invokes that boundary and
reads all incoming content from the canonical tree (`upgrade.sh:218-239`). A long-lived stale clone
holding CRLF therefore cannot leak those bytes into an upgrade run on the current engine.

The consumer's F2 observation is most plausibly **downstream of N6**: their old engine never
received or ran that boundary. Direct reproduction of the stale-clone CRLF leak **through the v4.12
engine** is UNVERIFIED — do not treat it as an open defect.

Two further reasons not to build:

- Normalize-on-copy would create a **second canonicalization authority** after the existing source
  boundary — two places that must agree forever.
- A zero-touch lib fix is impossible anyway: the raw copies happen at `upgrade.sh:552-558` and
  `:576-580`, in a file pinned at its FR-25 module-size baseline, so any helper needs call-site
  changes in a file that must not grow.

Remaining work: **one regression test** proving the existing boundary delivers LF from a staging
clone that holds CRLF. They explicitly do not ask us to take the `stamper-hashes-worktree-not-
artifact` trade, and we still should not.

### S5 — N4 residual: publisher-only scoping — BUILD SEPARATELY, never managed adoption

All three of their manifests carry `name: fusebase-flow`, so the ownership-scoped check fires; and
`list-managed --dirs` returns only `flow-skills agents workflows policies templates hooks`, so the
upgrade will never refresh them. The result is a hand edit after **every** release — they have now
done it twice (4.9.2, 4.11.0).

The draft offered a choice; the review locks it: **scope the check to publisher repos. Do not adopt
the three plugin manifests into the managed set.** `managed_content_manifest.py:38-44` already
records why those files are publisher-only: adopting them lets an upgrade overwrite a consumer's
own plugin manifest. Adoption is the option more likely to be silently wrong in a year — provider
schemas and consumer ownership evolve while upgrades keep overwriting apparently valid files. A
publisher-context check may miss enforcement **visibly**; managed adoption corrupts ownership
**silently**.

### R1 — no action, at their request

Recorded for completeness. They are explicit: not asking for a change, the backlog's false-negative
analysis is correct, and the v4.9.2 denial message was the right mitigation.

## Standing wasted-work risk

As the review states it: in three months this effort is most likely judged **harmful** because S3
removed or weakened base seeding — recreating the exact missing-base state this spec exists to
kill — while S4 added a second canonicalization implementation that v4.12.0 already had. That is
precisely why S3 is replaced with the transactional invariant and S4 is cut to a regression test.
Any future edit to these slices should be checked against this failure mode first.

## Explicitly NOT doing

| Not doing | Why |
|---|---|
| Restamping the base from the consumer's tree | K13b rejects it — that records their edits as upstream base |
| Removing the base manifest from `MANAGED_FILES` (draft S3) | does not stop the copy (`build_plan` appends it independently) and breaks source attestation + fresh installs |
| Normalize-on-copy in the upgrade engine (draft S4) | duplicates v4.12.0's canonical source boundary; impossible without growing an FR-25-pinned file |
| Adopting the three plugin manifests into the managed set (S5 alternative) | silently overwrites consumer-owned files as schemas evolve |
| Taking the committed-bytes hashing trade for F2 | they explicitly do not ask for it; it costs local-tamper detection |
| Claiming the shipped health check reaches already-affected installs | the check is itself among the frozen files — delivery is out-of-band (S2) |
| Narrowing the command-gate patterns (R1) | trades a false positive for an evasion hole |

## Verified sound in v4.12.0 — do not re-chase

They exercised these rather than reading them: the stamp-time EOL guard (all three callers, returns
non-zero, does not write), the enforcement-layer health verdict (matching the canonical handler
*inside* the chain is the right discriminator), the v4.7.0 note correction, the CLI version gate
against a real banner-shadow host printing a *"New version … 0.29.9!"* line before the version, and
the CLI advisory asymmetry (0.29.9 newer than the 0.29.8 snapshot — advisory only, moved neither
verdict nor exit code).

One field observation offered for `gate-bounds-lack-headroom`, not as a finding:
`FFHC_PREFLIGHT_TIMEOUT=120` expired inside the health check on a loaded MSYS host while the same
preflight passed standalone minutes earlier; it passed at 420. They note the message named the check,
the knob and the current budget, so it was actionable in one command — unlike the job-probe case.
