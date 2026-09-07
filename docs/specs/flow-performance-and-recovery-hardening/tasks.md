# Tasks - flow-performance-and-recovery-hardening

**T-counter going in:** T11
**Historical implementation:** T1-T10 complete provisionally; T10 gate superseded by Astra CHANGES REQUIRED
**Corrective implementation:** T31 `1cad34d`; T32 paused narrow diff; T33 scoped-validation amendment locked
**Final technical gate:** T21, report-only after T33
**Repeated adversarial review:** T22, GPT-6 Astra review-only
**Closeout:** T23, docs-only; former T11 moved without reuse
**Starting source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Linked spec:** `docs/specs/flow-performance-and-recovery-hardening/spec.md`
**Linked decisions:** A1-A7, B1-B5
**Review owner:** `docs/specs/flow-performance-and-recovery-hardening/adversarial-review.md`

## Historical implementation ledger

| T# | Scope | SHA/status |
|---|---|---|
| T1 | overlay replacement | `c158b451f52c89190b6be745b4340f4cbf3a75ea`; provisional evidence superseded by B6 |
| T2 | settings ownership/uniqueness | `5bf89f8b0cf9bc2519f3693702372f708cfbbe7e`; provisional evidence superseded by B4-B5 |
| T3 | intent restoration/recovery verdict | `0829d169d1ddb4a39472f1836260def04e5ae4b8`; provisional evidence superseded by B3-B4 |
| T4 | mirror/recovery no-op | `1b44a95dd794bc6384d85eadeb0dc95dca5e05df`; provisional evidence superseded by B3/N2 |
| T5 | one-read Stop | `598c6670195bf2d0e95ee90abcc8a1ad23f0547f`; retained, subject to T21 regression |
| T6 | diagnosis-first lightweight flow | `0db37fc1f436e6cdbf90dd8da991e1edfa459c39`; provisional evidence superseded by B7 |
| T7 | startup compaction | `7ab052af5a372017ad997b0e2749033bed4f025f`; host telemetry remains UNVERIFIED |
| T8 | validator evidence | `b581d71f6a953cae5d2bf77d90fb6384a7a2dcf6`; provisional evidence superseded by B1-B2/N1 |
| T9 | temporal evidence/benchmark | `ff941eafb1618bd061ce4ee8a6dd660304f02153`; provisional evidence superseded by B8/N2 |
| T10 | integrated gate plus fix-forward | `b42a2038d9c50308d894418318561b4ae88f3904`, `e300953de504633a03c071514b1ca17babad7830`, final source `2217a9c631300e510b18437548ed4bccb5f31036`; gate superseded |

## Corrective chain

| T# | Slice | Review | Decision | Depends on | Commit/status |
|---|---|---|---|---|---|
| T11 | complete validator-visible identity and portable fixture | B1, N1 | A6, B1 | T10 | `86b98db`; complete |
| T12 | trusted validator execution/signing boundary | B2 | A6, B1 | T11 | `6af5291`; complete |
| T13 | ownership-safe atomic mirror/command/health writes | B3 | A1-A3, B2 | T10 | `2db3f5b`; complete |
| T14 | whole-plan recovery preflight and durable progress | B4 | A2-A3, B2 | T13 | `d126865`; complete |
| T15 | authoritative recovery verification and provider/Git proof | B4 | A2-A3, B2 | T14 | `41c1fd2`; complete; T21 exposed fixture contract gap |
| T16 | exact Flow hook recognition and isolated matcher scope | B5 | A1-A4, B3 | T15 | `deb21b1`; complete |
| T17 | bounded markerless overlay migration | B6 | A1, B4 | T14 | `82db5f0`; complete |
| T18 | executed lane workflow and mutation-resistant evidence | B7 | A4, B5 | T16-T17 | `44cc556`; complete |
| T19 | outcome/task-specific temporal linkage | B8 | A7, B5 | T18 | `bd3bc76`; complete |
| T20 | repeated write-mode no-op benchmark and claim correction | N2, B7 | A6-A7, B5 | T15, T18-T19 | `adc1a3d`; complete |
| T24 | initialize recovery E2E as a real disposable Git repository | T21 fixture defect | A2-A3, B2 | T20 | `fe1629c`; complete |
| T25 | Windows/MSYS timeout reap liveness and observable bounded engine fixtures | registered wrapper stall | A2-A3, B2 | T24 | `ef320de`; complete |
| T26 | correct U14 assertions and intended Stop status text | stale fixture / encoding regression | A2-A3, B3 | T25 | `335ed08`; complete |
| T27 | recognized legacy fixture and ambiguous-input refusal | stale U7/U9 fixture | A1, B4 | T26 | one fixture-only commit |
| T28 | bounded public recovery diagnostic selectors | efficiency E2-E4 | A2-A3, B2 | T27 | one test-tooling commit |
| T29 | single-process mutation artifact manifests | measured spawn amplification | A6-A7 | T28 | one test-tooling commit |
| T30 | probe-boundary timeout evidence and mutation budget semantics | PY5 wall/mutation failures | A6, B1 | T29 | one diagnosed correction commit |
| T31 | synchronized AC5 heartbeat proof and focused selector | one-of-two heartbeat wall race | A2-A3, B2 | T30 | one test-only commit |
| T32 | compose health/liveness coverage once; single-run status capture | >19m nested duplicate | A6-A7 | T31 | one test-tooling commit |
| T33 | durable scoped-validation policy and phase visibility | B6 | B6 | T32 | one bounded implementation commit |
| T21 | final scoped technical acceptance/report | B1-B8, N1-N2 | A1-A7, B1-B6 | T33 | report-only |
| T22 | repeated GPT-6 Astra whole-implementation review | all | all | T21 | review-only |
| T23 | final docs closeout | all | all | T22 zero blockers | docs-only pending |

## T11 - Complete validator-visible identity and portable fixture

