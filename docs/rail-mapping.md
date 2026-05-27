# Rail mapping — FR-01..FR-19 → enforcement surface

Every always-on rule in `FLOW_RULES.md` maps to one or more enforcement surfaces (rule statement only, workflow procedure, on-demand skill, lifecycle hook, machine-readable policy). This table is the canonical map.

| Rule | Title | Rule (FLOW_RULES) | Workflow | Skill | Hook | Policy |
|---|---|---|---|---|---|---|
| FR-01 | Spec before code | yes | `eight-phase-flow.md`, `greenlight-implement.md` | `requirements-specification` | `pre_tool_use` (when host emits Edit/Write before spec exists) | `required-artifacts.yml: before_implementation` |
| FR-02 | Plan before edit | yes | `implementation-planning` workflow elements | `implementation-planning` | n/a (judgment-based) | n/a |
| FR-03 | One task = one commit | yes | `git-workflow.md`, `greenlight-implement.md` | n/a | n/a (commit-time) | `commit-msg` git hook (T-number requirement) |
| FR-04 | Persist handoffs | yes | `greenlight-implement.md`, `greenlight-deploy.md`, `architect-escalation.md` | (all skills that produce handoffs) | `stop` (blocks "handoff-shown" claim without persisted file) | n/a |
| FR-05 | Stop at gate | yes | `verification-gate.md`, `greenlight-implement.md` | `validation-and-qa` | `stop` (blocks deploy-ready claim without gate evidence) | `required-artifacts.yml: before_done_claim`, `before_deploy_command` |
| FR-06 | Reversible by default | yes | `git-workflow.md` | n/a | `pre_tool_use` (deny destructive Bash) | `command-policy.yml: deny` |
| FR-07 | Worker-undisturbed | yes | `verification-gate.md`, `greenlight-deploy.md` | `code-review`, `validation-and-qa`, `release-deploy-reporting` | `pre_tool_use` (path policy), `post_tool_use` (warn on protected modifications), `pre-commit` git hook | `protected-paths.yml` + exception artifact format |
| FR-08 | Mode-A operator chat | yes | (across all workflows) | `communication` (mandatory) | n/a (judgment-based) | n/a |
| FR-09 | Mode-B AI-optimized internal docs | yes | (across all workflows) | `communication` (mandatory) | n/a (judgment-based; `code-review` skill flags violations) | n/a |
| FR-10 | Reproducibility before fix | yes | `smoke-verification.md` | `validation-and-qa` (sub-mode C) | n/a | n/a |
| FR-11 | Stop and ask, don't improvise | yes | (across all workflows) | (all skills explicitly guard against improvisation) | `user_prompt_submit` (flags bypass-attempt patterns like "skip clarify", "ignore approvals") | n/a |
| FR-12 | Approval-gated side effects | yes | `greenlight-deploy.md`, `architect-escalation.md` | `security-permissions-review`, `release-deploy-reporting` | `pre_tool_use` (require_approval), `permission_request` (artifact lookup), `pre-commit` git hook (secret block) | `approval-policy.yml`, `command-policy.yml: require_approval`, `secret-patterns.yml` |
| FR-13 | Lint + typecheck per commit | yes | `git-workflow.md` | n/a (AI Developer attestation) | `pre-commit` git hook | n/a (project-defined commands) |
| FR-14 | Single docs commit on deploy | yes | `greenlight-deploy.md` | `release-deploy-reporting` | `stop` (blocks "deploy complete" claim without single-docs-commit signal) | `required-artifacts.yml: before_deploy_complete_claim` |
| FR-15 | Knowledge curation triggers | yes | `knowledge-curation.md` | (Product Owner judgment; not a skill) | n/a | n/a |
| FR-16 | Operator is a thin relay | yes | `greenlight-implement.md`, `greenlight-deploy.md`, `architect-escalation.md` | `role-discipline` (Operator Relay Protocol) | n/a (judgment-based) | n/a |
| FR-17 | Forward momentum, never retreat | yes | (across all workflows) | `role-discipline` (Forward Momentum Protocol) | n/a (judgment-based) | n/a |
| FR-18 | Supersede, don't accumulate | yes | (artifact revision discipline) | `role-discipline` (Supersede Convention) | n/a (judgment-based) | n/a |
| FR-19 | Chat-text questions, no popup menus | yes | `greenlight-deploy.md`, `session-initiation.md` | `communication`, `role-discipline` (Chat-Text Questions Protocol) | n/a (tool grants remove popup tools where available) | n/a |

## Surface counts

| Surface type | Count of rules with this surface |
|---|---|
| Rule statement (FLOW_RULES.md) | 19 / 19 |
| Workflow | 15 / 19 |
| Skill | 14 / 19 |
| Hook | 9 / 19 |
| Policy | 6 / 19 |

## Cross-cutting mandatory skills

Two skills are **mandatory** (loaded at every session start; presence enforced by `hooks/handlers/session_start.py`) and apply across multiple rules rather than mapping cleanly to one row above:

- **`communication`** — governs FR-08 / FR-09 (Mode A / Mode B discipline) and FR-19 (chat-text questions). Listed in the table.
- **`role-discipline`** — per-role don't-list + refusal phrasing; touches FR-01, FR-05, FR-06, FR-11, FR-12, FR-13, FR-14, FR-16, FR-17, FR-18, and FR-19 depending on the role. Not listed per-row to avoid table noise; see `skills/role-discipline/SKILL.md` for the role-by-role mapping.

## Drift detection

Any new rule (FR-16+) must be added to:

1. `FLOW_RULES.md` — full statement.
2. This file — enforcement-surface row.
3. The relevant workflow / skill / hook / policy if the rule is enforceable mechanically.

`preflight.sh` does not currently parse this file; drift is operator-detected during Phase-N reviews. Tracked in `open-questions.md` for v0.2 automation.

## Last amended

```
2026-05-27 — v3.1; added FR-16..FR-19 rows and updated surface counts.
```
