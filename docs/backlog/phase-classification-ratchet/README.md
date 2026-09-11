# Phase-classification ratchet — every registered phase must name its gating route (phase-classification-ratchet)

**Status:** BUILT and landed on `main` (2026-09-10), one commit, no dedicated tag — effective on the next push through the preflight step of both workflows
**Filed:** 2026-09-10
**One-liner:** Mechanize the sentence `docs/maintainer-testing.md` §16 already states in prose — "registration alone leaves the outcome incomplete" — as a closed-world check in `preflight.sh`: every tag in `FF_TAGS` must be classified in `maintainer-testing.md` (release / step-gated / opt-in / deferred / unreviewed-legacy), the classification must agree with the runner arrays both ways, and the unreviewed-legacy row count may only shrink.

## Decision record (delegated call, 2026-09-10)

**Build it — the narrow form, not the graph audit the review sketched.** The review proposed tracing `registered controls → selected cases and platforms → executable workflow steps → failure propagation → required gate`. Four of those five links already have gating controls: `test-ff-only.sh` (own step in `fusebase-flow-verify.yml`) rejects phase failures, timeouts, missing selected phases, unauthorized `N/A` and zero-result success, and asserts the allowlist's exact size and boundary tags; `release-authority` validates the parsed job graph; `verify-linux` + `verify-windows-msys` + the aggregate gate own platform reachability. The one link with **no** control is the first: a tag can be added to `FF_TAGS` with nobody deciding whether it gates. That is the exact shape of v4.16.0→v4.16.2 (`minimal-path-fixture` existed, gated nowhere, cost a cycle to wire). The T83 ratchet (`release-profile-is-explicit-37-tag-allowlist`) catches a tag being **removed** from the allowlist; nothing catches a tag never being **added or excused**.

**Day-one flag count, measured at `a1961f0` (76 registered / 36 release), not guessed — RE-MEASURED at the landing commit's parent `d7abf49` (77 registered / 37 release / 7 opt-in) and unchanged in substance: `git-capture-guard` was added in v4.16.4 and went straight into `FF_RELEASE_TAGS`, so it moved both totals by one and the unrouted set not at all. Seeded baseline `FF_UNREVIEWED_BASELINE = 28`, i.e. the record's own honest gap of 28, now 28 of 77:**

| Classification | Count | Tags |
|---|---:|---|
| In `FF_RELEASE_TAGS` | 36 | as listed in `maintainer-testing.md` release table |
| Opt-in with a row in the Diagnostic-exclusions table (`FF_OPTIN_TAGS`) | 7 | return-budget, supersede-primitive, rule-inventory, startup-context, budget-literals, history-extraction, consumer-benchmark |
| Phase is a self-test of a checker that gates as its **own** workflow step | 4 | ff-only (own step), module-size (`check-module-size.sh --all` step), hook-manifest (`verify-hook-manifest.sh` step), fingerprint-rows (preflight §10) |
| Deferred on measured cost, documented | 1 | preboundary-consumed |
| Reaches only `fusebase-flow-maintainer.yml` "Focused contracts (not release evidence)" — no release route, no documented reason | 2 | lane-router, newline-preserve |
| **No route and no documented reason** | **26** | liveness, health-check-timeout, msys-tree-cleanup, signal-reap, job-probe, ws5-upgrade, interpreter-mutation, python3-version-mutation, git-context-mutation, cli-version, cli-vendor, codex-parity, codex-plugin, install-doc, policy-state, sync-allowlist, approval-receipt, denial-message, lane-workflow, fr22-delivery, po-verifiable-boot, po-investigate, boot-size, prohibition-residency, token-waste-classify, wasted-effort-windowing |

So the honest gap is **28 of 76**, not "40 ungated": 12 of the difference are step-gated self-tests, documented opt-ins or the documented deferral. Indirect routes were checked and ruled out — every other reference to those 26 scripts from a gated script or workflow is a comment, a shared-library `source`, or a tripwire note, not an invocation (`po-investigate` in `verify.yml:71` is a comment about `fetch-depth`).

**Why 28 is a half-day, not a project:** the ratchet does not require deciding the 28. It requires each to be *listed* with a reason, and the only reason it refuses for a **new** tag is "unreviewed". The 28 legacy rows carry `unreviewed (pre-ratchet, 2026-09-10)` under a shrink-only count baseline — the FR-25 module-size shape this repo already uses. Green on the day it lands; gates the recurring defect (a new control with no decision) from that day; the triage of the 28 is a separate outcome scheduled by responsibility, not folded in here.

**Weighed and rejected as blockers:**