**Files:** `hooks/local/lib/validator-evidence.py`; `hooks/tests/test-validator-evidence.sh`.
**Work:** include declared ignored validator inputs/dependencies, followed symlink target identity, arbitrary validator-affecting environment supplied by the trusted runner, and every executable/interpreter/wrapper/package-runner layer. Ambiguous/unreadable identity returns reuse unavailable. Make path conversion conditional; no mandatory `cygpath`.
**Acceptance:** AC9; B1; N1.
**Tests:** existing state mutations plus ignored dependency, ignored input, symlink target without link-text change, custom environment key, interpreter/wrapper/nested toolchain change, unreadable target, Linux-native path execution when available.
**Commands:** `bash hooks/tests/test-validator-evidence.sh`; Linux/CI same command for real-symlink and no-`cygpath` coverage.
**Module size:** `validator-evidence.py` is 325 and the shell test is 256 lines. Both remain <=800; extract a named identity concern before either crosses the ceiling. No exemption.
**Worker-undisturbed:** `.claude/hooks/run-lint-on-stop.sh`, `.claude/hooks/run-typecheck-on-stop.sh`, `.claude/hooks/quality-check-apps.js`, provider assets, settings, and Git-hook destinations remain byte-identical.
**Commit:** one `T11` commit; stage exact files only.

## T12 - Make the trusted runner own execution and signing

**Files:** `hooks/local/run-validators.sh`; `hooks/local/lib/validator-evidence.py`; new `hooks/local/lib/validator-runner.py`; `hooks/git/pre-commit`; new `hooks/local/lib/precommit-validator-reuse.sh`; `hooks/tests/test-validator-evidence.sh`; `hooks/tests/test-validation-instructions.sh`.
**Work:** remove public `begin`/`finish` success minting. The trusted runner launches validators, observes each required zero exit, rechecks identity, and alone requests signing. Bind evidence to runner/tool identity. A substituted runner, direct signer call, missing validator, or unproved authority cannot mint/reuse. Hosts without independently proved authority rerun at pre-commit. Extract the pre-commit reuse seam because the hook is already 800 lines.
**Acceptance:** AC9; B2; B1 authority fallback.
**Tests:** direct begin/finish rejected; direct mint rejected; substituted runner rejected; lint/typecheck skip/failure never signs; matching trusted run reuses only when authority is proved; unavailable authority reruns; replay/edit/concurrency/live secret/protected/release checks remain fail-closed.
**Commands:** `bash hooks/tests/test-validator-evidence.sh`; `bash hooks/tests/test-validation-instructions.sh`.
**Module size:** `hooks/git/pre-commit` is 800 lines and must shrink through `precommit-validator-reuse.sh`; all new helpers stay <=800. No baseline increase/exemption.
**Worker-undisturbed:** CLI Stop validators and CLI provider assets byte-identical; protected `hooks/git/pre-commit` requires exact staged digest-bound approval.
**Commit:** one `T12` commit; stage exact files and approval artifact only as required, then consume approval.

## T13 - Preserve unowned recovery targets and atomically repair owned targets

**Files:** new `hooks/local/lib/recovery-owned-write.py`; `hooks/local/mirror-skills.sh`; `hooks/local/mirror-agents.sh`; `hooks/local/post-fusebase-update.sh`; `hooks/tests/cli-flow-recovery-direct.sh`; `hooks/tests/cli-flow-recovery-e2e.sh`.
**Work:** classify skill, agent, command, and health-skill targets before write. `current` is no-op; `missing-and-authorized` and proven `owned-repair` use atomic replacement; owned repair retains original bytes; unowned collision, directory/type mismatch, and symlink remain untouched and yield partial/exit 1. Preserve manifest consistency without claiming the collision is mirrored.
**Acceptance:** AC5, AC11, AC12; B3.
**Tests:** owned/current/unowned skill; agent; command; health target; symlink destination and symlink target; injected interruption before replace and after retained original; retry convergence; no unowned byte/mtime change.
**Commands:** `bash hooks/tests/cli-flow-recovery-direct.sh`; `bash hooks/tests/cli-flow-recovery-e2e.sh`.
**Module size:** current sources: mirror skills 268, agents 123, recovery 599 lines. Centralize ownership/atomic logic in the named helper; every gated source remains <=800.
**Worker-undisturbed:** CLI skills/app agents, `.claude/hooks/**`, MCP/config, consumer settings, and unowned collisions are zero-write boundaries.
**Commit:** one `T13` commit; stage exact files only.

## T14 - Prevalidate the complete recovery plan and retain truthful progress

**Files:** `hooks/local/post-fusebase-update.sh`; `hooks/local/lib/flow-recovery-plan.sh`; new `hooks/local/lib/recovery-preflight.py`; `hooks/local/fusebase-flow-overlays/settings-json-merge.py`; `hooks/tests/cli-flow-recovery-direct.sh`; `hooks/tests/cli-flow-recovery-e2e.sh`.
**Work:** enumerate every authorized target and source before target mutation; validate sources, ownership classifications, marker spans, settings hook/event arrays, provider states, intent schema, and Git prerequisites. Persist plan identity plus applied/verified/pending surfaces; resume/reconcile an interrupted record instead of resetting it. Keep diagnostics separate from target writes.
**Acceptance:** AC2, AC3, AC5, AC11; B4 preflight/progress.
**Tests:** malformed early/later event arrays, unavailable later source, invalid overlay, ownership conflict, missing interpreter/provider, and stale in-progress record. Invalid plan exits 2 with zero target/backup/receipt/intent/Git writes; injected interruption exits 1 with retained accurate applied/pending inventory; retry reconciles rather than erases history.
**Commands:** `bash hooks/tests/cli-flow-recovery-direct.sh`; `bash hooks/tests/cli-flow-recovery-e2e.sh`.
**Module size:** recovery is 599 and settings merge 492 lines. Put plan construction/validation in `recovery-preflight.py`; do not grow recovery past 800.
**Worker-undisturbed:** same zero-write boundaries as T13; status evidence may change only after plan validation and must not be counted as a repair target.
**Commit:** one `T14` commit; stage exact files only.

## T15 - Verify every recovered surface authoritatively

