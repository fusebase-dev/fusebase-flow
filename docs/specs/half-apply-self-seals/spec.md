# N6 — the half-apply self-seals

**Status:** SPECIFIED — premise review pending (run BEFORE implementation)
**Opened:** 2026-08-20
**Source:** WorkHub Managed escalation `2026-08-20-v4.12.0-escalation.md` (committed `7f37f632`), finding N6, HIGH
**Severity rationale:** v4.11.0's N5 fix cannot reach the population it was written for, and one attempt to take it freezes the tree permanently.

## Verified locally before this spec was written

Two facts, both checked against this repo rather than taken on trust:

1. **`audit/managed-content-manifest.json` is an ordinary member of the managed set** —
   `managed_content_manifest.py list-managed --files` lists it, alongside
   `audit/hook-layer-manifest.json`. So when absent it is not synthesized; it is **copied from
   upstream** like any other content file.
2. **Their sandbox's poisoned base is byte-identical to our own published v4.11.0 fingerprint row** —
   `326 assets / c0bd8faad60785a62cadce5626e92baa606fbb09547e4352b5fa0ae67a667a82`, matching
   `docs/release-fingerprints.md`. That is proof the base was copied from upstream, not derived from
   the consumer's tree.

## The mechanism

The base is meant to record **what upstream last shipped this consumer**. The copy records **what
upstream ships now**. That single substitution is the whole defect.

For a consumer with no base — the F1/N1 population, installs whose last upgrade ran a pre-4.7.0
engine:

| Step | Result |
|---|---|
| every pre-existing file classifies `unknown-base` | preserved, **not refreshed** — including `hooks/local/upgrade.sh` |
| genuinely new files have no local counterpart | `upstream-only` → **delivered** |
| the absent base manifest is itself `upstream-only` | **delivered — i.e. copied** |

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
the consumer's own edit, so no future release can repair it.

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

## Slices

Ordered by who they reach, not by elegance. That is the consumer's own ranking and it is right: the
root fix helps nobody already exposed.

### S1 — detect and route in `/fusebase-health` — BUILD FIRST

A missing `audit/managed-content-manifest.json` is a one-line check, and the health check is the
**consumer-facing** surface. `preflight.sh` already warns, but our own N5 spec states plainly that
preflight is maintainer-side and the consumer never runs it.

Route to `bootstrap-upgrade.sh`, which stages the new engine **first** and is the only path that
works from this state. This turns a silent permanent freeze into one sentence of guidance, and needs
no change to the upgrade path at all.

It is the only slice that reaches people already exposed who can still run a command.

### S2 — say it in the release notes — NO CODE

Any release carrying an engine-side upgrade fix must state: *if you have no base manifest, use
`bootstrap-upgrade.sh`, not `upgrade.sh`.* Add it retroactively to the v4.11.0 and v4.12.0 notes —
those are the releases whose fix is unreachable — and to `PUBLISHING.md` so the next one carries it.

### S3 — stop shipping the base manifest as content — root fix, reaches nobody already exposed

It is derived state about *this install*, not material to install. Write it only by synthesis or by a
completed upgrade; never copy it. That removes the poisoning step at its root.

**Design question for the review — do not decide it here.** Removing it from the managed set changes
what `list-managed` reports, which feeds the classifier, the upgrade allowlist, and possibly the
fingerprint asset counts. `audit/hook-layer-manifest.json` sits in the same position and may have the
same problem or may not — establish that rather than assuming symmetry.

### S4 — F2 residual: normalize on copy — MEDIUM

v4.12.0 closed the **stamp-time** subclass. The consumer-side residual is untouched, and it is the
half that reached them: a staging clone checked out at a tag whose `.gitattributes` pins `eol=lf`
still holds CRLF for files whose content did not change across the checkout, and `upgrade.sh`
**copies** them across, where no `.gitattributes` can intervene. A fresh clone is clean — measured, 0
of 18 `.jsonl` fixtures CRLF at v4.10.1 — but every long-lived adopter arrives by the copy path.

They explicitly do **not** ask us to take the `stamper-hashes-worktree-not-artifact` trade, and we
should not. Their narrower proposal: have `upgrade.sh` normalize on copy for paths whose resolved
attribute is `eol=lf`, using the same `git check-attr` resolution `eol_guard` already performs. That
fixes transport without touching what the verifier hashes.

FR-25 constraint: `upgrade.sh` is at its module-size baseline and must not grow — new logic goes in a
lib.

### S5 — N4 residual: scope or adopt — LOW

All three of their manifests carry `name: fusebase-flow`, so the ownership-scoped check fires; and
`list-managed --dirs` returns only `flow-skills agents workflows policies templates hooks`, so the
upgrade will never refresh them. The result is a hand edit after **every** release — they have now
done it twice (4.9.2, 4.11.0).

Either scope the check to publisher repos, or add the three files to the managed set. The present
pairing asserts a requirement the upgrade declines to satisfy. Pick one; do not leave it.

### R1 — no action, at their request

Recorded for completeness. They are explicit: not asking for a change, the backlog's false-negative
analysis is correct, and the v4.9.2 denial message was the right mitigation.

## Explicitly NOT doing

| Not doing | Why |
|---|---|
| Restamping the base from the consumer's tree | K13b rejects it — that records their edits as upstream base |
| Taking the committed-bytes hashing trade for F2 | they explicitly do not ask for it; it costs local-tamper detection |
| Narrowing the command-gate patterns (R1) | trades a false positive for an evasion hole |
| Treating S3 as sufficient alone | it cannot help anyone already exposed — that is what S1 is for |

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
