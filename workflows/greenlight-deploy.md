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
2. Draft deploy handoff using the template at the bottom of this workflow.
3. Save to `docs/handoff/<YYYY-MM-DD>-<slug>-deploy.md` BEFORE outputting in chat (FR-04).
4. Tell operator: "Deploy handoff saved to <path>. Open and paste into the Implementer chat to authorize deploy."

## Procedure (Deploy phase / Implementer side)

1. Read deploy handoff. Verify approval artifact exists.
2. Self-attest: "Operating as Deploy phase under Fusebase Flow v0.1. I will follow FR-01 through FR-15, including FR-05 (gate fulfilled), FR-06 (reversible by default), FR-07 (worker-undisturbed), FR-12 (approval-gated), FR-14 (single docs commit on deploy)."
3. Final worker-undisturbed re-check before deploy command. If anything changed since gate, STOP.
4. Run deploy command (exact command from `AGENTS.md` project-specific section).
5. Capture deploy hash from command output.
6. Run probes per `verification-gate.md`. For each: report status with concrete evidence (HTTP code + body excerpt, log line, screenshot).
7. Run smoke prompts S1..Sn if applicable. Persist evidence to `docs/handoff/<date>-<slug>-smoke/`.
8. Produce single docs commit (FR-14) covering:
   - `spec.md` DRAFT → DONE with deploy hash captured
   - `tasks.md` verification marks for T<gate>..T<deploy>
   - `docs/backlog/index.md` status flip to DONE with deploy hash
   - README header updates (if applicable)
9. Output deploy report to operator with all required fields.

## Deploy phase self-attestation

> "Operating as Deploy phase under Fusebase Flow v0.1. Gate fulfilled (FR-05). Approval artifact verified (FR-12). I will run final worker-undisturbed re-check (FR-07), run deploy with reversible-by-default discipline (FR-06), capture probes (rule + gate contract), and bundle docs in a single commit (FR-14). I will apply Mode A on chat output and Mode B on the deploy report."

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

S1..Sn from `docs/specs/<slug>/verification-gate.md` smoke section. Persist evidence to `docs/handoff/<date>-<slug>-smoke/`.

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

- `skills/release-deploy-reporting/SKILL.md` — produces this handoff (manual-invoke)
- `workflows/verification-gate.md` — gate contract referenced for probes
- `workflows/smoke-verification.md` — smoke procedure
- `policies/approval-policy.yml` — `production_deploy` approval requirement
- `policies/protected-paths.yml` — worker-undisturbed list
