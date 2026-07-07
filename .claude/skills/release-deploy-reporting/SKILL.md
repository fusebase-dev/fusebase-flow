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

If the ticket was classified **Lightweight** (`flow-skills/lightweight-lane/SKILL.md`), do NOT draft a deploy handoff, do NOT require a `production_deploy` JSON artifact, and do NOT use the DP.6 magic phrase. Instead the same single AI Developer session that built + live-verified the change deploys it on a **plain explicit operator go-ahead** ("ship it"). Still required (safety floor): the FR-07 protected-path re-check, capturing the deploy hash, a one-line rollback, one commit + SHA, and an explicit go-ahead (never auto-deploy). Report in 1–3 lines. The durable record is `change_tier: lightweight` + the SHA in the change-note / commit body (git carries it); a consolidated ledger is **opt-in and path-configurable** — only if the project keeps one, append one line (default `docs/changes/index.md`, but a per-app layout may point elsewhere or omit it — never assume a repo-root ledger exists). In hook-wired projects, record the go-ahead with `bash hooks/local/approve-local.sh lightweight_deploy <slug> 'ship it'` (one command — see `policies/approval-policy.yml`). The full procedure below applies to **Full-lane** deploys only.

## When to invoke (Full lane)

- Active phase is `Deploy` (per FLOW_RULES state announcement)
- `validation-and-qa` reported gate passed
- `code-review` reported zero blockers — OR every still-open blocker carries a **recorded waiver** in the deploy handoff's `blocker_waivers:` block: verbatim review-summary blocker line + the operator's own accept-phrase naming it + the accepted consequence (the concrete failing scenario / missing test case being shipped). Safety blockers (correctness defect — code-review step 4d; missing/meaningless tests — step 5) are never downgradable to "non-blocker"; they ship only under such a named waiver. A bare "operator accepted the blockers" — unquoted, unnamed, unrecorded — does NOT satisfy this precondition.
- `security-permissions-review` either ran clean OR all approval artifacts are in place per `approval-policy.yml`
- Operator says "prepare deploy" / "draft deploy handoff" / "ship it"

## Do not invoke when

- Gate has not passed (`validation-and-qa` reported failures)
- Code-review surfaced unaddressed blockers (unaddressed = neither fixed nor covered by a recorded `blocker_waivers:` entry per § When to invoke — a chat-only "operator said it's fine" leaves the blocker unaddressed)
- Security review surfaced missing approval artifacts
- Operator did NOT explicitly ask — this skill's `invocation: manual-for-side-effects` means no auto-trigger

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Spec | `docs/specs/<slug>/spec.md` (status DRAFT) | Stop; cannot deploy without spec |
| Verification gate report | chat paste from `validation-and-qa` | Stop; cannot deploy without gate pass |
| Deploy command | project-specific section of `AGENTS.md` | Stop; ask operator for deploy command |
| Approval artifact for `production_deploy` | `state/approvals/production_deploy-<slug>-<YYYYMMDD>.json` | Stop; operator authors artifact per FR-12 — OR mark `dp1_waiver: eligible` in the handoff when the ticket qualifies (reversible-deploy waiver; Deploy session stamps it at DP.6) |
| Worker-undisturbed list | `policies/protected-paths.yml` | Stop; cannot run final pre-deploy check without it |
| CLI edition map, for Fusebase Apps deploys | `docs/fusebase-cli-edition.md` | Continue with generic deploy handoff, but mark CLI probes/log diagnostics unknown |

## Procedure

