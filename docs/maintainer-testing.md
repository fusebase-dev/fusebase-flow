# Maintainer testing

Test behavior at the smallest useful boundary. Small decision tests use data tables; filesystem/Git tests use tiny isolated repositories; real install/recovery scenarios prove the integrated result. Do not copy the full repository or launch recovery to test a string predicate. Use existing fixtures and runners before creating another harness.

## Required guarantees

| Guarantee | Required coverage |
|---|---|
| Install and distribution | Preflight, manifests, mirror parity, command/provider delivery and actual installer scenarios |
| Ownership and upgrade | Merge/classification, source/path boundaries, user/CLI byte preservation and supported upgrade paths |
| Recovery | Prior intent/opt-out, invalid-input zero writes, interrupted-write partial status, retry convergence and no-op |
| Executable safety | Secret scan, protected paths, approval/trusted-enforcer cases, real Git hook allow/deny/failure paths |
| Process lifecycle | Failure/timeout propagation, owned-child cleanup, zero-result refusal and selector completeness |
| Publication | Parsed workflow graph, both platforms, required-job success, manifests and tag/verified-SHA binding |

`hooks/tests/run-tests.sh` owns membership and `FF_LIST=1` lists it. The full required set includes every registered phase except explicit `FF_OPTIN_TAGS`. The fast default is developer feedback; `FF_ONLY` names affected groups; neither is a full result. New phases enter the required set unless explicitly classified as diagnostics with a reason below.

## Diagnostic exclusions

These checks remain available with `FF_ONLY` when their subject changes. They do not add unique runtime protection to every release. This table authorizes the T63 runner classification; no existing supported behavior is removed.

| Tag | Why opt-in | Required protection retained |
|---|---|---|
| return-budget | Checks exact editorial wording of delegated response limits | Delivery/preflight and actual hook controls; response-size guidance remains shipped |
| supersede-primitive | Searches prose for editing advice and retired phrases | Actual recovery preservation/idempotency tests; editorial review on instruction changes |
| rule-inventory | Instrument for deliberate rule-compression comparisons | Boot/delivery/prohibition checks; run inventory explicitly for rule changes |
| startup-context | Frozen compression baseline and size comparison | boot-size, prohibition-residency, provider delivery and mirror checks |
| budget-literals | Consistency of historical prose performance-budget numbers | boot-size retains the implemented structural/size checks |
| history-extraction | One-time migration equivalence against historical Git blobs | Current rule/skill structure and delivery; Git preserves migration history |
| consumer-benchmark | Comparative profiling/benchmark output | Actual recovery, ownership, no-op and failure scenarios in cli-flow-recovery |

Exact machine-consumed markers, schema keys and public command names remain valid assertions. Prose synonyms and numbered comments are not executable contracts. `release-authority` validates the parsed job graph; `validation-instructions` exercises configured validator execution instead of matching guidance sentences. Broader validator-evidence tests continue to cover unavailable reuse and failure propagation.

## Execution and completion

Aim for seconds to two minutes in the edit loop and a focused hosted check within ten minutes per platform. These are design targets, not measured guarantees or reasons to skip a critical test. Release checks retain their committed bounds until evidence supports a deliberate redesign.

After a change, run its affected group once. Repeat only after a relevant correction or to investigate a named nondeterministic condition. A failed execution never becomes a passing result because earlier rows passed. Preserve the failing diagnostic, fix its owner and rerun the affected group; do not replay an unrelated successful prefix.

Only release CI on the exact tagged SHA authorizes a release claim. Use the reusable verification workflow on a candidate before tagging to find platform issues early. Maintainer feedback is a subset and cannot authorize publication. No test-result signing/cache system is needed; a normal run records its source, platform, command, result and log pointer.
