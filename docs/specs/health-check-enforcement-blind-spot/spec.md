# Health-check enforcement blind spot + manifest stamp discipline

**Status:** SPECIFIED — premise review complete (verdict: SOUND-WITH-FIXES, 2026-08-18); corrections applied below
**Opened:** 2026-08-18
**Source:** paperclip+hermes-v1 escalation `2026-08-17-health-check-enforcement-blind-spot-and-manifest-stamp-discipline.md` (fifth in that chain). Every claim in it survived an independent adversarial review that refuted two of their own companion claims first.
**Verified locally before this spec was written** — see each section.

## Why this is being specced before it is built

Tonight's retrospective named the biggest process waste: on the CLI 0.29.8 ticket the premise review
ran *after* eleven commits, and cut two of them. This ticket ran it first. The review confirmed the
core premise — S1 and S3a address real failures — and corrected the receipt design, the S3a strength,
and the S3b placement. Those corrections are folded in below.

## S1 — the health check cannot see the enforcement layer (their §1, medium) — BUILD, revised first

**Verified.** `hooks/local/fusebase-flow-health-check.sh:271-298` keys on exactly two facts: the count
of expected event keys, and whether `hooks/handlers/stop.py` appears in the Stop chain. `PreToolUse`
is never inspected. The final `else` reports "Flow lifecycle hooks not wired (opt-in default)" as
`LOCAL_OK`.

So a tree where the CLI rewrote `.claude/settings.json` and stripped **everything** is
indistinguishable from a tree that never opted in. Their observation stands: the same ✓ printed
minutes after they found enforcement stripped, and again after they restored it.

Their point about blast radius is the one that matters: `/fusebase-health` is the command a consumer
is told to run to answer *"did the update break anything?"*, and it answers yes-only-for-content —
skills, agents, overlays — while the runtime enforcement layer (FR-06/07/12) can be absent.

Partial stripping **is** already caught: if `stop.py` survives but events are incomplete, the third
branch records drift. The blind spot is specifically *everything gone at once*, which is what a
wholesale CLI regeneration produces — four times in their history.

### The opt-in signal: a dedicated intent marker (review ruling — reverses the earlier draft)

The earlier draft recommended reusing the presence of `state/audit/cli-stop-baseline.json` (written by
`hooks/local/post-fusebase-update.sh:335-344` on every `--wire-hooks` run) as the opt-in signal, on a
zero-new-artifacts argument. The review rejects that, and the rejection is adopted:

- It couples unrelated lifecycles: replacing or removing the Stop-diff mechanism would silently
  disable the new PreToolUse arm.
- A future writer could create the baseline for diagnostics without opting into `PreToolUse`.
- "Any file exists at this path" provides no schema and no corruption handling.

One extra gitignored file costs less than a silently incorrect cross-contract a year from now.

**Build instead:** a dedicated, schema-validated intent marker — `state/audit/flow-hook-wiring-intent.json` —
carrying a schema version and an explicit `enabled` state. It is:

- written only after a **successful** `--wire-hooks` (never on a failed or aborted merge);
- gitignored, like the rest of `state/audit` — a fresh clone has not opted in;
- paired with a supported opt-out/reset path that clears it or flips `enabled` — intent must have a
  revocation lifecycle, not just a creation event.

The three-row contract, restated over the marker:

| Marker | `PreToolUse` Flow handler in chain | Verdict |
|---|---|---|
| valid, `enabled` | present | ✓ wired |
| valid, `enabled` | **absent** | **DRIFT** — name it as the 379 breach class |
| absent, or `enabled: false` | either | today's opt-in-default line, unchanged |

**"Present" means the canonical handler, not the event key.** Matching only the `"PreToolUse":` key
does not prove Flow enforcement is wired — the check must match the canonical Flow handler command
within the chain. The exact canonical literal is **UNVERIFIED** (the review could not confirm it under
its file-read cap); the implementer must establish it before building the match.

### The six states where the marker can lie — each with required handling

1. **Deliberate opt-out:** enabled marker remains, block intentionally removed → FALSE drift unless
   there is an explicit opt-out lifecycle. Hence the required opt-out/reset path above.
2. **Legitimate settings replacement:** replacement is correctly drift only if enabled intent remains
   authoritative; if the replacement *meant* opt-out it is a false alarm. File replacement alone
   cannot communicate intent — the opt-out path is the only channel for it.
3. **Archive/zip copy:** `state/audit` is gitignored, but archives carry it; a copied tree can
   inherit another checkout's intent. Frequency: UNVERIFIED. The contract must define copied-state
   semantics or provide an acknowledgement/reset operation.
