# heartbeat-reader

**Status:** open — 6.0.0 rebuild, **wave 2** (with `task-slicer`, one writer). Supersedes `outside-liveness-watcher`. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 7a (R §2). **Surface:** `hooks/local/lib/reader.py` (new core file, row 31; the calibration tool now at that path leaves first, `maintainer-tree-split` commit 1), `hooks/local/lib/bounded-run.sh` (heartbeat line 2), `state/status.line`, `state/reader/last.json`, `maintainer/calibration/calib_histogram.py` (the emulated series). **FR-07:** no (`hooks/local/**` is outside `policies/protected-paths.yml:84-101` until the release-close commit).

## Delivers

- **`reader.py --once`**: stateless, counters in `state/reader/last.json`, registered by install as a scheduled task (`flow-install-declared-providers` prints the line). **`--watch`** is the terminal form (H non-negotiable 5). Plan proposal: `--watch` exits on its first alert or at its deadline, so a watcher under `bounded_run` is the primary wake on Claude Code (R §5b row 15).
- **Signals** (D §6): `state/audit/liveness/*.hb` (ask 1), `.git/index` mtime, the last commit time, mtimes under `state/`, and, when a provider's hooks are wired, the audit line's command hash as a fourth signal. The provider-neutral signals alone must raise the silence alert (H §4a).
- **Heartbeat line 2** (ask 1): `bounded-run` writes `pid=<wrapper pid> cmd_sha256=<hash of the wrapped argv>` after the header line (`hooks/local/lib/bounded-run.sh:115`). The path (`:28-32`, `:112`), line 1 and the last line stay as they are; the 5.11 fixtures read only those (R §5b row 1), so they pass unchanged. The child is not backgrounded to get its own pid.
- **Alerts**: silence past `SILENCE_MIN`, and the same command hash three times in flight.
- **`state/status.line`**: running or idle, last activity, hooks per provider (`hooks: claude wired, codex unenforced`; `claude wired, no Python: disabled` when the run-handler marker exists), `git hooks: flow|other|none` (the effective-hook check whose workflow file goes, R §6), open alerts, reader last seen. It never writes `ledger.md`; the ledger's first line points at the status file.
- **`hooks_state()`**: one function that says wired, partial or unenforced per provider, keyed on the exact commands of the two kept handlers (R §3, answers table). The maintainer health engines call it instead of grepping for `stop.py` (the switch-over is `stop-gate-retirement`'s wave-3 tail).
- **Calibration, in the maintainer tool** (owner, second message: calibration is not core): the emulated reader-visible gap series and the command-repeat counts cut from T165 are added to `maintainer/calibration/calib_histogram.py` and run over release 1. Any change to `SILENCE_MIN` afterwards is the owner's call; until then 30 stays the only alerting silence threshold (R §7).

## Constants (owner, 2026-10-16, second message; carried verbatim)

| Constant | Value | Provenance | Status |
|---|---|---|---|
| `SILENCE_MIN` | 30 | consumer watchdog 2026-10-14; owner kept it as the alerting seed 2026-10-16 | SEED, alerts |
| `SILENCE_FLOOR_MIN` | 15 | release 1 histogram 2026-10-16: 2 of 22,143 agent command gaps >= 15 min (both hangs), main 1 of 474; owner 2026-10-16 | recorded floor; not an alert |

The repeat count (3) is an owner seed of 2026-10-15 with no measurement yet (D §14); it ships with that provenance, the same seed `overbuilding-flags` uses for check 3. Any other threshold with no provenance ships `UNCALIBRATED`, logs instead of alerting, and is listed in the release note (H non-negotiable 2).

## Decisions and asks carried

Ask 1 (path kept, line 2); ask 9 (hooks status per provider); decision 9 (Codex rows unproven); H non-negotiables 2, 5, 9 (log a hash, never command text); addition 3 and the second message (line count against D's 60, a stated ceiling, one line on the extra lines when over 120); R §4 lock on the heartbeat file (path, line 1, last line).

## Estimate

Share of R §2 WP 7 (16 to 21.5 agent-h for 7a to 7d): 5.5 to 7, including 1.5 to 2 for the emulated series in the maintainer tool and 0.5 for line 2. Ceiling, plan proposal: 300 lines (R §5a row 5 estimated 250 to 350 including the histogram mode, which is no longer here).

## Depends

`maintainer-tree-split` commit 1 (frees the name), `audit-line-command-hash` (the audit fields), `core-hook-inventory` (the run-handler no-Python marker), `four-document-model` (the ledger's first line). Blocks: `task-slicer` (status line and last-seen age), `eight-rule-kernel-and-cards` (rule 8), `flow-install-declared-providers` (scheduled-task line).

## Acceptance

1. The reader alerts on a synthetic silence past the threshold and on a command hash repeated three times, stays quiet under both, and passes with no audit line at all (H WP 7 fixtures).
2. A planted secret in a command never reaches `state/status.line`, `last.json` or any stream; only its sha256 appears.
3. `hooks_state()` reads wired only for the exact commands of the two kept handlers; no reference to `stop.py` remains.
4. The 5.11 `liveness` rows pass unchanged with line 2 present (hosted `liveness` group, 25 s on MSYS last time).
5. With no reader registered, a printed slice shows "last seen: never" (with `task-slicer`).
6. The release note gives `reader.py`'s line count against D's 60, its stated ceiling, and one line on what the extra lines do.

## Wave split

Wave 2: two commits planned — (a) heartbeat line 2 with its fixture row; (b) `reader.py` with fixtures. The calibration-tool extension is a third, separate commit in `maintainer/`. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13-14; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
