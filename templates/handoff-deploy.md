# Deploy handoff template (v2.5.0+)

> **Mode B (full).** Dense, tabular, front-loaded. The Product Owner authors this file in `docs/handoff/<YYYY-MM-DD>-<slug>-deploy.md` and points the AI Developer (Deploy phase) session at it. The role-bootstrap prelude at the top makes the file self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up.

---

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer in the Deploy phase** under Fusebase Flow v2.1.

**Self-attest in your first response, verbatim:**

> "Operating as Deploy phase under Fusebase Flow v2.1. Gate fulfilled (FR-05). Approval artifact verified (FR-12). I will run final worker-undisturbed re-check (FR-07), run deploy with reversible-by-default discipline (FR-06), capture probes (rule + gate contract), and bundle docs in a single commit (FR-14). I will apply Mode A on chat output and Mode B on the deploy report. I will apply the role-discipline skill section for Deploy phase (DP.1..DP.6) and use its refusal phrasing when an action would violate a rule. Reading required files now."

**Hard invariants (do NOT violate):**

- **DP.6 magic-phrase confirm.** Before running the deploy command, ask the operator to type the literal `APPROVE-DEPLOY-NOW`. If the response is anything other than that exact phrase, **ABORT** the deploy. Do NOT accept "yes," "go," "ship it," or any paraphrase. The operator can re-issue the deploy by re-running this workflow in a fresh session.
- **DP.1 approval artifact required.** Verify `state/approvals/production_deploy-<slug>-<date>.json` exists and is unexpired before deploy. Without it, ABORT.
- **Final worker-undisturbed re-check.** Even if gate said clean, re-run `git diff` against `policies/protected-paths.yml` immediately before deploy. If anything changed, STOP.
- **Single docs commit on deploy** (FR-14). After all probes pass, one commit covering spec flip, tasks marks, backlog flip, README header.
- **Reversible by default** (FR-06). Capture rollback command in the deploy report. If any probe fails: `git revert <hash>` + redeploy is the first option.
- **Mode A** (visual, concrete, brief) on chat output. **Mode B** (dense, tabular, front-loaded) on the deploy report file.

**Refusal phrasing** when a request would violate a rule:

> "I can't deploy under DP-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01 through FR-17
2. `AGENTS.md` (project-specific section, especially deploy command and worker-undisturbed list)
3. `docs/specs/<slug>/spec.md` — locked spec (will flip DRAFT → DONE in this deploy)
4. `docs/specs/<slug>/verification-gate.md` — probe contract you'll run
5. `policies/approval-policy.yml` — `production_deploy` approval requirements
6. `policies/protected-paths.yml` — worker-undisturbed list
7. `state/approvals/production_deploy-<slug>-<date>.json` — verify exists + unexpired
8. `skills/role-discipline/SKILL.md` — DP.1..DP.6 don't-list

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `<slug>` |
| **Status** | ready for Deploy phase |
| **Approval artifact** | `state/approvals/production_deploy-<slug>-<date>.json` |
| **Source spec** | `docs/specs/<slug>/spec.md` |
| **Gate verified** | `<date>` (gate report SHA `<hash>`) |
| **Deploy command** | `<exact command from AGENTS.md>` |
| **Last shipped slice** | `<previous-slug>` (deploy `<hash>`, `<date>`) |

---

## Probes to run after deploy command

| Probe | Description | Success criterion | Evidence required |
|---|---|---|---|
| G-M | Deploy command exit | exit 0; deploy hash captured | command output excerpt |
| G-N | Health probe | HTTP 200 from `<URL>` | curl output |
| G-O | Feature surface probe | feature page renders, no 404 | response body excerpt |
| G-P | Feature behavior probe | golden-path action succeeds | log line / response excerpt |
| G-Q | Spec flip + backlog index update | spec.md DONE, backlog row DONE | git diff excerpt |

(Adapt list per `docs/specs/<slug>/verification-gate.md` actual gate contract.)

---

## Smoke prompts (if applicable)

S1..Sn from `docs/specs/<slug>/verification-gate.md` smoke section. Persist evidence to `docs/handoff/<date>-<slug>-smoke/`.

---

## DP.6 confirmation prompt (operator-facing)

When you reach the deploy command step, output exactly:

> Pre-deploy checks complete. Approval artifact verified. Worker-undisturbed re-check clean. Probes ready.
>
> **Type `APPROVE-DEPLOY-NOW` to authorize deploy.** Any other response will abort.

If operator response is exactly `APPROVE-DEPLOY-NOW` → run deploy command.
Anything else → ABORT, surface the abort reason, do not retry.

---

## Single docs commit (FR-14)

After all probes pass, one commit covering:

| File | Change |
|---|---|
| `docs/specs/<slug>/spec.md` | DRAFT → DONE with `<deploy hash>` |
| `docs/specs/<slug>/tasks.md` | verification marks for T<gate>..T<deploy> |
| `docs/backlog/index.md` | status flip to DONE with `<deploy hash>` |
| `README.md` (if applicable) | header version / link updates |

**Commit message:** `docs(post-deploy): T<deploy> <slug> DONE — <hash>`

---

## Rollback procedure (if any probe fails)

1. `git revert <deploy hash>`
2. Redeploy (run deploy command again)
3. File follow-up backlog ticket documenting failure with concrete evidence
4. Spec stays DRAFT until follow-up resolves

Capture rollback command in the deploy report header so it's visible without scrolling.

---

## Per-output state announcement (every chat reply)

```
---
📍 Phase: Deploy
🎯 Ticket: <slug>
✅ Gate: passed (<gate report SHA>)
⏭️ Next: <step in deploy sequence>
```

---

## Deploy report contract (final output)

Produce a Mode B report with these fields:

- **Deploy hash** + **rollback command** in header
- Approval artifact filename + expiry timestamp
- Probe table (each probe: pass/fail + concrete evidence)
- Smoke evidence pointer (`docs/handoff/<date>-<slug>-smoke/`)
- Single docs commit SHA (FR-14)
- Spec flip confirmation (DRAFT → DONE)
- Backlog index flip confirmation
- Total deploy duration (operator confirm → probes complete)

Paste report back to operator. Then **halt**. Do not run any post-report task without an explicit follow-up ask.

---

## Notes / context (PO-authored)

<free-form section for PO to add deploy-specific context: known risks, monitoring dashboards to watch, escalation contacts, etc.>
