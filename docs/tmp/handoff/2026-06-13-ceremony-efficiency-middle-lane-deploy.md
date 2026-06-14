# Deploy handoff — ceremony-efficiency-middle-lane (Phase 1)

## Role bootstrap
You are operating as the **Deploy phase** (AI Developer) under FuseBase Flow v3.21.1 → shipping **v3.22.0**. Self-attest per FLOW_RULES.md (FR-01..FR-26) naming Deploy phase + the DP role-discipline section.

**Lane:** Phase 1 is **Lightweight-eligible** (additive/reversible: a new skill + read-only analyzer + governance annotations; no schema/data; `git revert` undoes it). Per **DP.12**, a plain operator go-ahead replaces the DP.1 artifact + DP.6 magic phrase. **Operator go-ahead is GIVEN: "confirm first then deploy" after a clean round-7 SHIP verdict.** Proceed.

## Pre-deploy state
- Branch `main`, **18 commits ahead of origin/main, unpushed**, HEAD `1abfff1`, working tree clean.
- 7 independent Codex adversarial rounds → SHIP; selftest 114/114 + 2 skipped; preflight 0/0; health HEALTHY; recovery-sim all PASS; mirror drift 0.
- VERSION = `3.21.1`; `.claude-plugin/plugin.json` = `3.21.1` (invariant: plugin == VERSION).

## Step 0 — bounded pre-deploy hardening (one commit, then verify)
Close the round-7 acceptable-LOW so nothing dangles:
- In `hooks/local/find_wasted_effort/evidence.py` `_NON_OUTCOME_HEADING_RE`, add the missing non-outcome synonyms: `runbook`, `instructions`, `sop`, `recipe`, and hyphenated `how-to` (alongside the existing procedure/example/steps/playbook/guide/how to/appendix).
- Add fixtures: `## Outcome: rollback runbook` + body → fires NOTHING; `## Rollback result: rolled back the deploy` → still fires (guard).
- Commit: `fix(find-wasted-effort): extend non-outcome heading veto with runbook/sop/recipe/instructions/how-to (Codex round-7 LOW)`.
- Verify: `--selftest` all pass (skips separate); `bash hooks/local/preflight.sh` 0/0; `bash hooks/local/mirror-skills.sh` 0 drift. FR-07: no diff to FLOW_RULES FR rows or the 3 deploy policies. FR-25: modules < 800. Read-only preserved.

## Step 1 — version bump + string sweep
- `VERSION` 3.21.1 → **3.22.0**; `.claude-plugin/plugin.json` version → **3.22.0** (keep == VERSION so preflight §8 stays 0/0).
- Run `bash hooks/local/sync-version-strings.sh` (live attestation / FR-range FR-01..FR-26 / skill-count 31). Confirm it does NOT touch dated history (the v3.11.1 prune fix).
- Reconcile remaining count strings: selftest count → **current `--selftest` tally** (114 + the new fixtures from Step 0; use the real number the tool reports), skills 31, policies 9, modules 6.

## Step 2 — finalize release notes (no longer "pending")
- `docs/release-notes/v3.22.0.md` + `CHANGELOG.md [3.22.0]`: set real release date, final selftest tally, and the deploy hash (filled after Step 4). Remove any "pending" ambiguity. Summarize Phase 1: A3 ratchet-governance (`prevents:` + `policies/ratchet-governance.yml`), A2 `/find-wasted-effort` read-only process-per-outcome audit (31st skill), and that Phase 2 (audit writes) + Phase 3 (Middle Lane / `middle_deploy`) are deferred per the spec.

## Step 3 — final pre-push gate
`bash hooks/local/preflight.sh` (0/0) · `--selftest` (all pass) · `bash hooks/tests/run-tests.sh` (24/24) · health HEALTHY · mirror drift 0 · plugin valid · `git status` clean.

## Step 4 — release (the deploy)
1. `git push origin main` (pushes all commits).
2. `git tag -a v3.22.0 -m "FuseBase Flow v3.22.0 — find-wasted-effort (process-per-outcome ceremony audit) + ratchet governance"` ; `git push origin v3.22.0`.
3. `gh release create v3.22.0 --title "v3.22.0 — find-wasted-effort + ratchet governance" --notes-file docs/release-notes/v3.22.0.md --latest`.
4. Capture the deploy hash (the release commit SHA).

## Step 5 — post-deploy probes + smoke S1
- Probes G-M..G-Q per `docs/specs/ceremony-efficiency-middle-lane/verification-gate.md` (push/tag landed; preflight on shipped tree; new skill discoverable in `.claude/skills/` + `.agents/skills/`; analyzer runs; docs updated).
- **Smoke S1 (AC7 first-consumer):** run `/find-wasted-effort` against THIS repo; confirm it writes a `state/audit/` report with per-rule confirmed/dismissed/inconclusive + FP header, makes NO edits (read-only), and a known-clean round is not flagged.

## Step 6 — single FR-14 docs commit
One commit: spec.md Phase-1 status note + deploy hash; tasks.md T18..T23 SHAs + verification; backlog/README skill-count (31) if applicable. (Spec stays LOCKED — Phase 2/3 remain.) Output the deploy report from `templates/deploy-report.md`.

## Rollback
If any probe/smoke fails: `git revert <deploy hash>`; re-push; re-mirror; file a follow-up; do not re-tag until fixed. Phase 1 is additive — revert is clean (no schema/data).

## Notes
- This ticket changes NO deploy authority (that's Phase 3); it's a normal additive framework release.
- Do NOT start Phase 2 or Phase 3 — they are separate, later tickets/gates per the spec's Implementation order.