**Files:** `hooks/local/post-fusebase-update.sh`; `hooks/local/lib/flow-recovery-plan.sh`; new `hooks/local/lib/recovery-verify.py`; `hooks/local/lib/hook-wiring-intent.sh`; `hooks/local/install-git-hooks.sh`; `hooks/tests/cli-flow-recovery-direct.sh`; `hooks/tests/cli-flow-recovery-e2e.sh`; `hooks/tests/test-hook-wiring-intent.sh`.
**Work:** parse/hash the final state against the prevalidated plan before status complete. Provider overlay restoration uses verified retained original bytes or records uncertainty; no base synthesis. Git hooks require exact per-surface intent, exact Flow ownership marker/content, executable state, and installed-destination verification. Do not infer success from installer output. Status inventory records verified vs pending/uncertain surfaces.
**Acceptance:** AC3, AC4, AC11; B4 final verification/provider/Git proof.
**Tests:** missing provider with verified backup; missing provider without backup; tampered backup; stale/missing/custom/non-executable Git hooks; settings-only schema-1 intent; false installer text; post-apply tamper; verified complete exit 0; each uncertainty partial exit 1; final mismatch never complete.
**Commands:** `bash hooks/tests/cli-flow-recovery-direct.sh`; `bash hooks/tests/cli-flow-recovery-e2e.sh`; `bash hooks/tests/test-hook-wiring-intent.sh`.
**Module size:** keep final verification in `recovery-verify.py`; recovery caller and all helpers <=800. No exemption.
**Worker-undisturbed:** unproven provider/Git content remains untouched; custom Git hooks retained; CLI paths and consumer config unchanged.
**Commit:** one `T15` commit; exact staging; protected installed-hook source edits require digest-bound approval where policy matches.

## T16 - Recognize exact Flow hooks and isolate matcher scope

**Files:** `hooks/local/fusebase-flow-overlays/settings-json-merge.py`; `hooks/local/lib/hook-wiring-intent.sh`; `hooks/tests/test-wire-hooks-add-beside.sh`; `hooks/tests/test-hook-wiring-intent.sh`; `hooks/tests/cli-flow-recovery-direct.sh`.
**Work:** replace substring ownership with exact event-specific command parsing. Isolate an exact Flow command from mixed blocks before applying Flow matcher/timeout. Preserve custom block/command order, matcher, timeout, and scope. Deduplicate to one dedicated Flow block with full required matcher, independent of which duplicate appears first.
**Acceptance:** AC4; B5; B3.
**Tests:** exact current/legacy command; substring lookalike; added flags/custom path; mixed Flow/custom block; restrictive first duplicate plus full later duplicate; Stop handler outside first block; malformed structures remain preflight failures; second run byte-identical.
**Commands:** `bash hooks/tests/test-wire-hooks-add-beside.sh`; `bash hooks/tests/test-hook-wiring-intent.sh`; focused recovery direct test.
**Module size:** settings merge is 492 and intent library 266 lines; extract exact command parsing to a named helper if either approaches 800. No exemption.
**Worker-undisturbed:** CLI Stop chain order/timeouts, consumer matchers/commands, settings outside exact Flow entries, and CLI hooks unchanged.
**Commit:** one `T16` commit; stage exact files only.

## T17 - Bound or refuse markerless overlay migration

**Files:** `hooks/local/fusebase-flow-overlays/overlay-block-replace.py`; `hooks/tests/cli-flow-recovery-direct.sh`.
**Work:** replace markerless heading-to-EOF ownership with a proven legacy terminal boundary. Refuse unknown/custom suffix structure before backup or target write. Preserve marker-wrapped behavior, CRLF/Unicode, and FLOW:PRESERVE bytes.
**Acceptance:** AC1; B6; B4 zero-write invalid plan.
**Tests:** recognized bounded legacy layout; unrelated text suffix; custom heading suffix; extra same/lower-level section; duplicate/absent legacy footer; marker-wrapped prefix/suffix; refusal exit 2 with target and backup absent/unchanged; second run no-op.
**Commands:** focused overlay section in `bash hooks/tests/cli-flow-recovery-direct.sh`.
**Module size:** helper is 226 lines and test owner 432 lines; remain <=800 or extract an overlay fixture module by responsibility. No exemption.
**Worker-undisturbed:** bytes outside the proven owned span and all CLI/provider content remain identical.
**Commit:** one `T17` commit; stage exact files only.

## T18 - Execute lane fixture actions and derive evidence from results

**Files:** `hooks/tests/lane-workflow-fixture.py`; `hooks/tests/test-lane-workflow.sh`; `hooks/tests/benchmark-flow-consumers.py`; `hooks/tests/test-flow-consumer-benchmark.sh`.
**Work:** run each scenario in a disposable fixture, perform a bounded read-only diagnosis, invoke router/assessor, create the actual lane artifacts/relay, perform the allowed fixture action, and inspect filesystem/action records for counts. No hardcoded decision/relay/artifact/diagnosis success fields. Add mutation modes for extra relay, extra artifact, and skipped diagnosis; each must fail. Label any remaining scripted boundary as simulation and keep host workflow coverage UNVERIFIED.
**Acceptance:** AC8, AC10; B7; B5.
**Tests:** ordinary one-pass fixture; every sensitive trigger; unresolved assessment; three mutation controls; observed artifact/relay/action counts; benchmark consumes the observed record.
**Commands:** `bash hooks/tests/test-lane-workflow.sh`; `bash hooks/tests/test-flow-consumer-benchmark.sh`.
**Module size:** lane fixture 145 and benchmark 263 lines. Extract fixture artifact/action execution into a named module before any file exceeds 800. No exemption.
**Worker-undisturbed:** disposable fixture only; no shared spec/handoff, approval, provider, config, or production files written.
**Commit:** one `T18` commit; do not stage generated smoke logs/JSON.

## T19 - Link conclusions by outcome, task, and commit

