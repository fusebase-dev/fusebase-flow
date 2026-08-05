# Deploy handoff — secret-scan-and-msys-liveness-fix → v3.30.2 (PATCH)

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.30.1 → shipping **v3.30.2**. Self-attest FR-01..FR-27 + DP. **DP.1/DP.12 approval:** operator said **"ship now and consumer will test it"** (2026-06-30) — explicit go-ahead; proceed under DP.12, no interactive DP.6. **Run SYNCHRONOUSLY — no background monitors (FR-27); bound every long run, read results from files, leave NO runaways.** Host is CPU-saturated (~87 procs) — the full suite is slow and may exceed a single bound; see Step 4. **Re-read VERSION immediately before writing 3.30.2 into any public file.** "FuseBase" = two capitals.

## What ships
Fixes for **two consumer-reported Windows/MSYS bugs**:
- **Bug A — pre-commit secret-scan self-trip.** `hooks/git/pre-commit` now scans only added (`+`) lines + path-excludes the scanner's own designed-token files (`policies/secret-patterns.yml`, `.local`, `hooks/tests/fixtures/`) via a Python helper; `scan()` unchanged → a Flow-upgrade that edits `secret-patterns.yml` no longer BLOCKs, fixtures 10/11 still detect, **no whitelist needed** (avoids the trap). Two consumers validated.
- **Bug B — MSYS bounded-run hang + health-check false-BROKEN.** A native pipe-holding descendant surviving POSIX `timeout` cleanup made any bounded `$(…)` capture hang (B1) and surfaced an unrecognized rc → non-deterministic false BROKEN (B2). Fix: **tempfile capture** in `ffhc_run_bounded` + conflict reporter = guaranteed anti-hang (the parent never starves a pipe); **MSYS best-effort process-tree kill** (winpid captured at launch → `taskkill //F //T` on timeout) reaps native runaways; **POSIX `run_with_timeout` byte-unchanged**. Health-check reclassifies a killed/unparseable hook-test run to advisory `HOOK_TESTS_INCONCLUSIVE`→`PARTIAL_UNVERIFIED` (exit 4), **not BROKEN** — with a no-strict-PASS guard so a crash-after-PASS still reads BROKEN. `--skip-hook-tests` alias (Windows escape); `upgrade.sh` progress echoes.
**No new FR rule, no new Flow skill (FR-01..FR-27, 32 skills unchanged); verdict ENUM + exit codes (0/2/3/4) unchanged.** 10 commits on `origin/main` `e12aabf`, HEAD `a7735a1`. **Reviews:** Codex design ×2 (RESCOPE folded — root cause corrected by consumer field evidence) + FuseBase impl (SHIP, on-host RED 8.2s→GREEN 3s) + Codex final (DO-NOT-SHIP → BLOCKER fixed) + **Codex re-validation (SHIP, all findings resolved, no regressions)**. Honest limit: the MSYS tree-kill is BEST-EFFORT (Windows doesn't reparent orphans; the tempfile capture is the guaranteed anti-hang) — documented; consumers confirm on their builds post-release.

## Step 1 — version bump
- Re-read `VERSION` (expect 3.30.1). Set `VERSION` + `.claude-plugin/plugin.json` `3.30.1` → **3.30.2** (equal).
- `bash hooks/local/sync-version-strings.sh` (bound it) — verify GEMINI.md = v3.30.2; FR-01..FR-27 + 32 skills unchanged; no consumer doc touched.

## Step 2 — README
- Badge (line 9) `3.30.1` → `3.30.2` (manual).

## Step 3 — release notes + CHANGELOG
New `docs/release-notes/v3.30.2.md` + `CHANGELOG.md [3.30.2]` (2026-06-30, deploy hash after release commit): the two Bug A / Bug B fixes above; FR-07-clean/additive; POSIX byte-unchanged; the honest best-effort tree-kill limit; dual-reviewed + Codex re-validated; root cause corrected by consumer field evidence.

## Step 4 — final gate (host-load-aware — do NOT push on an unverified gate)
preflight 0/0 (bounded) · `bash -n` the changed shells · plugin==VERSION==3.30.2 · the 5 FR-07 surfaces UNCHANGED (FLOW_RULES FR rows, approval-policy, protected-paths, command-policy, ratchet-governance) · **POSIX `run_with_timeout` byte-identical to `1c762cc`/`83b15f5`** · check-module-size --all exit 0 · mirror 0 drift · **run-tests: CONFIRM 0 FAIL across ALL phases.** The full monolith may exceed a single bound under load — if so, prove every phase green via targeted bounded runs (the load-bearing ones: `test-health-check-timeout.sh` incl. the 3 B2 cases, `test-msys-tree-cleanup.sh` 6/6, `test-secret-scan-staged.sh` 8/8, the JSON/module-size phases) and record 0 FAIL from each; **DO NOT push if any phase FAILs or cannot be verified.** git clean after the release commit.

## Step 5 — release
1. `git push origin main`.
2. `git tag -a v3.30.2 -m "FuseBase Flow v3.30.2 — secret-scan self-trip + MSYS bounded-run hang/false-BROKEN fixes"`; `git push origin v3.30.2`.
3. `gh release create v3.30.2 --title "v3.30.2 — secret-scan + MSYS liveness fixes" --notes-file docs/release-notes/v3.30.2.md --latest`.
4. Capture deploy hash.

## Step 6 — probes + smoke (bounded; capture evidence)
- GEMINI.md = v3.30.2; README badge = 3.30.2; FR-01..FR-27 + 32 skills; `git grep -ni headroom` in code = 0; mirror byte-identical.
- **Bug A smoke:** `test-secret-scan-staged.sh` (a staged `secret-patterns.yml` edit not blocked + a real secret on a `+` line in a normal file STILL blocks + fixtures 10/11 detect).
- **Bug B smoke:** `test-msys-tree-cleanup.sh` (no-hang, rc 124/137, tempfile faster than pipe) + the B2 trio (`b2-signal-inconclusive` exit 4, `b2-genuine-crash-broken` exit 2, `b2-pass-then-signal-broken` exit 2) + POSIX `run_with_timeout` byte-identical.

## Step 7 — single FR-14 docs commit
- Flip `docs/specs/secret-scan-and-msys-liveness-fix/spec.md` → **DONE** + deploy hash + tag + release URL + a one-line note that D-VALIDATION consumer re-test happens POST-release (operator chose "ship now").
- Push. Output the deploy report.

## Hard rules
FR-07: FR-01..FR-27 rows + 3 deploy-policy semantics + ratchet UNCHANGED (version attestation lines allowed). POSIX `run_with_timeout` byte-identical; `ffhc_*` API + rc(124/137) + verdict ENUM + exit codes intact. Keep `internal/` + repo-polish + `.claude/settings.local.json` + the `*-implement.md`/`*-fix.md`/`*-deploy.md` handoffs + `state/` untracked. If any gate/probe FAILs or can't be verified, STOP and report — do not push a broken/unverified release.

## Rollback
`git revert <release range>` — additive/advisory (secret-scan pathspec + a tempfile-capture anti-hang + best-effort MSYS reap + a B2 reclassification; POSIX path unchanged; no FR/skill added). Re-push; re-mirror.

## Return
Deploy report: version, deploy hash, tag, release URL, GEMINI + README badge = v3.30.2, FR-01..FR-27/32-skills confirmation, the Bug A + Bug B smoke evidence (secret-scan; msys-tree no-hang; B2 trio; POSIX byte-identical), FR-07 confirmation, and the FR-14 docs commit SHA.
