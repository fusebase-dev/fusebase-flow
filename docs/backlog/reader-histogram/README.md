# reader-histogram

**Status:** DONE as T165 (`37d80a25`; built as `daca7971` on `rebuild/hist`, replayed linear). A **calibration tool**: it moves to `maintainer/` under a new name (owner, 2026-10-16, second message) and is **not** the core `reader.py` (that is `heartbeat-reader`). **Filed:** 2026-10-16 (6.0.0 rebuild, wave 0; R §2 "before the table"). **Surface:** `hooks/local/lib/reader.py` (767 lines), `hooks/tests/fixtures/reader_histogram.py` (697). **FR-07:** no.

## Delivered

- `reader.py --histogram --out …` over the audit log and Claude Code transcript JSONL, numbers only. Series: transcript line gaps by kind (command, delegate, other tool, model, idle; main session and agents apart), audit-row gaps, tool-call spans, tool calls per agent (total, before first work, between `git commit` commands), and every gap of 20 min or more with its start time.
- Every output row is typed and checked against a fixed schema before anything is written; argument errors print fixed text only (`reader.py:2-8`). Display edges 1 to 480 min are display bins, not thresholds (`reader.py:24-25`).
- Fixtures H1-H6, H10-H13: 119 checks, including planted secrets in commands, paths, tool names, cwd and session ids that never reach stdout, stderr or `--out`.
- Known property: "between commits" counts only a literal `git commit` command, so commits made through a wrapper script are not boundaries (R §7).

## The release 1 run (addition 1)

- Run by the Flow team over 378 transcripts (5 main, 373 agent), 80,310 timed lines in the window, 29,483 tool calls, 0 unreadable; exit 0, 10.1 s. The owner filed the output as `calibration-histogram-r1-2026-10-16.txt` beside D (D:226).
- It shows both known hangs: the agent command series has max 518.8 min, and 2 gaps at or above 15 min are the 518.8 and 185.8 min hangs (D §14). Main-session command gaps: n 474, 1 at or above 10 min (the 350.2 min host hang).
- The audit half is near empty: 29 audit rows, because Flow's hooks were not wired in release 1 (R §7).

## Decisions and asks carried

| Item | Where it lands |
|---|---|
| Addition 1 (run it ourselves; say whether the two hangs show) | Done, above: both show |
| Second message: calibration tool, moves to `maintainer/` under a new name | `maintainer-tree-split` commit 1 (T170): `maintainer/calibration/calib_histogram.py` |
| Second message: `reader.py` at 767 lines against D's 60 is a size finding, resolved because this is not the core reader | Recorded in the release note by `provider-coverage-proof` |
| Second message: constants `SILENCE_MIN` 30 (seed, alerts), `SILENCE_FLOOR_MIN` 15 (recorded floor), `CALLS_NO_COMMIT_MAX` 200, `CALLS_BEFORE_WORK_MAX` 135, each with its provenance from this run | `heartbeat-reader` (silence) and `overbuilding-flags` (check 3) |
| Second message: register the tests with the hosted runner in wave 1 | Inside `maintainer-tree-split` commit 1 (T170, WP1a-1), one commit for both tools: tag `calib-histogram` |
| R WP 7a: the emulated reader-visible gap series and command repeats, cut from this build | Added to the maintainer copy by `heartbeat-reader` (wave 2): they read transcripts, so they are calibration, not core |

## Remaining wave-1 work

- Move, rename and registration (tag `calib-histogram`): one commit, `maintainer-tree-split` commit 1 (T170, WP1a-1). Nothing is owned here.

## Acceptance

1. Met: numbers only, guarded at runtime; planted secrets never reach any stream (fixture).
2. Met: the output shows the 518.8 and 185.8 min hangs (R §7 asked for this or an explanation).
3. Open (wave 1): no file named `reader.py` remains under `hooks/local/lib/` that is the calibration tool; the core name is free for `heartbeat-reader`.
4. Open (wave 1): `FF_ONLY=calib-histogram` runs the fixtures on both hosted platforms.

## Estimate and depends

Built: counted with `checks-retro-mode` (5 to 7 agent-h for both, R §2). Remaining work is owned elsewhere (above). Blocks nothing in the core; the emulated series it lacks gates any change to `SILENCE_MIN` (`heartbeat-reader`).

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13-14; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