**Files:** `hooks/local/find_wasted_effort/windowing.py`; `hooks/local/find_wasted_effort/evidence.py`; `hooks/local/find_wasted_effort/selftest_windowing.py`; `hooks/local/find-wasted-effort.py`; `hooks/tests/test-wasted-effort-windowing.sh`.
**Work:** parse structured conclusion records and link each conclusion to its task/commit. File last-commit and generic SHA mentions are context only. Partition mixed reports per conclusion; keep unlinked/historical outcomes visible without affecting the selected-window verdict.
**Acceptance:** AC10; B8; B5.
**Tests:** old outcome plus current cosmetic footer; old outcome plus unrelated selected SHA mention; mixed current/historical outcomes in one report; task mismatch; exact outcome/task/commit match; approvals remain action/outcome scoped; report labels both scopes.
**Commands:** `bash hooks/tests/test-wasted-effort-windowing.sh`; focused `python hooks/local/find-wasted-effort.py --selftest` if registered separately.
**Module size:** windowing 73, evidence 749, main 504 lines at plan check. Extract a named conclusion-link parser before changing `evidence.py`; keep each <=800. No exemption.
**Worker-undisturbed:** read-only repository analysis; generated audit report remains evidence-only unless a later task explicitly stages it.
**Commit:** one `T19` commit; stage exact files only.

## T20 - Prove no-op writes with repeated write-mode recovery

**Files:** `hooks/tests/benchmark-flow-consumers.py`; `hooks/tests/test-flow-consumer-benchmark.sh`; `hooks/tests/cli-flow-recovery-fixture.sh`; `hooks/tests/cli-flow-recovery-e2e.sh`.
**Work:** label `mirror-skills.sh --check` as read-only integrity. In one isolated initialized fixture, run full write-mode recovery to convergence, then perform three independent bounded write-mode recovery attempts. Snapshot repair-target bytes/mtimes before and after every attempt and consume structured write/copy counts. Derive performance/no-op claims only from those observations. Do not promote update-only CLI evidence to install/update/recover coverage.
**Acceptance:** AC5, AC10, AC11; N2; B7 smoke repetition correction.
**Tests:** three distinct process executions with attempt IDs/timestamps; zero target writes/copies/hash/mtime changes each; injected write detected; diagnostics excluded by named inventory; `--check` result labeled read-only; current CLI comparison stays UNVERIFIED unless full chain runs.
**Commands:** `bash hooks/tests/test-flow-consumer-benchmark.sh`; `bash hooks/tests/cli-flow-recovery-e2e.sh`.
**Module size:** benchmark 263 and fixture/e2e 15/194 lines; keep repeated-run recorder in a named function/module, all <=800. No exemption.
**Worker-undisturbed:** fixture directory only; shared workspace hash/status unchanged; no real workspace `fusebase update`; generated smoke evidence is not committed in T20.
**Commit:** one `T20` commit; stage exact source/test files only.

## T24 - Initialize the recovery E2E fixture as a real Git repository

**Files:** `hooks/tests/cli-flow-recovery-e2e.sh` only.
**Work:** in `ffcf_e2e_build`, initialize the disposable `$PROJECT` with `git init` and fixture-local `user.name`/`user.email` before recovery. Let Git create `.git/hooks`; remove the directory-only Git imitation. Normalize the fixture root only where required so the intent writer, recovery planner, and final verifier compare the same repository identity across MSYS/native paths. Do not weaken T15 Git verification or production recovery behavior.
**Acceptance:** the T15 focused path runs in a real disposable repository; `post-fusebase-update.sh --wire-hooks` no longer returns partial from Git rc128 or project-identity mismatch; exact Flow pre-commit/commit-msg destinations and same-project hook intent verify; CLI/user sentinel bytes remain identical. Focused rc0 is recorded; full registered wrapper completion is the distinct T25 blocker, not a T24 commit prerequisite.
**Tests:** `FFCF_T15_ONLY=1 bash hooks/tests/test-cli-flow-recovery.sh`; assert fixture `git rev-parse --show-toplevel` succeeds, local identity is configured, Git hooks verify exact owned content/executable state, intent root matches normalized Git root, and CLI/user before/after hashes match. Preserve the full-wrapper stalled attempt as T25 evidence.
**Module size:** `hooks/tests/cli-flow-recovery-e2e.sh` is 334 lines before T24 and must remain <=800; no extraction/exemption needed.
**Worker-undisturbed:** only a disposable fixture changes. Shared `.git`, installed hooks, CLI/provider assets, consumer config, `docs/wasted-code/`, and smoke evidence remain untouched.
**Commit:** exactly one `T24` commit; stage only `hooks/tests/cli-flow-recovery-e2e.sh`; normal pre-commit; no `--no-verify`.

## T25 - Bound Windows/MSYS reap liveness and expose recovery engine phases

**Files:** `hooks/local/lib/run-with-timeout.sh`; `hooks/tests/test-health-check-timeout.sh`; `hooks/tests/cli-flow-recovery-engine.sh`. `hooks/local/lib/job-fence.sh` only if reproduction proves that seam contributes to the stall.
**Work:** reproduce the Windows/MSYS `run_with_timeout` / `ffhc_msys_wait_reap` stall with bounded process/phase evidence before choosing a fix. Repair completion/reaping at its proven owner; extend the existing timeout selftest. Emit engine scenario/start/completion/timeout identity incrementally outside captured verdict output; bound each engine call below the outer suite watchdog, including cleanup margin. Do not merely increase the 600s fixture budgets or 1200s outer timeout.
**Acceptance:** repeated bounded Windows/MSYS cases complete or time out with correct exit status and no lingering owned children; normal child failure, timeout, and termination stay fail-closed. Timeout selftest 23/23 and bounded U16/U17/U18 rc0 permit the T25 commit: the wrapper advanced to 33 PASS then exposed the independent U14 stale assertion owned by T26. U17/U18 still execute the real engine and assert HEALTHY; no skipped check, fabricated verdict, swallowed timeout, or weaker verification. T21 verifies relevant wrapper coverage through the B6 dependency ledger.
**Tests:** `bash hooks/tests/test-health-check-timeout.sh`; bounded reproducer covering normal/nonzero exit, timeout and reap/descendant cleanup; repeated U17/U18 execution with visible phase identity; `FFCF_T15_ONLY=1 bash hooks/tests/test-cli-flow-recovery.sh`; full `bash hooks/tests/test-cli-flow-recovery.sh` under an outer watchdog with incremental saved evidence. Preserve the 23-row stalled run and targeted <=180s rc0 HEALTHY observations; isolated success does not close nondeterministic liveness.
**Module size:** inspect current counts before edits; each gated source stays <=800 and no already-over-ceiling file grows. Extract only a named timeout/reap responsibility if needed; no exemption or baseline increase.
**Worker-undisturbed:** owned disposable processes/fixtures only; no shared Git/config/provider changes, broad process killing, smoke removal, or `docs/wasted-code/` mutation. T24 source diff belongs solely to T24.
**Commit:** one `T25` commit after focused timeout/engine proof; exact file staging, normal pre-commit, policy-required protected approval only where applicable. Retain both the historical stall and subsequent U14 failure; neither is a full-wrapper PASS.

