# trivial-tier-and-task-ids

**Status:** open — 6.0.0 rebuild, **wave 2**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 10 (R §2). **Surface:** `hooks/git/commit-msg` (57 lines; the prefix exemption `:27-38`, the T-number rule `:40-49`), `hooks/local/lib/validator_tier.py` (row 7, gains `--commit-msg`), `policies/evidence-classes.yml` (the tier lists, read from HEAD), `maintainer/calibration/calib_retro.py` (the reject-rate column). **FR-07:** yes for the `commit-msg` commit (`hooks/git/**`, `policies/protected-paths.yml:93`); the tier helper and the calibration column are not protected.

## Delivers

- **The trivial tier of rule 1** (H WP 10; D §10 row 1): when every staged path matches the project's docs-only, test or copy globs, or the diff is formatting only, one `T<n>` in the subject suffices and no backlog item is needed. The lists are keys in `policies/evidence-classes.yml`, read from HEAD the way the docs-only tier is (`validator_tier.py`), empty by default (the tier is inert until declared), non-code extensions only for docs and copy, never widened by a `.local.yml`. Outside the tier: deleting a test file, adding a skip token to a test, any edit to the four documents, any staged code extension.
- **The new `commit-msg`**: exactly one `T<n>` in a code, test or copy commit subject, resolved in `phases.md` at HEAD; `plan:` and `ship:` only when the staged paths are the four documents, plus `state/flags/*.tsv` and `state/gate/*.txt` (decision 6). It replaces the lowercase prefix exemption (`commit-msg:28`). The vague-subject checks stay (`:32`, `:52`).
- **Decision 10c conditions**, each with a fixture: (a) a merge is exempt by git state (`MERGE_HEAD`), never by its subject; (b) a revert is judged on its inner subject; (c) exactly one `T<n>`, resolved in `phases.md` at HEAD; (d) a standing housekeeping task per phase takes trivial commits (`four-document-model` carries it in the grammar); (e) the reject rate is reported before this ships.
- **The reject-rate column** for (e): added to `maintainer/calibration/calib_retro.py`, a "would `commit-msg` v2 accept this" verdict per commit from the subject and the staged paths. Release 1 has no `phases.md`, so the column checks the subject shape and the path tier only and says so. The Flow team runs it over release 1 (outputs under `c:/tmp/flow-retro`, as for addition 1) and sends the rate to the owner before the hook change lands.
- **Legacy mode** when no `phases.md` exists, so pre-migration projects and the Flow repository itself can still commit (R §2 WP 10). Open for this WP's plan: whether conditions (a) and (b) also apply in legacy mode (today a default "Merge branch …" subject is rejected, which is why T165 and T166 were replayed linear).
- `validator_tier.py --commit-msg`: one Python spawn per commit, sharing the HEAD-read list loader (R §3 row 7).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 10c and its five conditions | The hook change and its fixtures |
| Decision 11 (lists in `evidence-classes.yml`, HEAD only, no local twin) | Read path |
| Decision 6 (`plan:`/`ship:` may stage the flags and gate files) | Allowed paths |
| R §4 lock (tier lists read from HEAD; docs and copy lists take non-code extensions only; the tier never skips the secret scan, protected paths, module size, or lint and typecheck on code) | Fixtures |

## Estimate

R §2: 5 to 7 agent-h (mid 6), including about 0.5 for the reject-rate column. Review: independent (hook behaviour change).

## Depends

`four-document-model` (the `phases.md` task row and the housekeeping task), `seven-policies` (`evidence-classes.yml`), `maintainer-tree-split` commit 1 (the calibration tool's new home); decisions 10c and 11. The id-resolution part waits for the WP 2 grammar; the rest can be built first. Blocks: `overbuilding-flags` and `done-check` (the tier test), `eight-rule-kernel-and-cards` (rule 1), `flow-migrate` (the first commit after migration must pass).

## Acceptance

1. A commit with only test paths and one `T<n>` passes without a backlog item; the same paths plus one source file require the item; a `docs:` subject with no `T<n>` and a code path is rejected; a `plan:` commit touching a source file is rejected; a local policy override does not widen the lists (H WP 10).
2. A merge with `MERGE_HEAD` present passes; a revert is judged on its inner subject; two ids in one subject are rejected; an id absent from `phases.md` at HEAD is rejected (fixtures).
3. A code extension in the docs or copy list is rejected by the list loader.
4. With no `phases.md`, the 5.11 `commit-msg` rows of `hooks/tests/test-git-hooks-smoke.sh` pass unchanged (legacy mode).
5. The owner has the release 1 reject rate before the hook change is committed.
6. Proof: hosted groups `git-smoke`, `trusted-enforcer`, `hook-install-rc`, `validator-evidence`, plus the new tier group.

## Wave split

Wave 2, three commits planned: (a) the reject-rate column in the maintainer tool and its run; (b) `validator_tier.py --commit-msg` with fixtures; (c) the `commit-msg` change (one FR-07 approval), after the owner has the rate. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
