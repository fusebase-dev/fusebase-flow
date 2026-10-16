# evidence-row-validator

**Status:** open — 6.0.0 rebuild, **wave 2**. Supersedes `gate-countable-facts-tally`. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 7c (R §2). **Surface:** one function in `hooks/local/lib/gate.py` (new core file, row 32, shared with `done-check` and `slice-gate`); one warn-only stage in `hooks/git/pre-commit` after `:827`; `policies/evidence-classes.yml` (read, from HEAD). **FR-07:** the validator commit no; the pre-commit commit yes (`hooks/git/**`, `policies/protected-paths.yml:93`).

## Delivers

The validator of D §6 and H WP 7c:
- every criterion id in the phase has exactly one row, status PASS or FAIL;
- the capture path exists and postdates the deploy;
- the capture is above a size floor, with its sha256 and size in the output; two rows citing one digest are FAIL for both unless the criterion names a shared capture;
- no finding marker in the run log behind a PASS row; the marker and the row-status pattern are constants in `policies/evidence-classes.yml` (decision 11); an unrecognised run log fails every row citing it;
- run ids under `state/runs/<phase>/`: a pass after a fail with no reproduction note is FLAKY, reported as FAIL (the computed form of T142 and T147, R §6);
- a test-file capture class for unit-risk rows: the row cites a run log in which the test id appears with the runner's pass marker; the file exists at the row's SHA; no skip token was added to a cited test in the slice's diff;
- the row's minimum evidence class comes from the paths its task touched against the evidence-classes policy; the risk tag may raise it, never lower it;
- a flag when an item's `risk` or `criterion` line changes inside its own slice window.

Plus **one warn-only line in the commit hook** (decision 6; R §5a row 3): when a staged path is a phase `evidence.md`, `pre-commit` runs the validator on the staged rows and prints its findings; it never blocks. `gate` is where the validator decides. This line is one of the named exceptions to the byte-identical kernel lock (R §4).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 6 (the commit hook only warns; `gate` decides) | Warn-only stage; exit code unchanged |
| Decision 11 (`evidence-classes.yml` holds the finding marker, row-status pattern, class globs) | Read from HEAD, no `.local` twin |
| Ask 8 (the consumer's runner conventions before wave 2: deploy timestamp source, run-log path per row, pass and FINDING markers) | Answered by the owner 2026-10-16: `runner-conventions-wp7c-2026-10-16.md` beside the handoff (binding; the owner's summary is in `docs/changes/2026-10-16-v600-minimal-core.md`). Without them the validator fails every row (H WP 7c) |
| R §4 lock (kernel byte-identical except named exceptions) | Only the one warn line is added to `pre-commit` |
| Addition 3 and the second message | The function span is reported against D's 80 lines, with a stated ceiling and one line on the extra lines when over 160 |

## Estimate

Share of R §2 WP 7 (16 to 21.5 agent-h for 7a to 7d): 6 to 8, the longest wave-2 package (R §2 critical path: 11.5 h with review). Ceiling, plan proposal: 300 lines for the function span (R §5a row 5 estimated 200 to 300). Review: independent (the new correctness core).

## Depends

`four-document-model` (row grammar and parser), `seven-policies` (`evidence-classes.yml` keys), the owner's runner conventions (ask 8, answered 2026-10-16). Blocks: `slice-gate`.

## Acceptance

1. The validator rejects a blank capture, a capture dated before the deploy, two rows sharing a digest, a PASS row with a finding marker in its run log, and a test-id row whose test does not exist at the SHA or gained a skip token; it accepts a test-id row with a pass marker in its run log (H WP 7 fixtures).
2. A pass after a fail with no reproduction note reports FLAKY as FAIL; an unrecognised run log fails every row citing it.
3. The pre-commit line prints only when a phase `evidence.md` is staged and never changes the exit code; `hooks/tests/test-validator-evidence.sh` passes unchanged (hosted `validator-evidence`, `git-smoke`, `trusted-enforcer`).
4. The same fixtures pass with no provider hook present (H §4a).
5. The release note reports the function's line count against D's 80 and its ceiling.

## Wave split

Wave 2, two commits planned: (a) the validator function and its fixtures in `gate.py` (not FR-07); (b) the warn-only `pre-commit` stage (one FR-07 approval). Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
