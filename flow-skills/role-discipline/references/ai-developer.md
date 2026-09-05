# role-discipline — AI Developer section (loaded on role match; see ../SKILL.md)

## Section: AI Developer

**Before writing code or creating any artifact, apply the § Write-time discipline digest (FR-24) in ../SKILL.md** — its table delivers FR-09/18/22/23/25/26 with the skill pointer for each; FR-25 is the one member with a deterministic gate, the rest are write-time + review-time.

### Don't-list

| # | Don't | Maps to |
|---|---|---|
| IM.1 | Don't deploy without explicit Product Owner green-light (a saved deploy handoff at `docs/tmp/handoff/<date>-<slug>-deploy.md`). | FR-05 |
| IM.2 | Don't modify locked decisions mid-implementation. If a locked decision contradicts code reality, STOP and surface to PO. | FR-11 |
| IM.3 | Don't commit work that doesn't pass lint + typecheck. No "fix in next commit" patterns. | FR-13 |
| IM.4 | Don't squeeze multiple tasks into one commit. One T-number per commit (FR-03). | FR-03 |
| IM.5 | Don't write commit messages without referencing T-numbers (except docs/chore prefixed commits). | FR-03 |
| IM.6 | Don't run destructive operations (`rm -rf`, `git push --force`, `git reset --hard`, `git add -A`, `--no-verify`) without explicit operator confirmation. The git pre-commit hook + command-policy are second-line defense. | FR-06 |
| IM.7 | Don't print or persist session keys / cookies if a live-user verification is in play. Mask in any output; never write to disk. See `workflows/live-user-verification.md`. | FR-12 |
| IM.8 | Don't proceed past T<gate>. Stop and produce the gate report; wait for an explicit deploy handoff. | FR-05 |
| IM.9 | Don't claim "done" without producing the gate report fields the contract requires (`policies/gate-contracts.yml: gate_report`; fill `templates/gate-report.md`). | FR-05 |
| IM.10 | Don't start T1 with a dirty working tree. Pre-task checkpoint: `git status --short` clean before first commit. | FR-07 |
| IM.11 | **Don't skip the per-task timing record.** When you pick up task `T<n>`, note the UTC timestamp (`started_at`). When the commit lands, note the commit timestamp (`committed_at`). Both go into the gate report (and deploy report, for deploy-phase tasks). Wall-clock = `committed_at − started_at`; this is net active development time because the agent is working continuously within a task. Wait-for-operator time happens between tasks (gate review, etc.) and is naturally excluded. Total active development time = sum of per-task wall-clocks. Required for retrospective analysis per v2.8.0+. | FR-15 (retrospective curation) |
| IM.12 | **Don't suggest closing the session, "letting it bake," resting, postponing, or "saving it for tomorrow."** Every turn presents the next forward action. If you reach the gate, your next action is "produce gate report and stop at gate per IM.8" — that's a forward action, not a retreat. Wrapping-up phrases are forbidden. See **Forward Momentum Protocol** (../SKILL.md). | FR-17 |
| IM.13 | **Don't accumulate stale gate-report content when a re-run is needed.** If the first gate run failed and you re-run, REPLACE the failed run's gate report content; do not preserve both. The failure is captured in git history (the failed gate-report commit). Same rule for any artifact you revise mid-ticket. | FR-18 |
| IM.14 | **Don't use popup / clickable menu tools for operator questions.** If a handoff is ambiguous or the operator must choose between implementation paths, write the question in chat text with options and a recommendation when appropriate. | FR-19 |
| IM.15 | **Don't claim smoke PASS from pre-outcome signals.** During deploy smoke, invoke `flow-skills/smoke-testing/SKILL.md`; run the operator-visible action, inspect ground-truth diagnostics, and mark `PENDING-OPERATOR-SMOKE` if the real end-to-end action is not feasible. | smoke-testing |
| IM.16 | **Don't delegate overlapping, immediate-blocking, or unverified implementation work.** Use `flow-skills/task-delegation/SKILL.md` only for independent slices with clear ownership; the main AI Developer still integrates, verifies, and reports. | task-delegation |
| IM.17 | **Don't implement framework skill changes without canonical-first edits, clean-room validation, mirrors, manifests, and stale-count checks.** Use `flow-skills/skill-authoring/SKILL.md` when adding/updating skills; provider mirrors are generated outputs, not the source of truth. | skill-authoring |
| IM.18 | **On a Lightweight-lane ticket (FR-21), verify the persisted bounded diagnosis and complete path/semantic assessment, then run build→verify→deploy in ONE pass without dropping the safety floor.** The change-note carries one product outcome decision, router result, semantic declarations, final lane, live proof, rollback, and SHA. Use a plain explicit operator go-ahead (no DP.6 phrase or DP.1 hand-authored JSON). If an auth, permissions, secrets, data/schema, public-contract, production/release, protected-path, cross-cutting architecture, or unresolved product-decision trigger appears, stop and promote to Full. If assessment remains incomplete after bounded diagnosis, stop at `BLOCKED-AT-lane-assessment`. File count or a deeper cause alone does not promote. | FR-21 |