## T26 - Correct U14 assertions for isolated Stop blocks

**Files:** `hooks/tests/cli-flow-recovery-direct.sh` (675 lines before T26) and `hooks/local/fusebase-flow-overlays/settings-json-merge.py` only; each remains <=800, no exemption.
**Work:** replace U14's `hooks.Stop[0]` assumption with parsed traversal of every Stop block. Match exact Flow command/status identity; require exactly one `stop.py` entry with runtime status `Fusebase Flow stop hook…` across all blocks. Correct only the mojibake status literal at `settings-json-merge.py:59`, preferably using Python `\u2026` for encoding-stable source. T16 `deb21b1` introduced the bytes `c3 a2 e2 82 ac c2 a6`; `CHANGELOG.md:2677` records intended text. Assert both unique CLI entries, order, timeout and original block/matcher semantics survive; Flow occupies its intended block without widening a consumer matcher or corrupting a shared block. Extend U14 mixed/restrictive coverage if needed; production merge behavior and T16 ownership remain unchanged.
**Acceptance/tests:** focused U14 1/1 and wire/settings 36/36 PASS permit commit; full wrapper crossed U14/U15 and reached 35 PASS before independent stale U7 failed. Assert duplicate/missing Flow or CLI entries and matcher widening fail. Preserve failed attempts; T16 correctly keeps CLI Stop[0] and adds Flow Stop[1]. T21 owns relevant wrapper acceptance under B6.
**Worker-undisturbed:** only disposable fixture settings; CLI/provider/config/source and unrelated untracked evidence unchanged.
**Commit:** one `T26` two-file commit after the focused proof above; exact stage, normal pre-commit.

## T27 - Correct legacy migration fixtures

**Files:** `hooks/tests/cli-flow-recovery-direct.sh` only; remain <=800 lines.
**Work/AC:** replace U7's arbitrary `old stale body` positive fixture with a recognized legacy footer/span accepted by T17. Prove positive bounded migration, prefix/suffix and operator-value preservation, and second-run no-op. Keep the arbitrary/ambiguous body as an explicit negative case: refusal and unchanged bytes. Inspect sibling U9 once and preserve its marker/idempotence coverage. Never weaken T17 or edit production recovery.
**Tests:** focused legacy functions through bounded diagnostic setup before T28 exists; record actual invoked functions and assertions, never count execution of a sourced-only module as proof. Final default wrapper is covered once at T21.
**Commit/boundaries:** one exact-file T27 commit; normal pre-commit; disposable fixtures only; CLI/provider/config and untracked evidence unchanged.

## T28 - Add bounded recovery diagnostic selectors

**Files:** `hooks/tests/test-cli-flow-recovery.sh`; new `hooks/tests/test-cli-flow-recovery-selectors.sh`; `hooks/tests/run-tests.sh` only for registering that selftest. Existing sourced modules remain unchanged. Each source stays <=800 or obeys its existing ratchet; no exemption/growth of an over-ceiling file.
**Work:** expose `--list` and `--only <group>` for `u14`, `legacy`, `engine` (U16-U18), and current task selectors T1/T14/T15/T20. Preserve legacy environment selectors compatibly. Validate unknown/missing/empty/conflicting selection before fixture creation. Keep no-argument full dispatch/count unchanged; U20 snapshot dependencies remain intact.
**AC:** selected output explicitly SCOPED and cannot satisfy full PASS parsers; unknown/missing selection exits 2 with no fixture mutation. Selected execution omits unrelated groups and runs real setup/assertions. Group START/END include elapsed seconds and exit code on stderr; failures/timeouts retain a durable diagnostic path. Preserve tempfile capture, failure status, owned cleanup and timeout semantics; no environment/secret dump or pipe capture.
**Tests:** tiny registered selftest covers list/invalid/missing/empty/conflict parsing, selected-vs-unselected dispatch, default group list parity, nonzero/timeout propagation and non-attesting scoped output. Run actual U14, legacy and engine group diagnostics; default case/count dispatch is covered synthetically; complete execution belongs to release CI. Parser probes must not recreate full recovery trees repeatedly.
**Commit/boundaries:** one T28 commit, exact three-file scope; normal pre-commit; no production recovery, CLI assets, cache/receipt authority, CI rewrite or new governance mechanism.

## T29 - Batch mutation artifact manifests

**Files:** `hooks/tests/test-pre-commit-python3-version-mutation.sh` (212 lines); new `hooks/tests/lib/artifact-manifest.py`; new `hooks/tests/test-artifact-manifest.py`. The mutation harness invokes the small parity selftest so existing registered mutation coverage includes it; no runner-registry rewrite. Each remains <=800.
**Work:** replace per-file wc/tr/sha256sum/cut subprocesses with one captured real interpreter (`REALPY`, never the scenario shim) using stdlib traversal/stat/hashlib. Keep every independent snapshot, regular-file scope, relative `./` paths, `.git` pruning, mutation-input hook exclusion, size/hash and deterministic C-compatible ordering. Fail on unreadable/unstable enumeration rather than emitting partial success; preserve supported symlink semantics. No baseline-hash caching or fixture reduction.
**AC/tests:** byte-parity on a tiny old/new fixture with empty/binary/CRLF/space/Unicode/nested files; exclusion tests; same-size mutation and added/deleted artifact detection; one interpreter process and zero per-file subprocesses. Preserve baseline block, mutant declared delta, unmutated-negative rejection, index/HEAD/temp/tracked-hook evidence. T29 may commit parity/manifest proof with the known distinct budget failure explicitly retained for T30; never claim full mutation PASS from 10/11.
**Measurement:** prior manifests 384-440s each over approximately 195 files/2.11MB, whole mutation 1577s. Record final corpus count/hash and each manifest elapsed; do not rerun the slow old corpus loop just for timing. Keep tiny old/new parity evidence. Expected >95% manifest-time reduction is a hypothesis until measured, not a test threshold.
**Focused commands:** `python hooks/tests/test-artifact-manifest.py`; bounded `FF_ONLY=python3-version-mutation bash hooks/tests/run-tests.sh` after manifest parity, once if needed for independent snapshot measurement. T30 owns final mutation semantic closure; T21 consumes scoped mutation evidence under B6.
**Boundaries/commit:** one exact three-file T29 commit; normal pre-commit; test-only, no CLI/provider/runtime/config mutation; preserve untracked evidence.

