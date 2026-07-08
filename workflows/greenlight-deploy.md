# Workflow: greenlight-deploy

> **Style:** Mode-B-lite. The handoff that authorizes deploy past the verification gate.

## When to run

After:
- `validation-and-qa` confirms gate passed
- `code-review` confirms zero blockers — OR every still-open blocker carries a **recorded waiver** in the deploy handoff's `blocker_waivers:` block: verbatim review-summary blocker line + the operator's own accept-phrase naming it + the accepted consequence (the concrete failing scenario / missing test being shipped). Safety blockers (correctness defect — code-review step 4d; missing/meaningless tests — step 5) are never downgradable to "non-blocker"; they ship only under such a named waiver. A bare "operator accepted the blockers" — unquoted, unnamed, unrecorded — does NOT satisfy this (`flow-skills/release-deploy-reporting/SKILL.md` § When to invoke)
- `security-permissions-review` confirms approval artifacts in place per `approval-policy.yml` — invoked only when the diff matches the skill's trigger list (auth, permissions, secrets, env, deploy config, external messages, production data); otherwise the review summary records `security: N/A — no sensitive surface`
- Operator explicitly says "draft deploy" / "ship it" / "prepare deploy"

## Procedure (Product Owner side, via release-deploy-reporting skill)

1. Final pre-deploy checklist:
   - [ ] Approval artifact for `production_deploy` exists at `state/approvals/production_deploy-<slug>-<date>.json` — OR the handoff marks `dp1_waiver: eligible` (reversible-deploy waiver below; the Deploy session stamps the artifact at DP.6) <!-- prevents: unauthorized-deploy (catastrophic-low-frequency) — taxonomy: policies/ratchet-governance.yml -->
   - [ ] Worker-undisturbed re-check: run `git diff` against `protected-paths.yml`. Must be empty (or bounded per spec)
   - [ ] Gate passed; code-review zero blockers — OR every open blocker recorded in the handoff's `blocker_waivers:` block (verbatim blocker + operator accept-phrase + consequence; safety blockers per code-review step 4d / step 5 are non-downgradable); security clean
   - [ ] Spec is still DRAFT (will flip to DONE in this deploy)
2. **Author handoff from `templates/handoff-deploy.md`** (v2.5.0+). The template includes a role-bootstrap prelude that makes the handoff self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up. Do NOT hand-roll the prelude; copy from the template so DP.6 + DP.1 invariants stay canonical.
3. Save to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md` BEFORE outputting in chat (FR-04). Fill in placeholders (slug, approval artifact path, deploy command, probe table, smoke pointers).
4. Tell operator: "Deploy handoff saved to `<path>`. Paste this into the AI Developer chat (fresh or existing) — the file is self-bootstrapping: `Execute docs/tmp/handoff/<path>`."

## Procedure (Deploy phase / AI Developer side)

1. Read deploy handoff. Verify approval artifact exists — or, on a `dp1_waiver: eligible` handoff, note that you will stamp it at step 4 (waiver below).
2. Self-attest: "Operating as Deploy phase under Fusebase Flow v3.31.0. I will follow FR-01 through FR-27, including FR-05 (gate fulfilled), FR-06 (reversible by default), FR-07 (worker-undisturbed), FR-12 (approval-gated), FR-14 (single docs commit on deploy), FR-19 (chat-text questions). I will apply the role-discipline skill section for Deploy phase (DP.1..DP.12)."
3. Final worker-undisturbed re-check before deploy command. If anything changed since gate, STOP. <!-- prevents: silent-protected-path-drift — taxonomy: policies/ratchet-governance.yml -->
4. **Operator confirm (DP.6 + FR-19).** Ask the operator in chat text to type the literal `APPROVE-DEPLOY-NOW` phrase. Do not use popup / clickable menu tools. If the response is anything other than the exact phrase, ABORT the deploy and surface the abort. The operator can re-issue the deploy by re-running this workflow in a fresh session. <!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) — taxonomy: policies/ratchet-governance.yml -->
   **Reversible-deploy waiver (DP.1 auto-stamp):** when the handoff marks `dp1_waiver: eligible` (ticket is reversible AND touches no protected path, security surface, or migration), the operator's typed DP.6 phrase also authorizes you to stamp the DP.1 artifact yourself — run `bash hooks/local/approve-local.sh production_deploy <slug> 'APPROVE-DEPLOY-NOW'`, then proceed. The artifact still exists on disk (FR-12 + hook semantics unchanged); only the stamping party changes. `dp1_waiver: excluded` (migration / security / protected-path classes) keeps operator-run DP.1 — never stamp those yourself.
5. Run deploy command (exact command from `AGENTS.md` project-specific section).
6. Capture deploy hash from command output.
7. Run probes per `verification-gate.md`. For each: report status with concrete evidence (HTTP code + body excerpt, log line, screenshot). **Delegated/deploy sessions complete all evidence IN-TURN** — poll with bounded sleeps or read durable records (`smoke-testing` § Verification cost discipline); never end the turn "watching in background" (a delegated session cannot self-resume). **Progress ledger (`task-delegation` §3):** append each probe result to the smoke evidence files / deploy-report draft AS IT LANDS — skeleton first, rows as earned; never hold all evidence for an end-of-run write (a dying session loses everything unwritten).
8. Run smoke prompts S1..Sn if applicable under `flow-skills/smoke-testing/SKILL.md`. Smoke PASS requires operator-visible outcome evidence plus ground-truth diagnostic inspection; supporting checks alone are incomplete. Persist evidence to `docs/tmp/handoff/<date>-<slug>-smoke/`. <!-- prevents: false-green-deploy — taxonomy: policies/ratchet-governance.yml -->
9. Produce single docs commit (FR-14) covering:
   - `spec.md` DRAFT → DONE with deploy hash captured
   - `tasks.md` verification marks for T<gate>..T<deploy>
   - `docs/backlog/index.md` status flip to DONE with deploy hash
   - README header updates (if applicable)
10. Output deploy report **using `templates/deploy-report.md`** (v2.6.0+). The template includes a section-8 operator-relay block that the operator copies into PO chat for closeout — per FR-16, the Deploy phase composes this block so the operator doesn't have to scan the technical body. Filled-template fields: pre-deploy verification, deploy command output, probe results table, smoke results, FR-14 commit SHA, operator-side pending actions (literal commands), total deploy duration, section 8 operator-relay block (mandatory).

## Deploy phase self-attestation

Per `FLOW_RULES.md` § Self-attestation (FR-01..FR-27); name Deploy phase as the role and `flow-skills/role-discipline/references/deploy.md` (DP.1..DP.12; entry: role-discipline SKILL.md). DP.6 (magic-phrase confirm), DP.1 (approval artifact), DP.10 (smoke evidence integrity), DP.11 (no delegated deploy side effects), and FR-19 (chat-text questions) are the load-bearing gates for this phase.

## State announcement (every output)

```
---
📍 Phase: Deploy
🎯 Ticket: <slug>
✅ Gate: passed (<gate report SHA>)
⏭️ Next: <step in deploy sequence>
```

## Pre-deploy worker-undisturbed re-check (mandatory)

```
Pre-deploy worker-undisturbed verification:
<file-1>: empty diff ✓
<file-2>: empty diff ✓
<file-3>: bounded to <function-names> ✓
...

