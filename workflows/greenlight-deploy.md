# Workflow: greenlight-deploy

> **Style:** Mode-B-lite. The handoff that authorizes deploy past the verification gate.

## When to run

After:
- `validation-and-qa` confirms gate passed
- `code-review` confirms zero blockers (or operator accepted them as non-blockers)
- `security-permissions-review` confirms approval artifacts in place per `approval-policy.yml`
- Operator explicitly says "draft deploy" / "ship it" / "prepare deploy"

## Procedure (Product Owner side, via release-deploy-reporting skill)

1. Final pre-deploy checklist:
   - [ ] Approval artifact for `production_deploy` exists at `state/approvals/production_deploy-<slug>-<date>.json`
   - [ ] Worker-undisturbed re-check: run `git diff` against `protected-paths.yml`. Must be empty (or bounded per spec)
   - [ ] Gate passed; code-review zero blockers; security clean
   - [ ] Spec is still DRAFT (will flip to DONE in this deploy)
2. **Author handoff from `templates/handoff-deploy.md`** (v2.5.0+). The template includes a role-bootstrap prelude that makes the handoff self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up. Do NOT hand-roll the prelude; copy from the template so DP.6 + DP.1 invariants stay canonical.
3. Save to `docs/handoff/<YYYY-MM-DD>-<slug>-deploy.md` BEFORE outputting in chat (FR-04). Fill in placeholders (slug, approval artifact path, deploy command, probe table, smoke pointers).
4. Tell operator: "Deploy handoff saved to `<path>`. Paste this into the AI Developer chat (fresh or existing) — the file is self-bootstrapping: `Execute docs/handoff/<path>`."

## Procedure (Deploy phase / AI Developer side)

1. Read deploy handoff. Verify approval artifact exists.
2. Self-attest: "Operating as Deploy phase under Fusebase Flow v3.10.0. I will follow FR-01 through FR-22, including FR-05 (gate fulfilled), FR-06 (reversible by default), FR-07 (worker-undisturbed), FR-12 (approval-gated), FR-14 (single docs commit on deploy), FR-19 (chat-text questions). I will apply the role-discipline skill section for Deploy phase (DP.1..DP.12)."
3. Final worker-undisturbed re-check before deploy command. If anything changed since gate, STOP.
4. **Operator confirm (DP.6 + FR-19).** Ask the operator in chat text to type the literal `APPROVE-DEPLOY-NOW` phrase. Do not use popup / clickable menu tools. If the response is anything other than the exact phrase, ABORT the deploy and surface the abort. The operator can re-issue the deploy by re-running this workflow in a fresh session.
5. Run deploy command (exact command from `AGENTS.md` project-specific section).
6. Capture deploy hash from command output.
7. Run probes per `verification-gate.md`. For each: report status with concrete evidence (HTTP code + body excerpt, log line, screenshot).
8. Run smoke prompts S1..Sn if applicable under `flow-skills/smoke-testing/SKILL.md`. Smoke PASS requires operator-visible outcome evidence plus ground-truth diagnostic inspection; supporting checks alone are incomplete. Persist evidence to `docs/handoff/<date>-<slug>-smoke/`.
9. Produce single docs commit (FR-14) covering:
   - `spec.md` DRAFT → DONE with deploy hash captured
   - `tasks.md` verification marks for T<gate>..T<deploy>
   - `docs/backlog/index.md` status flip to DONE with deploy hash
   - README header updates (if applicable)
10. Output deploy report **using `templates/deploy-report.md`** (v2.6.0+). The template includes a section-8 operator-relay block that the operator copies into PO chat for closeout — per FR-16, the Deploy phase composes this block so the operator doesn't have to scan the technical body. Filled-template fields: pre-deploy verification, deploy command output, probe results table, smoke results, FR-14 commit SHA, operator-side pending actions (literal commands), total deploy duration, section 8 operator-relay block (mandatory).

## Deploy phase self-attestation

Per `FLOW_RULES.md` § Self-attestation (FR-01..FR-22); name Deploy phase as the role and `flow-skills/role-discipline/SKILL.md` § Deploy phase (DP.1..DP.12). DP.6 (magic-phrase confirm), DP.1 (approval artifact), DP.10 (smoke evidence integrity), DP.11 (no delegated deploy side effects), and FR-19 (chat-text questions) are the load-bearing gates for this phase.

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
  - Rollback: `git revert <hash>` + redeploy
  - Fix-forward: file follow-up task; spec stays DRAFT
- Operator decides which path

## Handoff content template

> **As of v2.5.0, the canonical deploy handoff template lives at `templates/handoff-deploy.md`** with a role-bootstrap prelude built in. PO sessions should copy that file and fill in placeholders, rather than hand-rolling from the snippet below. The snippet is retained for legacy reference and to show the body shape; **prefer the standalone template** for new handoffs.

```markdown
# Deploy handoff — <slug> (<YYYY-MM-DD>)

**Status:** ready for Deploy phase
**Approval artifact:** `state/approvals/production_deploy-<slug>-<date>.json`
**Source spec:** `docs/specs/<slug>/spec.md`
**Gate verified:** <date> (gate report SHA <hash>)

## Mandatory pre-execution

1. Self-attest as Deploy phase
2. Final worker-undisturbed re-check (`git diff` against `protected-paths.yml`)
3. If clean: proceed to deploy command. If not: STOP and report.

## Deploy command

```
<exact command from AGENTS.md>
```

## Probes (run after deploy command)

1. G-M: <description, success criterion>
2. G-N: <description, success criterion>
3. G-O: <description, success criterion>
4. G-P: <description, success criterion>
5. G-Q: <description, success criterion>

## Smoke prompts (if applicable)

S1..Sn from `docs/specs/<slug>/verification-gate.md` smoke section. Each S<n> must include an operator-visible success criterion, ground-truth diagnostic, adversarial check, and evidence requirement per `flow-skills/smoke-testing/SKILL.md`. Persist evidence to `docs/handoff/<date>-<slug>-smoke/`.

## Single docs commit (FR-14)

After all probes pass, one commit covering:
- spec.md DRAFT → DONE with `<deploy hash>`
- tasks.md verification marks
- docs/backlog/index.md status flip
- README header (if applicable)

Commit message: `docs(post-deploy): T<deploy> <slug> DONE — <hash>`

## Rollback procedure (if any probe fails)

1. `git revert <deploy hash>`
2. Redeploy (run deploy command again)
3. File follow-up backlog ticket documenting failure
4. Spec stays DRAFT until follow-up resolves
```

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