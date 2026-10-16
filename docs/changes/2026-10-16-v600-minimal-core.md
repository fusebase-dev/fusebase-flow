# 6.0.0 — minimal-core rebuild (owner acceptance 2026-10-16)

**Outcome:** build Flow 6.0.0 as the minimal core the owner accepted on 2026-10-16 (R: all eleven decisions and all eleven asks as recommended, with their conditions): the core at the repository root in project layout, upstream-only material under `maintainer/`; 4 document templates and one parser (`flow_docs.py`) replace 25 templates; 7 policies; 34 core hook files (a fresh install writes 53 Flow files, 70 with both provider mirrors); the heartbeat reader, DONE check, evidence-row validator, slice gate, overbuilding flags, task slicer and task-id `commit-msg`; six skills plus an optional pack; planner and builder; `flow migrate` for 5.x projects. The consumer's phase 7 runs on 5.11 if 6.0.0 is not ready at the phase 6 to 7 boundary (decision 1).

**Inputs:**
- **R** (accepted reply): `c:/tmp/flow-review-2026-10-14/minimal-core/reply-to-owner-2026-10-16.md`; byte-identical copy `flow-team-reply-rebuild-2026-10-16.md` beside the handoff in `FuseBase Product and SaaS/outputs/flow-5.10-dual-review-2026-10-14/`. It answers `flow-handoff-2026-10-15-minimal-core.md` rev 2 (H) and `flow-minimal-core-2026-10-15.md` rev 3 (D, "file 1").
- **Owner decisions** (`c:/tmp/flow-review-2026-10-14/v6/`): `owner-decisions-2026-10-16.md` (a), `owner-decisions-2026-10-16b.md` (b), `owner-decisions-2026-10-16c.md` (c); a later file wins. Messages verbatim in § Owner messages.
- **Runner conventions** (ask 8; binding per c): `FuseBase Product and SaaS/outputs/flow-5.10-dual-review-2026-10-14/runner-conventions-wp7c-2026-10-16.md`.
- **Release 1 calibration runs** (addition 1): `c:/tmp/flow-retro/release-1.tsv` (`RETRO_EXIT=0`, 15 s) and `c:/tmp/flow-retro/histogram-r1.txt` (`HIST_EXIT=0`, 10 s); the owner's copies beside D: `calibration-release-1-flags-2026-10-16.tsv`, `calibration-histogram-r1-2026-10-16.txt`.
- **Wave-1 plans** (`c:/tmp/flow-review-2026-10-14/v6/`): `plan-wp1a.md` (+ `plan-wp1a-refs.tsv`, `plan-wp1a-paths.tsv`), `plan-wp2.md` (+ `wp2-grammar-spec.md`, `wp2-grammar-review-brief.md`), `plan-wp6.md` (+ `wp6-draft/`), `plan-wp11.md`, `plan-wp12.md`. Integration order `wave1-order.md`: its §5 fixes and cross-plan rules X-1 to X-3 override the plans. Backlog drafts `backlog/<slug>/README.md` and `backlog/index-rows.md` (filed by T168).

**Authorization:** one release-wide FR-07 authorization (a, ask 6; b: "Wave 1 is approved to continue under the release-wide authorization"). The integrator stages each protected commit's exact set, mints one single-use, digest-bound approval for it (`write-bootstrap-approval.sh --category …`) and consumes it after the commit. CI workflow edits (`.github/workflows/**`, `ci_cd_config`) are asked once, with the full list, before any workflow file is touched: `c:/tmp/flow-review-2026-10-14/v6/ci-ask-2026-10-16.md` (Part A: 31 wave-1 rows in 4 commits; Part B: 6 foreseen later rows); sent 2026-10-16, approved by the owner 2026-10-16 (all 31 Part A rows and the 6 Part B rows, one commit each under its own single-use approval). No duplicate pre-tag full run: the tagged gate is the release evidence (ask 7). `hooks/local/**` becomes protected only in the release-close commit (ask 10). The 24 older artifacts in `state/approvals/` stay until the owner reviews them (a).

**Review round cap:** 2 per boundary (R §2 "Review and fix rounds", accepted); exhaustion returns the open work for an owner budget or scope decision, never a silent third round (`docs/maintainer-execution.md` step 5). Wave-1 boundaries (`wave1-order.md` §2.1): WP2-b grammar review; WP 12 premise review and diff review; WP 6 rule-preservation review; WP 11 R1, R2, R3a, R3b; WP 1a review of the carve script, edit lists and diffs. Independent review on WP 1, 4, 7, 10, 11 and 12 (R §2). Slice gates in the 6.0.0 runtime: `gate_rounds: 2`; the owner closes at the limit unless the owner authorizes an unattended close beforehand (decision 3, a).

