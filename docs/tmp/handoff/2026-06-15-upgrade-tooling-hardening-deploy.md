# Deploy handoff — upgrade-tooling-hardening → v3.25.0

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.24.0 → shipping **v3.25.0**. Self-attest (FR-01..FR-26), DP section.

**Lane:** Full (upgrade/refresh tooling — a bug strands every consumer). DP.12 plain go-ahead applies (operator authorized autonomous end-to-end execution). No interactive DP.6.

## Pre-deploy state
- Branch `main`, **9 local/unpushed commits** (6 impl Ua–Ue + Ua-fix, + 3 remediation `8c401bd`/`b86d9eb`/`899a698`), HEAD `899a698`. origin/main = `6f50ae2`.
- Codex: design review (RESCOPE, folded) → impl review (2 test-reliability blockers) → **round-2 confirm SHIP, no findings.**
- Gates: preflight 0/0; run-tests **79/79**; check-module-size --all exit 0; mirror manifest byte-identical; **recovery-sim 31/31** (captured `state/audit/recovery-sim-2026-06-15.log`, ~27m — slow-host, do NOT re-run per-deploy); FR-07/FR-25 clean; v3.24.0 health exit-4 contract intact.

## Step 1 — version bump (this exercises the new sync allowlist + GEMINI fix — a live self-test)
- VERSION + `.claude-plugin/plugin.json` 3.24.0 → **3.25.0** (equal).
- Run `bash hooks/local/sync-version-strings.sh` — it now uses the NEW in-script `SYNC_ROOTS` allowlist. **Verify after:** (a) all framework adapters/docs bumped to v3.25.0 incl. **GEMINI.md** (the U5 regex fix — confirm GEMINI's version actually updated, not stuck); (b) the under-reach guard test passes (no framework file omitted); (c) NO consumer-style doc touched (this repo has none, but confirm scope). FR-range FR-01..FR-26, 31 skills unchanged.

## Step 2 — release notes
New `docs/release-notes/v3.25.0.md` + `CHANGELOG.md [3.25.0]`: date, deploy hash. Summary: **upgrade-tooling hardening** (reactive — from two independent consumer upgrade reports: paperclip+hermes-v1 + WorkHub Managed). Shipped: U1 batched mirror/sync spawns (Windows ~5min→seconds; bounded copy, manifest byte-identical, ARG_MAX-safe); U2 portable EOF-newline-preserving sync (no more consumer-doc churn); U3 **`module-size-baseline.txt` (+ policy) merge-preserve** on upgrade (project rows survive — fixes the post-upgrade `check-module-size` break); U4 **executable framework-owned sync allowlist + under-reach guard** (stops rewriting consumer docs; prevents silent adapter drift); U5 GEMINI version regex (un-sticks the `Local v2.1` drift); U7 upgrade trap recovery + health-check **`PARTIAL_UPGRADE`** signal; U9 progress output; U11 `.gitattributes` LF pins; U8 Windows docs (Git-Bash, `http.sslBackend=openssl`). **Deferred follow-up:** U6 (GEMINI/copilot/cursor overlay-refresh parity). Credit both consumer projects.

## Step 3 — final gate
preflight 0/0 · run-tests.sh **79/79** PASS · check-module-size --all exit 0 · mirror manifest byte-identical · sync --dry-run scoped (framework-only) · plugin valid · git clean. **Recovery-sim:** reference the captured evidence (`state/audit/recovery-sim-2026-06-15.log` = 31/31, exit 0) — do NOT re-run the 27-min suite at deploy; the remediation already ran it green. Health HEALTHY (raised SLO knobs + `--no-upstream`, per v3.24.0).

## Step 4 — release
1. `git push origin main`.
2. `git tag -a v3.25.0 -m "FuseBase Flow v3.25.0 — upgrade-tooling hardening (Windows perf, baseline/policy merge-preserve, sync allowlist, GEMINI sync, PARTIAL_UPGRADE)"`; `git push origin v3.25.0`.
3. `gh release create v3.25.0 --title "v3.25.0 — upgrade-tooling hardening" --notes-file docs/release-notes/v3.25.0.md --latest`.
4. Capture deploy hash.

## Step 5 — probes + smoke (the things we changed)
- Probes G-M..G-Q.
- **Smoke (ground truth):** (a) `mirror-skills.sh` → manifest byte-identical (diff vs committed); (b) `sync-version-strings.sh --dry-run` → only framework files in scope, a consumer-style `docs/product-backlog`-shaped path with an FR token NOT in scope; (c) GEMINI.md shows v3.25.0 (U5 worked); (d) health-check `PARTIAL_UPGRADE` check: no false-positive on the just-synced repo; (e) `.gitattributes` present, progress output visible. Capture evidence.

## Step 6 — single FR-14 docs commit + follow-up
- Flip `docs/specs/upgrade-tooling-hardening/spec.md` → DONE + deploy hash; fill task SHAs.
- **File the U6 follow-up backlog ticket** `docs/backlog/adapter-overlay-refresh-parity/README.md` (GEMINI/copilot/cursor marker-anchored overlay-refresh path) + add to `docs/backlog/index.md`.
- Output the deploy report.

## Rollback
`git revert <deploy hash range>` — the changes are to tooling scripts + tests + docs; additive/behavior-preserving where it counts (manifest byte-identical, content model untouched). Re-push; re-mirror.

## Notes
- FR-07: NO change to FLOW_RULES FR rows / 3 deploy-policy rule semantics / ratchet-governance.yml. U3 changes only how upgrade HANDLES policy project-state. internal/ + repo-polish untracked.
