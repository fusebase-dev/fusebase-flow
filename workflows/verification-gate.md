# Workflow: verification-gate

> **Style:** Mode-B-lite. The contract every implementation must satisfy before deploy approval.

## Purpose

Define the gate report shape so `validation-and-qa` and `code-review` can verify objectively rather than reading vibes.

## Gate report required fields

Canonical in exactly two carriers: `policies/gate-contracts.yml: gate_report` (machine-readable field schema) and `templates/gate-report.md` (the producer template the AI Developer fills). Do not restate the field list elsewhere — point here.

If any required field is missing, the gate report is incomplete and must be redirected.

## Verification procedure (Product Owner side, via validation-and-qa skill)

1. Verify all required fields present.
2. Cross-reference per-task SHAs against `tasks.md` — every task has a SHA.
3. Cross-reference test deltas against `verification-gate.md` expected coverage.
4. Verify each local acceptance row has risk/AC, dependencies, toolchain/platform, exact command, expected counterexample, actual rc/result, durable evidence, status, and invalidation rationale. Changed or unknown dependencies rerun the affected group; missing evidence remains open. `DEFERRED`/`UNVERIFIED` rows are never PASS.
5. Verify scoped/fast results close only their mapped rows and are not presented as full-suite or release evidence. Confirm the declared expected local budget against per-phase START/END tag, elapsed, rc, and timeout-budget records. A missing phase, zero result rows, crash, or timeout fails; diagnose unexplained overruns. After an interruption, require a full owned-descendant process scan and cleanup record; parent-process absence is insufficient.
6. Verify worker-undisturbed: re-run `git diff` against `protected-paths.yml`. Must match implementer's report.
7. Cross-artifact consistency:
   - Every spec AC<n> exercised in at least one task
   - Every locked decision <Letter><n> cited in at least one task description
   - No TODO/FIXME/WIP markers in diff
   - Spec status still DRAFT (will flip in deploy)
8. Confirm lint/typecheck, staged secret scan, protected-path, module-size, and pre-commit controls ran live.
9. If verified, advance phase to Deploy. If not, redirect AI Developer with concrete failure list.

`code-review` trusts this gate's recorded verdict for the deterministic/cross-artifact fields (AC↔task map, decisions-cited, lint/typecheck, TODO scan, protected paths) and reviews only semantic dimensions — see `flow-skills/code-review/SKILL.md`.

## Smoke prompts (when applicable)

For tickets that touch user-facing or operator-facing surfaces, `verification-gate.md` (per-ticket file in `docs/specs/<slug>/`) defines numbered smoke prompts S1..Sn under `flow-skills/smoke-testing/SKILL.md`. The `smoke-verification.md` workflow runs them post-deploy. Pass threshold (e.g., `4/4 PASS`) is part of the gate contract. Supporting checks alone (exit code, file hash, service active, symbol presence, auth sanity) do not satisfy smoke.

## Probes (when applicable)

For tickets that deploy infrastructure or new endpoints, `verification-gate.md` defines probes (typically G-M deploy success, G-N health, G-O feature surface, G-P feature behavior, G-Q spec flip + backlog update). The `release-deploy-reporting` skill runs them post-deploy.

## Per-ticket gate file

Each ticket gets its own `docs/specs/<slug>/verification-gate.md` drafted by `implementation-planning`, using `templates/verification-gate.md`. That file specifies:
- Acceptance criterion → task mapping
- Changed-risk / AC-to-test ledger, dependency invalidation, evidence status, and expected local budget
- Lint/typecheck/test commands (project-specific)
- Worker-undisturbed paths for this ticket
- Manifest version bump (if applicable)
- Smoke prompts (if applicable)
- Ground-truth diagnostic surface for each smoke prompt
- Probes (if applicable)
- Pass thresholds

## Gate failure response

| Failure | Response |
|---|---|
| Missing field | Redirect AI Developer: "Gate report missing <field>. Re-run." |
| Test delta below expected | Surface: missing tests for AC<n>; require additional task |
| Scoped evidence has no complete risk/dependency row | Keep affected AC open; rerun or complete the ledger |
| Deferred/unverified evidence presented as PASS | Reject the claim; preserve the row as open |
| Lint/typecheck not clean | Surface: must fix before deploy; do NOT advance phase |
| Protected path diff | Surface: FR-07 violation; require approval artifact OR revert |
| Decision not cited | Surface: which decision unimplemented; require additional task or decision redirect |

## Related

- `flow-skills/implementation-planning/SKILL.md` — drafts per-ticket gate file
- `flow-skills/validation-and-qa/SKILL.md` — verifies gate
- `flow-skills/code-review/SKILL.md` — reviews diff against gate findings
- `templates/verification-gate.md` — substrate for per-ticket files
- `policies/gate-contracts.yml` — machine-readable required fields