| Argument against | Weight |
|---|---|
| The execution review returned DISPROPORTIONATE; the operator objects to ceremony | This adds **no human step**: no artifact, no ritual, no relay. Registering a phase already requires the decision in prose (§16, written 2026-09-07 in `4c58d4a`); the check replaces remembering it with one table row. A rule that lives only in the doc it protects is a comment, not a control — the project's own catalog principle (`ci-linux-msys-test-divergence` §8) |
| The audit is itself a control — does it gate? | It lives in `hooks/local/preflight.sh`, which is step one of **both** workflows and is selected by no `FF_` profile, so dropping a tag from a profile cannot switch it off (the same non-self-referential argument T83 used for `ff-only`). Its red arm lives in `test-ff-only.sh` (also its own step): mutate a copy of `run-tests.sh`/the doc, prove red, prove the unmutated control is clean |
| Blast radius on day one | 28, seeded as honest legacy rows under a shrink-only baseline; see above |
| FR-03 and v4.16.4 in flight | **Not folded in.** v4.16.4 is the hang fix. This is one commit on `main` after v4.16.4's tag is green; it needs no tag of its own (`PUBLISHING.md` requires a tag for a code fix consumers receive; this is maintainer harness + maintainer doc) and becomes effective on the next push via the maintainer workflow's preflight step |
| The "40 ungated" correction shrinks the value | It shrinks the *triage* (28 rows, of which ~11 are editorial instruments or mutation oracles that will stay out). It does not touch the value, which is the next tag, not the existing 28. Three cycles in one day were lost to this class at tag time after a human waited; the fix is smaller than one of those cycles |