→ All clear. Deploying.
```

If anything has changed since gate report, STOP and surface to operator. Do NOT deploy on changed protected paths (FR-07).

## Probe completeness (mandatory before reporting deploy)

```
Probe results:
☐ G-M deploy success: <pass/fail + evidence>
☐ G-N health probe: <pass/fail + evidence>
☐ G-O feature surface probe: <pass/fail + evidence>
☐ G-P feature behavior probe: <pass/fail + evidence>
☐ G-Q spec flip + backlog index update: <confirmed>
```

## Probe failure response

If ANY probe fails:
- Do NOT mark spec DONE
- Surface failure with `Pn observed Y, expected Z`
- Recovery options:
  - Rollback: `git revert <hash>` + redeploy ONLY for a `code-only` deploy. For a migration / secret/config / sidecar/infra / cross-app-contract deploy a revert un-ships only the code (schema/data/secret/sidecar/contract stay forward) — execute the surface-appropriate plan from the handoff (`flow-skills/release-deploy-reporting/SKILL.md` § Rollback-surface classification)
  - Fix-forward: file follow-up task; spec stays DRAFT
- Operator decides which path

## Handoff content template

The canonical deploy handoff template (role-bootstrap prelude, ticket header incl. `dp1_waiver`, probes, smoke, FR-14 docs commit, rollback) lives at `templates/handoff-deploy.md` — copy it and fill placeholders; never hand-roll.

## Related

- `templates/handoff-deploy.md` — **canonical deploy handoff template** (v2.5.0+); copy + fill placeholders for new handoffs
- `templates/deploy-report.md` — **canonical deploy report template** (v2.6.0+); Deploy phase fills this after T<deploy>; section 8 is the operator-relay block per FR-16
- `flow-skills/release-deploy-reporting/SKILL.md` — produces this handoff (manual-invoke)
- `flow-skills/role-discipline/SKILL.md` — PO section includes the **Operator Relay Protocol** (FR-16) used when operator pastes the deploy report back to PO for closeout
- `flow-skills/smoke-testing/SKILL.md` — outcome-based smoke definition/execution discipline
- `workflows/verification-gate.md` — gate contract referenced for probes
- `workflows/smoke-verification.md` — smoke procedure
- `policies/approval-policy.yml` — `production_deploy` approval requirement
- `policies/protected-paths.yml` — worker-undisturbed list