4. **Invalid or empty marker:** presence alone must NOT imply opt-in. Parse and validate; a malformed
   marker produces `UNVERIFIED`/`BROKEN`, never enforcement drift.
5. **Missing `.claude/settings.json` entirely:** the current arm has no `else` outside the
   file-exists condition (`fusebase-flow-health-check.sh:269`). The spec requires: enabled marker +
   missing settings = **DRIFT**.
6. **Wrong `PreToolUse`:** the event key exists but the chain does not contain the canonical Flow
   handler — must be treated as not wired (drift when the marker is enabled), per the match rule
   above.

### Recovery — detection must carry it

Detection-without-restoration is the legitimate contract here: the health engine is deliberately
read-only and never repairs; it offers recovery for the agent to run after operator approval.
Auto-restoring opt-in hooks inside health would be the wrong contract.

But the new drift MUST recommend the effective recovery command **including `--wire-hooks`**, because
the default recovery explicitly does not modify settings (`post-fusebase-update.sh:319`). Without
that, S1 merely relocates the forensics. The new check also gets a **stable check ID** of its own and
**exits 1** on drift.

**Honest limit to record:** when `python3` is unavailable the merge never runs, so no marker is
written even though an operator may have wired hooks manually via
`cp .claude/settings.json.example`. Marker-absence therefore means *"not known to have opted in"*,
not *"definitely never opted in"* — which is exactly why the third row must stay at today's behaviour
rather than becoming drift. This manual-copy false negative is unavoidable without a separate
acknowledgement path.

## S2 — design constraint, no code (their §2) — NO BUILD, keep as design constraint

Record, so it is not built wrong: **a SessionStart assertion wired into `.claude/settings.json`
cannot report its own absence**, because it is deleted by the same CLI rewrite that deletes
`PreToolUse`. Any check covering the update→recovery window must live on a surface the CLI does not
regenerate, or be the S1 marker + health arm pair.

They reached this by adversarially reviewing their own proposed fix and nearly filed the
self-deleting version. Recording it costs nothing and prevents a whole wrong implementation.

## S3a — stamp-time byte-compliance guard (their §3.1) — BUILD, as a guard, not a warning

The stamp is a pure function of covered-file bytes, and nothing checks those bytes are the canonical
LF form before attesting them. The earlier draft asked for one warning line; the review corrects
that: **a warning that still writes a knowingly non-canonical attestation is observability, not a
guard.**

**Build:** if a covered text file violates its resolved `eol=lf` attribute, the stamper emits the
diagnostic (*"N covered file(s) hold CRLF bytes contrary to .gitattributes"*), **returns non-zero,
and does NOT rewrite the manifest.** The wrong baseline is never created.

**This repo is independent evidence for the same class, four occurrences in two days:** the
cli-vendor manifests, `check-vendored-rendered.sh`, the annotated-tag target, and
`policies/module-size-baseline.txt` — which hashed as CRLF, shipped as LF, and reddened CI twice
because the stamper and verifier both read the same wrong local bytes and agreed. Two unrelated
consumers converging on one mechanism, with forensics on both sides, is the strongest signal this
ticket carries.

**Scope limit, stated explicitly:** S3a closes only the proven CRLF subclass. The parked
`stamper-hashes-worktree-not-artifact` ticket stays open — S3a does not settle the
committed-bytes-vs-worktree-bytes trade-off (which trades away local-tamper detection), and must not
be read as solving filters/smudge/case-folding.

## S3b — drift attribution (their §3.2) — DO NOT BUILD in default verify; optional diagnostics only

`DRIFT` names files; the operator reconstructs *why* by hand. The forensic value is real: their 9
modified files spanned attribution across **five** later commits rather than the one assumed, and 2
files had **no post-stamp commit at all** because the manifest had recorded CRLF bytes — the
distinction between a correct hold and a wrong re-stamp.

But it does not belong in default `verify`. `verify` is a deterministic membership/hash check with a
stable four-exit contract consumed by health, preflight, CI, and upgrade gates. Git history is
read-only, so S3b breaks no mutation contract — what it changes is dependency, cost, and failure
semantics:

- non-Git trees currently fall back and can still verify bytes;
- shallow history makes *"no post-stamp commit"* FALSE;
- an uncommitted manifest makes the *"last commit touching the manifest"* anchor wrong;
- one `git log` per drifted file scales badly.

**Respec as optional diagnostics:** behind `verify --explain`, a standalone drift-diagnostic command,
or a health recommendation offered after DRIFT. Requirements wherever it lands:

- batch all drifted paths into **one** history query;
- **never** change the integrity verdict or exit code when attribution is unavailable;
- **never** emit *"byte-level divergence"* unless the manifest is tracked and clean, the anchor
  commit exists, and history is known complete (not shallow).

