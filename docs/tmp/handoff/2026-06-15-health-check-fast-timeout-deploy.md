# Deploy handoff — health-check-fast-timeout → v3.24.0

## Role bootstrap
You are the **Deploy phase** (AI Developer) under FuseBase Flow v3.23.1 → shipping **v3.24.0**. Self-attest (FR-01..FR-26), DP section.

**Lane:** Full (the diagnostic engine + a verdict/exit-code **contract change** — new `PARTIAL_UNVERIFIED`/exit 4). DP.12 plain go-ahead applies since the operator authorized autonomous end-to-end execution ("execute all of the end to end … expecting it all be completely done"). No interactive DP.6 needed; proceed.

## Pre-deploy state
- Branch `main`, **14 local/unpushed commits** (8 impl T1–T8 + 6 fixes), HEAD `9294b08`. origin/main = `720c1eb`.
- **4 Codex review rounds → SHIP** (round-4: no realistic false-HEALTHY; residual is exotic/out-of-threat-model). preflight 0/0; targeted tests 26/26; full harness 50/50; check-module-size --all exit 0 (engine 799); FR-07 clean.
- VERSION + plugin.json should both be **3.24.0** (the impl set VERSION; verify plugin.json matches).

## Step 0 — document the exotic residual (one small commit)
Per round-4: add a ≤2-line threat-model note where the run-tests verdict is computed (`hooks/local/fusebase-flow-health-check.sh` near the PASS classifier, and/or `flow-skills/fusebase-flow-health-check/SKILL.md`): *"The hook-test PASS classifier trusts the framework-owned `run-tests.sh` `FAIL:`/`N/N PASS` contract. A maliciously-crafted harness output that emits one clean summary while hiding failures is out of threat model — it requires control of the harness (i.e. the repo is already compromised)."* Verify preflight 0/0 after.

## Step 1 — version + sweep
Confirm VERSION + `.claude-plugin/plugin.json` = **3.24.0** (equal). Run `bash hooks/local/sync-version-strings.sh` (FR-01..FR-26; 31 skills — no new skill; this extends the engine). Dated history untouched.

## Step 2 — release notes
New `docs/release-notes/v3.24.0.md` + `CHANGELOG.md [3.24.0]`: date, deploy hash (after push). Summary: **health-check fast/timeout hardening** — every slow op (`git fetch`, preflight, run-tests, check-cli-flow-conflicts) is now bounded via `run_with_timeout` (timeout→gtimeout, `-k`, rc-124/137); a timed-out/skipped **critical** check returns the new **`PARTIAL_UNVERIFIED` verdict / exit 4** (never false-HEALTHY); upstream comparison is optional (fetch-timeout = note); `--fast` (quick partial, exit 4) + `--no-upstream` (full local, exit 0) flags; fixed a pre-existing run-tests rc-masking bug (crash/garbled/wrong-count summary ⇒ BROKEN). **New exit code 4** documented as a contract addition (callers: 0 HEALTHY · 1 drift · 2 BROKEN · 3 EXCEPTION · 4 PARTIAL_UNVERIFIED). Note the exotic residual is out-of-threat-model.

## Step 3 — final gate
preflight 0/0 · `bash hooks/tests/test-health-check-timeout.sh` all pass · `bash hooks/tests/run-tests.sh` PASS · `check-module-size.sh --all` exit 0 · health HEALTHY (use raised SLO env knobs on this slow host: `FFHC_PREFLIGHT_TIMEOUT=120 FFHC_CONFLICT_TIMEOUT=120 FFHC_TESTS_TIMEOUT=240 ... --no-upstream`) · mirror 0 drift · plugin valid · git clean.

## Step 4 — release
1. `git push origin main`.
2. `git tag -a v3.24.0 -m "FuseBase Flow v3.24.0 — health-check fast/timeout hardening (PARTIAL_UNVERIFIED verdict + exit 4)"`; `git push origin v3.24.0`.
3. `gh release create v3.24.0 --title "v3.24.0 — health-check fast/timeout hardening" --notes-file docs/release-notes/v3.24.0.md --latest`.
4. Capture deploy hash.

## Step 5 — probes + smoke
- Probes G-M..G-Q (push/tag landed; preflight shipped tree; engine present; --fast returns exit 4 quickly; docs updated).
- **Smoke (the thing we changed):** run the health-check on this repo with raised SLO knobs + `--no-upstream` ⇒ HEALTHY/0 with `[run-tests] N/N PASS`; run `--fast` ⇒ exit 4 + "not a full verdict"; force a timeout (low env knob) on a critical ⇒ PARTIAL_UNVERIFIED/4. Capture exit codes (ground truth).

## Step 6 — single FR-14 docs commit
Flip `docs/specs/health-check-fast-timeout/spec.md` → DONE + deploy hash; fill tasks T1–T12 SHAs; backlog `health-check-fast-timeout` → done in `docs/backlog/index.md`. Output the deploy report.

## Rollback
`git revert <deploy hash>` (the engine change is additive + read-only; exit-4 is a new code, no caller breaks per AC8). Re-push; re-mirror. Tag v3.24.0.

## Notes
- FR-07: NO change to FLOW_RULES FR rows / 3 deploy policies / ratchet-governance.yml. Engine read-only (never repairs). internal/ + repo-polish untracked. Do NOT start the upgrade-tooling ticket (that's the next ticket; its spec is at docs/specs/upgrade-tooling-hardening/).
