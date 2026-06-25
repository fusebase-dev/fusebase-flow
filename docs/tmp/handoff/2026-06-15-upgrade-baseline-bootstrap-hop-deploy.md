# Deploy handoff — upgrade-baseline-bootstrap-hop → v3.25.1 (PATCH)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.25.0 → shipping **v3.25.1** (PATCH hotfix). Self-attest FR-01..FR-26, DP section. Operator authorized autonomous end-to-end execution (DP.12 plain go-ahead). No interactive DP.6. **Run everything SYNCHRONOUSLY — no background monitors.**

## Why this release
Post-ship Codex adversarial review of v3.25.0 found a verified BLOCKER: U3's baseline merge-preserve didn't run on the FIRST upgrade adopting v3.25.x (merge lib sourced from the local path before hooks/ refresh; bootstrap didn't stage lib/) → project `module-size-baseline.txt` rows clobbered on adoption. Fixed by 4 commits (`49f335c`,`b562166`,`5324358`,`28fe2ea`). Codex re-review verdict: **SHIP** (only residual = ACCEPTED-RISK old-engine-direct path, mitigated by bootstrap docs).

## Pre-deploy state
- HEAD `28fe2ea`, 4 unpushed hotfix commits on top of origin/main `a6eae12` (v3.25.0).
- Gate (AI Dev + Codex both ran): preflight 0/0; run-tests **92/92** (79 + 13 new adoption-hop); check-module-size --all exit 0; mirror 0 drift; both scripts `bash -n` clean; FR-25 upgrade.sh 465; FR-07 untouched.
- **recovery-sim (this hotfix, engine change):** evidence at `state/audit/recovery-sim-v3.25.1-2026-06-15.log` — confirm it shows 31/31 exit 0 before proceeding. Do NOT re-run it (already run by the orchestrator).

## Step 1 — version bump
- VERSION + `.claude-plugin/plugin.json` 3.25.0 → **3.25.1** (equal).
- Run `bash hooks/local/sync-version-strings.sh` — verify all framework adapters incl. GEMINI.md sweep to v3.25.1; under-reach guard passes; no consumer doc touched.

## Step 2 — release notes
New `docs/release-notes/v3.25.1.md` + `CHANGELOG.md [3.25.1]`: date, deploy hash. Summary: **hotfix — baseline merge-preserve now runs on the first upgrade adopting v3.25.x.** v3.25.0 shipped the U3/W2 merge but it was skipped on the adoption hop (lib sourced from local path before hooks/ refresh; bootstrap didn't stage lib/). Fix: `upgrade.sh` sources the merge lib from the authoritative target tree (`$SOURCE_CLONE/hooks/local/lib/`) with local fallback + re-source before Step 1a + loud no-skip warning; `bootstrap-upgrade.sh` stages `hooks/local/lib/`; README routes pre-v3.25 installs through `bootstrap-upgrade.sh` for the v3.25.x hop; new RED-then-GREEN adoption-hop integration test. Credit: found by post-ship Codex adversarial review. Note the ACCEPTED-RISK (old installed upgrade.sh run directly can't run target-version merge code — use bootstrap).

## Step 3 — final gate
preflight 0/0 · run-tests **92/92** · check-module-size --all exit 0 · mirror manifest byte-identical · sync --dry-run scoped · plugin==VERSION==3.25.1 · recovery-sim evidence 31/31 (referenced, not re-run) · git clean.

## Step 4 — release
1. `git push origin main`.
2. `git tag -a v3.25.1 -m "FuseBase Flow v3.25.1 — baseline merge-preserve runs on the v3.25.x adoption hop (bootstrap + new-engine)"`; `git push origin v3.25.1`.
3. `gh release create v3.25.1 --title "v3.25.1 — adoption-hop baseline merge-preserve" --notes-file docs/release-notes/v3.25.1.md --latest`.
4. Capture deploy hash.

## Step 5 — probes + smoke (synchronous, capture evidence)
- Probes G-M..G-Q.
- (a) mirror manifest byte-identical; (b) sync --dry-run framework-only + consumer-decoy excluded; (c) GEMINI.md = v3.25.1; (d) health no PARTIAL_UPGRADE false-positive; (e) `bash hooks/tests/test-bootstrap-baseline-hop.sh` PASS 13/13 on the released tree.

## Step 6 — single FR-14 docs commit
- Create `docs/specs/upgrade-baseline-bootstrap-hop/spec.md` (concise; Status DONE — shipped v3.25.1; deploy hash; the blocker, the 4 tasks + SHAs, AC = adoption-hop merge runs). This is the permanent artifact for the hotfix.
- Add a row to `docs/backlog/index.md` (or note under upgrade-tooling-hardening) referencing v3.25.1.
- Output the deploy report.

## Rollback
`git revert <deploy hash range>` — additive (script source-ordering + bootstrap staging + docs + test); steady-state behavior unchanged. Re-push; re-mirror.

## Notes
- FR-07: NO change to FLOW_RULES FR rows / 3 deploy-policy rule semantics / ratchet-governance.yml / the LOCKED merge rule (only how/when the lib is sourced). internal/ + repo-polish untracked.
