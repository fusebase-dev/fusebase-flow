# Workflow: verification-gate

> **Style:** Mode-B-lite. The contract every implementation must satisfy before deploy approval.

## Purpose

Define the gate report shape so `validation-and-qa` and `code-review` can verify objectively rather than reading vibes.

## Gate report required fields

A gate report from the AI Developer session MUST contain all of:

| Field | Format | Source |
|---|---|---|
| Implementation summary | 1–3 sentences | AI Developer summary of what landed |
| Per-task SHAs | `T<n>: <sha> <subject>` for every task in range | `git log` |
| Test counts | `before: <n>, after: <m>, delta: +<k>` per layer (unit / integration / e2e) | test runner output |
| Lint status | `clean` / `<n> warnings` / `<n> errors` | lint runner output |
| Typecheck status | `clean` / `<n> errors` | typecheck output |
| Worker-undisturbed git diff | `<file>: empty diff ✓` for each protected path; or explicit "exception artifact ref" | `git diff` against `protected-paths.yml` |
| Manifest version | `<old> → <new>` if applicable; or `N/A` | manifest file |
| Architect/PO deviations | listed with reasoning, or `none` | implementer judgment |
| Gate self-attestation | "Operating as AI Developer..." phrase | AI Developer first response |

If any field is missing, the gate report is incomplete and must be redirected.

## Verification procedure (Product Owner side, via validation-and-qa skill)

1. Verify all required fields present.
2. Cross-reference per-task SHAs against `tasks.md` — every task has a SHA.
3. Cross-reference test deltas against `verification-gate.md` expected coverage.
4. Verify worker-undisturbed: re-run `git diff` against `protected-paths.yml`. Must match implementer's report.
5. Cross-artifact consistency:
   - Every spec AC<n> exercised in at least one task
   - Every locked decision <Letter><n> cited in at least one task description
   - No TODO/FIXME/WIP markers in diff
   - Spec status still DRAFT (will flip in deploy)
6. If verified, advance phase to Deploy. If not, redirect AI Developer with concrete failure list.

## Smoke prompts (when applicable)

For tickets that touch user-facing or operator-facing surfaces, `verification-gate.md` (per-ticket file in `docs/specs/<slug>/`) defines numbered smoke prompts S1..Sn under `skills/smoke-testing/SKILL.md`. The `smoke-verification.md` workflow runs them post-deploy. Pass threshold (e.g., `4/4 PASS`) is part of the gate contract. Supporting checks alone (exit code, file hash, service active, symbol presence, auth sanity) do not satisfy smoke.

## Probes (when applicable)

For tickets that deploy infrastructure or new endpoints, `verification-gate.md` defines probes (typically G-M deploy success, G-N health, G-O feature surface, G-P feature behavior, G-Q spec flip + backlog update). The `release-deploy-reporting` skill runs them post-deploy.

## Per-ticket gate file

Each ticket gets its own `docs/specs/<slug>/verification-gate.md` drafted by `implementation-planning`, using `templates/verification-gate.md`. That file specifies:
- Acceptance criterion → task mapping
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
| Lint/typecheck not clean | Surface: must fix before deploy; do NOT advance phase |
| Protected path diff | Surface: FR-07 violation; require approval artifact OR revert |
| Decision not cited | Surface: which decision unimplemented; require additional task or decision redirect |

## Related

- `skills/implementation-planning/SKILL.md` — drafts per-ticket gate file
- `skills/validation-and-qa/SKILL.md` — verifies gate
- `skills/code-review/SKILL.md` — reviews diff against gate findings
- `templates/verification-gate.md` — substrate for per-ticket files
- `policies/gate-contracts.yml` — machine-readable required fields
