# Deploy report template (v2.6.0+)

> **Mode B (full).** This template is what the **AI Developer in Deploy phase** produces after completing T<deploy> (deploy command + probes + smoke + single docs commit per FR-14). Two sections: the **technical deploy body** (for the PO's audit work — verifying probes, FR-14 commit landed, rollback option visible) and the **operator relay block** at the bottom (a copy-paste-ready chunk the operator pastes into PO chat).
>
> Per FR-16, the Deploy phase composes the operator-relay block — operator never digests the technical body. Scroll → copy → paste in PO chat.
>
> **Self-recording systems (FR-23):** if the system under test has durable evidence surfaces (journals, run records, logs, snapshots), report fields carry POINTERS to them — transcribe only what no system records.

---

## Use this template when

You are an AI Developer Deploy-phase session that has just completed T<deploy> (deploy command, probes, smoke, single docs commit). Don't ad-hoc the deploy report — copy this template, fill it in, output it as your final response.

---

## Template body

```markdown
# Deploy report — <slug> (T<deploy>)

**Status:** Deploy complete; awaiting PO closeout
**Slug:** `<slug>`
**Deploy hash:** `<hash>` ← rollback: `<from the handoff's Rollback surface — `git revert <hash>` only if code-only; else the surface-appropriate plan>`
**Approval artifact:** `state/approvals/production_deploy-<slug>-<date>.json` (expires `<timestamp>`)
**Reporting session:** AI Developer / Deploy phase under Fusebase Flow v4.1.0 (FR-01..FR-27)
**Date:** <YYYY-MM-DD>

---

## 1. Pre-deploy verification (before deploy command)

| Check | Result |
|---|---|
| DP.1: approval artifact exists + unexpired | ✓ |
| DP.6: operator typed `APPROVE-DEPLOY-NOW` literal | ✓ |
| Final worker-undisturbed re-check | ✓ (all protected paths empty diff) |

---

## 2. Deploy command

```
$ <exact command>
<output excerpt — must show success>
```

Deploy hash captured: `<hash>`

---

## 3. Probe results

| Probe | Description | Status | Evidence |
|---|---|---|---|
| G-M | Deploy command exit | ✓ PASS | exit 0 |
| G-N | Health probe | ✓ PASS | `<curl output excerpt>` |
| G-O | Feature surface probe | ✓ PASS | `<response excerpt>` |
| G-P | Feature behavior probe | ✓ PASS | `<log/response excerpt>` |
| G-Q | Spec flip + backlog index update | ✓ PASS | `<git diff excerpt>` |
| ... | <additional probes per gate contract> | ... | ... |

If ANY probe failed: replace this section with **failure section** below.

---

## 4. Smoke prompts (if applicable)

| Smoke | Result | Operator-visible outcome | Ground-truth diagnostic | Evidence path |
|---|---|---|---|---|
| S1 | PASS / FAIL / PENDING-OPERATOR-SMOKE | `<observed outcome>` | `<diagnostic checked; error=null / no error entry / expected row present>` | `docs/tmp/handoff/<date>-<slug>-smoke/S1-output.md` |
| S2 | PASS / FAIL / PENDING-OPERATOR-SMOKE | `<observed outcome>` | `<diagnostic checked>` | `docs/tmp/handoff/<date>-<slug>-smoke/S2-output.md` |
| ... | ... | ... | ... | ... |

Supporting checks only (exit code, hashes, service active, symbol presence, auth sanity) are not sufficient smoke evidence. If any S<n> is `PENDING-OPERATOR-SMOKE`, leave spec DRAFT and provide the exact operator smoke steps.

---

## 5. Single docs commit (FR-14)

**Commit SHA:** `<sha>`
**Commit message:** `docs(post-deploy): T<deploy> <slug> DONE — <hash>`

Files in commit:

| File | Change |
|---|---|
| `docs/specs/<slug>/spec.md` | DRAFT → DONE with deploy hash `<hash>` |
| `docs/specs/<slug>/tasks.md` | T<gate>..T<deploy> verification marks |
| `docs/backlog/index.md` | row flipped to DONE with `<hash>` |
| `README.md` (if applicable) | header version updated |

---

## 6. Operator-side actions still pending (if any)

| Action | Why | Where |
|---|---|---|
| <e.g., manual SSH PATCH commands for canonical agents> | Cross-system deploy not auto-rolled | <description> |
| <none, if fully self-contained deploy> | — | — |

If pending actions exist: list them with **literal commands the operator should run**. Do not say "manually update X" — show the exact command.

---

## 7. Net deploy duration breakdown

Per IM.11 (v2.8.0+), separate active deploy work from operator-wait time. Retrospective analysis uses these numbers.

### 7a. Per-phase elapsed (wall-clock)

| Phase | Started (UTC) | Ended (UTC) | Wall-clock |
|---|---|---|---|
| Operator typed `APPROVE-DEPLOY-NOW` → deploy command started | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` |
| Deploy command running | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` |
| Probes running | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` |
| Smoke prompts running (if any) | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` |
| FR-14 docs commit prep + push | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` |

### 7b. Net active vs wait

| Metric | Value | Notes |
|---|---|---|
| **Total elapsed (wall)** | `<H:MM:SS>` | operator-confirm → deploy report ready; end-to-end including all waits |
| **Active deploy work** | `<H:MM:SS>` | sum of "deploy command running" + "probes running" + "smoke running" + "FR-14 commit prep+push"; **excludes operator-wait moments** |
| Wait time | `<H:MM:SS>` | elapsed − active; e.g., operator deciding rollback-vs-fix-forward on a probe failure |
| Deploy-command-only duration | `<m:ss>` | the deploy command itself, for tracking deploy-script bottlenecks |

These numbers feed retrospective analysis per FR-15. Useful comparisons: deploy-command duration over time (regression in build pipeline?), probe duration over time (test suite drift?), active vs wait ratio (where are we spending the slow-but-not-running minutes?).

---

## 8. For operator: paste this in PO chat

**Per FR-16, the operator should copy the block below verbatim and paste into the PO chat for closeout. The PO will verify the FR-14 commit landed correctly, surface any operator-side PATCH commands, and mark the ticket DONE.**

````
Deploy complete for <slug> (T<deploy>).

Headline: <one-line summary — e.g., "All probes PASS. FR-14 docs commit landed. Spec flipped DRAFT -> DONE.">

Deploy hash: <hash>
Rollback plan: <code-only: git revert <hash>; migration/secret/sidecar/cross-app-contract: the surface-appropriate plan from the handoff — a revert does NOT reverse a non-code deploy>
Total elapsed: <H:MM:SS> (active <H:MM:SS> + wait <H:MM:SS>; per IM.11/v2.8.0+)
Deploy-command-only: <m:ss>

Probes: <N>/<N> PASS (G-M..G-Q + smoke S1..Sn)
FR-14 docs commit: <commit SHA>
Spec status: DRAFT -> DONE
Backlog index: row flipped DONE with deploy hash

Operator actions still pending post-deploy:
  <list — or "none" if self-contained>

Approval artifact <state/approvals/production_deploy-<slug>-<date>.json> remains on disk; will be naturally expired by its expires_at timestamp (<expiry>) — no manual cleanup needed.

Full deploy report attached above. PO: please follow Operator Relay Protocol — brief me in Mode A, surface any operator-side PATCH commands as a copy-paste block, mark backlog ticket CLOSED, update memory entry.
````

---

📍 Phase: Deploy (complete)
🎯 Ticket: `<slug>`
✅ Deploy hash: `<hash>`
⏭️ Next: PO closeout (verify FR-14 commit, surface operator PATCH commands if any, mark ticket DONE)
```

---

## If a probe FAILED — use this section instead of section 3

```markdown
## 3. Probe results — FAILURE

| Probe | Description | Status | Evidence |
|---|---|---|---|
| G-M | Deploy command exit | ✓ PASS | exit 0 |
| G-N | Health probe | **✗ FAIL** | observed: `<actual>`, expected: `<expected>` |
| G-O | Feature surface probe | ⏸ NOT RUN (aborted after G-N) | — |
| ... | ... | ... | ... |

**Probe failure response:**

- Spec stays DRAFT (do NOT flip to DONE)
- Two recovery paths:
  - **A. Rollback:** for a `code-only` deploy, `git revert <deploy hash>` + redeploy reverses it. For a migration / secret/config / sidecar/infra / cross-app-contract deploy a revert un-ships only the code — schema/data/secret/sidecar/contract stay forward — so execute the surface-appropriate plan from the handoff (`flow-skills/release-deploy-reporting/SKILL.md` § Rollback-surface classification).
  - **B. Fix-forward:** file follow-up backlog ticket; spec stays DRAFT until follow-up resolves.
- Operator decides which path. Surface this decision in the relay block below.
```

The relay block in section 8 must reflect the failure: include **"DEPLOY FAILED — operator decision needed: rollback vs. fix-forward"** as the headline.

---

## Fill-in checklist

When filling this template, the Deploy phase should consult `templates/references/deploy-report-checklist.md` for the canonical fill-in checklist (v2.9.0+ -- lazy-loaded reference). Don't paraphrase the checklist into the filled artifact; it's a fill-time aid, not output content.


## Why the operator-relay block matters (FR-16 / v2.6.0)

The operator just typed `APPROVE-DEPLOY-NOW` and waited 5–8 minutes. They want to know two things: **did it work?** and **what do I do now?** The relay block answers both in 10 lines. The technical body is for the PO to verify; the operator doesn't have to read it.

Pre-v2.6.0, deploy reports were 50-line technical documents the operator had to skim. Per FR-16, that's friction we now remove.