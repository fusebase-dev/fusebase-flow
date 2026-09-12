# Maintainer testing

Test behavior at the smallest useful boundary: table/parser or function first, then a tiny filesystem/Git repository, then an integrated scenario only when the changed boundary requires it. Use a full disposable app or real CLI cycle only when an integration boundary changes or compatibility evidence is missing, never as routine feedback for every edit. Destructive recovery scenarios use the smallest isolated temporary repository, verify the mutation root, and leave the consumer tree and maintainer worktree clean. Do not copy the full repository or launch recovery to test a string predicate. Use existing fixtures and runners before creating another harness.

## Required guarantees

| Guarantee | Required coverage |
|---|---|
| Install and distribution | Preflight, manifests, mirror parity, command/provider delivery and actual installer scenarios |
| Ownership and upgrade | Merge/classification, source/path boundaries, user/CLI byte preservation and supported upgrade paths |
| Recovery | Prior intent/opt-out, invalid-input zero writes, interrupted-write partial status, retry convergence and no-op |
| Executable safety | Secret scan, protected paths, approval/trusted-enforcer cases, real Git hook allow/deny/failure paths |
| Process lifecycle | Failure/timeout propagation, owned-child cleanup, zero-result refusal and selector completeness |
| Publication | Parsed workflow graph, both platforms, required-job success, manifests and tag/verified-SHA binding |

`hooks/tests/run-tests.sh` owns membership and `FF_LIST=1` lists it. `FF_RELEASE=1` selects an explicit 40-tag release allowlist; a newly registered phase stays out until its consumer or safety responsibility is reviewed and deliberately added. Do that review in the outcome that adds or changes the phase: an essential consumer or safety contract enters the allowlist, an excluded diagnostic gets a brief reason in the table below, and registration alone leaves the outcome incomplete. `FF_FULL=1` runs every non-opt-in diagnostic, while `FF_ONLY` names affected groups. Neither local mode authorizes publication.

That last sentence is now a control, not prose: preflight §11 (`hooks/local/lib/phase_registry_check.py`) rejects any `FF_TAGS` phase that is not classified in exactly one of the three tables below, any release/exclusions table row that disagrees with `FF_RELEASE_TAGS`/`FF_OPTIN_TAGS` in either direction, any row naming a tag that no longer exists, and an `unreviewed` count that differs from `FF_UNREVIEWED_BASELINE` in either direction (above: a new phase was parked; below: a reviewed row did not lower the constant in the same commit). It runs in the preflight step of both workflows and is selected by no `FF_` profile.

| Release responsibility | Existing required tags |
|---|---|
| CLI/user ownership and recovery intent, paths, partial state, receipts and no-op | `baseline-merge`, `hook-wiring-intent`, `wire-hooks-beside`, `bootstrap-baseline-hop`, `cli-0259`, `cli-flow-recovery`, `cli-flow-recovery-selectors` |
| Install, upgrade and provider delivery | `bootstrap-exception`, `upgrade-classify`, `upgrade-classify-eol`, `upgrade-boundary`, `upgrade-repair`, `n5-delivery`, `n6-truthful-base`, `n6-missing-base`, `n6-recover`, `cli-rendered` |
| Executable safety | `fixtures`, `git-smoke`, `interpreter-contract`, `python3-version`, `git-context`, `secret-scan-staged`, `trusted-enforcer`, `hook-install-rc`, `approval-binding`, `approval-writer`, `approval-schema3`, `command-policy` |
| Validator execution | `validator-evidence`, `validation-instructions` |
| Publication integrity | `release-authority`, `release-tag-binding` |
| Caller-summary truthfulness and publisher scoping | `hop-log-truth`, `n4-parity-scope` |
| Test-harness fidelity (a suite must exercise its own subject on both platforms) | `minimal-path-fixture` |
| Consumer-facing stamper and recovery-hint honesty | `stamp-eol-guard`, `recovery-hint` |
| Harness liveness — no command substitution may capture a git/hook process tree, and a block must be bounded at its own operation | `git-capture-guard` |
| Runner invocation preconditions — refused with rc 2 before any phase runs, and never in hosted CI | `run-preconditions` |

The reusable workflow separately requires the UNSCOPED `test-ff-only.sh` suite plus preflight, runner parity, both manifests, module size, mirror parity, public-surface allowlisting and a clean tree. That suite rejects phase failures, timeouts, missing phases, unauthorized `N/A` and zero-result success, AND asserts this allowlist's size and boundary tags. It runs as its own step, never inside `FF_RELEASE=1`: it drives the runner with `FF_ONLY`/`FF_FULL`, which the runner refuses to combine with `FF_RELEASE` (rc 2), so `ff-only` must stay OUT of the allowlist. Keeping it a separate step is also what makes the membership ratchet non-self-referential — dropping a tag cannot switch off the assertion that would have caught it. Full and change-scoped diagnostics remain callable; release selection does not delete or weaken them.

