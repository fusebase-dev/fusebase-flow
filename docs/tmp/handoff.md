# Active handoff — v4.7.0 unpublished; M16 implemented and gated, one threat-model decision blocks it

**Updated:** 2026-08-02 (rev 3 — M16 locked + implemented + gated; review 5 = NO-SHIP on source authority) · **Branch:** `fix/msys-v3307-hardening` · **HEAD:** `3557b66` · **VERSION:** 4.7.0
**Stopped by rule, not by defect count.** Five review rounds this session. Round 5 returned NO-SHIP with one **(b)** — **do not start a round 6 implementation pass.**

## State — nothing shipped, nothing to undo

| | |
|---|---|
| `origin/main` | `85b97dd` — untouched, CI green |
| Tag `v4.7.0` | `b11c60d` — **not** moved; no GitHub Release (404) |
| Local | `3557b66`, tree clean, 51 commits unpushed |
| Gate at `3557b66` | Windows unscoped **739/739 PASS, 0 FAIL** (baseline 737 + the 2 new M16 cases) |
| Linux parity | **NOT RUN** at this HEAD — the review returned NO-SHIP first. Required before any release claim |
| FR-07 | empty diff `2d88844..3557b66` on `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` |
| Operator DP.6 | never consumed — the 2026-07-30 phrase was conditioned on a SHIP verdict |

## STATUS: M16 is implemented and green; the reviewer rejects its *premise*, not its code

`1d1a2f9` locks **M16**: repair bound-set membership is read from the VERIFIED SOURCE tree's coverage (`$SOURCE_TREE/<manifest-rel>`), never from the tree being repaired; a declared layer whose consumer manifest — or whose wrapper the source ships — is missing is a FAILURE, not a skip. `54ba8bb` implements it with two RED-at-`2d88844` discriminators. The M14 pre-authorization downgrade is closed: deleting both managed-layer artifacts no longer drops the layer.

**Round-5 blocker (b): "outside consumer control" is not established for `$SOURCE_TREE` itself.** The anchor is `.fusebase-flow-source` — reused if present (`bootstrap-upgrade.sh:92`), ref-resolved local-first (`materialize-managed-source.sh:56-58`), verified against its own shipped manifest. An actor who can delete files in the consumer root can generally also commit into that staging repo and move its ref, producing a self-consistent tree that *declares fewer layers*. `git archive <oid>` defeats worktree tampering, not authorship. So M16 relocates the downgrade from the consumer root to the staging repo; it does not eliminate it.

**The decision this needs — the threat model for `--repair-managed`, not another anchor:**

| | Option | Consequence |
|---|---|---|
| a | Same-principal assumption (already documented for the pre-boundary route): staging dir, hop and engine share one principal | M16 stands as-is; fix the *wording* ("outside the repaired tree's control", not "outside consumer control") + the four (a)s. M16 is still strictly stronger than M14: a downgrade now costs authoring a self-consistent source tree instead of deleting two files |
| b | Adversary-in-workspace: the staging directory is untrusted | Repair must anchor on an authority outside the workspace — fetch the version's tree from `--repo`/a tag, or verify a signature. That is a new capability with its own ticket, not a patch |

Do not pick this inside an implementation pass. It is the same class of question M13/M14/M16 kept re-answering.

## The four (a) defects (finite; fix only after the (b) is decided)

1. **Layer-artifact symlink substitution.** `[ -f ]` and both hashers follow symlinks, so a consumer manifest/wrapper symlinked to byte-matching files in the staging source satisfies presence + hash. R2's symlink refusal covers repair *targets*, not the post-repair layer artifacts. Needs a discriminator.
2. **The recovery instruction is impossible for the manifest case.** `ff_boot_repair_verify` tells the operator to name the missing artifact in `--repair-managed`, but repair only authorizes verifier-*reported* paths; an absent `audit/managed-content-manifest.json` makes its own verifier return `ABSENT` with an empty file list and nothing else covers `audit/`, so naming it hits `REFUSED: not reported as drifted`. (The *wrapper* case does work in a real tree — `hooks/local/*.sh` is hook-layer content.) Confirmed independently, not just reviewer-asserted. Same overclaim in `docs/release-notes/v4.7.0.md`.
3. **"Before any repository write" is still literally false.** The bind now precedes `.git/info/exclude` (`bootstrap-upgrade.sh:427` vs `:441`), but a repair invoked with no staging directory clones into `$ROOT/.fusebase-flow-source` first (`:100`,`:107`). Either bind before that clone or narrow the contract wording in M13/M16 + release notes.
4. **"Unreachable-by-construction" overclaims.** `VERIFIED ⇒ source manifest exists` holds at verification time, but `$SOURCE_TREE` stays mutable until the bind, so the empty-set branch is fail-closed rather than unreachable. Also: `test-upgrade-repair-managed.sh` 3h-4's "only the attribution is new" comment is stale w.r.t. this delta.

Reviewer also flags the new M16 comment block (`bootstrap-upgrade.sh:240`) as FR-22-long — non-blocking.

## Landed this session — 3 commits

`1d1a2f9` decisions: M16 LOCKED, M14 SUPERSEDED · `54ba8bb` T1 M16 implementation + 2 REDs + both manifests restamped · `3557b66` release-note bullet restated

RED-at-`2d88844` evidence (observed, not asserted): `m16-removing-both-artifacts-before-authorization-cannot-drop-a-source-declared-layer` and `m16-a-wrapper-the-source-ships-is-required-even-when-the-consumer-manifest-verifies` both FAILed at baseline with the log line `repair layer NOT carried by this install`, both PASS at HEAD. Two further cases are labelled COVERAGE (already held at baseline); AC3 stays green *by design* — its source declares only the managed layer and ships no wrapper.

## Constraints (unchanged, all still binding)

Never `--no-verify`. FR-07 protected = `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` only. Locked: M2 byte-exact hashers, M3 tempfile capture, `.gitattributes`, `templates/**`, the FR-06 deny. Linux parity is mandatory before any release claim. Before diagnosing a timing FAIL, run `ps -W | grep run-tests`. The unscoped Windows suite needs **>40 min** — bound any wrapper timeout at ≥5400s (a 2400s bound killed one run mid-phase). `run-tests.sh:342` still misnames the running phase during a bounded wait (`cli-flow-recovery` appears as `upgrade-repair`).

## Release sequence once the (b) is decided and both platforms are green

Restamp both manifests → unscoped Windows + Linux `ubuntu:24.04` container → one review → DP.1 mint → `git push origin HEAD:refs/heads/main` → `git push origin :refs/tags/v4.7.0` → re-tag → `git push origin v4.7.0` → watch verify+publish via the public REST API (`gh` is not installed) → FR-14 single docs commit. Publish is `needs: verify`, so a red suite cannot release. **The operator must re-authorize** — no prior DP.6 survives a NO-SHIP.

Release notes must carry: the moved-tag notice (`git fetch --force --tags origin`), the F7 limitation with `git commit -F` as the sanctioned path, that downgrading from 4.7.0 restores the replayable gate, and the plain-source trust disclosure.

## Filed, deferred

`docs/backlog/`: `command-gate-shell-evasion` (F7 parser) · `approval-single-use-consumption` · `approval-binding-omits-head` · `rm-rule-pattern-single-space-gap` · `provenance-and-single-seam-guarantees`.
Reviews: `c:/tmp/m16-review.md` (round 5) · `c:/tmp/ffrev7/r.md`..`r4.md`; earlier rounds in `docs/tmp/handoff/2026-07-2[89]-*`, `2026-07-3[01]-*`.
