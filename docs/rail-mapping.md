# Rail mapping — FR-01..FR-27 → enforcement surface

Every always-on rule in `FLOW_RULES.md` maps to one or more enforcement surfaces (rule statement only, workflow procedure, on-demand skill, lifecycle hook, machine-readable policy). This table is the canonical map.

Maintainer-facing, lazy: `FLOW_RULES.md` is the boot-time contract (rule + why only) and no longer carries an Enforcement column — it lives in § Enforcement notes below, verbatim as relocated.

| Rule | Title | Rule (FLOW_RULES) | Workflow | Skill | Hook | Policy |
|---|---|---|---|---|---|---|
| FR-01 | Spec before code | yes | `eight-phase-flow.md`, `greenlight-implement.md` | `requirements-specification`, `role-discipline` (writing code outside role re-fires FR-01) | n/a (no tool-time hook checks spec existence before Edit/Write) | `required-artifacts.yml: before_implementation` (policy declaration; enforced via workflow/gate discipline, not a tool-time hook) |
| FR-02 | Plan before edit | yes | `implementation-planning` workflow elements | `implementation-planning` | n/a (judgment-based) | n/a |
| FR-03 | One task = one commit | yes | `git-discipline.md`, `greenlight-implement.md` | n/a | n/a (commit-time) | `commit-msg` git hook (T-number requirement) |
| FR-04 | Persist handoffs | yes | `greenlight-implement.md`, `greenlight-deploy.md`, `architect-escalation.md` | (all skills that produce handoffs) | n/a (stop.py has no handoff-persistence check; the deploy handoff's existence is required at deploy time by `required-artifacts.yml: before_deploy_command`, not a stop-hook claim gate) | `required-artifacts.yml: before_deploy_command` (deploy handoff `exists_and_recent`, Full lane) |
| FR-05 | Stop at gate | yes | `verification-gate.md`, `greenlight-implement.md` | `validation-and-qa` | `stop` (CLAIM_PATTERNS `before_done_claim`: blocks a done/ready-to-deploy claim without gate-evidence signals) + `pre_tool_use` (deny deploy commands without approval per `command-policy.yml: production_deploy`) | `required-artifacts.yml: before_done_claim` (stop-gated); `before_deploy_command` (deploy-time policy gate — its `worker_undisturbed_recheck` signal has no stop-hook consumer; enforced via workflow discipline) |
| FR-06 | Reversible by default | yes | `git-discipline.md` | n/a | `pre_tool_use` (deny destructive Bash) | `command-policy.yml: deny` |
| FR-07 | Worker-undisturbed | yes | `verification-gate.md`, `greenlight-deploy.md` | `code-review`, `validation-and-qa`, `release-deploy-reporting` | `pre_tool_use` (path policy) — defense-in-depth for ALREADY-STAGED content, never the boundary (`workflows/violation-recovery.md` § FR-07); `post_tool_use` (warn on protected modifications); **`pre-commit` git hook — the boundary** | `protected-paths.yml` + exception artifact format |
| FR-08 | Mode-A operator chat | yes | (across all workflows) | `communication` (mandatory) | n/a (judgment-based) | n/a |
| FR-09 | Mode-B AI-optimized internal docs | yes | (across all workflows) | `communication` (mandatory) | n/a (judgment-based; `code-review` skill flags violations) | n/a |
| FR-10 | Reproducibility before fix | yes | `smoke-verification.md` | `validation-and-qa` (sub-mode C) | n/a | n/a |
| FR-11 | Stop and ask, don't improvise | yes | (across all workflows) | (all skills explicitly guard against improvisation) | `user_prompt_submit` (flags bypass-attempt patterns like "skip clarify", "ignore approvals") | n/a |
| FR-12 | Approval-gated side effects | yes | `greenlight-deploy.md`, `architect-escalation.md` | `security-permissions-review`, `release-deploy-reporting` | `pre_tool_use` (require_approval + secret block on Write), `user_prompt_submit` (secret warn on pasted prompt — fires on native `prompt` key), `permission_request` (artifact lookup), `pre-commit` git hook (secret block) | `approval-policy.yml`, `command-policy.yml: require_approval`, `secret-patterns.yml` |
| FR-13 | Lint + typecheck per commit | yes | `git-discipline.md` | n/a (AI Developer attestation) | `pre-commit` git hook | n/a (project-defined commands) |
| FR-14 | Single docs commit on deploy | yes | `greenlight-deploy.md` | `release-deploy-reporting` | `stop` (blocks "deploy complete" claim without single-docs-commit signal) | `required-artifacts.yml: before_deploy_complete_claim` |
| FR-15 | Knowledge curation triggers | yes | `knowledge-curation.md` | (Product Owner judgment; not a skill) | n/a | n/a |
| FR-16 | Operator is a thin relay | yes | `greenlight-implement.md`, `greenlight-deploy.md`, `architect-escalation.md` | `role-discipline` (Operator Relay Protocol) | n/a (judgment-based) | n/a |
| FR-17 | Forward momentum, never retreat | yes | (across all workflows) | `role-discipline` (Forward Momentum Protocol) | n/a (judgment-based) | n/a |
| FR-18 | Supersede, don't accumulate | yes | (artifact revision discipline) | `role-discipline` (Supersede Convention) | n/a (judgment-based) | n/a |
| FR-19 | Chat-text questions, no popup menus | yes | `greenlight-deploy.md`, `session-initiation.md` | `communication`, `role-discipline` (Chat-Text Questions Protocol) | n/a (tool grants remove popup tools where available) | n/a |
| FR-20 | Zoom out, don't patch-myopically | yes | (fix-time discipline across workflows) | `zoom-out`, `validation-and-qa` (reproduce-before-fix) | n/a (judgment-based) | n/a |
| FR-21 | Ceremony proportional to change size | yes | `lightweight-lane.md` | `lightweight-lane`, `requirements-specification` (lane gate) | `stop` (LL deploy-claim fixtures 15/16) | tier-aware `approval-policy.yml`, `required-artifacts.yml` |
| FR-22 | Comment policy: tripwire + pointer only | yes | (write-time; not a workflow) | `comment-policy` (carrier), `code-review` (dimension 5b) | n/a (deliberately never a gate — semantic) | `comment-policy.yml: trust_critical_globs` |
| FR-23 | Documentation budget | yes | (artifact-creation discipline) | `documentation-budget`, `implementation-planning` (tier gate) | n/a (judgment-based) | n/a |
| FR-24 | Write-time discipline delivery | yes | (delivery mechanism, not a procedure) | `role-discipline` (§ Write-time discipline digest) | `session_start` (reminder line) | n/a |
| FR-25 | Module-size ratchet | yes | (write/plan-time; CI step) | `module-size-discipline`, `implementation-planning` (target-file rule), `code-review` (dimension 5c) | `pre-commit` git hook (module-size step) + CI `--all` step | `policies/module-size.yml` + `module-size-baseline.txt` |
| FR-26 | Token-efficient execution | yes | (execution-time discipline + retrospective audit; deliberately no gate — semantic) | `token-economy` (carrier), `role-discipline` (digest line) | n/a (`/token-waste-audit` parser `hooks/local/token-waste-audit.py` is operator tooling, not a hook) | n/a |
| FR-27 | Liveness — never launch bare | yes | (launch-time discipline; deliberately no gate AND no verification hook — a hang is undetectable by construction, so a "watchdog: applied" signal would be attestation theatre) | `liveness-discipline` (carrier + protocol), `role-discipline` (digest line); cross-links `task-delegation` (BLOCKED-AT) + `smoke-testing` (record-then-read) | `session_start` (reminder line) — NOT a verification hook; enforcement = digest delivery + `hooks/local/lib/bounded-run.sh` (structural bounded-run tooling) | n/a |

## Enforcement notes (relocated from `FLOW_RULES.md`, v4.6.0)

Verbatim Enforcement column of the `FLOW_RULES.md` FR table, moved here so the boot-time rules file carries rule + why only (token-floor-remediation S5c / AC1). Rule statements were not touched. The per-surface breakdown above is the structured view; this is the prose one.

| Rule | Enforcement |
|---|---|
| FR-01 | rule + `required-artifacts.yml: before_implementation` (policy declaration) + role-discipline (writing code outside role re-fires the rule) + spec-review / verification-gate discipline (workflow) — NOT a tool-time hook (no hook checks spec existence before an Edit/Write) |
| FR-02 | rule + skill `implementation-planning` |
| FR-03 | rule + `commit-msg` git hook |
| FR-04 | rule + workflow discipline + `required-artifacts.yml: before_deploy_command` (deploy handoff must exist at deploy time; no stop-hook handoff-persistence check) |
| FR-05 | rule + workflow + `pre_tool_use` hook on deploy commands |
| FR-06 | rule + `command-policy.yml` + `pre_tool_use` hook |
| FR-07 | rule + `protected-paths.yml` + `pre_tool_use` + `pre-commit` git hook |
| FR-08 | mandatory skill `flow-skills/communication/SKILL.md` (Mode A pattern library) |
| FR-09 | mandatory skill `flow-skills/communication/SKILL.md` (Mode B principles + anti-patterns) |
| FR-10 | rule + skill `validation-and-qa` |
| FR-11 | rule (judgment-bound) + `user_prompt_submit` flag for "skip clarify" patterns |
| FR-12 | rule + `approval-policy.yml` (committed default) + optional `approval-policy.local.yml` (ignored override) + `permission_request` hook + `pre_tool_use` (secret block on Write) + `user_prompt_submit` (secret warn on pasted prompt; native `prompt` key) |
| FR-13 | rule + `pre-commit` git hook |
| FR-14 | rule + workflow `greenlight-deploy` |
| FR-15 | rule + workflow `knowledge-curation` (operator-confirmed only) |
| FR-16 | rule + `flow-skills/role-discipline/SKILL.md` (§ Operator Relay Protocol) + `templates/gate-report.md` + `templates/deploy-report.md` + `templates/architect-response.md` |
| FR-17 | rule + `flow-skills/role-discipline/SKILL.md` (PO.11 / IM.12 / DP.7 + § Forward Momentum Protocol) |
| FR-18 | rule + `flow-skills/role-discipline/SKILL.md` (PO.12 / IM.13 / AR.7 / DP.8 + § Supersede Convention) |
| FR-19 | rule + mandatory skills `flow-skills/communication/SKILL.md` and `flow-skills/role-discipline/SKILL.md` + agent tool grants |
| FR-20 | rule + `flow-skills/zoom-out/SKILL.md` + `flow-skills/validation-and-qa/SKILL.md` (reproduce-before-fix, FR-10) |
| FR-21 | rule + `flow-skills/lightweight-lane/SKILL.md` + `flow-skills/requirements-specification/SKILL.md` (lane-classification gate) + tier-aware `approval-policy.yml` / `required-artifacts.yml` |
| FR-22 | rule + `flow-skills/comment-policy/` (write-time carrier) + `references/audit-prompt.md` + `docs/comment-policy.md` + `code-review` dimension + `policies/comment-policy.yml` (`trust_critical_globs`); NOT a regex/lint gate (semantic) |
| FR-23 | rule + `flow-skills/documentation-budget/SKILL.md` + Mode-B review (`code-review` doc dimension) |
| FR-24 | rule + `flow-skills/role-discipline/SKILL.md` (§ Write-time discipline digest) + `templates/handoff-implement.md` + `hooks/handlers/session_start.py` + `code-review` (review-time) |
| FR-25 | rule + `policies/module-size.yml` + `hooks/shared/module_size.py` (`hooks/local/check-module-size.sh`) + `pre-commit` git hook + CI `--all` step + skill `flow-skills/module-size-discipline/SKILL.md` + plan-time rule (`implementation-planning`) + `code-review` dimension + FR-24 digest line |
| FR-26 | rule + `flow-skills/token-economy/SKILL.md` (rules + quality guards) + role-discipline § Write-time discipline digest line (FR-24 channel) + `/token-waste-audit` retrospective audit (Claude Code; portable fallback in the skill) — deliberately NOT a gate (semantic, FR-22 class; a budget gate trains truncation) |
| FR-27 | rule + `flow-skills/liveness-discipline/SKILL.md` (full protocol) + `hooks/local/lib/bounded-run.sh` (structural bounded-run tooling) + role-discipline § Write-time discipline digest line (FR-24 channel) — deliberately NO blocking gate and NO verification hook (a hang is undetectable by construction; a "watchdog: applied" signal would be attestation theatre); enforcement = safe-default tooling + present-by-construction delivery |

## Git surface — direct-to-main vs branch/PR (relocated from `FLOW_RULES.md`, v4.6.0)

Solo/local default: **direct-to-main** + pre-task git checkpoint + one task = one commit + verification gate. This is the speed mode.

Team/shared/high-risk default: **feature branch + PR**. Switch via `approval-policy.yml: workflow_mode: branch_pr` (or override locally in `approval-policy.local.yml`). The flow rules are identical; only the git surface changes.

Both modes preserve FR-03, FR-13, FR-14.

## Surface counts

| Surface type | Count of rules with this surface |
|---|---|
| Rule statement (FLOW_RULES.md) | 27 / 27 |
| Workflow | 16 / 27 |
| Skill | 23 / 27 |
| Hook | 11 / 27 |
| Policy | 9 / 27 |

## Cross-cutting mandatory skills

Two skills are **mandatory** (loaded at every session start; presence enforced by `hooks/handlers/session_start.py`) and apply across multiple rules rather than mapping cleanly to one row above:

- **`communication`** — governs FR-08 / FR-09 (Mode A / Mode B discipline) and FR-19 (chat-text questions). Listed in the table.
- **`role-discipline`** — per-role don't-list + refusal phrasing; touches FR-01, FR-05, FR-06, FR-11, FR-12, FR-13, FR-14, FR-16, FR-17, FR-18, and FR-19 depending on the role. Not listed per-row to avoid table noise; see `flow-skills/role-discipline/SKILL.md` (shared protocols + role index) and `references/<role>.md` (per-role don't-lists) for the role-by-role mapping.

