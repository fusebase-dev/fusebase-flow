# Spec — delegation residuals (v3.21.1)

**Status:** LOCKED (operator 2026-06-12 "proceed"; source: POST-DELIVERY RESIDUALS + ADDENDUM 2 in downstream proposal 2026-06-12, post-v3.20.1/v3.21.0 verification — downstream confirms all 10 prior asks delivered)
**Tier:** 2 · **Lane:** Lightweight-plus (4 small fixes; independent post-implementation review before ship)
**Deploy hash:** (at DONE flip)

## Problem

Second-order residue of the two shipped tickets: (1) `upgrade.sh` step 4 runs the overlay/command recovery with output and exit code fully suppressed (`>/dev/null 2>&1 || true`) — a mid-run recovery crash half-applies (downstream: 2 of 5 command files stale) with the root cause masked; (2) the delegation contract (turn-completion + progress ledger) reaches implement handoffs but NOT `templates/handoff-deploy.md` — the prompt a delegated Deploy session actually reads — and its mandatory-reads list omits `greenlight-deploy.md`; (3) report templates induce transcription of events the system under test already records durably (v3.21.0 fixed returns; reports are the remaining home); (4) the return shape requires a verdict but not the verification behind it — a false "launched" claim built from an attempted action + look-alike artifact survived ~19h.

## Decisions (locked)

| ID | Decision | Rejected |
|---|---|---|
| S1 | **Surface the recovery call.** upgrade.sh step 4 captures the recovery's output + exit code: on success, print its "Actions taken" summary lines (prefixed `[upgrade] recovery:`); on non-zero exit (the script exits 1 on warnings OR crash), print a loud WARN — "recovery reported warnings or failed; may have HALF-APPLIED (stale slash commands / overlay blocks possible)" + last output lines + the literal re-run command. Verified by sim both ways: success path shows summary; stubbed-crash source shows the WARN block. | Keeping `\|\| true` silence (the defect); failing the whole upgrade on recovery warnings (post-fusebase-update exits 1 on mere warnings — too strict, upgrade content already landed). |
| S2 | **Deploy-handoff push.** `templates/handoff-deploy.md`: add a Critical-invariants bullet carrying the delegation contract (in-turn evidence, facts-as-they-occur/skeleton-first, `BLOCKED-AT-<gate>` at unbounded waits) AND add `workflows/greenlight-deploy.md` to the mandatory-reads list. Same push-not-pull blocker class as PR:F1 — closed for implement handoffs in v3.21.0, missed for deploy. | Relying on greenlight-deploy workflow text alone (the delegated Deploy session reads the template, not the workflow). |
| S3 | **Self-recording clause for reports.** One sentence in `templates/gate-report.md` header + `templates/deploy-report.md` header + `flow-skills/validation-and-qa` : *if the system under test has durable evidence surfaces (journals, run records, logs, snapshots), report fields carry POINTERS to them — transcribe only what no system records* (FR-23 applied to operational reports; extends the v3.21.0 pointers rule from returns to reports). | A new skill/rule (FR-23 already anchors it); changing report field sets (pointer-vs-transcribe is per-field judgment, not structure). |
| S4 | **Ground-truth rule in the return shape.** `task-delegation` § Delegated return shape gains: *any claim that system state changed (launched / registered / deployed / completed) names the verification performed — the system surface read and what it showed; an attempted action or an observed look-alike artifact is not evidence.* Push block + handoff-implement condensed quote gain the short form ("state-change claims cite the ground-truth check"). | Hook enforcement (semantic); requiring screenshots (surface-read evidence is the contract, medium varies). |
| S5 | No FR/count changes; v3.21.1 patch bump; mirrors (task-delegation, validation-and-qa); sweep; gates; one independent post-implementation review. | Full lane (4 bounded one-surface fixes with known root causes). |

## ACs

1. AC1 — upgrade.sh: recovery output surfaced on success (summary lines) and failure (WARN + tail + re-run command); sim-proven both paths; `bash -n` clean.
2. AC2 — handoff-deploy.md: contract bullet present in Critical invariants; greenlight-deploy.md in mandatory reads.
3. AC3 — clause present in gate-report.md, deploy-report.md, validation-and-qa (mirrored).
4. AC4 — ground-truth rule in return shape + short form in push block + handoff-implement quote (all three consistent).
5. AC5 — preflight 0/0 · run-tests 24/24 · mirrors 78/0 drift · sweep clean · overlays byte-match · independent review findings fixed pre-tag.

## Out of scope

Re-architecting post-fusebase-update exit semantics; report template field changes; FR-27.
