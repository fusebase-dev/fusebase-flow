# Ovation escalation F1-F4

**Outcome:** close the Ovation Benchmarking consumer escalation (2026-09-30) with three independently reversible fixes and one declined item. **Authorization:** operator "go + release" in the PO chat, 2026-09-30; "1. Publish as 5.6 (Recommended)", 2026-10-01. **Release target:** v5.6. **Status:** v5.5 tagged (c78e283 -> ac293c1), not published: GitHub run 36802723787 stuck (Windows runner froze; cancel/force-cancel 409; job timeout did not finalize); shipping as v5.6.

| Item | Outcome | Boundary | Success / failure example | Result |
|---|---|---|---|---|
| F4 · T116 `9df3e6e` | `.fusebase-flow-source/` is never staged: shipped `.gitignore` and both `ff_git_exclude_backups` writers exclude `/.fusebase-flow-source/` | `.gitignore`; `hooks/local/lib/backup-hygiene.sh` (upgrade.sh, bootstrap-upgrade.sh); `hooks/local/post-fusebase-update.sh` | Failure: consumer `111d02a`, FuseBase CLI pre-update checkpoint `git add -A` committed the clone as gitlink 160000 with no `.gitmodules`. Success: after any writer, `git add -A` stages the project file and skips the clone | DONE — new release phase `transient-exclude` 6/6; RED on HEAD writers + `.gitignore` 1/6 (control only) |
| F2 · T117 `fcbd71e` | Pre-commit lint/typecheck BLOCK names the project command and its exit code and places the failure in the project | `hooks/local/lib/precommit-validator-reuse.sh` | Failure: bare `BLOCK — typecheck failed (FR-13).` read as a Flow defect. Success: `BLOCK — typecheck failed (FR-13): your project's command "npm run -s typecheck" exited 2; its output is above. ...` | DONE — `validator-evidence` 29/29 + selectors `t48-remaining` 4/4, `t53` 3/3 |
| F1 · T118 `8eddc0a` | Health check prints a CLI advisory when an `@fusebase/*` package resolves to more than one installed version across package.json roots; verdict, counts and exit code unchanged | new `hooks/local/lib/fusebase_package_split.py`; `cli-version-check.sh`; `health-stage-progress.sh`; engine header rename only | Failure: `Verdict: HEALTHY` while `@fusebase/fusebase-gate-sdk` resolves to 2.14.0 and 2.11.9, so `instanceof ApiError` fails silently. Success: `@fusebase/fusebase-gate-sdk resolves to 2 versions — 2.14.0: ., tests/e2e · 2.11.9: apps/benchmarking/backend. ...` | DONE — new release phase `cli-packages` 9/9; 4/4 mutants caught |
| F3 | DECLINED — blocking pre-commit `@fusebase/*` version check | — | A blocking check fires on the CLI's own `fusebase update` checkpoint commit; Flow already hard-blocked that checkpoint once (v4.3.2, `backup-hygiene.sh` header). Off-by-default protects only teams that already have a guard. F1 gives detection without blocking | DECLINED |

**Test placement:** no existing phase covered `ff_git_exclude_backups` or the new advisory, so F4 adds `transient-exclude` and F1 adds `cli-packages` (no engine spawn); both guard essential consumer contracts and enter `FF_RELEASE_TAGS` (43 → 45) per `docs/maintainer-testing.md:16`. Open for PO: release-profile membership changed under implementer-only review.

**F1 implementation choices:** the engine's `ffhc_run_cli_version_stage "$FFHC_CLIVER_LIB"` line is unchanged (it is the `cli-version` mutation-control anchor, `test-cli-version-gate.sh:304-307`); the existing wrapper in `health-stage-progress.sh` runs the scan as its own `cli-packages` stage. The module is fed on stdin through `ffhc_run_bounded_stdin_stdout`, not as a path through `ffhc_run_bounded_stdout`: under `MSYS_NO_PATHCONV=1`, native Windows python3 cannot open an MSYS `/c/...` path (measured: `os.path.isdir('/c/Users')` is False, converted `C:/Users` is True).