**Explicitly NOT attempted (the review's caveats, kept):** this would not have diagnosed the v4.16.3 hang; it does not judge oracle adequacy; it does not address the other root cause (incomplete family coverage — `git-capture-guard` in v4.16.4 covers one family; the general form is a separate problem); it cannot see a "control" that is neither a registered `FF_TAGS` phase nor a named workflow step (registry-only by design; that boundary is stated, not hidden).

**Second seeding finding (for the triage outcome):** 3 of the 4 `step-gated` rows are checker self-tests — the workflow step runs the CHECKER (`check-module-size.sh --all`, `stamp-hook-manifest.sh`+`verify-hook-manifest.sh`, preflight §10), while the phases `module-size`, `hook-manifest`, `fingerprint-rows` themselves gate nowhere. Only `ff-only` is run by its step. A regression in a self-test (the checker's red arm going vacuous) is therefore unguarded; decide during triage whether each self-test belongs in its step or the release profile.

**Finding surfaced by the seeding pass, not decided here:** the Required-guarantees row "Process lifecycle — failure/timeout propagation, owned-child cleanup, zero-result refusal and selector completeness" has **zero** tags in the release table; `liveness`, `health-check-timeout`, `msys-tree-cleanup`, `signal-reap`, `job-probe`, `ws5-upgrade` are all among the 26. `test-ff-only.sh` covers propagation and zero-result; owned-child cleanup is covered by nothing in the release gate, and `signal-reap` is red pre-existing (its `docs/maintainer-testing.md` row). Likewise `cli-vendor`/`cli-version` (provider delivery) and `approval-receipt`/`denial-message` (executable safety) sit under required-guarantee rows. Triage those first when the 28 are reviewed; each promotion carries an MSYS cost (`gate-bounds-lack-headroom`).

## Operator pain (in their words)

Three release cycles lost in one day (v4.16.0, v4.16.2, v4.16.3) to controls that existed but could not fail the relevant gate, each discovered at tag time by CI after a human waited. "The control existed; it was in no gating profile."

## Why now

`4c58d4a` (2026-09-07) wrote the rule; v4.16.2 and v4.16.3 (T83) then had to wire two controls by hand three days later. The prose rule has already failed to hold once. The next registered phase is the next instance unless the decision is forced at registration.

## As built

| Piece | Path |
|---|---|
| Predicate + `FF_UNREVIEWED_BASELINE` (28) | `hooks/local/lib/phase_registry_check.py` |
| Gate wiring (§11, maintainer trees only, no `FF_` selector) | `hooks/local/preflight.sh` |
| Registry of record — third table `Registered, not in the release profile` | `docs/maintainer-testing.md` |
| Red arm — 12 mutation rows (incl. the below-baseline red/green pair) + 4 wiring/scoping rows + 1 clean-tree control | `hooks/tests/test-ff-only.sh` |

Deviations from the sketch below, all additive: the predicate is a standalone Python module rather than inline bash (the doc-table parse and the malformed-table refusal are not cheap in `case`/`${}`); the exclusions table's Tag column was backticked so all three tables parse by one rule; the red arm is 17 rows, not 3, because each rejected shape needs its own predeclared message; and sketch (e) is enforced in BOTH directions — a count below the baseline is red too, so a reviewed row cannot free a slot a later unreviewed row silently takes (coordinator decision at landing).

## Architectural sketch (rough)

- `docs/maintainer-testing.md` becomes the registry of record: keep the release table and the Diagnostic-exclusions table as they are; add one table **"Registered, not in the release profile"** with columns `Tag | Classification | Reason`, classification ∈ {`step-gated` (names the workflow step), `deferred` (names the measurement), `unreviewed (pre-ratchet, <date>)`}. Move the `preboundary-consumed` paragraph into it as a `deferred` row.
- `hooks/local/preflight.sh` §11, maintainer trees only (both `hooks/tests/run-tests.sh` and `docs/maintainer-testing.md` present; otherwise `note` and skip — never silently disable, see the header lesson in that file): parse `FF_TAGS`, `FF_RELEASE_TAGS`, `FF_OPTIN_TAGS` from the runner and backticked tags per table from the doc; `err` on (a) a tag in `FF_TAGS` absent from all three tables, (b) a release-table tag not in `FF_RELEASE_TAGS` or vice versa, (c) an exclusions-table tag not in `FF_OPTIN_TAGS` or vice versa, (d) a tag in more than one table, (e) `unreviewed` rows > `FF_UNREVIEWED_BASELINE` (constant in the script, seeded 28, lowered only by a reviewer — the ratchet), (f) a table tag not in `FF_TAGS` (stale row).
- `hooks/tests/test-ff-only.sh`: three rows, using its existing patch-a-copy pattern (`OPTINREPO`): add `probe-tag` to `FF_TAGS` of a copy with no doc row → preflight red naming the tag; remove a tag from the copy's release table while it stays in `FF_RELEASE_TAGS` → red; unmutated copy → clean (negative control). Predeclare expected messages; a red that is not the named red is a FAIL.
- `PUBLISHING.md`/`maintainer-testing.md` §16: one sentence each pointing at the check; no new procedure.
- Cost: ~60 lines bash, ~30 doc rows, 3 test rows. Under a second at runtime.

## Acceptance criteria (rough)

1. AC1 — MET. `bash hooks/local/preflight.sh` is rc 0 on the real tree and reports `phase registry: 77 registered, 37 release, 7 opt-in, 28 unreviewed (baseline 28)`; all 77 registered tags appear in exactly one of the three tables.
2. AC2 — Adding a tag to `FF_TAGS` with no doc row makes preflight exit non-zero naming the tag and the table it must join; proven by a `test-ff-only.sh` row against a patched copy, with an unmutated negative control.
3. AC3 — Release-table ↔ `FF_RELEASE_TAGS` and exclusions-table ↔ `FF_OPTIN_TAGS` disagree in either direction → preflight red naming the tag.
4. AC4 — MET, both directions. `unreviewed` rows above `FF_UNREVIEWED_BASELINE` → red; below it → red with the instruction to lower the constant to the new count in the same commit; equal → quiet.
5. AC5 — Both `fusebase-flow-maintainer.yml` and `fusebase-flow-verify.yml` reach the check through their existing preflight step; no new step, no new `FF_` selector, `ff-only` and the check itself stay outside every profile.
6. AC6 — Consumer trees (no `run-tests.sh`) get a `note`, never an `err`, and `install-doc` §8's scoped-check-disabled lesson is not reintroduced.

## Out of scope

- Reviewing or promoting any of the 28 legacy rows (separate outcome; promotions have MSYS cost and belong under `gate-bounds-lack-headroom`'s measurements).
- Workflow-graph or failure-propagation tracing (already gated by `test-ff-only.sh`, `release-authority`, the two platform jobs).
- The family-coverage root cause (shell-syntax capture rules, bounded operation owners, retained-pipe fault injection — the review's 1d list). Separate problem, separate ticket.
- Oracle adequacy, the v4.16.3 hang, `signal-reap`'s red baseline.
- Any change inside v4.16.4.

## Risks / unknowns

- A doc table as a machine-consumed registry is prose-adjacent; the check must match backticked tags exactly and reject a malformed table loudly (a silently empty parse reads as "all classified"). Mutation row AC2 must include a doc with the table heading removed → red.
- Someone classifies a new tag `step-gated` without a real step. The check verifies the named step string exists in `.github/workflows/fusebase-flow-verify.yml` (`grep -F` on the step name); that is the whole depth of step verification, stated as such.
- `unreviewed` becomes a permanent parking lot. The baseline can only shrink and the rows carry a date; that is a visible debt, not a hidden one — the same trade FR-25 made.

## Related

- `docs/maintainer-testing.md` §16 (the prose rule this mechanizes), release table, Diagnostic-exclusions table
- `docs/maintainer-execution.md` — "Apply process simplification here first"; this adds a control, not a step
- `hooks/tests/test-ff-only.sh` `release-profile-is-explicit-37-tag-allowlist` — the sibling ratchet that catches removal but not omission
- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` §8 — "a rule that lives only inside the file it protects is a comment, not a control"
- `docs/problem-catalog/msys-git-command-substitution-hang/problem.md` — the other root cause (family coverage), deliberately not addressed here
- `docs/backlog/gate-bounds-lack-headroom/` — the cost side of any promotion out of the 28
- `docs/maintainer-testing.md` `signal-reap` row — red baseline
- `/c/tmp/ff-blockers-out.md` §2a, §2b, §2d, §3a — the adversarial analysis that proposed the wider audit