## Registered, not in the release profile

Every registered phase that is neither in `FF_RELEASE_TAGS` nor an opt-in diagnostic states its route here. `step-gated` names the `fusebase-flow-verify.yml` step that runs it outside `FF_RELEASE=1` (the step name is verified literally; that is the whole depth of step verification). `deferred` names the measurement that bought the deferral. `unreviewed (pre-ratchet, <date>)` is the seeded legacy backlog: the count may only shrink, the commit that reviews a row lowers `FF_UNREVIEWED_BASELINE` to match, and a NEW phase can never be parked here. Reviewing these rows is a separate outcome — each promotion carries an MSYS cost (`docs/backlog/gate-bounds-lack-headroom/`).

| Tag | Classification | Reason |
|---|---|---|
| `ff-only` | step-gated — `Runner selection, failure, timeout, zero-result and release-membership contracts` | Drives the runner with `FF_ONLY`/`FF_FULL`, which the runner refuses to combine with `FF_RELEASE` (rc 2); membership would redden it |
| `module-size` | step-gated — `Module-size ratchet (FR-25, full scan vs committed baseline)` | Self-test of the FR-25 checker that step runs with `--all` |
| `hook-manifest` | step-gated — `Hook-layer manifest freshness` | Self-test of the stamper/verifier pair that step runs |
| `fingerprint-rows` | step-gated — `Preflight (structure + YAML + frontmatter + mirror drift + action-name consistency)` | Self-test of preflight §10, which that step runs against the real tag history |
| `preboundary-consumed` | deferred | Green on both platforms but measured 204 s on MSYS (13 `bootstrap-upgrade.sh` engine hops across 9 fixture trees) against 5-56 s for every phase promoted in v4.16.3. Excluded on cost, not on coverage; reopen with the operator if the MSYS leg gains headroom |
| `approval-receipt` | unreviewed (pre-ratchet, 2026-09-10) | Approval-receipt durability; sits under the Executable safety guarantee — triage first |
| `boot-size` | unreviewed (pre-ratchet, 2026-09-10) | Structural/size assertions on the session boot surface |
| `cli-vendor` | unreviewed (pre-ratchet, 2026-09-10) | Vendored CLI asset refresh; sits under Install and distribution (provider delivery) — triage first |
| `cli-version` | unreviewed (pre-ratchet, 2026-09-10) | CLI version gate; sits under Install and distribution (provider delivery) — triage first |
| `codex-parity` | unreviewed (pre-ratchet, 2026-09-10) | Codex prompt/command parity with the canonical commands |
| `codex-plugin` | unreviewed (pre-ratchet, 2026-09-10) | Codex plugin surface manifest |
| `denial-message` | unreviewed (pre-ratchet, 2026-09-10) | Command-policy denial text; sits under the Executable safety guarantee — triage first |
| `fr22-delivery` | unreviewed (pre-ratchet, 2026-09-10) | FR-22 comment-policy delivery guarantee |
| `git-context-mutation` | unreviewed (pre-ratchet, 2026-09-10) | Mutation oracle for `git-context`, which is itself in the release profile |
| `health-check-timeout` | unreviewed (pre-ratchet, 2026-09-10) | Health-check timeout propagation; Process lifecycle row, which has zero release tags |
| `install-doc` | unreviewed (pre-ratchet, 2026-09-10) | Install-doc contract, including the §8 scoped-check-must-narrow lesson |
| `interpreter-mutation` | unreviewed (pre-ratchet, 2026-09-10) | Mutation oracle for `interpreter-contract`, which is itself in the release profile |
| `job-probe` | unreviewed (pre-ratchet, 2026-09-10) | Job-probe honesty; Process lifecycle row, which has zero release tags |
| `lane-router` | unreviewed (pre-ratchet, 2026-09-10) | Lane classification router; reaches only maintainer `Focused contracts (not release evidence)`, which is feedback, not a release route |
| `lane-workflow` | unreviewed (pre-ratchet, 2026-09-10) | Lightweight-lane workflow contract |
| `liveness` | unreviewed (pre-ratchet, 2026-09-10) | FR-27 bounded-run behavior; Process lifecycle row, which has zero release tags |
| `msys-tree-cleanup` | unreviewed (pre-ratchet, 2026-09-10) | Owned-child cleanup on MSYS; covered by nothing in the release gate today |
| `newline-preserve` | unreviewed (pre-ratchet, 2026-09-10) | Newline preservation; reaches only maintainer `Focused contracts (not release evidence)`, and doubles as the cheap deterministic fixture phase |
| `po-investigate` | unreviewed (pre-ratchet, 2026-09-10) | Product-owner investigate contract (editorial instrument) |
| `po-verifiable-boot` | unreviewed (pre-ratchet, 2026-09-10) | Product-owner verifiable-boot contract (editorial instrument) |
| `policy-state` | unreviewed (pre-ratchet, 2026-09-10) | Policy-state preservation across an upgrade |
| `prohibition-residency` | unreviewed (pre-ratchet, 2026-09-10) | Prohibitions must stay resident in skill bodies (editorial instrument) |
| `python3-version-mutation` | unreviewed (pre-ratchet, 2026-09-10) | Mutation oracle for `python3-version`, which is itself in the release profile |
| `signal-reap` | unreviewed (pre-ratchet, 2026-09-10) | Runner signal reaping; RED pre-existing baseline (`launch-window-signal-still-reaps`, red identically at `24cbff3`) — resolve before any promotion |
| `sync-allowlist` | unreviewed (pre-ratchet, 2026-09-10) | Version-string sweep allowlist |
| `token-waste-classify` | unreviewed (pre-ratchet, 2026-09-10) | Token-waste classifier (editorial instrument) |
| `wasted-effort-windowing` | unreviewed (pre-ratchet, 2026-09-10) | Wasted-effort windowing (editorial instrument) |
| `ws5-upgrade` | unreviewed (pre-ratchet, 2026-09-10) | Bounded upgrade WS5; Process lifecycle row, which has zero release tags |