## T30 - Measure the actual probe deadline and preserve mutation discrimination

**Files:** `hooks/tests/test-pre-commit-python3-version-contract.sh` (213 lines); `hooks/tests/test-pre-commit-python3-version-mutation.sh` after T29. `hooks/git/pre-commit` (773 lines) only if bounded reproduction proves its probe deadline/reap implementation is defective; protected-path approval and exact staging apply. No other runtime file or blanket watchdog change.
**Diagnosis first:** separate hook startup/staged enumeration, each actual `_ffpc_bounded` probe, and cleanup/follow-on controls with monotonic timing and owned-process evidence. Reproduce on this MSYS host without competing full suites. Existing failure: contract 20/21 in 516s, two timeout-attribution checks passed but whole-hook 39s violated 16-26s; mutation 10/11 in 1577s because baseline `budget_ok=yes` versus mutant `no`. The mutant deliberately continues into extra controls, so whole-hook duration is not inherently an invariant of that mutation.
**Work/AC:** preserve the <=10-second deadline for each actual probe, both timeout attributions, nonzero failure, no later controls after real refusal, and cleanup/reap of owned children. Assert deadline scheduling/termination at the actual probe boundary; report host scheduling/reap delay separately rather than pretending whole-hook wall time equals probe time. If real code exceeds its promised deadline, correct that owner; do not solve by raising 26s or labeling any delay benign. Mutation `budget_ok` must derive from the same valid bounded-probe property on baseline/mutant/negative; record differing total hook time as diagnostic, not an undeclared security delta. Never simply delete the bound or make budget success unconditional.
**Tests:** focused PY5 (a minimal optional case selector within contract script is permitted; unknown/empty selection exits 2 and scoped output is non-attesting); deterministic over-budget/missing-timeout/broken-cleanup negative controls must fail. Then `FF_ONLY=python3-version,python3-version-mutation bash hooks/tests/run-tests.sh` once with durable logs: complete contract and all mutation rows green, only declared mutant changes accepted, unmutated negative rejected, production-hook hash preserved. Record per-probe deadline/termination/cleanup and total hook/manifest timing on this host; Linux comparison when available, otherwise explicit residual.
**Boundaries/commit:** one T30 commit after focused closure; <=800 per source, no exemption. No CLI-owned assets, shared configuration, wider mutation normalizations, cache authority or unrelated timeout changes. If no trustworthy probe-boundary observable can be established, retain the blocker; do not convert the flaky wall proxy into fabricated proof.

## T31 - Synchronize actual-child heartbeat evidence

**Files:** `hooks/tests/test-health-check-timeout.sh` (759 lines before edit); new `hooks/tests/health-check-heartbeat.sh` containing extracted AC5 responsibility; optional new `hooks/tests/lib/heartbeat-probe.py` for one persistent stdlib controller. Exact test-only scope; each <=800; extraction shrinks the existing script. No production timeout/heartbeat changes or runner rewrite.
**Diagnosis:** at `314ead3`, health-check-timeout 22/23 in 1319s; one heartbeat observed against >=2 over a fixed ~4s child. Every T25 timeout/reap case passed. Spec owner `docs/specs/upgrade-source-integrity-and-observability/spec.md` AC5 requires parent stderr before actual child exit and byte-exact capture. Current loop assumes independent sleeps stretch proportionally and mistakes wrapper-done for child-alive. Neither assumption is reliable under MSYS scheduling; no production defect is proved.
**Work/AC:** replace fixed-duration/count-ratio race with actual child started/release/exited synchronization. Under an independent real watchdog, hold child alive until controller observes two genuine parent heartbeats, then release it. Count only emissions observed after child-started and before child-exited/release; no fabricated progress. Keep two emissions as deterministic recurring-behavior proof, not a timing-ratio assertion. Off case releases independently and emits zero progress. Preserve parent nonblocking return, rc, merged child stderr, byte-exact capture, no leaked progress in payload, and owned child/heartbeat cleanup. Missing heartbeat must fail within the watchdog; never merely extend sleep/cap or change threshold to hide the race.
**Negative controls:** disabled/one-shot/late-only heartbeat fails live recurring proof; capture contamination fails parity; missing cleanup fails owned-process check. Keep controls bounded and local to test copies/stubs; do not mutate production. Use monotonic deadlines and actual child markers rather than loop-counter seconds or wrapper completion as liveness evidence.
**Focused entry:** validate `--only ac5`/`--list` before golden-fixture creation; unknown/missing/empty selector exits 2 with no fixture mutation. Selected output explicitly SCOPED/non-attesting; run both AC5 behavior and carrier assertions. No-argument default still executes all existing 23 predicates; helper includes new controls within AC5 proof. One persistent controller avoids per-poll grep/wc/tr subprocesses.
**Tests/measurement:** `bash hooks/tests/test-health-check-timeout.sh --only ac5` with three independent bounded executions and negative controls; record actual-child start, heartbeat observations, release/exit, wrapper rc, cleanup and elapsed. Record focused duration against historical whole-phase 1319s without claiming all 1319s was AC5 or a guaranteed full-suite speedup. T21 consumes unaffected recorded phase evidence under B6; do not repeat the 1319s prefix. No covered scenario deletion or lowered liveness requirement.
**Commit/boundaries:** one T31 commit, exact two/three test paths; normal pre-commit, no exception. CLI/provider/config and preserved untracked directories unchanged. Broader full-engine optimization needs per-case profiling and is outside T31.