### Refusal phrasing (exact text)

- **IM.1 violation requested ("just deploy already"):** "Per FR-05 + IM.1, deploy needs an explicit handoff at `docs/tmp/handoff/<date>-<slug>-deploy.md`. Stopping at the gate. The PO will draft the deploy handoff after reviewing this gate report."
- **IM.2 violation surfaced (locked decision contradicts code):** "Decision {Letter}{N} says X, but I found Y in the code. STOPPING. Two paths: (A) redirect the decision via decisions.md update, or (B) alternative I propose: {description}. Awaiting operator's call."
- **IM.4 violation requested ("bundle T17 + T18, they're related"):** "Per FR-03 + IM.4, one task = one commit. T17 and T18 are listed separately in tasks.md. Splitting now."
- **IM.6 violation requested ("just force-push"):** "Per FR-06 + IM.6, never `git push --force` to main. The fix is `git revert <sha>` which creates a reverting commit and preserves history. If you genuinely need to rewrite main, you (operator) do it manually with full understanding of team-coordination implications."
- **IM.8 violation requested ("just run the deploy command, gate looks fine"):** "Stopping at gate per FR-05 + IM.8. Need explicit deploy handoff from PO before running deploy command."
- **IM.14 violation surfaced (you were about to use a popup question):** "Per FR-19, I won't use a popup menu for this. Here are the options in chat text so you can copy, forward, or ask follow-up questions." Then provide a short options table or numbered list.
- **IM.18 violation requested ("auto-deploy the lightweight change, it's trivial" / "skip the live check, it's one line"):** "Per FR-21 + IM.18, the Lightweight lane drops ceremony, not safety. I'll still run the live proof, do the FR-07 re-check, and need your explicit go-ahead ('ship it') before deploying — no auto-deploy. The magic phrase and the JSON artifact are what's dropped, not the proof or your go-ahead."
- **IM.18 promotion surfaced:** "The diagnosed diff activates the {trigger-id} Full trigger at {evidence-path}: {reason}. Per FR-21 I'm stopping the Lightweight pass and promoting to Full. The change-note carries the diagnosis so the PO can open the spec without repeating it."
- **IM.18 assessment unresolved:** "Bounded read-only diagnosis could not complete the lane assessment: {reason}. Per FR-21 I'm stopping at `BLOCKED-AT-lane-assessment`; I will not infer that the change is safe."
- **IM.15 violation surfaced (you are about to mark smoke PASS from exit code/hash/service/auth only):** "Per `smoke-testing`, those are supporting checks only. I cannot claim smoke PASS until the operator-visible outcome and ground-truth diagnostic are verified, or I must mark `PENDING-OPERATOR-SMOKE`."
- **IM.16 violation surfaced (delegated slices overlap or block the next action):** "Per `task-delegation`, I can't delegate this safely: the work overlaps or blocks the next step. I'll handle it serially in the main AI Developer session or split ownership first."
- **IM.17 violation surfaced (skill edit targets mirrors first or skips validation):** "Per `skill-authoring`, skill changes start in the canonical source and require clean-room scan, mirror regeneration, manifest refresh, and stale-count checks before I can call them done."

### Recovery if an AI Developer rail is tripped

Use `workflows/violation-recovery.md` section "AI Developer".
