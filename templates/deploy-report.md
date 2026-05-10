# Deploy report template (v2.6.0+)

> **Mode B (full).** This template is what the **AI Developer in Deploy phase** produces after completing T<deploy> (deploy command + probes + smoke + single docs commit per FR-14). Two sections: the **technical deploy body** (for the PO's audit work — verifying probes, FR-14 commit landed, rollback option visible) and the **operator relay block** at the bottom (a copy-paste-ready chunk the operator pastes into PO chat).
>
> Per FR-16, the Deploy phase composes the operator-relay block — operator never digests the technical body. Scroll → copy → paste in PO chat.

---

## Use this template when

You are an AI Developer Deploy-phase session that has just completed T<deploy> (deploy command, probes, smoke, single docs commit). Don't ad-hoc the deploy report — copy this template, fill it in, output it as your final response.

---

## Template body

```markdown
# Deploy report — <slug> (T<deploy>)

**Status:** Deploy complete; awaiting PO closeout
**Slug:** `<slug>`
**Deploy hash:** `<hash>` ← rollback: `git revert <hash>`
**Approval artifact:** `state/approvals/production_deploy-<slug>-<date>.json` (expires `<timestamp>`)
**Reporting session:** AI Developer / Deploy phase (Fusebase Flow v2.1, FR-01..FR-16)
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

| Smoke | Result | Evidence path |
|---|---|---|
| S1 | ✓ PASS | `docs/handoff/<date>-<slug>-smoke/S1-output.md` |
| S2 | ✓ PASS | `docs/handoff/<date>-<slug>-smoke/S2-output.md` |
| ... | ... | ... |

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

## 7. Total deploy duration

| Phase | Duration |
|---|---|
| Operator confirm → deploy command exit | <mm:ss> |
| Deploy command exit → probes complete | <mm:ss> |
| Probes complete → docs commit pushed | <mm:ss> |
| **Total** | <mm:ss> |

---

## 8. For operator: paste this in PO chat

**Per FR-16, the operator should copy the block below verbatim and paste into the PO chat for closeout. The PO will verify the FR-14 commit landed correctly, surface any operator-side PATCH commands, and mark the ticket DONE.**

````
Deploy complete for <slug> (T<deploy>).

Headline: <one-line summary — e.g., "All probes PASS. FR-14 docs commit landed. Spec flipped DRAFT -> DONE.">

Deploy hash: <hash>
Rollback command: git revert <hash>
Total duration: <mm:ss>

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
  - **A. Rollback:** `git revert <deploy hash>` + redeploy. Reverses the deploy.
  - **B. Fix-forward:** file follow-up backlog ticket; spec stays DRAFT until follow-up resolves.
- Operator decides which path. Surface this decision in the relay block below.
```

The relay block in section 8 must reflect the failure: include **"DEPLOY FAILED — operator decision needed: rollback vs. fix-forward"** as the headline.

---

## Fill-in checklist for Deploy phase using this template

Before pasting:

- [ ] DP.1 + DP.6 verification rows actually performed (not just claimed)
- [ ] Deploy hash captured from real command output
- [ ] Each probe result has concrete evidence (output excerpt, log line, screenshot path) — not just "PASS"
- [ ] FR-14 commit SHA is real
- [ ] Section 6 operator-side pending actions: literal commands, not paraphrases
- [ ] Section 8 operator-relay block is filled with actual content (not template `<...>` placeholders)
- [ ] If any probe failed: section 3 replaced with failure version + relay block reflects failure

---

## Why the operator-relay block matters (FR-16 / v2.6.0)

The operator just typed `APPROVE-DEPLOY-NOW` and waited 5–8 minutes. They want to know two things: **did it work?** and **what do I do now?** The relay block answers both in 10 lines. The technical body is for the PO to verify; the operator doesn't have to read it.

Pre-v2.6.0, deploy reports were 50-line technical documents the operator had to skim. Per FR-16, that's friction we now remove.
