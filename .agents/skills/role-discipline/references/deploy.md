# role-discipline — Deploy phase section (loaded on role match; see ../SKILL.md)

## Section: Deploy phase

### Don't-list

| # | Don't | Maps to |
|---|---|---|
| DP.1 | Don't run the deploy command without the approval artifact at `state/approvals/production_deploy-<slug>-<date>.json`. **(Full lane.** For a Lightweight-lane deploy this is replaced by a plain operator go-ahead — see DP.12.) | FR-12 |
| DP.2 | Don't skip the final pre-deploy worker-undisturbed re-check. The gate ran one; deploy phase runs another (something might have changed). | FR-07 |
| DP.3 | Don't mark spec DRAFT → DONE without the deploy hash captured. No "TBD" / "see commit" placeholders. | FR-14 |
| DP.4 | Don't split deploy docs across multiple commits. One single docs commit at the end captures spec.md flip + tasks.md verification + backlog index update + README header. | FR-14 |
| DP.5 | Don't mark spec DONE if any post-deploy probe or smoke prompt failed. Surface failure; operator decides rollback vs fix-forward. | FR-05 |
| DP.6 | Don't run the deploy command without the operator typing the literal phrase `APPROVE-DEPLOY-NOW`. No `yes` / `y` / `ok` / partial matches. The pause keeps a human at the keyboard for the production cutover moment. ~5s structural friction; mirrors the `APPEND-ONLY` pattern in `install.sh`. **(Full lane.** A Lightweight-lane deploy uses a plain go-ahead instead — see DP.12.) | FR-12 |
| DP.7 | **Don't suggest closing the session, "letting it bake," resting, postponing, or "saving the deploy for tomorrow"** unless the operator has explicitly indicated they're done. After probes complete, the next forward action is the FR-14 docs commit + report-back. If a probe failed, the next forward action is rollback-vs-fix-forward decision. There is always a next action through deploy completion; never recommend stopping mid-deploy. | FR-17 |
| DP.8 | **Don't accumulate stale deploy-report content when re-running.** First deploy aborted? REPLACE the report content with the corrected/resumed version. Don't preserve both. The aborted attempt is captured in git history (the failed deploy-report commit + the abort-recovery commit). This is the rule that fixes the paperclip+hermes-v1 25KB-deploy-handoff pattern. | FR-18 |
| DP.9 | **Don't use popup / clickable menu tools for deploy confirmations or operator decisions.** DP.6 requires the operator to type the literal phrase in chat; rollback-vs-fix-forward decisions must also be written as chat text. | FR-19 |
| DP.10 | **Don't mark deploy smoke PASS without outcome evidence and ground-truth diagnostics.** Execute S1..Sn per `skills/smoke-testing/SKILL.md`; if end-to-end smoke is blocked, report `PENDING-OPERATOR-SMOKE` and do not mark spec DONE. | smoke-testing |
| DP.11 | **Don't delegate deploy side effects.** Deploy command, rollback, approval artifacts, secret handling, and live-session smoke stay in the main Deploy phase session. Delegation is read-only triage only. | task-delegation |
| DP.12 | **Lightweight-lane deploy (FR-21): a plain explicit operator go-ahead replaces DP.1 (JSON artifact) and DP.6 (magic phrase) — but never the go-ahead itself.** For an LL-eligible deploy, accept a plain "ship it" / "deploy it" / "go" in chat instead of the literal phrase + hand-authored artifact, and run it in the same single build→verify→deploy pass (no separate deploy session). You still keep DP.2 (final FR-07 re-check), capture the deploy hash, keep a one-line rollback, and never auto-deploy. In hook-wired projects, record the go-ahead with one command — `bash hooks/local/approve-local.sh lightweight_deploy <slug> 'ship it'` — which satisfies the tier-aware `before_deploy_command` gate. If the change is not genuinely LL-eligible, use the Full lane (DP.1 + DP.6). | FR-21, FR-12 |

### Refusal phrasing

- **DP.1 violation requested ("approval artifact's missing, just deploy"):** "Per FR-12 + DP.1, no deploy without `state/approvals/production_deploy-<slug>-<date>.json`. Operator authors with `bash hooks/local/approve-local.sh production_deploy <slug> '<reason>'`. Stopping until artifact present."
- **DP.5 violation requested ("probe G-O failed but it's not important; mark DONE"):** "Per FR-05 + DP.5, do NOT mark spec DONE on probe failure. G-O observed Y, expected Z. Recovery options: (A) rollback (`git revert <hash>` + redeploy), (B) fix-forward via follow-up task. Operator decides."
- **DP.6 violation requested ("just deploy, I'm watching, no need for the phrase"):** "Per FR-12 + DP.6, the literal `APPROVE-DEPLOY-NOW` phrase is required before the deploy command runs. Anything else aborts. Re-issue when ready."
- **DP.9 violation surfaced (you were about to use a popup question):** "Per FR-19, deploy confirmations and recovery choices stay in chat text. Type `APPROVE-DEPLOY-NOW` to proceed, or reply with a question / redirect."
- **DP.10 violation surfaced (smoke evidence is only exit code/hash/service/auth):** "Per `smoke-testing`, this is not sufficient smoke evidence. I need the operator-visible outcome plus the ground-truth diagnostic, or I must report `PENDING-OPERATOR-SMOKE` and leave the spec DRAFT."
- **DP.11 violation requested ("delegate the deploy/rollback"):** "Per `task-delegation`, deploy side effects stay in the main Deploy phase session. I can delegate read-only triage, but I won't delegate deploy, rollback, approval, secrets, or live-session smoke."
- **DP.12 applied (Lightweight-lane deploy):** "This is a Lightweight-lane deploy (FR-21): no magic phrase / JSON artifact needed — just reply with an explicit go-ahead ('ship it') and I'll deploy in this same pass. I've run the live proof and the FR-07 re-check; rollback is `git revert <SHA>`. I won't auto-deploy without your go-ahead." (If the change isn't genuinely LL-eligible: "This needs the Full-lane gate — DP.1 artifact + `APPROVE-DEPLOY-NOW` — because {reason}.")

### Recovery if a Deploy phase rail is tripped

See `workflows/violation-recovery.md`. High-level:

- DP.1 (deployed without artifact): produce artifact retroactively; document the bypass in spec.md audit log; file incident if production was disturbed.
- DP.5 (marked DONE despite probe fail): reverse spec to DRAFT; either rollback or file fix-forward task; document.
- DP.6 (deployed without operator confirm phrase): unusual — the wrapper requires the phrase. If the agent ran deploy without confirmation, treat as agent rule violation; document; tighten the agent's prompt or wrapper.
