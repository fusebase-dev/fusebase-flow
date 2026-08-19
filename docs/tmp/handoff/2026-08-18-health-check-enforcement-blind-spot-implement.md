# AI Developer handoff — health-check enforcement blind spot + stamp guard

**Spec (authoritative — read it first, it carries the review corrections):** `docs/specs/health-check-enforcement-blind-spot/spec.md`
**Consumer escalation:** `c:/Users/Pavel/projects/paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-08-17-health-check-enforcement-blind-spot-and-manifest-stamp-discipline.md`
**Branch:** create `fix/health-check-enforcement-blind-spot` off `main` (`cc30dfc`, v4.11.0 published)

The premise review ran **before** any code this time and changed four of six slices. Its corrections
are already in the spec — build what the spec says, not what the consumer's report says where they
differ.

FR-03: one task = one commit. Stop at the gate (IM.8). Do not push, do not tag, do not bump VERSION.

## Build scope

| Slice | Call |
|---|---|
| S1 — intent marker + health arm | **BUILD FIRST** |
| S3a — stamp-time eol guard | **BUILD** |
| S5 — v4.7.0 notes text fix | **BUILD** |
| S4 — dated backlog snapshot | **DOCS ONLY** |
| S2 — design constraint | already recorded in the spec; no code |
| S3b — drift attribution | **DO NOT BUILD.** File as a backlog entry with the review's requirements and its wasted-work prediction |

## T1 — S1: the intent marker

Do **not** reuse `state/audit/cli-stop-baseline.json`. The review rejected that: it couples unrelated
lifecycles, a future diagnostic writer could create it without opting in, and file-presence carries no
schema or corruption handling.

Build `state/audit/flow-hook-wiring-intent.json` — schema version + explicit `enabled` state, written
only after a **successful** `--wire-hooks` (never on a failed or aborted merge), gitignored like the
rest of `state/audit`, with a supported opt-out/reset path that clears it or flips `enabled`.

**Establish the canonical handler literal before writing the match.** The spec marks it UNVERIFIED
because the reviewer could not confirm it under its file-read cap. Matching `"PreToolUse":` alone does
NOT prove Flow enforcement is wired — read `.claude/settings.json.example` and match the actual Flow
handler command in the chain. Report what you established.

All six lying states in the spec need handling, and two are easy to get wrong:
- **malformed marker → UNVERIFIED/BROKEN, never drift.** Presence alone must not imply opt-in.
- **enabled marker + missing `.claude/settings.json` → DRIFT.** The current arm has no `else` outside
  the file-exists condition (`fusebase-flow-health-check.sh:269`), so this path does not exist today.

The drift must carry a stable check ID, exit 1, and **recommend the effective command including
`--wire-hooks`** — the default recovery explicitly does not modify settings
(`post-fusebase-update.sh:319`). Without that, this ticket only relocates the consumer's forensics.

Health stays read-only and never repairs. Do not auto-restore.

**Acceptance rows (all seven, RED-first where an oracle applies):** enable; wholesale strip; deliberate
opt-out; malformed marker; missing settings; manual wiring with no marker; legacy no-marker tree.

## T2 — S3a: the stamp guard

If a covered text file violates its resolved `eol=lf` attribute, the stamper must emit the diagnostic,
**return non-zero, and NOT rewrite the manifest**. A warning that still writes a knowingly
non-canonical attestation is observability, not a guard.

Specify the attribute-resolution rule you use (`git check-attr`), and scope it to the **proven CRLF
subclass** — this does not settle `stamper-hashes-worktree-not-artifact` (committed bytes vs worktree
bytes), which stays open and undecided because it trades away local-tamper detection.

**This repo is its own test case.** Four occurrences in two days, most recently
`policies/module-size-baseline.txt` — hashed CRLF, shipped LF, reddened CI twice, invisible locally
because stamper and verifier read the same wrong bytes and agreed. Your RED arm can reproduce exactly
that.

## T3 — S5: the notes contradiction

`docs/release-notes/v4.7.0.md:60` warns *"Use the 4.7.0 `bootstrap-upgrade.sh`, not the copy already
installed in your repo"*, and `:65` then prints `bash hooks/local/bootstrap-upgrade.sh -- --auto-yes`
— the installed path. A consumer pasting the block runs the copy the caveat warns against.

The correct replacement command/path is **UNVERIFIED** — establish it from how the release actually
expects adoption to run, and say what you established. Do not guess a path.

## T4 — S4: dated backlog snapshot

Update `compat-approval-surfacing` with the **2026-08-17 measurement**: 61 unexpired
`production_deploy` artifacts (98 total — keep distinct); all 61 lack both `command_digest` and
`repo_id`; 29 lack a body `action`; zero carry `schema_version: 2`; latest expiry 2026-09-01.

Record the dynamics, which is the part that sharpens the parked contract: expiry-bearing artifacts age
out, expiry-less ones never do, so an aged tree's accepted population converges on exactly the set the
compat default accepts forever — and an `--inventory`-style reporter scoped to "what a strict cutover
rejects" reports a shrinking, self-resolving set while missing the permanent one.

Date it explicitly. "61" decays; an undated count reads as timeless and will be wrong within weeks.

## T5 — S3b as a backlog entry, not code

File it with the review's three hard requirements (batch into one history query; never change the
verdict or exit code when attribution is unavailable; never emit "byte-level divergence" unless the
manifest is tracked and clean, the anchor exists, and history is known complete) and its wasted-work
prediction: placed in the critical verifier it gets removed within three months, because attribution
is unreliable on shallow and non-Git trees. Preserve the consumer's forensic evidence — five-commit
attribution, two files with no post-stamp commit — as the case for building it behind a flag later.

## Gate report must include

Per task: SHA, RED-then-GREEN evidence with the actual failing output, the canonical handler literal
you established, the S5 replacement path you established, and preflight + relevant phase results.
Re-stamp manifests LAST. If any acceptance row cannot be made to fail first, say so plainly.
