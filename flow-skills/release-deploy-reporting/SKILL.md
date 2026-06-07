---
name: release-deploy-reporting
description: Use ONLY when verification passed AND operator explicitly says "prepare deploy" / "draft deploy" / "ship it"; drafts deploy handoff, captures deploy hash + probes + smoke, advises spec DRAFT→DONE flip. Do NOT auto-invoke; operator triggers explicitly.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: high
invocation: manual-for-side-effects
expected_outputs:
  - docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md
  - release notes section
  - deploy report (after operator pastes back)
  - rollback notes
related_workflows:
  - greenlight-deploy.md
  - verification-gate.md
  - smoke-verification.md
hook_dependencies:
  - permission_request
  - pre_tool_use
  - stop
---

# Release & Deploy Reporting

## Purpose

The final skill in the eight-phase flow: draft the deploy green-light handoff, capture deploy artifacts (hash + probes + smoke), produce release notes, and advise the spec DRAFT→DONE flip. Manual-invoke only — operator types "prepare deploy" or equivalent; this skill never auto-fires.

## Lightweight-lane mode (FR-21)

If the ticket was classified **Lightweight** (`skills/lightweight-lane/SKILL.md`), do NOT draft a deploy handoff, do NOT require a `production_deploy` JSON artifact, and do NOT use the DP.6 magic phrase. Instead the same single AI Developer session that built + live-verified the change deploys it on a **plain explicit operator go-ahead** ("ship it"). Still required (safety floor): the FR-07 protected-path re-check, capturing the deploy hash, a one-line rollback, one commit + SHA, and an explicit go-ahead (never auto-deploy). Report in 1–3 lines and log one line in `docs/changes/index.md`. In hook-wired projects, record the go-ahead with `bash hooks/local/approve-local.sh lightweight_deploy <slug> 'ship it'` (one command — see `policies/approval-policy.yml`). The full procedure below applies to **Full-lane** deploys only.

## When to invoke (Full lane)

- Active phase is `Deploy` (per FLOW_RULES state announcement)
- `validation-and-qa` reported gate passed
- `code-review` reported zero blockers (or operator accepted them as non-blockers explicitly)
- `security-permissions-review` either ran clean OR all approval artifacts are in place per `approval-policy.yml`
- Operator says "prepare deploy" / "draft deploy handoff" / "ship it"

## Do not invoke when

- Gate has not passed (`validation-and-qa` reported failures)
- Code-review surfaced unaddressed blockers
- Security review surfaced missing approval artifacts
- Operator did NOT explicitly ask — this skill's `invocation: manual-for-side-effects` means no auto-trigger

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Spec | `docs/specs/<slug>/spec.md` (status DRAFT) | Stop; cannot deploy without spec |
| Verification gate report | chat paste from `validation-and-qa` | Stop; cannot deploy without gate pass |
| Deploy command | project-specific section of `AGENTS.md` | Stop; ask operator for deploy command |
| Approval artifact for `production_deploy` | `state/approvals/production_deploy-<slug>-<YYYYMMDD>.json` | Stop; operator must author artifact per FR-12 |
| Worker-undisturbed list | `policies/protected-paths.yml` | Stop; cannot run final pre-deploy check without it |
| CLI edition map, for Fusebase Apps deploys | `docs/fusebase-cli-edition.md` | Continue with generic deploy handoff, but mark CLI probes/log diagnostics unknown |

## Procedure

1. Verify all preconditions: gate passed, code-review clean, security clean, approval artifact present.
2. Final pre-deploy worker-undisturbed check: re-run `git diff` against `protected-paths.yml`. If anything changed since the gate report, STOP and report.
3. For Fusebase Apps deploys, use `docs/fusebase-cli-edition.md` to identify supporting CLI assets for commands, logs, app quality checks, and post-deploy diagnostics.
4. Draft deploy handoff using `templates/handoff-folder-README.md` shape adapted for deploy stage (see `workflows/greenlight-deploy.md`). Include:
   - Self-attestation phrase the deployer should output first
   - Pre-deploy worker-undisturbed re-check instructions
   - Deploy command (exact)
   - Probe list (G-M..G-Q or project equivalents from `verification-gate.md`)
   - Smoke prompts S1..Sn (if applicable), copied from the `smoke-testing` contract with success criterion, ground-truth diagnostic, adversarial check, and evidence required
   - Single-docs-commit instructions (FR-14): spec DRAFT→DONE flip with deploy hash, tasks.md verification marks, backlog index update, README header
5. Save handoff to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md` BEFORE outputting in chat (FR-04).
6. Tell operator: "Deploy handoff saved to <path>. Open and paste into the AI Developer (Codex) chat to authorize deploy."
7. After operator pastes back deploy report:
   - Verify deploy hash captured
   - Verify each probe result with concrete evidence
   - Verify smoke results meet threshold from gate contract and satisfy `skills/smoke-testing/SKILL.md` (operator-visible outcome + ground-truth diagnostic, not supporting checks only)
   - Verify single docs commit landed (one SHA covering all post-deploy doc updates)
8. If all verified, acknowledge with summary + tally update + identify what's next (parked backlog options, observation period).
9. If any probe failed, do NOT acknowledge as success. Surface failure with rollback (`git revert <hash>` + redeploy) or fix-forward (follow-up task) options. Operator decides.

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Deploy handoff | `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md` | Mode B (full) |
| Release notes | embedded in deploy handoff + spec.md DONE section | Mode B (full) |
| Deploy verification | chat acknowledgment to operator | Mode A |
| Tally update | project-specific counter in `AGENTS.md` | Human-readable |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Approval artifact missing | `state/approvals/` lacks file matching `approval-policy.yml: require_approval.production_deploy` | STOP. Surface which artifact is missing and how to author it. |
| Worker-undisturbed file changed since gate | `git diff` against `protected-paths.yml` non-empty | STOP. Per FR-07, do NOT deploy on changed protected paths. |
| Probe failure | Pasted report shows `Pn FAIL` | Do NOT mark spec DONE. Surface rollback / fix-forward options. |
| Smoke threshold not met | Pass ratio below gate contract | Do NOT mark spec DONE. Surface failure with concrete `Sn observed Y, expected Z`. |
| Multiple docs commits instead of one | Pasted report shows multiple SHAs for spec/tasks/backlog updates | Note as FR-14 violation; document but don't block (deploy already happened); flag for next deploy cycle |

## Escalation path

- Deploy command unknown or platform-blocker emerges → STOP; file `docs/problem-catalog/deploy-blocker-<date>/problem.md`
- Probe infrastructure unavailable → cannot verify; STOP and surface to operator before attempting deploy
- Rollback needed → produce concrete `git revert <hash>` + redeploy steps; operator confirms before execution

## Anti-patterns

- Do NOT auto-invoke (`invocation: manual-for-side-effects` enforces this)
- Do NOT deploy without approval artifact (FR-12)
- Do NOT mark spec DONE before all probes pass
- Do NOT split deploy docs across multiple commits (FR-14)
- Do NOT print or persist secrets / session keys in handoff or report
- Do NOT skip the final worker-undisturbed re-check even though gate already ran one

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