## S4 — data only, no code (their §4) — dated backlog update

Refresh the parked `compat-approval-surfacing` backlog entry with a **dated snapshot — measured
2026-08-17**, not a timeless current state: 71 → **61** unexpired `production_deploy` artifacts as of
that date (**98 total**, kept distinct; all 61 lack both `command_digest` and `repo_id`; 29 lack a
body `action`; zero carry `schema_version: 2`; latest expiry 2026-09-01). The 61 decays as artifacts
expire; the snapshot date is what keeps the number honest.

Their sharpening is the part to record alongside it: **expiry-bearing artifacts age out; expiry-less
ones never do.** An aged tree's accepted-artifact population therefore converges on exactly the set
the compat default accepts forever — so a reporter scoped to *"what a strict cutover rejects"* (the
`--inventory` framing) reports a shrinking, self-resolving set while missing the permanent one. The
carrier table needs its recorded-bindings column *more* as a tree ages, not less.

## S5 — the v4.7.0 notes contradiction (their §5, one text fix) — BUILD

**Verified.** `docs/release-notes/v4.7.0.md:60` says *"Use the 4.7.0 `bootstrap-upgrade.sh`, not the
copy already installed in your repo"* and `:65` then prints
`bash hooks/local/bootstrap-upgrade.sh -- --auto-yes` — the installed path. A consumer pasting the
block runs the copy the caveat warns against.

Still open from their 2026-07-30 §3. The M19 recovery-hint fix does not cover this instance. The
exact replacement command/path is **UNVERIFIED** — the implementer must establish it before editing
the notes.

## Acceptance tests (S1 marker + health arm)

The implementation is not done until these scenarios are exercised:

1. **Enable:** successful `--wire-hooks` → valid enabled marker written; health reports ✓ wired.
2. **Wholesale strip:** enabled marker + `PreToolUse` Flow handler absent → DRIFT, stable check ID,
   exit 1, recovery recommendation includes `--wire-hooks`.
3. **Deliberate opt-out:** opt-out/reset path run → marker cleared or `enabled: false`; no drift.
4. **Malformed marker:** invalid/empty JSON → `UNVERIFIED`/`BROKEN`, never enforcement drift.
5. **Missing settings:** enabled marker + no `.claude/settings.json` → DRIFT.
6. **Manual wiring (no marker):** hooks wired via `cp` without the merge → today's opt-in-default
   line (the recorded false negative, not drift).
7. **Legacy no-marker trees:** pre-marker checkouts with any settings state → today's behaviour,
   unchanged.

Also required before build: S3a's failure/no-write contract and attribute-resolution rules must be
specified; S3b's anchor validity, shallow/non-Git degradation, timeout budget, and unchanged
exit-code contract must be specified.

## Standing risk — the wasted-work prediction

Recorded from the review as the most likely wasted-work outcome: **S3b is removed within three
months** if built into the critical verifier — one atypical consumer's forensics placed in a critical
path, producing unreliable attribution in shallow/non-Git trees and maintenance cost without measured
ordinary-consumer demand. This is the reason S3b moves behind a flag rather than into default
`verify`.

## Slice calls

| Slice | Call |
|---|---|
| S1 | **BUILD** — revised first (dedicated marker, six lying states, recovery + check ID + exit 1) |
| S2 | **NO BUILD** — keep as design constraint |
| S3a | **BUILD** — fail/no-write guard, not warning-only |
| S3b | **DO NOT BUILD in default verify** — redesign as optional diagnostics |
| S4 | **NO CODE** — dated backlog update (2026-08-17 snapshot) |
| S5 | **BUILD** — text correction; exact replacement command/path UNVERIFIED, implementer establishes it |

## Explicitly NOT doing

| Not doing | Why |
|---|---|
| Re-litigating 379's "restore, don't report" ask | they explicitly scope it out; this is the detection half |
| Changing opt-in hook wiring as the default | their ask preserves it; the marker only separates never-opted-in from opted-in-then-stripped |
| Treating their CRLF bytes as an upstream bug | they state plainly the wrong bytes are on their disk; the ask is for tooling to *say so* |
| Deciding `stamper-hashes-worktree-not-artifact` | S3a guards only the CRLF subclass, not the hashing decision; that ticket stays open |
| Auto-repair inside health | the health engine is read-only by contract; it recommends, the agent runs recovery after operator approval |

## Surface classification

All internal — operator and agent facing. The interface changed is the `/fusebase-health` report and
the stamp/verify output; the design constraint is legibility and actionability, not visual design.
