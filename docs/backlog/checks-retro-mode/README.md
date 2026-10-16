# checks-retro-mode

**Status:** DONE as T166 (`4daa771c`; built as `edf4be9d` on `rebuild/retro`, replayed linear). A **calibration tool**: it moves to `maintainer/` under a new name (owner, 2026-10-16, second message) and is **not** the core `checks.py` (that is `overbuilding-flags`). **Filed:** 2026-10-16 (6.0.0 rebuild, wave 0; R §2 "before the table"). **Surface:** `hooks/local/lib/checks.py` (550 lines), `hooks/local/lib/checks_git.py` (294), `hooks/tests/fixtures/checks_retro.py` (631). **FR-07:** no (`hooks/local/**` and `hooks/tests/**` are outside `policies/protected-paths.yml:84-101`).

## Delivered

- `checks.py --retro RANGE --repo --include --vendored --out`: flag 2 (new runtime dependencies flagged, devDependencies logged, new config keys including JSONC `tsconfig`, new environment variable names in added lines) and flag 4 (duplicate blocks over 20 normalized lines in added code, outside the `--vendored` globs), one TSV per run.
- The TSV uses the `state/flags/<slice>.tsv` columns with an empty ruling column (`checks.py:31`). Names and counts only, never code or subject text.
- Constant git-process budget, a no-progress watchdog (exit 4, no TSV), bounded reads of oversized blobs. The git plumbing is `checks_git.py`, imported as a sibling (`checks.py:19`).
- Fixtures R1-R8, R10-R14, R17-R21 on a fast-import repository: 18 PASS, including a hostile git config, stalled git children and a planted secret that never reaches the TSV.

## The release 1 run (addition 1)

- Run by the Flow team over `512354c3..df1e995c`: 890 commits, 884 scanned, 6 merges skipped, 174 rows, exit 0, 15.2 s. The owner filed the output as `calibration-release-1-flags-2026-10-16.tsv` beside D (D:226).
- Rows (D §14): runtime dependencies 25 (18 from the T1 scaffold `b7e92365`, 3 `zod` at T28, 4 at T54); development dependencies 18, logged; config keys 116 (110 from the T1 and T2 scaffold commits); environment variables 8 (7 in test code, 1 `PORT` in the scaffold); duplicate blocks 7, all real, smallest 27 lines; 0 rows from `_core` or `_web`.
- The reference-manifest check printed `not run`, never `0`.

## Decisions and asks carried

| Item | Where it lands |
|---|---|
| Addition 1 (run the tool ourselves, outputs only under `c:/tmp/flow-retro`) | Done, above |
| Second message: calibration tool, moves to `maintainer/` under a new name | `maintainer-tree-split` commit 1 (T170): `maintainer/calibration/calib_retro.py` + `calib_retro_git.py` |
| Second message: the 550 + 294 split is a size finding, resolved because this is not a core file | Recorded in the release note by `provider-coverage-proof` |
| Second message: register the tests with the hosted runner in wave 1 | Inside `maintainer-tree-split` commit 1 (T170, WP1a-1), one commit for both tools: tags `calib-retro` and `calib-histogram` |
| Second message: `DUP_OVER_LINES` 20 kept; flag 2's two exemptions; the dependency rulings (T1 scaffold exempt; T28 `zod`, T54 `@dnd-kit/*` and `react-router-dom` requested, owner 2026-10-16 with the runner conventions) | `overbuilding-flags` (the core flags carry them) |
| Decision 10c condition (e): `--retro` reports the `commit-msg` v2 reject rate before it ships | `trivial-tier-and-task-ids` adds the column to the maintainer copy (wave 2) |

## Remaining wave-1 work

**Move and registration: inside `maintainer-tree-split` commit 1 (T170, WP1a-1), one commit for both calibration tools.** Nothing is owned here.
- Names: `checks.py` → `maintainer/calibration/calib_retro.py`, `checks_git.py` → `maintainer/calibration/calib_retro_git.py`, fixture `checks_retro.py` → `hooks/tests/fixtures/calib_retro.py`, group string `calib-retro`.
- Wrapper `hooks/tests/test-calib-retro.sh` makes a temp dir and runs the fixture beside itself (`"$HERE/fixtures/calib_retro.py" "$ROOT" "$TMP"`). A wrapper is needed because `run_shell_phase` runs `bash <script>` and counts `^(PASS|FAIL|N/A): <tag> ` lines (`hooks/tests/run-tests.sh:512-561`); the fixtures already print that shape (`checks_retro.py:39, 42`; `reader_histogram.py:24, 36, 39`), with the group renamed in the same commit.
- Opt-in tags `calib-retro` and `calib-histogram`: in `FF_TAGS` before `cli-flow-recovery-selectors` and in `FF_OPTIN_TAGS` before `consumer-benchmark` (`hooks/tests/run-tests.sh:85, 111`; never at an array head or tail, which `hooks/tests/test-ff-only.sh:145, 147, 359` anchor), plus one `run_shell_phase` line each. Not in `FF_RELEASE_TAGS` (`:91-98`): these are not consumer behaviour. One row per tag in `docs/maintainer-testing.md` § Diagnostic exclusions after `:93`: every registered tag must be classified (preflight §11, `hooks/tests/test-ff-only.sh:109-118`).
- Restamps `audit/hook-layer-manifest.json`, then `audit/managed-content-manifest.json`: `hooks/tests/*.sh` is in hook-layer coverage (`hooks/local/lib/hook_manifest.py:89-90`).
- The registration itself needs no workflow edit: the maintainer workflow's `groups` input accepts any registered tag (`.github/workflows/fusebase-flow-maintainer.yml:10-14, 91-99`). The commit is FR-07 `ci_cd_config` for the move's one workflow edit (CI row 1: `maintainer` on the public-surface allow-list).
- Proof: Python runs locally first, 18/18 and 119/119; hosted maintainer dispatch `groups=calib-histogram,calib-retro,ff-only` on Linux and MSYS (both calibration rows PASS; `ff-only` covers the classification check).

## Acceptance

1. Met: `--retro` ran over a 900-commit range with no operator step and wrote one TSV in minutes, not hours (H WP 8; 15.2 s).
2. Met: the TSV carries names and counts only; a planted secret never reaches it (fixture).
3. Open (wave 1): no file named `checks.py` or `checks_git.py` remains under `hooks/local/lib/` that is the calibration tool; the core name is free for `overbuilding-flags`.
4. Open (wave 1): `FF_ONLY=calib-retro` runs the fixtures on both hosted platforms.

## Estimate and depends

Built: 5 to 7 agent-h for both tools, including review (R §2). Remaining: none here; the registration is inside `maintainer-tree-split` commit 1 (T170; 1.5 agent-h with the move). Blocks nothing in the core.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13-14; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
