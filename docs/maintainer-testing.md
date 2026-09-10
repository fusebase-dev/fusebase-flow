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

`hooks/tests/run-tests.sh` owns membership and `FF_LIST=1` lists it. `FF_RELEASE=1` selects an explicit 36-tag release allowlist; a newly registered phase stays out until its consumer or safety responsibility is reviewed and deliberately added. Do that review in the outcome that adds or changes the phase: an essential consumer or safety contract enters the allowlist, an excluded diagnostic gets a brief reason in the table below, and registration alone leaves the outcome incomplete. `FF_FULL=1` runs every non-opt-in diagnostic, while `FF_ONLY` names affected groups. Neither local mode authorizes publication.

| Release responsibility | Existing required tags |
|---|---|
| CLI/user ownership and recovery intent, paths, partial state, receipts and no-op | `baseline-merge`, `hook-wiring-intent`, `wire-hooks-beside`, `bootstrap-baseline-hop`, `cli-0259`, `cli-flow-recovery`, `cli-flow-recovery-selectors` |
| Install, upgrade and provider delivery | `bootstrap-exception`, `upgrade-classify`, `upgrade-boundary`, `upgrade-repair`, `n5-delivery`, `n6-truthful-base`, `n6-missing-base`, `n6-recover`, `cli-rendered` |
| Executable safety | `fixtures`, `git-smoke`, `interpreter-contract`, `python3-version`, `git-context`, `secret-scan-staged`, `trusted-enforcer`, `hook-install-rc`, `approval-binding`, `approval-writer`, `command-policy` |
| Validator execution | `validator-evidence`, `validation-instructions` |
| Publication integrity | `release-authority`, `release-tag-binding` |
| Caller-summary truthfulness and publisher scoping | `hop-log-truth`, `n4-parity-scope` |
| Test-harness fidelity (a suite must exercise its own subject on both platforms) | `minimal-path-fixture` |
| Consumer-facing stamper and recovery-hint honesty | `stamp-eol-guard`, `recovery-hint` |

**Deferred, cost-reviewed — not a diagnostic exclusion.** `preboundary-consumed` is green on both platforms but measured 204 s on MSYS (13 `bootstrap-upgrade.sh` engine hops across 9 fixture trees) against 5-56 s for every phase promoted in v4.16.3. Excluded on cost, not on coverage; reopen with the operator if the MSYS leg gains headroom.

The reusable workflow separately requires the UNSCOPED `test-ff-only.sh` suite plus preflight, runner parity, both manifests, module size, mirror parity, public-surface allowlisting and a clean tree. That suite rejects phase failures, timeouts, missing phases, unauthorized `N/A` and zero-result success, AND asserts this allowlist's size and boundary tags. It runs as its own step, never inside `FF_RELEASE=1`: it drives the runner with `FF_ONLY`/`FF_FULL`, which the runner refuses to combine with `FF_RELEASE` (rc 2), so `ff-only` must stay OUT of the allowlist. Keeping it a separate step is also what makes the membership ratchet non-self-referential — dropping a tag cannot switch off the assertion that would have caught it. Full and change-scoped diagnostics remain callable; release selection does not delete or weaken them.

## Diagnostic exclusions

These checks remain available with `FF_ONLY` when their subject changes. They do not add unique runtime protection to every release. This table authorizes the T63 runner classification; no existing supported behavior is removed.

| Tag | Why opt-in | Required protection retained |
|---|---|---|
| return-budget | Checks exact editorial wording of delegated response limits | Delivery/preflight and actual hook controls; response-size guidance remains shipped |
| supersede-primitive | Searches prose for editing advice and retired phrases | Actual recovery preservation/idempotency tests; editorial review on instruction changes |
| rule-inventory | Instrument for deliberate rule-compression comparisons | Boot/delivery/prohibition checks; run inventory explicitly for rule changes |
| startup-context | Frozen compression baseline and size comparison | boot-size, prohibition-residency, provider delivery and mirror checks |
| budget-literals | Consistency of performance-budget numbers in live prose | boot-size retains the implemented structural/size checks |
| history-extraction | One-time migration equivalence against historical Git blobs | Current rule/skill structure and delivery; Git preserves migration history |
| consumer-benchmark | Comparative profiling/benchmark output | Actual recovery, ownership, no-op and failure scenarios in cli-flow-recovery |

Exact machine-consumed markers, schema keys and public command names remain valid assertions. Prose synonyms and numbered comments are not executable contracts. `release-authority` validates the parsed job graph; `validation-instructions` exercises configured validator execution instead of matching guidance sentences. Broader validator-evidence tests continue to cover unavailable reuse and failure propagation.

## Execution and completion

Aim for seconds to two minutes in the edit loop and a focused hosted check within ten minutes per platform. These are design targets, not measured guarantees or reasons to skip a critical test. Release checks retain their committed bounds until evidence supports a deliberate redesign.

After a change, run its affected group once. Repeat only after a relevant correction or to investigate a named nondeterministic condition. A failed execution never becomes a passing result because earlier rows passed. Preserve the failing diagnostic, fix its owner and rerun the affected group; do not replay an unrelated successful prefix.

Only release CI on the exact tagged SHA authorizes a release claim. Do not run the same unchanged full verification before tagging and again after tagging. The tag-triggered workflow runs the essential profile and package checks once on Linux and Windows/MSYS, then publishes only after the aggregate gate succeeds. Maintainer feedback is a focused subset and cannot authorize publication. No test-result signing/cache system is needed; a normal run records its source, platform, command, result and log pointer.
