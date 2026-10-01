# Ovation escalation F1-F4

**Outcome:** close the Ovation Benchmarking consumer escalation (2026-09-30) with three independently reversible fixes and one declined item. **Authorization:** operator "go + release" in the PO chat, 2026-09-30; phase 1 = local commits only, phase 2 = release. **Release target:** v5.5. **Status:** phase 1 in progress.

| Item | Outcome | Boundary | Success / failure example | Result |
|---|---|---|---|---|
| F4 · T116 | `.fusebase-flow-source/` is never staged: shipped `.gitignore` and both `ff_git_exclude_backups` writers exclude `/.fusebase-flow-source/` | `.gitignore`; `hooks/local/lib/backup-hygiene.sh` (upgrade.sh, bootstrap-upgrade.sh); `hooks/local/post-fusebase-update.sh` | Failure: consumer `111d02a`, FuseBase CLI pre-update checkpoint `git add -A` committed the clone as gitlink 160000 with no `.gitmodules`. Success: after any writer, `git add -A` stages the project file and skips the clone | DONE — new release phase `transient-exclude` 6/6; RED on HEAD writers + `.gitignore` 1/6 (control only) |
| F2 · T117 | Pre-commit lint/typecheck BLOCK names the project command and its exit code and places the failure in the project | `hooks/local/lib/precommit-validator-reuse.sh` | Failure: bare `BLOCK — typecheck failed (FR-13).` read as a Flow defect. Success: `BLOCK — typecheck failed (FR-13): your project's command "npm run -s typecheck" exited 2; its output is above. ...` | pending |
| F1 · T118 | Health check prints a CLI advisory when an `@fusebase/*` package resolves to more than one installed version across package.json roots; verdict, counts and exit code unchanged | new `hooks/local/lib/fusebase_package_split.py`; `cli-version-check.sh`; `health-stage-progress.sh`; engine header rename only | Failure: `Verdict: HEALTHY` while `@fusebase/fusebase-gate-sdk` resolves to 2.14.0 and 2.11.9, so `instanceof ApiError` fails silently. Success: `@fusebase/fusebase-gate-sdk resolves to 2 versions — 2.14.0: ., tests/e2e · 2.11.9: apps/benchmarking/backend. ...` | pending |
| F3 | DECLINED — blocking pre-commit `@fusebase/*` version check | — | A blocking check fires on the CLI's own `fusebase update` checkpoint commit; Flow already hard-blocked that checkpoint once (v4.3.2, `backup-hygiene.sh` header). Off-by-default protects only teams that already have a guard. F1 gives detection without blocking | DECLINED |

**Test placement:** no existing phase covered `ff_git_exclude_backups`, so F4 adds `transient-exclude` and, as an essential consumer contract, enters `FF_RELEASE_TAGS` (43 → 44) per `docs/maintainer-testing.md:16`. Open for PO: release-profile membership changed under implementer-only review.

## Checks

Host: Windows 11, MSYS2 bash 5.3.15, native Python 3.12.10, git 2.55.0.windows.2. Linux not run locally; maintainer/release CI owns it. Logs: `c:/tmp/ff-ovation/`.

| Item | Command | Result |
|---|---|---|
| F4 | `bash hooks/tests/test-transient-exclude.sh` | 6/6 PASS, 26 s. RED: HEAD `backup-hygiene.sh` + `post-fusebase-update.sh` + `.gitignore` 1/6 (control only). Mutant editing the shipped header line fails `lib-writer-upgrades-v54-exclude-by-one-line-idempotently` (10 → 12 lines) |
| F4 | `FF_ONLY=transient-exclude bash hooks/tests/run-tests.sh` | 6/6 PASS, 63 s; `t116-runner.log` |
| F4 | `bash hooks/tests/test-ff-only.sh --only selection` | 46/46 PASS incl. `release-profile-is-explicit-44-tag-allowlist`, 148 s; `t116-ffonly-selection.log` |
| F4 | `bash hooks/local/preflight.sh` | 0 errors, 0 warnings; registry 81 registered / 44 release / 4 unreviewed, 39 s; `t116-preflight.log` |
| F4 | stamp + verify both manifests | hook-layer 225 assets, managed-content 394; both verify rc 0 |
