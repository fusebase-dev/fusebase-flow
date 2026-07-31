# Active handoff — v4.7.0 unpublished; one design decision blocks it

**Updated:** 2026-07-31 (rev 2 — M13 implemented, M14 refuted) · **Branch:** `fix/msys-v3307-hardening` · **HEAD:** `d44618f` · **VERSION:** 4.7.0
**Stopped by rule, not by defect count.** Four review rounds this session, ten across the ticket. Round 4 returned NO-SHIP and the hard stop was honored — **do not start a round 5.**

## State — nothing shipped, nothing to undo

| | |
|---|---|
| `origin/main` | `85b97dd` — untouched, CI green |
| Tag `v4.7.0` | `b11c60d` — **not** moved; no GitHub Release (404) |
| Local | `d44618f`, tree clean, 48 commits unpushed |
| Gates at `d44618f` | Windows **732/732**, Linux `ubuntu:24.04` **729/729**, both `GATE_ALL_GREEN`, manifests MATCH, module-size clean |
| FR-07 | empty diff across `dea4445..d44618f` on every protected path |
| Operator DP.6 | `approve deploy now` given 2026-07-30, **conditioned on a SHIP verdict — never became live, still unused** |

## STATUS: M13 implemented and gated; M14 REFUTED — operator decision needed

`0f50c05` unlocked M14. The membership rule permits a **pre-authorization downgrade**: "neither artifact present = not carried" cannot be distinguished from "both artifacts were removed before authorization", so a layer leaves the bound set with no race. Review classification: **(b) the contract is wrong**, not a coding defect — so per the stop rule it returns here rather than into another implementation pass.

**The fix direction is known:** derive bound-set membership from an anchor the consumer tree does not control — the verified upstream tree's own coverage list (it already states which layers should exist), or an install/upgrade record of which layers were written. Then *never carried* and *both removed* become distinguishable. **Do not re-lock M14 without that anchor.**

M13's core (bind at authorization, no mid-run shrink, `rc == 0` AND exact `MATCH`, empty set refused) reviewed as **mostly correct** and is implemented at `1712e8e`. Gates at `257439a`: Windows **737/737**, Linux **734/734**, 0 FAIL. M15 (900s bound) stands but the reviewer notes 542s of whole-tree copying is a real performance residual worth optimizing, and a longer bound increases hang-detection latency.

## Superseded — the original three options



**What does "repair confirmed" mean when the consumer may not carry every manifest layer?**

Three options, and they are three different products — not three spellings of one check:

| | Option | Consequence |
|---|---|---|
| a | Require both manifest layers unconditionally; fail otherwise | Strictest; breaks installs that legitimately lack a layer |
| b *(recommended)* | Bind the required manifest set at authorization time so it cannot shrink mid-run, and require `rc == 0` **and** parsed verdict `== MATCH` | Small, closes both live blockers, preserves the old loop's guarantee |
| c | Narrow repair's claim to "the named paths were replaced from verified bytes"; stop asserting whole-tree cleanliness | Honest and simplest; weaker promise |

Plus, independent of a/b/c: **disclose plain-source trust explicitly.** `docs/release-notes/v4.7.0.md:127` claims a re-stamped manifest aborts for any manifest-bearing source. True for **git** transport (canonical tree comes from committed objects); **false for a plain `--source` directory**, where snapshot, payload, verifier and manifest share one authority and can be self-consistent.

## The three round-4 blockers (all in `bootstrap-upgrade.sh:248-268` + one release-note paragraph)

1. **`ff_boot_repair_verify` never captures the verifier's exit code** — `out="$(ff_boot_py …)"` with no `rc=$?`, so it returns 0 on a parsed `MATCH` regardless of rc. `ff_boot_verify` and `_ff_mms_verify` both require rc 0 **and** exact MATCH. `:262-268`
2. **Layer-skip keyed on the wrong artifact.** The skip is keyed on the *manifest*; the old loop keyed on the *wrapper script*. Delete `audit/managed-content-manifest.json` → the check is skipped, unrelated drift stays invisible, repair exits 0. The old loop would have returned rc 4. The hook manifest is anchored by being managed content; the managed-content manifest has **no reciprocal anchor**, so the justification only holds one way. `:248-251`
3. Release-note overclaim above.

Neither 1 nor 2 is a live exploit today — the verifier is the proven canonical module and does not print MATCH-then-fail — but both are contract violations in a security check, and 2 regresses a behaviour that was claimed preserved.

## Why this stopped rather than continued

Rounds 2, 3 and 4 each found defects **in the previous round's fix**, not new layers of the original problem. Round 4's reviewer calls the architecture coherent — one materialization boundary, verifier from the proven tree, isolated interpreters, exact verdict parsers, capability branch, binary-safe comparator — and the remaining items "localized inconsistencies."

That read of the code is probably right. What failed is the *process* of closing them unsupervised at the end of a long release run. The PO overrode the three-round breaker on a convergence argument that was then falsified. **Do not re-run that reasoning.** Disposition the contract above first; then one implementation pass against a decided contract, then one review.

## Landed this session — 9 commits, all gated, each with a RED-at-baseline discriminator

`3f429e0` B5 startup-file forgery · `0f1ac51` B6 unmanifested inputs · `bbb58d3` TOCTOU disclosure · `081238a` FF_TAGS · `2121489` B5c `sys.path[0]` module shadow + exact-MATCH · `f676f94` B7 binary-safe comparator · `490e569` manifest-bearing scoping · `5e9cbab` B8 post-repair verdict · `d44618f` scope corrections

## Constraints (unchanged, all still binding)

Never `--no-verify`. FR-07 protected = `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` only. Locked: M2 byte-exact hashers, M3 tempfile capture, `.gitattributes`, `templates/**`, the FR-06 deny. Linux parity is mandatory before any release claim. Before diagnosing a timing FAIL, run `ps -W | grep run-tests` — a competing suite on this host has caused that once.

## Release sequence once the contract is decided and green

Restamp both manifests → unscoped Windows + Linux container → one review → `git push origin HEAD:refs/heads/main` → `git push origin :refs/tags/v4.7.0` → re-tag → `git push origin v4.7.0`. Publish is `needs: verify`, so a red suite cannot release. Push permissions already in `.claude/settings.local.json`. **The operator must re-authorize** — the prior DP.6 was consumed by a NO-SHIP outcome.

Release notes must carry: the moved-tag notice (`git fetch --force --tags origin`), the F7 limitation with `git commit -F` as the sanctioned path, that downgrading from 4.7.0 restores the replayable gate, and the plain-source trust disclosure above.

## Filed, deferred

`docs/backlog/`: `command-gate-shell-evasion` (F7 parser) · `approval-single-use-consumption` · `approval-binding-omits-head` · `rm-rule-pattern-single-space-gap` · `provenance-and-single-seam-guarantees`.
Follow-up: `hooks/tests/run-tests.sh:342` — `run_exitcode_phase` never sets `FFHC_HEARTBEAT_LABEL`, so a stuck phase is misnamed during an FR-27 hang.
Reviews: `c:/tmp/ffrev7/r.md`, `r2.md`, `r3.md`, `r4.md`; earlier rounds in `docs/tmp/handoff/2026-07-2[89]-*`, `2026-07-3[01]-*`.
