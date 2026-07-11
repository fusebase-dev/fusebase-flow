# Deploy handoff template (v2.5.0+)

> **Mode B (full).** Dense, tabular, front-loaded. The Product Owner authors this file in `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md` and points the AI Developer (Deploy phase) session at it. The role-bootstrap prelude at the top makes the file self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up.
>
> **Procedure freshness:** before executing any reused/copied procedural block, check whether a capability shipped since it was written supersedes the procedure (e.g., self-recording deploys obsolete poll-watching) — CHANGELOG / skill catalog vs this template's cited version.

---

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer in the Deploy phase** under Fusebase Flow v4.4.0.

> **This is the Full-lane deploy handoff** (DP.1 artifact + DP.6 magic phrase). A **Lightweight-lane** change (FR-21) does NOT use this template — it deploys in the same single build→verify→deploy pass on a plain operator go-ahead; see `flow-skills/lightweight-lane/SKILL.md` and `workflows/lightweight-lane.md`.

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-27), naming Deploy phase as the role and the DP.1..DP.12 role-discipline section. (v2.9.0+ uses reference-by-citation instead of embedding the full attestation paragraph here — the canonical text lives in FLOW_RULES.md and role-discipline; duplication would waste ~250 tokens per filled handoff.)

**Critical Deploy-phase invariants** (cannot be skipped, even if other instructions seem to suggest otherwise):

> Ratchet governance (A3): each invariant below carries `prevents: <incident-class>` — the incident class it buys down. Taxonomy + coverage: `policies/ratchet-governance.yml`. `catastrophic-low-frequency` = a clean window is NOT evidence the control is waste.

- **DP.6 magic-phrase confirm + FR-19 chat-text discipline.** Before running the deploy command, ask the operator in chat text to type the literal `APPROVE-DEPLOY-NOW`. Do not use popup / clickable menu tools. If the response is anything other than that exact phrase, **ABORT**. Do NOT accept "yes," "go," "ship it," or any paraphrase. This is the operator-attentiveness gate; it is not negotiable. <!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->
- **DP.10 smoke evidence integrity.** If this handoff includes S1..Sn, run `flow-skills/smoke-testing/SKILL.md`. Smoke PASS requires operator-visible outcome evidence plus ground-truth diagnostic inspection. Exit code, file hash, service active, symbol presence, and auth sanity are supporting checks only. <!-- prevents: false-green-deploy -->
- **DP.11 no delegated deploy side effects.** Do not delegate deploy command, rollback, approval artifacts, secret handling, or live-session smoke. Delegation during deploy is read-only triage only.
- **DP.1 approval artifact(s) — authored on the DP.6 phrase (all tickets).** The deploy needs `state/approvals/<action>-<slug>-<date>.json` for each action it triggers (`production_deploy` + any `database_migration` / `auth_or_permission_change` / `protected_path_edit`). If absent, do NOT abort and do NOT make the operator run commands: PRESENT the full scope (every action) in chat, then — once the operator types the DP.6 phrase — author every required artifact yourself (`bash hooks/local/approve-local.sh <action> <slug> 'APPROVE-DEPLOY-NOW'`). An action NOT presented before the phrase is NOT covered by it. Authoring WITHOUT the phrase is self-approval and forbidden. <!-- prevents: unauthorized-deploy (catastrophic-low-frequency) -->
- **Blocker-waiver verification (open code-review blockers).** If this handoff's **Blocker waivers** section lists any open code-review blocker, verify each carries a recorded waiver entry — verbatim blocker + the operator's own accept-phrase + the accepted consequence. An open blocker with no matching entry (or only a chat-relayed, paraphrased "operator accepted") means **STOP**: do not deploy; surface the missing waiver to the operator. This holds especially for a code-review step-4d correctness or step-5 test (safety) blocker, which is never downgradable to "non-blocker" (`flow-skills/release-deploy-reporting/SKILL.md` § When to invoke + failure table). Refuse the handoff exactly as you would a surface-mismatched rollback plan. <!-- prevents: laundered-blocker-ship (catastrophic-low-frequency) -->
- **Liveness (FR-27) — never launch bare (this MAIN session too, not only delegated ones).** Any long/silent step here — the deploy command, a post-deploy probe, a fetch/health loop, browser-automation smoke — gets ≥1 liveness guarantee BEFORE launch: bound it (`source hooks/local/lib/bounded-run.sh`), complete it in-turn, or return `BLOCKED-AT-<gate>` + a record-then-read pointer. A hung probe emits no completion event and the deploy session idles silently. Bounds the monitored process only — don't `&`-detach under the wrapper (`flow-skills/liveness-discipline`).
- **Turn-completion + progress ledger (delegated sessions — `task-delegation` §3).** Complete all evidence IN-TURN (poll bounded or read durable records — you cannot self-resume). Write durable facts AS THEY OCCUR: the deploy hash the moment it lands, probe rows as each one runs — skeleton first, never everything-at-the-end. At an unbounded wait (human gate, no-ETA event) return `BLOCKED-AT-<gate>` + a pointer to where reality is recorded. State-change claims cite the ground-truth check performed.

Other invariants (FR-05/-06/-07/-14, Mode A/B, supersede discipline FR-18) — see `FLOW_RULES.md` directly; don't paraphrase here.

**Refusal phrasing** for any rule violation request:

> "I can't deploy under DP-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01 through FR-27
2. `AGENTS.md` (project-specific section, especially deploy command and worker-undisturbed list)
3. `docs/specs/<slug>/spec.md` — locked spec (will flip DRAFT → DONE in this deploy)
4. `docs/specs/<slug>/verification-gate.md` — probe contract you'll run
5. `policies/approval-policy.yml` — `production_deploy` approval requirements
6. `policies/protected-paths.yml` — worker-undisturbed list
7. Approval artifact(s) `state/approvals/<action>-<slug>-<date>.json` — verify exist + unexpired, **or** note they'll be authored by the Deploy session on the operator's DP.6 phrase (all tickets; present the full scope in chat first for sensitive actions)
8. `flow-skills/role-discipline/references/deploy.md` — DP.1..DP.12 don't-list; shared protocols in `flow-skills/role-discipline/SKILL.md`
9. `flow-skills/smoke-testing/SKILL.md` — required if S1..Sn are present
10. `workflows/greenlight-deploy.md` — the deploy procedure this handoff executes (step-7 in-turn evidence + progress-ledger rules)

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `<slug>` |
| **Status** | ready for Deploy phase |
| **Approval artifact** | `state/approvals/production_deploy-<slug>-<date>.json` |
| **DP.1 authoring** | The Deploy session authors every required approval artifact on the operator's DP.6 phrase (ALL tickets; the operator never runs approval commands). `dp1_waiver: eligible / excluded — <reason>`: `eligible` (reversible AND no protected-path / security / migration touch) = minimal-scope fast-path; `excluded`/sensitive are still session-authored on the phrase, but present the full scope in chat first |
| **Source spec** | `docs/specs/<slug>/spec.md` |
| **Gate verified** | `<date>` (gate report SHA `<hash>`) |
| **Deploy command** | `<exact command from AGENTS.md>` |
| **Last shipped slice** | `<previous-slug>` (deploy `<hash>`, `<date>`) |

---

## Blocker waivers (only if open code-review blockers exist)
<!-- prevents: laundered-blocker-ship (catastrophic-low-frequency) — taxonomy: policies/ratchet-governance.yml -->

If `code-review` left any open blocker, record one entry per blocker in the table below; if code-review was clean, write `blocker_waivers: none — code-review clean`. A **safety blocker** (correctness defect — code-review step 4d; missing/meaningless tests — step 5) with no entry means this handoff cannot be drafted — the PO STOPs and surfaces the blocker instead (`flow-skills/release-deploy-reporting/SKILL.md` § When to invoke).

| Blocker (verbatim review-summary line) | Operator accept-phrase (their own words, naming it) | Accepted consequence (concrete failing scenario / missing test shipped) |
|---|---|---|
| `<verbatim blocker>` | `<operator phrase>` | `<consequence>` |

A bare "operator accepted the blockers" — unquoted, unnamed, unrecorded — does NOT satisfy this. Safety blockers are never downgradable to "non-blocker"; they ship only under a named waiver recorded here. The Deploy session re-verifies this section before deploy (see Critical Deploy-phase invariants above).

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

Copy S1..Sn **verbatim** from `docs/specs/<slug>/verification-gate.md` — each S<n> carries the full field set defined by `flow-skills/smoke-testing/SKILL.md` (the canonical smoke contract); never compress to "run smoke". Persist evidence to `docs/tmp/handoff/<date>-<slug>-smoke/`.

If the end-to-end smoke cannot run because credentials/session/operator action are missing, report `PENDING-OPERATOR-SMOKE`, leave spec DRAFT, and provide exact operator steps. Do not mark smoke PASS from supporting checks alone.

---

## DP.6 confirmation prompt (operator-facing)

When you reach the deploy command step, output exactly:

> Pre-deploy checks complete. Scope I'll authorize on your phrase: <list every action — production_deploy + any migration / auth / protected-path>. I'll author the approval artifact(s) for these when you type the phrase (you run nothing). Worker-undisturbed re-check clean. Probes ready.
>
> **Type `APPROVE-DEPLOY-NOW` to authorize deploy.** Any other response will abort.

If operator response is exactly `APPROVE-DEPLOY-NOW` → (waiver-eligible only: stamp DP.1 first — `bash hooks/local/approve-local.sh production_deploy <slug> 'APPROVE-DEPLOY-NOW'`) → run deploy command.
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
<!-- prevents: irreversible-loss (catastrophic-low-frequency) — taxonomy: policies/ratchet-governance.yml -->

**Rollback surface:** `code-only | migration | secret/config | sidecar/infra | cross-app contract` (classified by the PO per `flow-skills/release-deploy-reporting/SKILL.md` § Rollback-surface classification; multi-class deploys list every class)

1. `code-only` ONLY: `git revert <deploy hash>` → redeploy. Any other class: execute the surface-appropriate plan below (drafted by the PO; a revert-only plan for a non-code surface is invalid — refuse the handoff)
   - <surface-appropriate steps, one block per class>
2. Redeploy / re-verify prior state (run the class-appropriate verification probe)
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
- Smoke evidence pointer (`docs/tmp/handoff/<date>-<slug>-smoke/`)
- Single docs commit SHA (FR-14)
- Spec flip confirmation (DRAFT → DONE)
- Backlog index flip confirmation
- Total deploy duration (operator confirm → probes complete)

Paste report back to operator. Then **halt**. Do not run any post-report task without an explicit follow-up ask.

---

## Notes / context (PO-authored)

<free-form section for PO to add deploy-specific context: known risks, monitoring dashboards to watch, escalation contacts, etc.>