# maintainer-tree-split

**Status:** open — 6.0.0 rebuild, **wave 1** (WP 1a). **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 1a (R §2). **Surface:** every tracked file outside the core list; `maintainer/` (new); `.github/workflows/*.yml` (path references); `policies/module-size-baseline.txt` (if `upgrade.sh` moves). **FR-07:** commit 1 yes (`ci_cd_config`, CI row 1); the carve yes where it touches `FLOW_RULES_HISTORY.md` or `policies/module-size-baseline.txt` (`policies/protected-paths.yml:84-101`); every workflow commit is `ci_cd_config` (`:74-82`).

## Delivers

- **The layout of ask 2.** The core stays at the repository root, laid out as in a project; everything upstream-only moves under `maintainer/`. Nothing under `maintainer/` is installed. A `core/` subfolder is not built: the Flow repository's own pre-commit blocks every commit when `hooks/local/lib/precommit-validator-reuse.sh` is missing (`hooks/git/pre-commit:817-822`), and `bounded-run.sh` finds the repository root three directories above itself (`hooks/local/lib/bounded-run.sh:28-32`).
- **Commit 1 (WP1a-1, T170): the calibration tools leave the core names and register with the hosted runner** (owner, second message). One outcome, wave 1, the first commit of this WP:
  - moves `hooks/local/lib/reader.py` → `maintainer/calibration/calib_histogram.py`, `hooks/local/lib/checks.py` → `maintainer/calibration/calib_retro.py`, `hooks/local/lib/checks_git.py` → `maintainer/calibration/calib_retro_git.py`, `hooks/tests/fixtures/reader_histogram.py` → `hooks/tests/fixtures/calib_histogram.py`, `hooks/tests/fixtures/checks_retro.py` → `hooks/tests/fixtures/calib_retro.py`;
  - edits the sibling import (`checks.py:19`), the fixtures' path and import lines (`checks_retro.py:1-3, 19-23`; `reader_histogram.py:21-22, 478`, importing the renamed modules under their old local aliases so no assertion line changes) and their group strings to `calib-retro` (`checks_retro.py:39, 42`) and `calib-histogram` (`reader_histogram.py:24`);
  - registers both as opt-in tags `calib-histogram` and `calib-retro`: wrappers `hooks/tests/test-calib-histogram.sh` and `hooks/tests/test-calib-retro.sh`, each finding its fixture beside itself; the tags in `FF_TAGS` before `cli-flow-recovery-selectors` and in `FF_OPTIN_TAGS` before `consumer-benchmark` (`hooks/tests/run-tests.sh:85, 111`; never at an array head or tail, which `hooks/tests/test-ff-only.sh:145, 147, 359` anchor), two `run_shell_phase` lines; two rows in `docs/maintainer-testing.md` § Diagnostic exclusions after `:93`;
  - adds `"maintainer"` to the allowed top-level entries (`.github/workflows/fusebase-flow-verify.yml:180`, CI row 1): `maintainer/` becomes a tracked top-level folder and the public-surface check fails any entry not on that list (`:182-197`);
  - restamps `audit/hook-layer-manifest.json`, then `audit/managed-content-manifest.json` (the three tools leave `hooks/local/lib/*` coverage, `hooks/local/lib/hook_manifest.py:101-102`; the wrappers enter `hooks/tests/*.sh` coverage, `:89-90`);
  - no consumer impact: both tools were added after `v5.11` (T165, T166) and never shipped; `maintainer/` is outside the managed set (`hooks/local/lib/managed_content_manifest.py:42-52`);
  - FR-07 yes, `ci_cd_config` (CI row 1). Proof: both fixtures locally in Python (119/119, 18/18); `phase_registry_check.py` prints no ERROR; hosted maintainer dispatch `groups=calib-histogram,calib-retro,ff-only` on Linux and MSYS. **1.5 agent-h** (new since R §2, registration included). Depends: the owner's answer to the CI edit list.