## T32 - Remove nested equivalent-state test execution

**Files:** `hooks/tests/test-liveness-bounded-run.sh`; `hooks/tests/run-tests.sh`; `hooks/tests/test-ff-only.sh` for small synthetic composition tests. No runtime/CLI changes. Respect <=800 or existing no-growth ratchet; no exemption or general runner rewrite.
**Diagnosis:** liveness AC3e/AC6 runs the complete health timeout suite again although composed runner already ran it; >19m repeated work observed. Liveness spec AC3e/AC6 requires green health regression evidence, not duplicate execution. Its `run_bounded` also executes identical commands twice to combine first stderr with second rc, wasting work and weakening attribution. Audit: `state/audit/execution-efficiency-review-2026-09-06.md`, nested-suite follow-up.
**Work/AC:** standalone no-argument liveness retains full nested health coverage. Add explicit `--core-only` diagnostic mode that omits only nested dependency invocation, labels summary partial/non-attesting, retains direct API and every other liveness predicate. Unknown arguments exit 2 before work. Composed runner uses that mode only when its earlier health phase actually executed and its result is accounted in the same invocation; no environment/cached-evidence success assertion. Failed/missing/timed-out health remains full-gate failure; no fabricated dependency PASS. `FF_ONLY=liveness` without health still runs dependency. Explain aggregate row-count reduction rather than silently retaining duplicate PASS. Capture stderr and rc from one bounded_run invocation; preserve 124/137/125, timeout messages, progress and non-execution sentinel.
**Tests:** extend existing ff-only synthetic fixtures to count health launches: full/both-selected exactly one; liveness-only/standalone retains health invocation; failed/missing dependency cannot produce full PASS; core-only summary rejected as standalone complete proof; unknown mode refused. Tiny execution counter plus distinct output/rc proves run_bounded executes once and couples evidence. Run real core-only genuine timeout/SIGTERM/degrade cases once; T21 consumes existing health evidence only after dependency validation; no extra full health run for this composition change. No extra full health run for development diagnostics.
**Measurement/boundaries:** record composed dependency count and focused liveness elapsed against observed >19m nested cost; preserve all semantic cases. Static sibling scan found necessary changed-input interpreter mutation, synthetic ff-only and selector probes; no other identical full heavy nested suite confirmed. Do not remove these distinct controls. One exact three-file T32 commit, normal pre-commit; CLI/provider/config and untracked evidence untouched.

## Efficiency rationale

**Evidence:** `state/audit/execution-efficiency-review-2026-09-06.md` (GPT-6 Astra Medium). T25 full wrapper took ~11m before U14 versus ~8s isolated; timeout-suite log activity totaled ~33m; four amendments repeated state across five docs. These are observed log intervals, not billed token/CPU measurements.
**Action:** tasks own scope/dependencies; gate owns proof mapping; handoff carries current state/pointers. Defer roadmap/report status churn to closeout. Diagnose the failed case before rerunning its group; structural retry requires a changed control. Preserve same-agent provider-limit retries under operator authorization. Expected isolated-case savings ~10m per similar late failure; aggregate savings unmeasured.

## T33 - Durable risk-scoped validation and phase visibility

**Dependency/scope:** after T32; one bounded task/commit. Implements locked B6 in developer-facing guidance and existing runner, not app/client UI. No new cache, signer, scheduling framework, runtime recovery or CLI edits.
**Likely exact files:** canonical `flow-skills/validation-and-qa/SKILL.md`; its `.agents/skills/validation-and-qa/SKILL.md` and `.claude/skills/validation-and-qa/SKILL.md` mirrors; `templates/verification-gate.md`; `templates/handoff-implement.md`; `workflows/verification-gate.md`; `hooks/tests/run-tests.sh`; `hooks/tests/test-ff-only.sh`; `hooks/tests/test-validation-instructions.sh`. If the runner's ratchet requires a seam, one `hooks/tests/lib/phase-reporting.sh` helper only. Regenerate existing `audit/managed-content-manifest.json` only if the normal integrity workflow requires it; no CLI/vendor manifest edits. Inspect exact file presence/callers before editing; avoid unrelated carrier rewrites.
**Policy AC:** scoped local acceptance is valid only with changed-risk/AC-to-test ledger (gate contract); strict full summary and separate subset files remain unchanged. Affected source/config/input/toolchain/platform changes invalidate matching evidence; unknown dependency completeness reruns affected group. Normal staged secret/protected checks and lint remain live. Broad matrix/compatibility execution belongs to maintainer/release CI; do not claim ordinary PR/nightly automation exists. Targeted counterexample re-review replaces entire repeated review loops. No equivalent-input nested full suites.
**Tooling AC:** existing runner emits each selected phase START/END, tag, elapsed, rc and configured timeout budget; errors retain diagnostics, absent/zero-row/crashed selections cannot claim success. Record skipped vs executed distinctly; no secrets/environment dumps. Bound semantics/defaults unchanged. Local plan states expected total and reevaluates unexplained overruns; heartbeat alone is not progress. Keep T32 dependency accounting and partial summary integrity.
**CI check:** inspected `.github/workflows/fusebase-flow-verify.yml` full unscoped command and Linux/Windows matrix; runner GITHUB_ACTIONS path forces full; release `needs: verify` blocks publication. The existing 60-minute CI wall remains unchanged; current-suite completion within it is UNVERIFIED, not inferred from configured coverage. A future timeout requires measured diagnosis, not automatic bound inflation. No workflow edit needed. No automatic PR or nightly jobs exist; full execution is deferred unless explicitly run. Do not launch a remote release/long CI run merely to implement this task.
**Focused validation:** cheap synthetic full/scoped/default/CI dispatch tests (existing ff-only fixtures) prove summary separation, single dependency ownership, START/END/rc/elapsed/budget on success/failure/timeout and missing/zero-row rejection. Carrier/template checks accept ledger-backed scoped local proof and reject subset-as-full/release claims; negative mutation removes required risk/dependency mapping and must fail. Run one tiny real selected phase plus mirror/preflight and normal exact-staged gates. No full local suite or broad mutation matrix. Do not add a new production ledger parser solely to test prose.
**Rollback/residuals:** exact task revert restores prior local policy/tooling; full-release classifiers and safety gates never weaken. Full Linux/Windows result, CLI chain, host telemetry, symlinks and signer isolation remain deferred/unverified without actual evidence. Budget improvements are measured, not promised. Normal one-task commit; preserve dirty handoff/archive, smoke and docs/wasted-code.