## Drift detection

Any new rule (FR-16+) must be added to:

1. `FLOW_RULES.md` — full statement.
2. This file — enforcement-surface row.
3. The relevant workflow / skill / hook / policy if the rule is enforceable mechanically.

`preflight.sh` does not currently parse this file; drift is operator-detected during release reviews (automation candidate — `ROADMAP.md` radar).

## Last amended

```
2026-05-27 — v3.1; added FR-16..FR-19 rows and updated surface counts.
2026-06-10 — v3.16.4; added FR-20..FR-25 rows (had drifted 6 releases behind), surface counts 19→25 base, removed dead open-questions.md reference.
2026-06-11 — v3.20.0; added FR-26 row (token-efficient execution) at ship time per § Drift detection, surface counts 25→26 base.
2026-06-17 — v3.28.0; added FR-27 row (liveness — never launch bare) per § Drift detection, surface counts 26→27 base. Enforcement = digest delivery + bounded-run.sh; no gate; no hook verification (a hang is undetectable by construction).
2026-07-03 — Phase C S1; FR-12 hook column adds `user_prompt_submit` (secret warn on the native `prompt` key) — the enforcement was inert live before the host-shape fix (see docs/hook-coverage.md § Host field-shape). No new row; surface counts unchanged.
2026-07-26 — token-floor-remediation S5c (T8); FLOW_RULES.md Enforcement column + the direct-to-main/branch-PR section relocated here verbatim (§ Enforcement notes, § Git surface) so the boot-time rules file carries rule + why only. No rule statement and no enforcement behavior changed; surface counts unchanged.
2026-07-03 — Phase C S6; doc-consistency corrections (no enforcement changed): FR-01 hook column `pre_tool_use`→n/a (no tool-time hook checks spec existence before an Edit/Write; enforced via role-discipline + workflow/gate); FR-04 hook column `stop`→n/a (stop.py has no handoff-persistence check; the deploy handoff is required at deploy time by `required-artifacts.yml: before_deploy_command`); FR-05 hook column made precise (stop `before_done_claim` + pre_tool_use deploy-deny) and notes `worker_undisturbed_recheck` has no stop-hook consumer. Hook surface count 13→11.
2026-08-25 — consumer escalation E4; FR-07 hook column names WHICH arm is the boundary (`pre-commit`) and which is defense-in-depth for already-staged content (`pre_tool_use`), pointing at workflows/violation-recovery.md § FR-07. No enforcement behavior changed; surface counts unchanged.
```