- **The carve.** The 62 non-test hook files R §1 lists as moved (installer, upgrader, health engine, manifests, recovery, release tooling), including the full `run-with-timeout.sh` and `job-fence.sh` (decision 4) and the five LF classed core (`job-fence.sh`, `active-approvals.sh`, `cli-version-check.sh`, `eol_guard.py`, `merge-module-size-baseline.sh`). Also the test tree (all tests leave the consumer), the maintainer docs and records, `install.sh`, the mirror and stamp scripts. The kept 18 files of decision 7 and every core-list path stay where they are.
- **Workflow path edits.** The four workflows carry about 35 path references to moved files. They go on the **one CI edit list** sent to the owner before any workflow file is touched (ask 6; second message); each workflow commit then mints a single-use `ci_cd_config` approval.

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Ask 2 (core at the root, `maintainer/` for the rest) | The layout |
| Decision 4 (trim) | The full `run-with-timeout.sh` (592 lines) and `job-fence.sh` move here; `core-hook-inventory` leaves lines 32-69 at the core path |
| Decision 7 (keep 18 files; confirmed drops; 62 moved) | The move list; nothing kept is moved |
| Decision 8 (≤10-line refusal file at `hooks/local/upgrade.sh`) | Open for this plan: the refusal file (text owned by `flow-migrate`) lands before `main` reaches a tree without the 5.11 upgrader (owner question B1, asked 2026-10-16: on a `release/6.0` integration branch, before `main` fast-forwards; on `main`, the upgrader move waits for the refusal-file commit in wave 4), so an installed 5.11 bootstrap never meets a missing engine without a message |
| Ask 6 (one release-wide authorization; ask once for CI path edits) | One approval per protected commit; the CI list goes first |
| Ask 7 (no duplicate pre-tag run) | Hosted focused groups only; the tagged gate is release evidence |
| Second message (calibration tools to `maintainer/` under new names, their tests registered with the hosted runner in wave 1; CI list before workflow edits) | Commit 1 (move and registration); the CI list |
| Backlog `upgrade-sh-at-module-ceiling` | Paid here only if moving `upgrade.sh` touches the file: its baseline row is keyed by path (`policies/module-size-baseline.txt:4`, 821 lines), so a move re-keys a protected file or triggers decompose-first (+3 to 4 agent-h) |

## Estimate

R §2 WP 1: 18 to 28 agent-h (mid 23) for 1a and 1b together; this entry's share 11 to 16 (mid 13.5), plus 3 to 4 if `upgrade.sh`'s debt triggers, plus 1.5 for commit 1 (move and registration). Review: independent (install authority), within R §2's review line.

## Depends

Commit 1: the owner's answer to the CI edit list (row 1). The carve: the decision table (answered); the owner's answer to the CI edit list before its workflow commits. Blocks: test and CI paths for every later WP; `flow-install-declared-providers`; `core-hook-inventory`'s trim of `run-with-timeout.sh` (its maintainer callers must move first, or in the same commit).

## Acceptance

1. A fresh `git clone` of the Flow repository still commits through its own installed hooks after the move (fixture), and the kept 5.11 fixtures pass from their new test location unchanged, except the named departures (asks 11a, 11b, the agent rename).
2. `bounded_run` still writes `state/audit/liveness/*.hb` at the repository root; a fixture fails when no `.hb` file appears (the silent-off case at `bounded-run.sh:28-32`).
3. No core-list path changes (`hooks/git/pre-commit:807, 817` resolve).
4. Nothing under `maintainer/` is on the install list (`flow-install-declared-providers` checks it by fixture).
5. No workflow file changes before the owner answers the CI edit list.
6. Proof per commit: hosted focused groups covering the moved callers (for example `liveness`, `health-check-timeout`, `upgrade-classify`, `run-preconditions`, `hook-manifest`), named per commit in this WP's plan.

## Wave split

All of WP 1a is wave 1. WP 1b is `flow-install-declared-providers` (wave 4).

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; LF = `flow-handoff-2026-10-15-lighter-flow.md`; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