1. Verify all preconditions: gate passed, code-review clean **or every open blocker recorded in `blocker_waivers:` (verbatim blocker + operator accept-phrase + accepted consequence — § When to invoke)**, security clean **or recorded `security: N/A — no sensitive surface`**, approval artifact present **or `dp1_waiver: eligible` (Deploy session stamps it on the DP.6 phrase)**.
2. Final pre-deploy worker-undisturbed check: re-run `git diff` against `protected-paths.yml`. If anything changed since the gate report, STOP and report.
3. For Fusebase Apps deploys, use `docs/fusebase-cli-edition.md` to identify supporting CLI assets for commands, logs, app quality checks, and post-deploy diagnostics.
4. Draft deploy handoff from `templates/handoff-deploy.md` (canonical; see `workflows/greenlight-deploy.md`). Include:
   - Self-attestation phrase the deployer should output first
   - **DP.1 waiver eligibility** — `dp1_waiver: eligible|excluded — <reason>`: `eligible` iff the ticket is reversible AND touches no protected path / security surface / migration (Deploy session then stamps the DP.1 artifact itself on the operator's DP.6 phrase); the excluded classes keep operator-run DP.1
   - **`blocker_waivers:` block** (only when open code-review blockers exist) — one entry per blocker: verbatim review-summary line + operator's accept-phrase + accepted consequence. A step-4d/step-5 safety blocker with no entry means the handoff cannot be drafted — STOP and surface the blocker instead
   - Pre-deploy worker-undisturbed re-check instructions
   - Deploy command (exact)
   - **Rollback surface + plan** — classify the deploy per § Rollback-surface classification below and include the surface-appropriate rollback steps; a bare `git revert` plan is valid ONLY for the `code-only` class
   - Probe list (G-M..G-Q or project equivalents from `verification-gate.md`)
   - Smoke prompts S1..Sn (if applicable), copied from the `smoke-testing` contract with success criterion, ground-truth diagnostic, adversarial check, and evidence required
   - Single-docs-commit instructions (FR-14): spec DRAFT→DONE flip with deploy hash, tasks.md verification marks, backlog index update, README header
5. Save handoff to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md` BEFORE outputting in chat (FR-04).
6. Tell operator: "Deploy handoff saved to <path>. Open and paste into the AI Developer (Codex) chat to authorize deploy."
7. After operator pastes back deploy report:
   - Verify deploy hash captured
   - Verify each probe result with concrete evidence
   - Verify smoke results meet threshold from gate contract and satisfy `flow-skills/smoke-testing/SKILL.md` (operator-visible outcome + ground-truth diagnostic, not supporting checks only)
   - Verify single docs commit landed (one SHA covering all post-deploy doc updates)
8. If all verified, acknowledge with summary + tally update + identify what's next (parked backlog options, observation period).
9. If any probe failed, do NOT acknowledge as success. Surface failure with rollback per the handoff's rollback-surface plan (`git revert <hash>` + redeploy ONLY for `code-only`; otherwise the surface-appropriate steps from § Rollback-surface classification) or fix-forward (follow-up task) options. Operator decides.

## Rollback-surface classification

`git revert <hash>` + redeploy only un-ships CODE. Every deploy handoff classifies what the deploy
actually changes and carries a rollback plan matched to that surface. A revert-only plan on a
non-code surface is a false rollback: the code goes back while the migration/secret/sidecar/contract
stays forward.

| Surface class | The deploy changes... | Valid rollback plan | `git revert`+redeploy alone? |
|---|---|---|---|
| `code-only` | app/backend source, assets, config fully re-applied by redeploy | `git revert <hash>` + redeploy | VALID |
| `migration` | DB/dashboard schema, store structure, data backfill | Down-migration or restore path, stated AND checked against data written since deploy; if irreversible, say so explicitly and give the forward-fix path | NOT valid alone |
| `secret/config` | secrets, env vars, third-party keys, permission grants | Restore prior secret/config value (name where the prior value lives); revoke newly-issued credentials | NOT valid alone |
| `sidecar/infra` | sidecar containers, cron registrations, resource tiers | Remove/re-register sidecar/cron to prior state with exact CLI commands (`app-sidecar`, backend cron docs) | NOT valid alone |
| `cross-app contract` | an API surface other apps call (`callAppApi` providers, `*.contract.json`) | Coordinated plan: contract-compatible revert or consumer notification; check dependent apps first (`app-api-contract-testing`) | NOT valid alone |

Classify by the DIFF + deploy steps, not intent: if the deploy runs a migration, writes a secret,
touches sidecars/cron, or changes a provider contract, that class applies even when "the main
change is code." Multi-class deploys carry one plan per class. A Deploy session must refuse a
handoff whose rollback plan does not match its surface class.

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
| Rollback plan mismatched to surface | Handoff for a migration / secret / sidecar / cross-app-contract deploy carries only `git revert` + redeploy | STOP before deploy; reclassify per § Rollback-surface classification and rewrite the rollback plan |
| Open code-review blocker without recorded waiver | Handoff/report carries an open blocker (incl. step-4d correctness / step-5 test blockers) with no matching `blocker_waivers:` entry (verbatim blocker + operator accept-phrase + consequence) | STOP before deploy. A chat-only or paraphrased "operator accepted" is not a waiver — record the entry in the operator's own words, or fix the blocker |

## Escalation path

- Deploy command unknown or platform-blocker emerges → STOP; file `docs/problem-catalog/deploy-blocker-<date>/problem.md`
- Probe infrastructure unavailable → cannot verify; STOP and surface to operator before attempting deploy
- Rollback needed → produce the surface-appropriate steps from the handoff's rollback-surface classification (`git revert` + redeploy only for `code-only`); operator confirms before execution

## Anti-patterns

- Do NOT auto-invoke (`invocation: manual-for-side-effects` enforces this)
- Do NOT deploy without approval artifact (FR-12)
- Do NOT mark spec DONE before all probes pass
- Do NOT split deploy docs across multiple commits (FR-14)
- Do NOT print or persist secrets / session keys in handoff or report
- Do NOT accept `git revert` + redeploy as the rollback plan for a deploy whose surface class is not `code-only` (§ Rollback-surface classification)
- Do NOT skip the final worker-undisturbed re-check even though gate already ran one

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
