# provider-coverage-proof

**Status:** open — 6.0.0 rebuild, **wave 5 (release close)**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** release close (R §2). **Surface:** `docs/provider-coverage.md` (new), `docs/hook-coverage.md` (replaced; today it marks every Codex handler "yes" and "implemented", `:9-14`), the 6.0.0 release note, the version sweep, the tagged gate. **FR-07:** yes for the release commit where the version sweep touches `FLOW_RULES.md` (`policies/protected-paths.yml:87`); the `hooks/local/**` protection lands in the same close and is owned by `seven-policies`.

## Delivers

- **`docs/provider-coverage.md`**, filled from one real Claude Code run on a scratch project through the core (install, slice, build, DONE check, validator, checks, reader), replacing `docs/hook-coverage.md` (H §4a). Every Codex row says "unproven" until it is run; no row relies on a provider hook for the core's behaviour.
- **Codex** (decision 9): the release note says "Codex: unproven" until the five probes pass in the phase 7 Codex slice: (1) `-o` writes inside the repository under `read-only`; (2) `rg` and `git log` run without stalling for approval; (3) a write probe fails on native Windows launched from Git Bash; (4) `exec` accepts `-c approval_policy="never"`; (5) an in-session subagent keeps running after its parent's turn ends.
- **The release note** names the consumer metric each change moves (H:90) and carries:
  - every constant with its provenance (the owner's 2026-10-16 table), and every constant still `UNCALIBRATED` (H §7);
  - the two named 5.11 gaps, labelled: `deploy-store-provisioning-ungated`, `secret-pattern-escaped-glue` (R §3);
  - the release 1 retro and histogram tables with the owner's reading (H §7; filed beside D as `calibration-release-1-flags-2026-10-16.tsv` and `calibration-histogram-r1-2026-10-16.txt`);
  - the owner's `flow migrate --dry-run` report on the Onboarding repository (H §7);
  - **the line counts** (addition 3; second message): each new core file against D's estimates (reader 60, DONE 20, validator 80, checks 150; `gate.py` reported with its DONE and validator spans), each file's stated ceiling, and one line on what the extra lines do wherever a file is more than double its estimate. A file that had to split to stay under 800 lines is a **finding**, not a pass. The two size findings already known are recorded as resolved by the move: the calibration `reader.py` (767 lines, histogram only) and `checks.py` (550 + 294 in `checks_git.py`) are maintainer calibration tools, not core files.
- **The version sweep** to 6.0.0, with every version and count string generated, none hand-edited (H §7).
- **The tagged gate** on the exact tagged SHA, both platforms, is the release evidence; no unchanged full pre-tag run is repeated (ask 7; `docs/maintainer-execution.md` § Checks and evidence).

## Decisions and asks carried

Decision 1 (6.0.0; if not ready at the phase 6 to 7 boundary, phase 7 runs on 5.11); decision 9 (five probes, "Codex: unproven"); ask 7 (no duplicate pre-tag run); ask 10 (protection at close, owned by `seven-policies`); addition 3 and the second message (line counts, ceilings, findings); R §3 (named gaps).

## Estimate

R §2: 4 to 6 agent-h (mid 5); the close is on the critical path (R §2: 7 h step).

## Depends

Every other 6.0.0 entry; the owner's dry run (`flow-migrate`); the owner's reading of the calibration tables. Blocks: the tag.

## Acceptance (at tag time, on the Flow repository; H §7 with R's corrections and the second message)

1. Always-on rules 8; skills 6 (as provider mirrors); templates 4; workflow pages 1 plus the quickstart; policies 7; canonical agents 3; hook files 34, listed; a fresh install with two declared providers and no optional pack writes 53 Flow files, plus mirrors 9 and 8 (70).
2. Builder boot under 6 KB and planner boot under 8 KB, measured by the published bootstrap read list.
3. The `FLOW_RULES.md` diff against 5.11 shows only the allowed changes (H §7).
4. Every threshold in WP 7 and WP 8 is a named constant with its provenance; any `UNCALIBRATED` one logs rather than alerts and is listed.
5. The fixtures named in WP 4, 7, 8, 10, 11 and 12 pass; the kept 5.11 fixtures pass unchanged except the three owner-approved departures (ask 11a, ask 11b, the agent rename); the 5.11 `commit-msg` rows still pass in legacy mode (`trivial-tier-and-task-ids`), and the new behaviour has its own fixtures.
6. The calibration tables and the dry-run report are attached; `docs/provider-coverage.md` is filled; no stale version or count strings; no design tool, ticket system or model is named anywhere in the core (H §7).
7. Phase 7 measurement (H §7, second list) is the owner's, under this release.

## Wave split

Wave 5, after the owner's dry run: (a) the provider-coverage run and page; (b) the release note; (c) the release commit with the version sweep (FR-07) and the `hooks/local/**` protection; (d) the tag and the tagged gate.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13-14; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
