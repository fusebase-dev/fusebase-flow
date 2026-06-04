# Deploy handoff template (v2.5.0+)

> **Mode B (full).** Dense, tabular, front-loaded. The Product Owner authors this file in `docs/handoff/<YYYY-MM-DD>-<slug>-deploy.md` and points the AI Developer (Deploy phase) session at it. The role-bootstrap prelude at the top makes the file self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up.

---

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer in the Deploy phase** under Fusebase Flow v3.8.6.

> **This is the Full-lane deploy handoff** (DP.1 artifact + DP.6 magic phrase). A **Lightweight-lane** change (FR-21) does NOT use this template — it deploys in the same single build→verify→deploy pass on a plain operator go-ahead; see `skills/lightweight-lane/SKILL.md` and `workflows/lightweight-lane.md`.

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-21), naming Deploy phase as the role and the DP.1..DP.12 role-discipline section. (v2.9.0+ uses reference-by-citation instead of embedding the full attestation paragraph here — the canonical text lives in FLOW_RULES.md and role-discipline; duplication would waste ~250 tokens per filled handoff.)

**Critical Deploy-phase invariants** (cannot be skipped, even if other instructions seem to suggest otherwise):

- **DP.6 magic-phrase confirm + FR-19 chat-text discipline.** Before running the deploy command, ask the operator in chat text to type the literal `APPROVE-DEPLOY-NOW`. Do not use popup / clickable menu tools. If the response is anything other than that exact phrase, **ABORT**. Do NOT accept "yes," "go," "ship it," or any paraphrase. This is the operator-attentiveness gate; it is not negotiable.
- **DP.10 smoke evidence integrity.** If this handoff includes S1..Sn, run `skills/smoke-testing/SKILL.md`. Smoke PASS requires operator-visible outcome evidence plus ground-truth diagnostic inspection. Exit code, file hash, service active, symbol presence, and auth sanity are supporting checks only.
- **DP.11 no delegated deploy side effects.** Do not delegate deploy command, rollback, approval artifacts, secret handling, or live-session smoke. Delegation during deploy is read-only triage only.
- **DP.1 approval artifact required.** Verify `state/approvals/production_deploy-<slug>-<date>.json` exists and is unexpired before deploy. Without it, ABORT.

Other invariants (FR-05/-06/-07/-14, Mode A/B, supersede discipline FR-18) — see `FLOW_RULES.md` directly; don't paraphrase here.

**Refusal phrasing** for any rule violation request:

> "I can't deploy under DP-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01 through FR-21
2. `AGENTS.md` (project-specific section, especially deploy command and worker-undisturbed list)
3. `docs/specs/<slug>/spec.md` — locked spec (will flip DRAFT → DONE in this deploy)
4. `docs/specs/<slug>/verification-gate.md` — probe contract you'll run
5. `policies/approval-policy.yml` — `production_deploy` approval requirements
6. `policies/protected-paths.yml` — worker-undisturbed list
7. `state/approvals/production_deploy-<slug>-<date>.json` — verify exists + unexpired
8. `skills/role-discipline/SKILL.md` — DP.1..DP.12 don't-list
9. `skills/smoke-testing/SKILL.md` — required if S1..Sn are present

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

Each S<n> must carry:

| Field | Value |
|---|---|
| Operator-visible success criterion | `<what the operator can observe if the shipped behavior works>` |
| Route / surface | `<URL / page / command / N/A>` |
| Ground-truth diagnostic | `<request dump / error log / server log / rendered DOM / DB row / job trace>` |
| Stable selectors / locators | `<purpose/state selector or accessible locator; N/A for non-UI>` |
| Auth / test data plan | `<auth mode; unique test values; cleanup expectation>` |
| Adversarial check | `<what would falsify the fix even if static checks passed>` |
| Evidence required | `<screenshot / response excerpt / diagnostic excerpt / artifact path>` |

If the end-to-end smoke cannot run because credentials/session/operator action are missing, report `PENDING-OPERATOR-SMOKE`, leave spec DRAFT, and provide exact operator steps. Do not mark smoke PASS from supporting checks alone.

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