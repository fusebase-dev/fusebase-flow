# done-check

**Status:** open — 6.0.0 rebuild, **wave 2** (with `slice-gate`, one writer). **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 7b (R §2). **Surface:** one function in `hooks/local/lib/gate.py` (new core file, row 32, shared with `evidence-row-validator` and `slice-gate`), reading `phases.md` through `hooks/local/lib/flow_docs.py`, `git log` and `state/returns/<slice>.json`. **FR-07:** no.

## Delivers

- Before verify starts, on the slice branch from the phase's base SHA, every task id in the slice has at least one commit whose **subject** carries exactly one `T<n>` and whose diff touches a path under that task's declared globs (D §6; H WP 7b).
- Body mentions, trivial-tier commits and `plan:` or `ship:` commits do not count.
- `state/returns/<slice>.json`, written by the builder before it ends its turn, names the same ids and SHAs; a missing file is a DONE failure.
- Open tasks are listed back to the builder instead of being sent to review: the **DONE send-back**, one of the two holds of decision 6, released by the builder committing the task or by one planner ruling. Plan proposal: a planner override is recorded as a `DONE` row in `state/flags/<slice>.tsv` so `--precision` counts it.
- The ledger's `committed` field is derived from this check; nobody writes it by hand.
- Provider-neutral: `git` and the returns file only (H §4a).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 6 (the DONE send-back is a hold, not a flag) | Send-back semantics above |
| R §4 lock (the DONE send-back before verify) | Protects 3.3 h measured, 8.0 h upper bound (release 1 report) |
| Decision 10c (exactly one `T<n>`; trivial tier) | Shares the tier test with `trivial-tier-and-task-ids` |
| Addition 3 and the second message | Its function span is reported against D's 20 lines, with a stated ceiling and one line on the extra lines when over 40 |

## Estimate

Share of R §2 WP 7 (16 to 21.5 agent-h for 7a to 7d): 2 to 3. Ceiling, plan proposal: 120 lines for the function span (R §5a row 5 estimated 80 to 120).

## Depends

`four-document-model` (parser and task globs), `trivial-tier-and-task-ids` (the tier test, by interface). Blocks: `slice-gate`, `task-slicer` (slices re-printed after a send-back), the phase 7 count "slices sent back by the DONE check" (H §7).

## Acceptance

1. The check sends back a slice whose task id appears only in a commit body, only in a trivial-tier commit, or only in a commit touching none of the task's globs; it passes a slice with every id committed inside its globs (H WP 7 fixtures).
2. A missing `state/returns/<slice>.json` fails; a returns file whose ids or SHAs disagree with the log fails.
3. The same fixture passes with no provider hook present (H §4a rule 1).
4. The release note reports the function's line count against D's 20 and its ceiling.

## Wave split

Wave 2, one commit (function plus fixtures). Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`.