**Host:** Windows 11, CPU saturated by other sessions; a bare `bash` start takes 5 to 46 s (2026-10-16). Python fixtures run locally; bash groups run hosted through `fusebase-flow-maintainer.yml` `groups=` dispatches, each preceded by the last hosted `END tag=… elapsed=` figure (`docs/maintainer-execution.md:9`). One writer per worktree: lanes deliver stacked patches; the integrator applies them, restamps `audit/hook-layer-manifest.json` then `audit/managed-content-manifest.json` for any `hooks/` change (`wave1-order.md` C4, X-3), and commits.

## Owner messages (verbatim)

### a — first message, 2026-10-16 (accepts R)

> Agree with all eleven decisions as you recommend, including every condition and change you listed: 6.0.0, with phase 7 on 5.11 if it is not ready at the boundary; slice.py in Flow and ticket-slice.mjs retired at migration; gate_rounds with (a) to (e), and I close at the limit unless I authorize an unattended close beforehand; the run-with-timeout.sh trim to lines 32 to 69; mirrors as in 5(a) to (e); flags only, with the two holds and --rule; the 18 kept files and the confirmed drops; flow migrate as an installer mode with the refusal file, and no --seed-backlog; the codex exec -s read-only reader, the polled boundary, and "Codex: unproven" until all five probes pass; 10a, 10b, and 10c with your conditions; evidence-classes.yml with validator-free-paths.yml folded in, seven policies.
>
> The eleven asks, all as you recommend: keep state/audit/liveness/ and add line 2; core at the repository root with maintainer/; rename to planner and builder, with the agent-tools.yml key rewrite as the one named exception; exact counts, 54 plus mirrors 9 and 8, skills only as provider mirrors; drop the receipts; one authorization for the release with a single-use digest-bound approval per protected commit, and ask once for the CI workflow path edits; no duplicate pre-tag run, the tagged gate is the release evidence; the runner conventions for WP 7c will come from my side before wave 2; wire Claude Code hooks in phase 7, Codex unwired until its slice; protect hooks/local/** at the release-close commit; both fixture departures.
>
> Three additions. First, run the two tools yourself now, from your worktrees, exactly as section 7 gives them, with outputs only under c:/tmp/flow-retro; attach both outputs with your wave 1 start, and say whether the histogram shows the 518.8 and 185.8 minute hangs. Merge rebuild/retro and rebuild/hist to main after that. Second, install hooks/git/pre-push in this clone, as your fded06b8 note recommends. Third, at close, report the line count of each of the six new files against file 1's estimates (reader 60, DONE 20, validator 80, checks 150), with one line on what the extra lines do wherever a file is more than double; a file that needs splitting to stay under the ceiling is a finding, not a pass.
>
> Keep the 24 old approval files for now; I will review them separately. The scratch folders under c:/tmp can go. Start wave 1.

### b — second message, 2026-10-16 (constants; the calibration tools are not core)

> Thank you for the runs; both outputs are filed on my side. Constants with provenance from them: silence stays 30 min as the alerting seed, with 15 min recorded as the floor the transcripts support (2 of 22,143 agent command gaps at or above 15 min, both hangs; main 1 of 474); check 3 flags a no-commit span above 200 calls (p99 between commits, n 434) and orientation above 135 calls before first work (p99, n 156). Flag 2 gains two exemptions: a commit that creates the manifest or config file it adds keys to is logged, not flagged; an environment variable read only under test paths is logged, not flagged. Flag 4 keeps 20 lines: all 7 rows are real and the smallest is 27. My rulings on the dependency rows: the T1 scaffold rows are exempt; T28 zod and T54 @dnd-kit and react-router-dom I will rule on against the spec and send with the runner conventions.
>
> On the two size findings: the histogram and the --retro driver with checks_git.py are calibration tools and move to maintainer/; they are not the core's reader.py and checks.py. Build the core reader (--once, --watch, state/status.line) and the core checks (the four flags on one slice's diff) to the design's intent, with a stated line ceiling for each in the release note and one line on what the extra lines do wherever a file is more than double the estimate. Register the two tools' tests with the hosted runner in wave 1 as you planned.
>
> Send the CI workflow edit list before touching any workflow file, as you said. Wave 1 is approved to continue under the release-wide authorization.

### c — ask 8 answer and the dependency rulings, 2026-10-16 (chat summary)

> Ask 8 is answered in …runner-conventions-wp7c-2026-10-16.md, with every fact cited to the Onboarding repository, plus the two dependency rulings. In short: captures are handled the test tool's native way (Playwright's test-results/, excluded by the tool's own gitignore; the live runner's own run directory for its JSON captures and run log), and Flow defines no capture folder; each evidence row cites the capture's path, sha256 and size and the validator hashes it in place. The run log is README.md with a Time (UTC) | Row | Record table; markers are PASS, FAIL: <message>, BLOCKED-AT-<reason> and FINDING <id>: <what>; exit codes 0, 1, 3 and 124. Test-id rows cite <file>::<test name> against a TAP log, pass marker ok <n> - <name> without # SKIP or # TODO. The deploy timestamp comes from state/deploys/<env>.jsonl, one line per deploy written by the ship step; until that exists, the gate report's deploy table. T28 and T54 were requested (AC15, AC27, FB-53), so with the scaffold exempt, flag 2 found no unrequested dependency in release 1; the backlog template should keep a place for an item to name a dependency.

## Owner additions (a)

| Addition | Status |
|---|---|
| 1. Run `--retro` and `--histogram` from the worktrees, outputs only under `c:/tmp/flow-retro`; say whether the histogram shows the 518.8 and 185.8 min hangs; then merge both branches | DONE: both hangs show (2 of 22,143 agent command gaps at or above 15 min, both hangs; b); merged as T165 `37d80a25` and T166 `4daa771c` |
| 2. Install `hooks/git/pre-push` in this clone | DONE 2026-10-16: `.git/hooks/pre-push` byte-identical to `hooks/git/pre-push` |
| 3. At close, the line count of each new file against D's estimates | Open: § Release close |

## Constants (b; the provenance string ships beside each value)

| Constant | Value | Provenance | Status |
|---|---|---|---|
| `SILENCE_MIN` | 30 | consumer watchdog 2026-10-14; owner kept it as the alerting seed 2026-10-16 | SEED, alerts |
| `SILENCE_FLOOR_MIN` | 15 | release 1 histogram 2026-10-16: 2 of 22,143 agent command gaps >= 15 min (both hangs), main 1 of 474; owner 2026-10-16 | recorded floor; not an alert |
| `CALLS_NO_COMMIT_MAX` (check 3) | 200 | release 1 histogram 2026-10-16, S7 between commits, working agents, p99 199, n 434; owner 2026-10-16 | flags above 200 |
| `CALLS_BEFORE_WORK_MAX` (check 3) | 135 | release 1 histogram 2026-10-16, S7 before first work, working agents, p99 134, n 156; owner 2026-10-16 | flags above 135 |
| `DUP_OVER_LINES` (check 4) | 20 | owner seed 2026-10-15; kept 2026-10-16: all 7 release 1 rows real, smallest 27 | SEED, flags |

- Flag 2 exemptions (b), both logged, not flagged: a commit that creates the manifest or config file it adds keys or dependencies to; an environment variable read only under test paths.
- Dependency rulings: the T1 scaffold rows are exempt (b); T28 `zod`, T54 `@dnd-kit/*` and `react-router-dom` were requested (AC15, AC27, FB-53; c). With the scaffold exempt, flag 2 found no unrequested dependency in release 1, so its precision there is not measurable as a hit rate. A dependency is "named by a backlog item" when the item's acceptance criterion or inputs name the package (c).

## Work packages (R §2; slugs filed by T168)

| WP | Backlog slug | Wave | FR-07 commits | Agent-h (mid) | Status |
|---|---|---|---|--:|---|
| before the table | `checks-retro-mode` | 0; move and registration in T170 | none | done | DONE T166 `4daa771c` |
| before the table | `reader-histogram` | 0; move and registration in T170 | none | done | DONE T165 `37d80a25` |
| 1a | `maintainer-tree-split` | 1 | T170, T186-T188 (`ci_cd_config`); T189 (baseline row) | 13.5 (+1.5 T170; +3 to 4 if `upgrade.sh` decomposes) | open |
| 1b | `flow-install-declared-providers` | 4 | none expected | 9.5 | open |
| 2 | `four-document-model` | 1 grammar (T177); 2 templates and parser; 3 template removal | none | 5 | open |
| 3 | `one-lifecycle-page` | 3 | the two policies; one workflow line (CI Part B row B1) | 2.75 | open |
| 4 | `reader-agent-and-dispatch-check` | 3 | if `pre_tool_use.py` is edited | 9.5 | open |
| 5 | `eight-rule-kernel-and-cards` | 3 | `FLOW_RULES.md` | 10.5 | open |
| 6 | `six-skills-and-optional-pack` | 1 drafts (T174); 3 final | none | 13.5 | open |
| 7a | `heartbeat-reader` | 2 | none | 6.25 | open |
| 7b | `done-check` | 2 | none | 2.5 | open |
| 7c | `evidence-row-validator` | 2 | `pre-commit` warn line | 7 | open |
| 7d | `slice-gate` | 2 | `gate-contracts.yml` retirement | 3 | open |
| 8 | `overbuilding-flags` | 2 | none | 7 | open |
| 9 | `task-slicer` | 2 | none | 5 | open |
| 10 | `trivial-tier-and-task-ids` | 2 | `commit-msg` | 6 | open |
| 11 | `seven-policies` | 1; tail 3; close | additive denies (T175); `gate_rounds`; deletions; `hooks/local/**` at close | 4.75 | open |
| 11 | `audit-line-command-hash` | 1 | handlers (T176) | 5.5 | open |
| 11 | `stop-gate-retirement` | 1; tail 3 | handler and `required-artifacts.yml` removal (T183) | 8.5 | open |
| 11 | `core-hook-inventory` | 1; tail 3 | none until close | 6.75 | open |
| 12 | `flow-migrate` | 1 classifier; 4 integration | none in Flow | 16 | open |
| close | `provider-coverage-proof` | 5 | the release commit | 5 | open |
| — | Build total | | | 147.5 (R §2) +1.5 since R | |
| — | Review and fix rounds (R §2) | | | 33 to 60 (46.5) | |

| Wave (R §2) | Work |
|---|---|
| 0 | the two calibration tools (done) |
| 1 | WP 1a, WP 2 grammar review, WP 11, WP 6 drafts, WP 12 classifier |
| 2 | 7b+7d, 7c, 7a+9, 8, 10: at most four writers, one integrator committing in order |
| 3 | WP 4, WP 3, WP 5, WP 6 final, WP 11 tail |
| 4 | WP 1b, then WP 12 integration |
| 5 | the owner's dry run, the provider-coverage run, the release note, the tagged gate |

## Wave-1 commit sequence (`wave1-order.md` §2.2)

T-numbers are proposed and assigned at commit time; the After column, not the number, is the constraint. Per-commit proofs and hosted groups: `wave1-order.md` §2.2. Lanes: INT integrator (T167, T168; WP6-a and WP2-c in a short-lived worktree; mints, consumes, restamps, dispatches) · L1 WP 11 handler chain · L2 WP 11 small core edits · L3 WP 12 · L4 WP 1a; at most four implementer lanes at once.

| T | Key | Outcome | Lane | FR-07 | After | Status |
|---|---|---|---|---|---|---|
| T167 | INT-1 | This program record | INT | no | — | this commit |
| T168 | INT-2 | Backlog filing: 22 items, `docs/backlog/index.md`, the re-pointed existing items; drafts corrected first (FI-1 to FI-4; C17; owner c) | INT | no | T167 | open |
| T169 | WP11-k | Approval receipts and `po-investigate.sh` removed | L2 | no | T168; owner B1; R3a | open |
| T170 | WP1a-1 | Calibration tools move to `maintainer/calibration/calib_{histogram,retro,retro_git}.py`; opt-in tags `calib-histogram`, `calib-retro` | L4 | `ci_cd_config` (CI row 1) | T169; the owner's CI answer | open |
| T171 | WP11-e | `run-handler.sh` leaves one no-Python marker; pointer at `:23` fixed | L1 | no | T168; R3a | open |
| T172 | WP11-c | Tool-profile validator runs without maintainer files (ask 11a) | L2 | no | T169; R3a | open |
| T173 | WP11-f | `install-git-hooks.sh` writes the per-clone excludes | L2 | no | T172; R3a | open |
| T174 | WP6-a | Six skill drafts, fold map and the `skill-carry` opt-in fixture | INT | no | T167; T169; X-2; WP 6 rule-preservation review round 1 | open |
| T175 | WP11-b | A local override cannot drop or bypass a command-policy deny | L1 | `fusebase_flow_internals` | T171; R1; owner B4 | open |
| T176 | WP11-g | Audit line: Bash and PowerShell arm, `PostToolUseFailure`, ids, hashed reasons | L1 | `fusebase_flow_internals` | T175; R1 | open |
| T177 | WP2-c | Frozen grammar at `docs/backlog/four-document-model/grammar.md` | INT | no | T168; WP2-b verdict folded; owner B5 | open |
| T178 | WP11-a | FR-13 tier reads `policies/evidence-classes.yml` (ask 11b) | L2 | no | T173; WP2-b key-set sign-off; R3b | open |
| T179 | WP11-d | `agent-tools.yml` accepts the input-kind map | L2 | no | T178, T172; WP2-b sign-off; R3b | open |
| T180 | WP12-a | Migrate classifier and action table (dry run, writes nothing) | L3 | no | T168; WP 12 premise review; diff review | open |
| T181 | WP11-h | Merge, example and detection key on the two kept handlers; Flow stops writing Stop | L1 | no | T176; R2; owner B3 | open |
| T182 | WP11-i | `.codex/hooks.json.example` follows the documented schema | L1 | no | T176; R2 | open |
| T183 | WP11-j | Five handlers and `required-artifacts.yml` removed | L1 | `fusebase_flow_internals` | T171, T181, T182; R2; owner B3 | open |
| T184 | WP12-b | Decision-8 report sections (references, open tasks, highest T) | L3 | no | T180 | open |
| T185 | WP12-c | `migrate-classify` registered (deferred) with the hosted runner | L3 | no | T184; T169; X-2 | open |
| — | Quiet point | Every lane patch landed; L1 to L3 worktrees closed; no wave-2 fork until the carve is pushed | — | — | T167-T185 | — |
| T186 | WP1a-2 | Flow's docs and records move to `maintainer/` | L4 | `ci_cd_config` (CI rows 2-7) | quiet point; WP 1a review; census regenerated (F1a-4); owner B3 | open |
| T187 | WP1a-3 | The test suite moves to `maintainer/tests/` | L4 | `ci_cd_config` (CI rows 8-18) | T186; T183; T169 | open |
| T188 | WP1a-4 | Maintainer tooling, overlays and `install.sh` move to `maintainer/` | L4 | `ci_cd_config` (CI rows 19-31) | T187; T172; T180, T184 | open |
| T189 | WP1a-5 | The 5.x upgrader moves, with its baseline row | L4 | `fusebase_flow_internals` (`policies/module-size-baseline.txt`) | T188; owner B1, B2; then the carve hosted batch, fast-forward only after it | open |
| T190 | WP11-l | Core `run-with-timeout.sh` trimmed to lines 32-69 | L2 | no | T188, T189; carve batch green | open |

Approvals: 8 single-use, digest-bound: `ci_cd_config` T170, T186, T187, T188; `fusebase_flow_internals` T175, T176, T183, T189. The 24 older approval files stay untouched.

## Release close: line counts (a, addition 3; b)

- The release note states a line ceiling for each new core file and reports its count against D's estimates: reader 60, DONE 20, validator 80, checks 150 (`gate.py` reported with its DONE and validator spans). `flow_docs.py`: ceiling 550, no D estimate (`plan-wp2.md:113`).
- Wherever a file is more than double its estimate: one line on what the extra lines do.
- A file that had to split to stay under the 800-line ceiling is a finding, not a pass.
- Resolved by b: the calibration tools (`reader.py --histogram`, 767 lines; `checks.py` + `checks_git.py --retro`, 550 + 294, a split) are not core files and move to `maintainer/calibration/` (T170). The core `reader.py` (WP 7a: `--once`, `--watch`, `state/status.line`) and `checks.py` (WP 8: the four flags on one slice's diff) are new files built to D's intent.
- Counts (b): 34 core hook files (R §3 row 35 withdrawn); a fresh install writes 53 Flow files, 70 with both provider mirrors (9 Claude Code, 8 Codex).

## Owner answers (wave 1; asked in `wave1-order.md` §4, answered 2026-10-16)

| # | Question (recommendation first) | Blocks | Status |
|---|---|---|---|
| B1 | Integration branch: integrate from T169 on `release/6.0` and fast-forward `main` at the 6.0.0 tag; alternative: keep `main` and the Onboarding project pins `v5.11`. It also places WP1a-5: on `release/6.0` the refusal file lands before `main` moves; on `main` WP1a-5 moves to wave 4, into the refusal-file commit | T169 | **yes**: integrate on `release/6.0`, fast-forward `main` at the 6.0.0 tag; dispatch the verify gate on the branch at every wave boundary |
| B2 | Upgrader move: rename and re-key its baseline row (`policies/module-size-baseline.txt:4`, `821 hooks/local/upgrade.sh` → `819 maintainer/local/upgrade.sh`); alternative: decompose `upgrade.sh` first (+3 to 4 agent-h) | T189 | **yes**: pure rename, baseline row re-keyed; `upgrade-sh-at-module-ceiling` closes as superseded |
| B3 | Fixture edits outside the departure list (11a, 11b, the agent rename) that follow from accepted decisions: (a) WP 1a path-only setup edits and the named non-path lines; (b) token fixtures 11 and 12 stay at `hooks/tests/fixtures/`; (c) WP 11 assertion edits in kept maintainer suites whose engine changes by decision. Full list: `wave1-order.md` §4 B3 | T181, T183, T186-T188 | **yes** to (a), (b) and (c); the two fixtures that stay under `hooks/tests/fixtures/` are not installed into projects, and the commit says so |
| B4 | Approval rules under a local override: deny lists only (built by default), or also make `require_approval` additive (one more line in the same protected commit) | T175 | **yes**: `require_approval` additive too, in the same protected commit |
| B5 | Project document folder: keep `docs/flow/` for the four documents | T177 | **yes**: `docs/flow/` |
| B6 | Host-fixed root files (`README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `.github/`, `.claude-plugin/`, `.codex-plugin/`, `.gitignore`, `.gitattributes`, `.python-version`) stay at the root; none is installed | T186 | **confirmed** |

Later questions answered on 2026-10-16: the `gate_rounds` lower-only rule lives in `gate.py` (wave 2); the unattended dev-deploy approval is minted by the main session after the owner approves the exact command in chat (wave 3); Onboarding is a 5.6 install and migrates 5.6 → 6.0.0 in one step, with a dry run that reads 5.6 manifests (wave 4); the reviewed build-script copy is `docs/handoff/upstream/release-1-procedural-review-2026-10-14/orchestration/build-phase-n.js.txt` in the Onboarding repository, and the owner names the live location before wave 4. Still open from `wave1-order.md` §4 "Later": retiring the two liveness `ac4` rows with `templates/handoff-implement.md`, the 12 substituted tokens in the verbatim 5.11 carries, `skill-authoring` upstream, and the `test-ff-only.sh` opt-in probe re-point (wave 3). Cross-plan X-1 (`run-tests.sh` has at most 3 free lines when wave 2 starts; recommendation: one shared tag for the wave-2 Python fixtures) is settled before wave 2 forks.

## Owner message d (2026-10-16, verbatim)

> CI list: approved, all 31 Part A rows and the 6 Part B rows as written, one commit each under its own single-use approval; I checked every cited line against 4daa771c. B1: yes, integrate on release/6.0 and fast-forward main at the 6.0.0 tag; since the maintainer workflow runs only on main and the verify gate is dispatch-only, dispatch the gate on the branch at every wave boundary, not only at the tag. B2: yes, a pure rename with the baseline row re-keyed; close upgrade-sh-at-module-ceiling as superseded. B3: yes to (a), (b) and (c); the two fixtures that stay under hooks/tests/fixtures/ are not installed into projects, and the commit says so. B4: yes, additive, in the same protected commit. B5: yes, docs/flow/. B6: confirmed. Later waves, so you have it now: the gate_rounds lower-only rule in gate.py is fine; the unattended dev-deploy approval is minted by the main session after I approve in chat; Onboarding is indeed a 5.6 install (I checked VERSION and the manifest), so plan the migration 5.6 to 6.0.0 in one step and make the dry run read 5.6 manifests. The live build script is not tracked in the Onboarding repository; the reviewed copy is docs/handoff/upstream/release-1-procedural-review-2026-10-14/orchestration/build-phase-n.js.txt, and I will tell you where the live one runs from before wave 4. With T174, give me the byte size of each of the six skill drafts and the projected builder bootstrap read list total, so the 6 KB target is measured now.