## T21 - Final technical gate report

**Files:** `docs/specs/flow-performance-and-recovery-hardening/gate-report.md`; uncommitted smoke JSON/log evidence under the existing smoke directory; durable `state/audit/` outputs only where existing commands own them.
**Work/tests:** no source change or commit. After T33, populate the B6 ledger in `verification-gate.md`; run only uncovered or invalidated AC/risk groups and current preflight/mirror/manifest/module/security/CLI checks. Reuse prior evidence only with explicit unchanged dependency/platform proof; uncertain rows rerun their group. Never restart the stopped 108-minute prefix. Keep 414 PASS/0 FAIL and earlier failed attempts as partial historical evidence, never full/final PASS. Registered selectors may satisfy matching local acceptance rows; sourced-only modules are not entry points. S1/S3 distinct scenarios once, S2 three independent write-mode calls. Replace gate report with scoped acceptance and DEFERRED CI/residual coverage.
**Acceptance:** every B1-B8/N1-N2 has direct closure evidence or remains open; exact T11-T20/T24-T33 SHAs/timing and failed-then-passed evidence recorded; real Git verification and affected wrapper/liveness contracts proved; spec remains DRAFT; stop at gate.
**Module size:** N/A; report/evidence only.
**Worker-undisturbed:** verify all task boundaries and shared workspace hash/status; do not stage `docs/wasted-code/` or existing smoke `.log` files.

## T22 - Repeat the GPT-6 Astra whole-implementation review

**Files:** read-only implementation/evidence review; review result prepared for `adversarial-review.md` but committed only in T23.
**Work/tests:** no implementation commit. GPT-6 Astra reviews `2217a9c..T33_HEAD`, T21 coverage/evidence, smoke, ownership/authority boundaries, and B1-B8/N1-N2 closure. Replay targeted mutations/false-claim cases, manifest parity and probe-budget negative controls; consume T21 scoped AC/dependency ledger rather than rerunning the whole suite. Any new source correction invalidates affected dependency rows only; rerun those rows and targeted review, never the complete prefix.
**Acceptance:** zero blockers. Any blocker returns to newly numbered implementation tasks and invalidates T23; do not claim closeout early.
**Module size:** N/A; read-only review.
**Worker-undisturbed:** no source/provider/config mutation during review.

## T23 - Final docs-only closeout

**Files:** `docs/specs/flow-performance-and-recovery-hardening/spec.md`; `roadmap.md`; `tasks.md`; `verification-gate.md`; `gate-report.md`; `adversarial-review.md`.
**Work:** after T22 reports zero blockers, record final SHAs/status and make one docs-only closeout commit. Keep five-provider startup telemetry, three real-symlink MSYS controls, Windows authority ACL, and actual CLI install/update/recover comparison UNVERIFIED unless direct evidence exists. Deployment/publication and UI/client work remain N/A.
**Tests/acceptance:** cross-artifact AC/decision/task/evidence audit, stale-status search, `git diff --check`, and exact staged-path inspection; spec changes DRAFT -> DONE only with zero blockers; rollback remains per-task `git revert` in reverse dependency order.
**Module size:** N/A; docs only.
**Worker-undisturbed:** source, provider, config, `docs/wasted-code/`, and smoke `.log` files unchanged/staged-excluded.
**Commit:** one docs-only `T23` closeout commit.

## Coverage audit

| Requirement | Task/evidence |
|---|---|
| AC1 / B6 / B4 zero-write invalid input | T17 -> overlay refusal/round-trip matrix -> T21 |
| AC2 | T14 -> complete settings/config preflight -> T21 |
| AC3 / B3-B4 | T13-T15 -> ownership, interruption, retry, provider/Git verification -> T21 |
| AC4 / B5 | T15-T16 -> exact parsed hook state and matcher isolation -> T21 |
| AC5 / N2 | T13, T20 -> collision tests plus three write-mode no-op attempts -> T21 |
| AC6 | retained T5 plus affected Stop regression -> T21 |
| AC7 | retained T7; five provider hosts remain UNVERIFIED unless measured -> T21/T23 |
| AC8 / B7 | T18 -> executed actions/artifacts and mutation controls -> T21 |
| AC9 / B1-B2/N1 | T11-T12 -> identity, trust, direct-mint, portability matrix -> T21 |
| AC10 / B8/N2 | T18-T20 -> observed workflow, scoped conclusions, write-mode metrics -> T21 |
| AC11 | T13-T15/T20 -> CLI byte/semantic boundaries; full real CLI chain remains residual unless run -> T21 |
| AC12 | T13-T15 -> canonical/snapshot ownership and verified mirrors -> T21 |
| T21 fixture contract | T24 -> real Git repository/identity, focused T15 Git verification, CLI/user byte sentinels -> T25 -> T21 |
| Registered wrapper closure | T25 timeout -> T26 Stop identity -> T27 legacy fixtures -> T28 selectors -> T21 relevant wrapper coverage |
| A1-A3 | T13-T17 |
| A4-A5 | T16-T18; retained T7 regression |
| A6 / B1-B2 | T11-T12/T20 |
| A7 / B5 | T18-T20 |
| Final zero-blocker review | T22 before T23 |

**Serialization:** T32 -> T33 -> T21 -> T22 -> T23. T29/T30 share the mutation harness; no concurrent writes. No worker-undisturbed path is configured; every task preserves the stricter CLI/user boundary.