## Checks

Host: Windows 11, MSYS2 bash 5.3.15, native Python 3.12.10, git 2.55.0.windows.2. Linux not run locally; maintainer/release CI owns it. Logs: `c:/tmp/ff-ovation/`.

| Item | Command | Result |
|---|---|---|
| F4 | `bash hooks/tests/test-transient-exclude.sh` | 6/6 PASS, 26 s. RED: HEAD `backup-hygiene.sh` + `post-fusebase-update.sh` + `.gitignore` 1/6 (control only). Mutant editing the shipped header line fails `lib-writer-upgrades-v54-exclude-by-one-line-idempotently` (10 → 12 lines) |
| F4 | `FF_ONLY=transient-exclude bash hooks/tests/run-tests.sh` | 6/6 PASS, 63 s; `t116-runner.log` |
| F4 | `bash hooks/tests/test-ff-only.sh --only selection` | 46/46 PASS incl. `release-profile-is-explicit-44-tag-allowlist`, 148 s; `t116-ffonly-selection.log` |
| F4 | `bash hooks/local/preflight.sh` | 0 errors, 0 warnings; registry 81 registered / 44 release / 4 unreviewed, 39 s; `t116-preflight.log` |
| F4 | stamp + verify both manifests | hook-layer 225 assets, managed-content 394; both verify rc 0 |
| F2 | direct: `run_precommit_validators` with lint `(exit 7)` / typecheck `sh -c "echo tc-out; exit 2"` | new BLOCK lines name the command and `exited 7` / `exited 2`, function rc 1; passing commands rc 0 under `set -e` |
| F2 | `FF_ONLY=validator-evidence bash hooks/tests/run-tests.sh` | 29/29 PASS, 343 s; `t117-validator-evidence.log`. The default run excludes the `:232` / `:273` rows |
| F2 | `test-validator-evidence.sh --only t48-remaining` / `--only t53` | 4/4 incl. `remaining-lint-failure-boundary-stays-red`; 3/3 incl. `t53-fallback-validator-failure-stays-red`; 29 s; `t117-ve-selectors.log` |
| F2 | stamp + verify both manifests | hook-layer 225, managed-content 394; both verify rc 0 |
| F1 | `bash hooks/tests/test-cli-package-split.sh` | 9/9 PASS, 35 s. Mutants (`t118-mutants.log`): dot-dirs walked → `node-modules-and-dot-dirs-ignored` FAIL; no Node walk-up → 3 FAIL; split routed to `LOCAL_DRIFT` → `wrapper-appends-one-advisory-and-no-verdict-entry` FAIL; `fusebase.json` gate removed → both gate rows FAIL |
| F1 | `FF_ONLY=cli-packages bash hooks/tests/run-tests.sh` | 9/9 PASS, 69 s; `t118-runner.log` |
| F1 | stage-wrapper smoke, uncommitted: `ffhc_run_cli_version_stage` on a split fixture, no engine | START/END for `cli-version` and `cli-packages`; split line in `CLI_VERSION_ADVISORY`; `LOCAL_OK`/`LOCAL_DRIFT`/`LOCAL_UNVERIFIED`/`CLI_VERSION_UNSUPPORTED` all 0 |
| F1 | engine not spawned (brief) | `fusebase-flow-health-check.sh` 800 → 800 lines; mutation anchor intact (1 match); engine-level rows stay with CI `health-check-timeout` / `cli-version` |
| F1 | `mirror-skills.sh`, `--check`, `cmp` overlay | 0 drift; canonical = overlay recovery copy = both mirrors |
| F1 | `bash hooks/local/preflight.sh` | 0 errors, 0 warnings; registry 82 registered / 45 release / 4 unreviewed, 31 s; `t118-preflight2.log` |
| F1 | `bash hooks/tests/test-ff-only.sh --only selection` | 46/46 PASS incl. `release-profile-is-explicit-45-tag-allowlist`, 129 s; `t118-ffonly-selection.log` |
| F1 | stamp + verify both manifests | hook-layer 227, managed-content 396; both verify rc 0 |