## Diagnostic exclusions

These checks remain available with `FF_ONLY` when their subject changes. They do not add unique runtime protection to every release. This table authorizes the T63 runner classification; no existing supported behavior is removed.

| Tag | Why opt-in | Required protection retained |
|---|---|---|
| `return-budget` | Checks exact editorial wording of delegated response limits | Delivery/preflight and actual hook controls; response-size guidance remains shipped |
| `supersede-primitive` | Searches prose for editing advice and retired phrases | Actual recovery preservation/idempotency tests; editorial review on instruction changes |
| `rule-inventory` | Instrument for deliberate rule-compression comparisons | Boot/delivery/prohibition checks; run inventory explicitly for rule changes |
| `startup-context` | Frozen compression baseline and size comparison | boot-size, prohibition-residency, provider delivery and mirror checks |
| `budget-literals` | Consistency of performance-budget numbers in live prose | boot-size retains the implemented structural/size checks |
| `history-extraction` | One-time migration equivalence against historical Git blobs | Current rule/skill structure and delivery; Git preserves migration history |
| `consumer-benchmark` | Comparative profiling/benchmark output | Actual recovery, ownership, no-op and failure scenarios in cli-flow-recovery |

Exact machine-consumed markers, schema keys and public command names remain valid assertions. Prose synonyms and numbered comments are not executable contracts. `release-authority` validates the parsed job graph; `validation-instructions` exercises configured validator execution instead of matching guidance sentences. Broader validator-evidence tests continue to cover unavailable reuse and failure propagation.

## Execution and completion

Aim for seconds to two minutes in the edit loop and a focused hosted check within ten minutes per platform. These are design targets, not measured guarantees or reasons to skip a critical test. Release checks retain their committed bounds until evidence supports a deliberate redesign.

`approval-schema3` is the most expensive release-profile phase: measured **184-286 s on MSYS** (the spread is concurrent load on the measuring machine; budget the upper figure) and **9-14 s on Linux** (25 rows, each a throwaway repository driven through the real writer, gate, handler and `pre-push` hook; the shared harness lives in `hooks/tests/fixtures/approval_fixture.py`, which the runner's `fixtures/*.json` glob ignores). It is in the profile because it is the only oracle for the FR-12 command-approval contract, but the cost sits beside `preboundary-consumed`, which was excluded at 204 s — reclassify deliberately if the MSYS leg loses headroom (`docs/backlog/gate-bounds-lack-headroom/`).

After a change, run its affected group once. Repeat only after a relevant correction or to investigate a named nondeterministic condition. A failed execution never becomes a passing result because earlier rows passed. Preserve the failing diagnostic, fix its owner and rerun the affected group; do not replay an unrelated successful prefix. Before tagging, run newly promoted phases and changed platform-dependent cases on Linux and MSYS.

Only release CI on the exact tagged SHA authorizes a release claim. Do not run the same unchanged full verification before tagging and again after tagging. The tag-triggered workflow runs the essential profile and package checks once on Linux and Windows/MSYS, then publishes only after the aggregate gate succeeds. Maintainer feedback is a focused subset and cannot authorize publication. No test-result signing/cache system is needed; a normal run records its source, platform, command, result and log pointer.

In this repository the runner rejects local `FF_FULL`/`FF_RELEASE` without a nonempty `FF_EVIDENCE_GAP`; hosted CI, including the release gate, is exempt, and a consumer tree without this file never sees the check. The gap names why affected groups cannot answer the question. The runner prints the reason but cannot judge it: the guard makes expansion deliberate, not justified.
