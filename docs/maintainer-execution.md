# Maintaining this repository

This is the maintainer process for `fusebase-dev/fusebase-flow`, approved on 2026-09-07. It overrides generic lifecycle ceremony for work on this framework. Consumer projects retain their own Flow workflow. Installation does not copy this file by default; `--with-framework-docs` places it under `docs/_fusebase-flow/` for reference.

## One outcome, one implementation pass

1. Record the intended outcome, affected boundary and a success/failure example in one issue or change note. Use a design document only when behavior or ownership needs a real decision. The same record owns the task list and results; no automatic spec/decisions/tasks/gate/handoff bundle.
2. Diagnose and implement with one owner. Existing operator authorization carries forward. Role changes within the approved work do not require a new session or relay. Ask only about a material product decision or an external action not already authorized.
3. Run the cheapest meaningful checks for the changed behavior. A deterministic reproduction with a causal explanation is enough to fix; repeat trials only investigate actual races, flaky behavior or measured performance. No mandatory baseline full suite or three-run ritual.
4. Review the diff after focused checks, before expensive verification. Ordinary maintenance uses implementer review. Changes to ownership, upgrade/recovery authority, security or release publication require an independent review of the relevant contract and diff.
5. Resolve substantive findings together. Re-review the corrections and affected boundaries, expanding only for a concrete new risk. Findings require an input/trigger, wrong outcome and expected behavior. Wording and unrelated improvements do not restart the gate unless they change behavior or a material public claim.
6. Commit one independently reversible outcome at a time. A probe, fixture calibration or report correction does not need its own task. Once behavior is demonstrated, applicable checks pass and blockers are resolved, finish.

If another fix breaks the same boundary, settle the shared contract before patching again. A known correctness or safety blocker never becomes acceptable because a review has already run once. Prior examples: `docs/problem-catalog/undecided-contract-drives-repeat-defects/problem.md`.

## Checks and evidence

| Stage | Required work |
|---|---|
| Edit loop | Affected tests and relevant syntax/configuration checks; `FF_ONLY=tag1,tag2 bash hooks/tests/run-tests.sh` when the registered runner is useful |
| Commit | Normal staged secret, protected-path, module-size and configured lint/typecheck checks; no mandatory separate validator invocation immediately before pre-commit |
| Maintainer CI | Focused deterministic contracts on Linux and Windows/MSYS; feedback only, not release evidence |
| Release | Explicit essential profile and package integrity through `.github/workflows/fusebase-flow-verify.yml` on the exact tagged SHA; both platforms must succeed |
| Diagnostics | Editorial instruction checks, profiling and repeated performance experiments explicitly selected when their subject changes |

Configured validators execute normally; no signed-receipt shortcut is required. An earlier manual validator run is optional feedback. CI repeats checks because it supplies a clean independent environment. If a check is not configured, report that fact rather than inventing a lint/typecheck result.

Two-platform gating is mandatory: `verify-linux` and `verify-windows-msys`, plus the aggregate gate, must pass before publication. A focused CI/local pass is not release evidence. `PUBLISHING.md` owns release procedures. Essential-profile membership and diagnostic access are documented in `docs/maintainer-testing.md`.

Record only commit/source state, selected command/group, environment, result and log pointer. CI logs and existing reports own the detail. A missing report field is repaired from evidence already present; rerun only when evidence is missing or invalidated. A focused result can close the affected local task without pretending it was a complete suite. Save a handoff only when work must cross sessions.

## Failure handling

| Observation | Action |
|---|---|
| Essential consumer behavior or runner-trust control fails | Resolve the blocker and rerun the affected owner before preparing the tagged release gate |
| Unrelated diagnostic or tooling check fails | Retain the evidence and open a separate follow-up; do not expand the release scope unless it invalidates an essential-profile result or runner trust |
| Wrong product behavior | Fix it and rerun affected tests |
| Proven fixture or tooling error | Fix the smallest responsible boundary and retain the original failure |
| Timeout, crash or zero result rows | Failed/incomplete execution; diagnose before retrying; never infer PASS from partial output |
| Same experiment without new inputs | Stop repeating it; choose a simpler oracle or resolve the prerequisite |
| Interrupted process tree | Inspect and clean only verified owned descendants before another run |
| Unrelated review suggestion | Record as optional follow-up; keep the current outcome fixed |

Use bounded execution and durable logs for long checks. Time budgets are design targets, not correctness assertions. Fix slow setup, isolation and repeated subprocesses before changing a wall; no blanket timeout increase or successful-prefix replay. No new instrumentation subsystem is needed to measure existing CI duration.
Reruns require a corrected input, implementation, or environment; there is no fixed retry allowance.

## Safety and scope

Preserve user/CLI ownership, supported upgrade paths, prior activation intent, recoverability, secret/protected-path enforcement and truthful partial/failure states. Keep tag/verified-SHA binding and the publication dependency on verification. Do not bypass Git hooks, rewrite published tags or interpret local verification as permission to publish.

Apply process simplification here first. Changing consumer roles, shipped skill behavior or supported compatibility is a separate product decision. Historical audit: `state/audit/find-wasted-effort-2026-09-07-process-review.md` (local, not required for using this process).
