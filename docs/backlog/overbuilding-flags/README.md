# overbuilding-flags

**Status:** open — 6.0.0 rebuild, **wave 2**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 8 (R §2). **Surface:** `hooks/local/lib/checks.py` (new core file, row 33: the four flags on **one slice's diff**; the calibration `--retro` tool now at that path leaves first, `maintainer-tree-split` commit 1), `state/flags/<slice>.tsv`, `policies/evidence-classes.yml` (vendored list, read from HEAD). **FR-07:** no.

## Delivers

Four computed flags and the two-question rubric (D §5; H WP 8), run by `gate <slice>` at the end of a slice, before review:
1. **Scope diff**: files changed against the globs the slice's tasks declare; a new file under no task's glob.
2. **Dependency and config diff**: new runtime dependencies (development dependencies logged), new config keys, new environment variables, and a dependency the reference project's manifest does not carry (the reference check is core, D:80; T166 printed it `not run`).
3. **Slice budget**: minutes, files and commits per task against the `phases.md` estimate and the slice start stamp the slicer writes; the same command hash three times; tool calls above the constants below; test paths budgeted separately.
4. **Redundancy**: duplicate blocks over `DUP_OVER_LINES` lines outside the project's vendored list.
- **Rubric**: two typed questions in the reader reviewer's return (does the diff add a feature the criterion does not ask for; is it further from the reference project than the task requires). A "yes" is a flag; it holds the slice for the planner only on a risk-tagged item.
- Each flag gets a stable id and a row in `state/flags/<slice>.tsv` (same columns T166 uses). `checks --rule <id> upheld|rejected` records one ruling at a time with a reason; `--rubric` ingests the saved reviewer return; `--precision` reports the share upheld and the share later acted on (decision 6).
- A trivial-tier commit runs no flag 1, flag 4 or rubric (H WP 10).
- **No flag blocks** in this release (decision 6; R §4 lock).

## Constants and exemptions (owner, 2026-10-16, second message; carried verbatim)

| Constant | Value | Provenance | Status |
|---|---|---|---|
| `CALLS_NO_COMMIT_MAX` (check 3) | 200 | release 1 histogram 2026-10-16, S7 between commits, working agents, p99 199, n 434; owner 2026-10-16 | flags above 200 |
| `CALLS_BEFORE_WORK_MAX` (check 3) | 135 | release 1 histogram 2026-10-16, S7 before first work, working agents, p99 134, n 156; owner 2026-10-16 | flags above 135 |
| `DUP_OVER_LINES` (check 4) | 20 | owner seed 2026-10-15; kept 2026-10-16: all 7 release 1 rows real, smallest 27 | SEED, flags |

- The other seeds keep their 2026-10-15 owner provenance: 2x the minute or file estimate, and three repeats of one command (D §5, D §14). The repeat seed is the same one `heartbeat-reader` alerts on.
- The calibration copy still carries the older provenance string (`checks.py:21-22`, "owner seed 2026-10-15"); the core file carries the 2026-10-16 text above.
- **Flag 2 exemptions, both logged, not flagged:** (1) a commit that **creates** the manifest or config file it adds keys or dependencies to; (2) an environment variable read **only** under test paths.
- **Owner rulings on the release 1 dependency rows:** the T1 scaffold rows are exempt; T28 `zod`, T54 `@dnd-kit/*` and `react-router-dom` were requested (AC15, AC27, FB-53; owner 2026-10-16 with the runner conventions), so flag 2 found no unrequested dependency in release 1 and its precision there is not measurable as a hit rate. A dependency counts as requested when a backlog item's acceptance criterion or inputs name the package (owner 2026-10-16). The rulings are recorded in the ruling column of the release 1 TSV (R §7).
- With the two exemptions, release 1 would have raised about 15 flags in 884 commits, every one on a real event (D §14).

## Decisions and asks carried

Decision 6 (flags only; two holds; `--rule`; two-column `--precision`; a `plan:` or `ship:` commit may stage `state/flags/*.tsv`); decision 11 (vendored list in `evidence-classes.yml`); decision 10c (trivial tier); the second message (constants, exemptions, rulings; core checks built to D's intent; a stated ceiling; one line on the extra lines when over 300); addition 3.

**Open for this WP's plan:** the "seed distributions" cut from T166 are calibration; if they are still wanted after the owner's constants, they go into `maintainer/calibration/calib_retro.py`, not the core file.

## Estimate

R §2: 6 to 8 agent-h (mid 7), which included the reference check and the seed distributions; plus decision 6's 1.5 shared with `evidence-row-validator`. Ceiling, plan proposal: 450 lines (R §5a row 5 estimated 500 to 750 including `--retro`, which is no longer here).

## Depends

`maintainer-tree-split` commit 1 (frees the name), `four-document-model` (globs, estimates, reference project), `trivial-tier-and-task-ids` (the tier test), `seven-policies` (`evidence-classes.yml`), `task-slicer` (slice start stamp, by interface). Blocks: `slice-gate`.

## Acceptance

1. Each flag has a fixture that fires and one that stays quiet (H WP 8); both flag 2 exemptions log and do not flag (fixtures).
2. A trivial-tier commit runs no flag 1, flag 4 or rubric (fixture).
3. `--precision` reproduces a hand count on a fixture flags file (H WP 8); a re-run of `gate` keeps existing rulings (stable ids).
4. No flag row carries code or command text; names, counts and hashes only.
5. The release note reports `checks.py`'s line count against D's 150, its stated ceiling, and one line on the extra lines if over 300.

## Wave split

Wave 2, two commits planned: (a) flags 1 to 4 with their fixtures; (b) `--rule`, `--rubric` and `--precision`. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13-14; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
