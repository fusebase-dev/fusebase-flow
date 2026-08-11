# Deploy handoff — healthcheck-baseline-and-custom-flag-hardening → v3.30.1 (PATCH)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.30.0 → shipping **v3.30.1**. Self-attest FR-01..FR-27 + DP section. **DP.1/DP.12 approval:** operator instruction "proceed to finalize them and deploy under new version" (2026-06-30) — explicit go-ahead to ship; proceed under DP.12, no interactive DP.6 needed. **Run SYNCHRONOUSLY — no background monitors (FR-27).** Re-read VERSION right before writing any version number into a public file. "FuseBase" is always two capitals.

## What ships
**Health-check baseline + custom-flag hardening** — the two non-blocking follow-ups from v3.30.0, both ADVISORY-ONLY:
- Durable updater-written receipt `state/audit/cli-stop-baseline.json` (written by `settings-json-merge.py --baseline-out` via `post-fusebase-update.sh --wire-hooks`, on real-merge AND no-op) replaces the ephemeral `.pre-flow-merge` diff source → closes the v3.30.0 silent-non-detection blind spot.
- Reporter is now advisory-only: `CLI_STOP_UNVERIFIED` (stop.py wired, no receipt) + `CLI_STOP_BASELINE_DRIFT` (a baselined CLI Stop hook missing now) — **the v3.30.0 `SHARED_MERGE_DRIFT`/exit-1 path is REMOVED** (preserve-only merge ⇒ a missing hook is never a merge fault).
- `CLI_CUSTOM_AT_RISK` now gated on provenance drift (sha≠provenance) → the pristine-`app-dev-practices` over-flag is gone; genuine operator-content signal preserved.
**No FR rule, no new Flow skill (FR-01..FR-27, 32 skills unchanged); verdict ENUM + exit codes (0/1/2) UNCHANGED** (the two new findings are advisory, like `CLI_SNAPSHOT_STALE`). 4 local commits on `origin/main` `61b8707`, HEAD `363b9be`. **Both reviews SHIP:** Codex design RESCOPE folded (advisory-only); FuseBase adversarial impl review **SHIP, zero findings** (advisory-only invariant unbreakable; recovery suite 31/0 to completion; sha-gate verified on the real skill).

## Step 1 — version bump
- Re-read `VERSION` (expect 3.30.0). Set `VERSION` + `.claude-plugin/plugin.json` `3.30.0` → **3.30.1** (equal).
- `bash hooks/local/sync-version-strings.sh` — verify adapters incl. GEMINI.md = v3.30.1; FR-01..FR-27 + 32 skills unchanged; under-reach guard passes; no consumer doc touched.

## Step 2 — README
- Badge (line 9) `3.30.0` → `3.30.1` (manual).

## Step 3 — release notes + CHANGELOG
New `docs/release-notes/v3.30.1.md` + `CHANGELOG.md [3.30.1]` (date 2026-06-30, deploy hash after release commit): **Health-check baseline + custom-flag hardening (advisory-only).** Cover: the durable receipt closing the v3.30.0 no-op blind spot; the advisory-only reclassification (no exit-1 from a missing CLI Stop hook — preserve-only merge means it's never a merge fault; re-run `post-fusebase-update.sh --wire-hooks` to re-baseline); the two new advisory findings; the `CLI_CUSTOM_AT_RISK` sha-gate. FR-07-clean / advisory-only (verdict enum + exit codes unchanged). Dual-reviewed (Codex design + FuseBase impl, both SHIP; recovery suite 31/0).

## Step 4 — final gate
preflight 0/0 · `bash -n check-cli-flow-conflicts.sh post-fusebase-update.sh` + `python -m py_compile settings-json-merge.py` · run-tests **182/182** PASS · `test-cli-flow-recovery.sh` to completion (31/0) · check-module-size --all exit 0 · mirror 0 drift (4 health-check skill copies byte-identical) · plugin==VERSION==3.30.1 · the 5 FR-07 surfaces UNCHANGED · git clean after the release commit.

## Step 5 — release
1. `git push origin main`.
2. `git tag -a v3.30.1 -m "FuseBase Flow v3.30.1 — health-check baseline + custom-flag hardening (advisory-only)"`; `git push origin v3.30.1`.
3. `gh release create v3.30.1 --title "v3.30.1 — health-check baseline + custom-flag hardening" --notes-file docs/release-notes/v3.30.1.md --latest`.
4. Capture deploy hash.

## Step 6 — probes + smoke (capture evidence)
- mirror byte-identical; sync --dry-run framework-only; GEMINI.md = v3.30.1; README badge = 3.30.1; FR-01..FR-27 + 32 skills; `git grep -ni headroom` in code = 0.
- **Ticket smoke (advisory-only invariant):** on a fixture, `post-fusebase-update.sh --wire-hooks` writes `state/audit/cli-stop-baseline.json` (3 CLI hooks, excludes stop.py) + survives a 2nd no-op; drop a baselined hook → `CLI_STOP_BASELINE_DRIFT` advisory, **verdict HEALTHY, exit 0**; delete receipt → `CLI_STOP_UNVERIFIED` advisory, exit 0; pristine skill (sha==provenance)+CUSTOM → NOT flagged; drifted → flagged. Confirm NO input yields exit-1 from the new findings. Clean up the fixture.

## Step 7 — single FR-14 docs commit
- Flip `docs/specs/healthcheck-baseline-and-custom-flag-hardening/spec.md` → **DONE** + deploy hash + tag + release URL.
- Flip both resolved backlog tickets → DONE: `docs/backlog/healthcheck-diff-source-hardening/README.md` + `docs/backlog/cli-custom-at-risk-overflag/README.md` (resolved by this release; note the resolution = advisory-only receipt model + sha-gate).
- Update `docs/backlog/index.md` rows if that index exists.
- Push. Output the deploy report.

## Hard rules
FR-07: FR-01..FR-27 rows + 3 deploy-policy semantics + ratchet UNCHANGED (version attestation lines allowed). Advisory-only (no new exit-1; verdict enum + exit codes intact). Health-check stays read-only. Keep `internal/` + repo-polish + `.claude/settings.local.json` + the `*-implement.md`/`*-deploy.md` handoffs + `state/` runtime artifacts untracked. If any gate/probe fails, STOP and report.

## Rollback
`git revert <release range>` — additive/advisory-only (a receipt mechanism + advisory findings + a sha-gate; removed one exit-1 path); no FR rule/skill added. Re-push; re-mirror.

## Return
Deploy report: version, deploy hash, tag, release URL, GEMINI + README badge = v3.30.1, FR-01..FR-27/32-skills confirmation, the advisory-only ticket smoke (receipt durable; dropped-hook→advisory exit 0; UNVERIFIED exit 0; sha-gate; no exit-1 forceable), FR-07 confirmation, and the FR-14 docs commit SHA (spec + 2 backlog tickets → DONE).
