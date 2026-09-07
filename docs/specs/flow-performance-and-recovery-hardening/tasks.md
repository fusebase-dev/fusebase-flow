# Tasks - flow-performance-and-recovery-hardening

**T-counter going in:** T11
**Historical implementation:** T1-T10 complete provisionally; T10 gate superseded by Astra CHANGES REQUIRED
**Corrective implementation:** T11-T20/T24-T47 complete or absorbed; final source `008ade7553009f38ebf0d9ee29c83df8be64d50b`; T35 absorbed into T36, T38 into T37, T39-T46 source into T46.
**Final technical gate:** T21 report reconciled; scoped OPEN pending T22 review and stated residuals; see verification-gate.md.
**Repeated adversarial review:** T22, GPT-6 Astra review-only
**Closeout:** T23, docs-only; former T11 moved without reuse
**Starting source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Linked spec:** `docs/specs/flow-performance-and-recovery-hardening/spec.md`
**Linked decisions:** A1-A7, B1-B6
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
| T34 | receiptless mirror ownership bootstrap and final manifest freshness | current AC12/integrity blockers | B2, B5-B6 | T33 | `7c9be06`; committed; T15 integration exposed T35 |
| T35 | preserve unregistered dynamic helper imports | T15 preflight import failure | B2, B6 | T34 | uncommitted; absorbed into T36 |
| T36 | shared baseline classification contract and preflight coherence | T15 API/ownership mismatch | B2, B5-B6 | T34/T35 diff | planned; one combined implementation commit |
| T37 | bounded observable T15 evidence without repeated recovery | T36 T15 timeout | B2, B6 | T36 dirty source | planned; test-harness slice |
| T38 | selected Bash propagation and direct status proof | T37 WSL-shim red | B6 | T37 dirty harness | absorbed correction before T37 commit |
| T39 | minimal real three-attempt write-mode no-op evidence | T20 timeout | B5-B6 | d0270f0 | planned; test-only |
| T40 | convergence stage budget within unchanged outer bound | T39 convergence55s red | B5-B6 | T39 dirty harness | absorbed correction before T39 commit |
| T41 | remove recovery subprocess amplification | T40 wired convergence timeout | B2/B5/B6 | T39/T40 dirty harness | planned runtime slice |
| T42 | PATH-independent process instrumentation | T41 observer false-zero | B6 | T41 dirty focused test | absorbed test correction |
| T43 | durable calibration and duplicate observer removal | T42 timed-out observation | B6 | T41/T42 dirty focused test | bounded test-only correction |
| T21 | final scoped technical acceptance/report | B1-B8, N1-N2 | A1-A7, B1-B6 | T36/T37 | report-only |
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
**Tests:** focused legacy functions through bounded diagnostic setup before T28 exists; record actual invoked functions and assertions, never count execution of a sourced-only module as proof. T21 consumes only affected legacy-selector proof under B6; no default-wrapper restart.
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

## T34 - Bootstrap proven mirror ownership and restore final manifest freshness

**Status/authority:** planned under existing B2/B5/B6 and authorized mitigation; no new trust/signing decision. One implementation commit, then report-only T21. Do not restamp a consumer base or adopt arbitrary tracked files.

**Exact source write set:** `hooks/local/lib/recovery-owned-write.py`; new focused `hooks/tests/test-recovery-owned-bootstrap.py`; `hooks/tests/test-cli-flow-recovery.sh`; `hooks/tests/test-cli-flow-recovery-selectors.sh`. Add one public `--only t34` group and include the same focused test once in the default recovery phase; no new scheduler or full-suite registration. The helper remains below 800 lines; new test targets <=300. Mirror shell callers need no API change.

**Derived write set:** regenerate `audit/hook-layer-manifest.json`, then `audit/managed-content-manifest.json` using their existing stamp tools in this publisher checkout. Normal mirror output may touch `audit/skill-mirror-manifest.txt` or `audit/agent-mirror-manifest.txt` only if source-truth regeneration differs; inspect exact diff before staging. No skill/agent source changes are planned; provider mirror bytes must remain unchanged here. Local ownership receipts are untracked runtime state, never commit inputs.

| Boundary | Required algorithm |
|---|---|
| Existing classifications | Preserve current-byte equality, missing authorization and receipt-backed ownership behavior. Bootstrap is a fallback only for existing regular skill/agent targets lacking matching receipt proof; command/health/Git/settings surfaces get no new authority. |
| Mapping | Require exact canonical-to-mirror projection: `flow-skills/<skill>/SKILL.md` or direct `references/<file>` to the same relative suffix under `.agents/skills` or `.claude/skills`; `agents/<name>/AGENT.md` to `.claude/agents/<name>.md` or `.codex/agents/<name>.md`. No caller-supplied alternate manifest, SHA or arbitrary mapping. Legacy `skills/` fallback is not bootstrapped by this task. |
| Prior ownership proof | Pin repository HEAD once before classification; read canonical blob, destination blob/mode and matching mirror-manifest blob from that same commit. Require all three bytes/hashes to agree: committed canonical SHA256 = committed target SHA256 = exactly one well-formed committed manifest row. Require current destination bytes to match that proven old hash. Tracking, current worktree manifest, filename or a manifest row alone never suffices. |
| Trusted input scope | HEAD is the operator-selected repository baseline, not authenticated upstream or validator evidence. This proves prior canonical mirroring within that baseline; it does not protect against an adversary rewriting the entire repository history/canonical source. Do not reuse this proof for validator receipts, consumer managed-base reconstruction or arbitrary source authorization. |
| Refusals | Missing/unborn/unreadable baseline, absent/duplicate/malformed row, wrong surface/mapping, committed symlink/gitlink/nonregular mode, modified destination, symlink destination/ancestor/source all preserve target and return partial. Resolve paths only after rejecting source/ancestor symlinks, so resolution cannot erase the evidence. Source/target must remain contained in root. |
| Apply and retry | Compute fallback proof without writing a receipt first. Revalidate pinned HEAD and target/source identities before retained-original/replace; detected change refuses affected write. Use existing retained-original/atomic-copy path; record only actually applied/current targets. Preserve interruption status and retry behavior; do not claim whole-run transactionality or hostile concurrent-writer resistance beyond observed checks. |
| No-op | Do not atomically replace byte-identical receipt content; skip unchanged per-target receipt updates. First successful bootstrap may record ownership, but three subsequent independent write-mode calls must preserve target/manifest/receipt bytes and mtimes and report zero target copies. |
| Cost | Read committed objects through one bounded batch or small fixed number of Git processes per invocation, not per-target `git show`/hash subprocesses. No network, full history scan, new cache authority or checkout mutation. |

**Focused cases:** real disposable Git repo committed with tiny skill/reference/agent mirrors and manifests; remove receipt or omit affected rows, edit canonical source, run actual normal mirror entry points, assert retained old original + exact new bytes + final manifest rows. Cover both providers and agent rename mapping. Negative cases: tracked custom collision, target edited after commit, current-worktree manifest forged, committed manifest stale/duplicate/malformed, committed canonical/target disagreement, missing HEAD/source/row, symlink or ancestor symlink, arbitrary surface/path and pinned-state invalidation. Each rejected target keeps bytes/mtime and creates no ownership/backup for that target. Verify unchanged receipt mtime, interrupted retained-original/retry, and negative control that removes one proof conjunct is rejected. Platform-unavailable real symlinks stay UNVERIFIED, never simulated PASS.

**Entry-point contract:** `python hooks/tests/test-recovery-owned-bootstrap.py` for direct development; `bash hooks/tests/test-cli-flow-recovery.sh --only t34` for registered focused proof. Selector selftest covers discovery, invalid/no-write selection, same real t34 execution and non-attesting summary. Default wrapper includes t34 once, but do not run that default locally to prove dispatch. Standalone helper test plus registered selection are alternative evidence paths, not mandatory duplicate runs.

**Sequence:** implement -> focused t34 + selector contract -> inspect actual publisher diff and ownership -> normal mirrors if needed -> stamp hook manifest -> stamp managed manifest (it includes hook manifest) -> verify both, skill mirror check and agent/preflight integrity -> normal exact-staged pre-commit. Any subsequent covered source change repeats only affected focused proof and both stamps in order. No VERSION change or hand-edited hashes. Inspect generated inventory, reject unexpected paths, and never stage smoke, receipts, backups or `docs/wasted-code/`.

**Budget/stop:** proposed <=5m focused helper/selector batch and <=10m T34 local validation; declare actual command watchdog and inspect unexplained overruns. Missing/zero-row/crash/timeout stays failure; no timeout increase, broad health run or 108-minute prefix. Post-interruption full owned-descendant scan required. If scope needs another runtime surface or independent authority, return precise blocker before editing it.

**T21 invalidation:** AC3/S1, AC5/S2, AC11/S1, AC12 and current integrity/safety require current-source revalidation. AC2 recovery preflight coverage is reviewed because the shared writer changed; rerun only its affected apply/zero-write caller cases if dependency is changed or unknown. T24-T30 support keeps independent proofs but rechecks shared-writer/selector-dependent assertions. T31-T32 composition remains already OPEN after T33; tiny focused composition proof, not health prefix. Preserve existing 9 PASS / 6 OPEN / 1 DEFERRED as the pre-T34 snapshot; do not change statuses before evidence. Stop/lane/validator/window rows carry forward only with explicit unchanged dependencies; deferred platform/real-CLI coverage stays deferred.

**Rollback/boundaries:** exact T34 commit revert restores helper/tests/generated manifests together; retained originals remain operator-owned recovery evidence, never delete them automatically. A rollback does not close T21. Worker-undisturbed configured paths: none; CLI assets, app/config/auth, consumer collisions and all pre-existing untracked paths remain protected by task scope. No deploy/push. Normal pre-commit and any protected-path authorization remain live; no bypass.

## T35 - Import carrier correction (absorbed into T36; no separate commit)

The uncommitted namedtuple/import-regression diff remains valid and is preserved. It removes the dataclass registry dependency but T15 then exposes the shared classification contract mismatch. T36 owns the combined root-cause correction and one commit; do not commit T35 separately or repeat its already-observed failure as a new gate.

## T36 - Unify read-only ownership preparation and recovery classification

**Source/state:** HEAD `7c9be06` plus preserved uncommitted T35 helper/test diff. Existing B2/B5/B6 authorize this correction; no new ownership authority or governance mechanism. Architect static review only; parent-reported T15 failures remain failed evidence, not locally reproduced results.

**Root cause:** T34 replaced the consumed public `classify(source, target, rel, targets) -> (state, detail)` with a five-argument `(source, target, PlanRow, targets, Baseline) -> (state, detail, proof)` contract. `recovery-preflight.py:102` still uses four args/two results. A compatibility shim alone is insufficient: receiptless preflight would still label proven old mirrors unowned; `recovery-verify.py:41-46` deliberately retains that classification even after successful writes. T35 import-only proof could not cover either semantic mismatch.

| Caller | Existing role / required result |
|---|---|
| `recovery-preflight.py` `target_rows` / `build_plan` | Only in-repo imported classify caller found; needs read-only batched bootstrap classification before any recovery writes. Preserve complete-plan invalid-input refusal. |
| `recovery-owned-write.py` `apply` | Parses TSV, builds one Baseline, retains proof for pre-write HEAD/source/target revalidation. Keep this trust boundary and atomic/receipt behavior. |
| `mirror-skills.sh`, `mirror-agents.sh` | Invoke writer CLI with skill/agent; unchanged public arguments and manifest behavior. |
| `post-fusebase-update.sh` health/commands | Writer CLI; no new health/command ownership permission. Exact already-covered canonical health mirror is deduplicated during planning, not independently promoted. |
| `recovery-verify.py` `verify_targets` | Consumes plan classification plus fresh exact bytes; no classify import. Keep collision/unsafe refusal and fresh final verification; never silence a stale plan by ignoring classification. |
| Existing bootstrap tests | Exercise direct writer and unregistered import, but lacked preflight-to-writer-to-verifier coherence. Add this seam once in existing test family. |

**Exact write set:** `hooks/local/lib/recovery-owned-write.py`, `hooks/local/lib/recovery-preflight.py`, `hooks/tests/test-recovery-owned-bootstrap.py`; generated `audit/hook-layer-manifest.json`, then `audit/managed-content-manifest.json`. Preserve/absorb current T35 namedtuple diff in first/third files. No edits to verify, loaders, mirror shell entry points, dispatcher/selectors, runtime CLI/provider/config, manifests by hand, or new files. Existing files stay <=800 lines.

| Design seam | Contract |
|---|---|
| Public compatibility | Restore four-argument `classify(source, target, rel, targets)` returning exactly two fields with pre-T34 conservative current/missing/receipt-owned/collision/unsafe semantics. No inferred root or HEAD, no hidden Git call and no fabricated bootstrap authority. Source non-file/symlink handling remains fail-closed. This is a supported consumed contract, although preflight moves to the explicit batch API. |
| One authoritative classifier | Put current/receipt/bootstrap decision logic behind one internal proof-bearing classifier; legacy wrapper invokes it without bootstrap context and drops proof. Do not maintain two independent copies of predicate logic or overload return arity by input type. |
| Shared row construction/preparation | Extract a small `make_plan_row(root, source_raw, target_rel, surface)` used by TSV parsing and preflight; it applies existing exact `expected_mapping`. Extract `prepare_rows(root, rows, targets)` returning one pinned Baseline plus PreparedRows without writes; both `apply` and preflight use it. Preserve proof objects for writer revalidation; preflight exposes only existing state/detail JSON fields, not reusable authorization. |
| Batch and freshness | Build Baseline once for all eligible rows per invocation, fixed bounded Git object reads; no per-target baseline or subprocess loop. Preflight validates HEAD/source/target proof freshness before emitting an owned classification; apply independently rebuilds/revalidates before mutation. Preflight success is not a capability to bypass later checks. |
| Actual target enumeration | Preflight must enumerate exactly mirror-skills SKILL.md and direct regular references plus mirror-agents AGENT.md projections, not arbitrary recursive canonical files. Reject relevant unsafe source paths rather than follow symlinks. Deduplicate identical source/target pairs before classification: health whose canonical source/target is already a skill mirror keeps that single skill row. The fallback overlay health path and command rows stay non-bootstrap. Conflicting same-target/different-source plans are invalid, exit 2 and zero recovery writes. |
| Failure semantics | Missing/malformed required input or unsafe source fails preflight before target/receipt/backup/Git writes. Valid but unproven existing destination remains collision/partial, not ownership. Convert shared-helper errors deliberately into existing ValueError/RuntimeError preflight refusal; never catch broadly and invent current/owned. Preserve verifier contract unchanged. |

**Focused test additions in existing T34 family:** (1) legacy four-arg two-result contract on current/missing/receipt-owned/unowned/unsafe, no Git/root guessing; (2) actual unregistered preflight loader and shared preparation, including T35 immutable records; (3) committed receiptless skill/reference/agent mirror with canonical edit: actual `target_rows` says owned-repair, actual writer applies, actual `verify_targets` accepts exact final bytes; (4) custom/modified destination or bad committed manifest stays collision before/after and verifier rejects; (5) later invalid source/malformed receipt/conflicting plan causes no recovery writes; (6) canonical health duplicate planned once while overlay fallback stays conservative; unrelated canonical README/nested files never become promised mirror targets; (7) one Baseline construction/bounded batch per preparation and pinned-state change still refuses before retained copy. Reuse tiny fixture tree, extending it only with required health/command sources; do not clone full repository for each row. No mock-only success oracle or weakened existing mutation/refusal tests.

**Test chain / one-run stop:** extend seam tests first; run the existing registered `--only t34` once after the combined source change, then `--only t15` once. T15 is the real preflight/apply/final-verifier/CLI-user/Git composition, not import-only proof. On first red/timeout, stop dependent testing, capture exact error and diagnose that row; no unchanged retry, default wrapper, health prefix or S2/T32 until these pass. Do not separately rerun the complete Python family if t34 already ran it. Dispatcher unchanged, so no selector-selftest rerun. Proposed <=10m focused chain under existing hard bounds; overruns are diagnostics, never authorization to raise limits. Preserve original failed logs; confirm complete owned-descendant cleanup after interruption.

**Final-source sequence:** focused T34 -> T15 -> stamp hook manifest -> stamp managed manifest -> verify both and applicable syntax/diff/module/normal exact-staged safety/pre-commit -> one `fix(T36)` commit including absorbed T35. No separate T35 commit or new roadmap. Any subsequent source edit invalidates only its dependent proof; no evidence reused merely because filename/HEAD is similar. Generated manifests include final combined source, not an intermediate T35 state.

**T21 continuation:** preserve existing 9 PASS / 6 OPEN / 1 DEFERRED as earlier snapshot; record T35/T36 correction separately. AC2, AC3/S1, AC5/S2, AC11/S1, AC12 and integrity depend on changed writer/preflight. Current T34/T15 can close only their mapped cases; then execute still-open independent S2 attempts and focused T32 composition once. Unchanged Stop/lane/validator/window evidence needs dependency confirmation only. Actual CLI/platform/authority gaps stay deferred. No invented PASS, no S2/T32 execution claimed from planning.

**Rollback/risk:** revert the one T36 commit to restore `7c9be06` and its known integration defects; keep gate OPEN. Preserve uncommitted docs and untracked smoke/archive/docs-wasted-code, receipts and retained originals. No deploy/push. Residuals: preflight enumeration must match actual shell mapping (especially canonical health aliases); proof freshness is checked, not a hostile concurrent-writer transaction guarantee; legacy four-arg calls intentionally cannot bootstrap without explicit root/context.

## T37 - Replace blind T15 repetition with one composed restore and focused negatives

**Status:** planned test-only mitigation; preserve all uncommitted T35/T36 source/test changes. T36 remains the source correction; T37 is its focused evidence-harness correction, not a runtime repair. No tests, source edits or commit in this Architect turn.

**Evidence:** `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/T36-t15.log`: inner 285s/outer 300s, START and heartbeats only, rc124 after 336.11s; no terminal scenario row. `T36-t15-survivors.log`: survivor_count=0 at 01:02:52-04:00. `T36-selector-t34.log`: real selected T34 4/4, rc0, elapsed 124.751s. Logs mix UTF-8 headers and UTF-16 native output; preserve raw files and normalize only when reading, never rewrite evidence. No phase-level timestamp/process sample identifies the exact blocked child, so timeout cause beyond aggregated orchestration is UNKNOWN, not a proved runtime hang.

**Topology/cause:** PowerShell launch -> outer timeout/bash -> selector parent -> `ffhc_run_bounded` inner captured child -> `ffcf_t15_verification` -> fixture builder and four sequential recovery processes. `cli-flow-recovery-e2e.sh:89-147` rebuilds fixture twice, runs complete recovery for positive restore, tampered backup, missing backup and post-apply mutation, and emits one PASS only at the end. Three runs discard output; selector releases captured output only after completion. Therefore absence of a row does not locate the failure or prove no work. Compounded process cost is credible; exact 285s attribution is not measured. Heartbeats are liveness, not progress.

| T15 assertion/dependency | Increment beyond current T34 | T37 owner |
|---|---|---|
| Valid hash-recorded provider backup restores exact bytes and composed rc0 | T34 covers target classification/writer/verify_targets, not provider-overlay backup and full status | One actual composed positive restore in existing T15 function, real disposable Git fixture, exact restored bytes and complete status |
| Tampered backup rejected; missing backup stays uncertain | Not covered by T34 | Tiny direct production `verified_provider_backup`/overlay-plan calls; no restored target, explicit uncertainty/hash refusal |
| Post-apply command mutation excluded from verified, included in uncertain, partial status | T34 collision/byte tests overlap, but final verification/status assembly is additional | Tiny actual `recovery-verify.verify` or CLI result + existing `ffrp_verified`/`ffrp_finish` status writer with real result; no fabricated passing dictionaries |
| Exact Git-hook installation/CLI hook preservation | NOT explicit T15 assertions: T15 never passes --wire-hooks or asserts installed hooks | Do not claim closure from T15; unchanged separate proof/S1 requirements remain mapped in T21 |
| Shared T36 preparation/import/ownership negatives | Already exercised by real T34 selection | Reuse the recorded result after unchanged-dependency confirmation; no T34 rerun for T37-only edits |

**Exact write set:** `hooks/tests/cli-flow-recovery-e2e.sh`, new `hooks/tests/test-recovery-final-verification.py`, `hooks/tests/test-cli-flow-recovery.sh` only for durable T15 diagnostic-path announcement before capture and passing that path to the child. Generated hook then managed manifests only when committing final covered bytes. No runtime helper, preflight, verifier, recovery orchestration, timeout library, fixture-common builder, policy, dispatcher selection semantics or CLI/provider edits. Do not edit the already-green T34 test. New test <=300 lines; existing modules <=800.

**Implementation:** keep `ffcf_t15_verification` entry point and replace its three additional recovery launches plus second build with direct tiny-fixture negatives. Use the actual provider validator, verifier and status writer; include a positive baseline before corrupting/missing bytes so a reject-everything oracle fails. Assert original T15 byte/status predicates individually; classify direct status-helper proof honestly, not as a rerun of the complete orchestration's negative routing. A single composed positive restore remains mandatory. Source direct negative fixtures from minimal real plan/overlay bytes, not full repository copies. Do not weaken rc0 positive restore or rc1/uncertainty negative assertions just to fit time.

**Progress/diagnostics:** before fixture creation, parent prints a unique durable diagnostic path outside selector-cleaned temp tree. Child appends flushed START/END/elapsed/rc for `fixture`, `positive-restore`, `tampered-backup`, `missing-backup`, `post-apply-verification`, plus stdout/stderr per scenario. Emit each semantic PASS/FAIL when earned. Merely echoing inside captured stderr is insufficient; the independently readable stage file must survive timeout and normal cleanup. Keep labels free of secrets; test process tree is owned. Existing raw timeout evidence remains untouched; use one consistent UTF-8 capture path next time, avoiding mixed PowerShell redirection encodings.

**One-run validation:** after test-only edits and source inspection, run only `--only t15` once with a fixed 120s inner budget and bounded 150s cleanup envelope (both lower than failed 285/300). Proposed stage ceilings: fixture 20s, composed positive restore 60s, direct negatives combined 30s; these are diagnostic targets, not observed timings. Stage helper reports actual command/result; no broad/default runner, separate preflight/health or selector-selftest rerun. On any red or deadline, stop dependent work, retain stage file/raw child output/rc and owned-descendant scan, identify the named stage before any new action. Do not rerun unchanged, extend timeout, or launch S2/T32 while blocked. If even the one positive composed restore cannot fit, return its stage-specific evidence; no speculative runtime patch is authorized by T37.

**Dependency/commit:** T36 changed-source proof already has recorded T34; T37 changes only T15 harness/wrapper diagnostics and therefore invalidates only T15 evidence. T15 focused success supports the named cases, not full suite/release/real CLI. Then resume mapped outstanding T21 evidence; no automatic zero-blocker result. Preserve existing 9 PASS / 6 OPEN / 1 DEFERRED historical snapshot. T35 remains absorbed into T36; T37 should be a separate exact-path test-harness commit after owning implementation review decides safe ordering; do not mix source-runtime and unrelated documentation into a new blanket commit. Stamp hook then managed manifest for each committed covered final state; no stale intermediate manifest claim.

**Residual:** exact stall location unproved; 336.11s exceeds configured bounds and lacks terminal selector cleanup evidence despite final zero-survivor scan. This plan does not claim a watchdog implementation fix. Direct negatives preserve predicate evidence but do not independently replay every shell negative-routing branch; unchanged routing evidence remains historical/deferred. Keep complete positive composition and final adversarial review rather than claiming all coverage is equivalent.

## T38 - Carry the selected Bash executable into direct status verification

**Diagnosis/evidence:** T37 raw `...smoke/T37-t15.log` reports selector rc1 at 84s, outer elapsed91s, not timeout. Durable `/tmp/fusebase-flow-t15-stages-873717.log` records fixture17s/rc0, positive restore51s/rc0, tampered0.015s/rc0, missing0.016s/rc0, post-apply0.188s/rc1. The last stage passed positive verification and mutation discrimination, then native Python `subprocess.run(["bash", ...])` selected the Windows WSL shim and failed `execvpe(/bin/bash)`. This is a test executable-resolution defect, not failed recovery or verifier semantics. `T37-launcher-precondition.log` describes an earlier non-start and is not this attempt. Only one subprocess call exists in the new Python test; imported production helpers are unchanged and not retargeted.

**Exact write set:** `hooks/tests/test-recovery-final-verification.py` and the invocation in `hooks/tests/cli-flow-recovery-e2e.sh`. No dispatcher, runtime, loader, verifier, timeout, policy, CLI/provider or T34 edits. Generated hook then managed manifests accompany the relevant final commit. Preserve untracked Python test and every other dirty/evidence path.

**Executable contract:** e2e passes the already-running `$BASH` as explicit `--bash-executable` argv; on Windows/MSYS convert that exact executable once with `cygpath -am`, on POSIX preserve its absolute path. Native Python validates an absolute existing executable file before any fixture mutation, records the selected path, and uses `[bash_executable, "-c", script, ...]` with `shell=False`; no PATH re-resolution, bare bash, WSL fallback, shell-string interpolation or Python/Git guessing. Normalize path arguments for the selected shell (forward-slash native absolute paths on Git Bash, POSIX paths on POSIX); retain argument-list quoting for spaces/Unicode. Invalid/missing executable must fail before status/target writes. This is test-owned selection, not a new runtime trust mechanism.

**Small direct selection:** expose `--only status-writer` in the existing Python file, explicitly partial/non-attesting, requiring executable and stage-file but not backup/recovered-project inputs. Build one tiny temporary command source/target plus valid minimal verification plan; invoke the real verifier for positive baseline and post-write mutation, then the existing real shell status writer and exact partial/commands-uncertain/not-verified assertions. Source production helper from the source checkout, write state only under the temporary root. Share status-writing/assertion code with the existing full post-apply check; do not add a second hand-written oracle or fabricated success dictionary. Unknown selection fails before fixture creation. Normal no-selection behavior remains the same three direct scenarios and now receives the explicit shell from e2e.

**One-run validation:** run only new direct `--only status-writer` once with the known Git Bash executable, durable stage file and fixed <=30s outer bound (existing status subprocess timeout20s unchanged). The same invocation includes invalid-executable/invalid-selection no-write controls and successful selected executable use; count those honestly. No composed restore, provider negatives, T15 wrapper, T34, full/default, separate preflight/health or timeout increase. On first red/timeout retain exact stderr/selected executable/phase/rc, inspect owned descendants and stop; no unchanged retry. If a smaller regression cannot exercise the real status subprocess, retain OPEN rather than substituting a mock.

**Evidence reuse:** T37 composed restore and backup-negative dependencies (runtime source, fixture inputs and their relevant test functions) remain unchanged; retain their recorded successes. T38 changes only the status launch and a direct selection seam, so no new end-to-end success claim. Prior post-apply stage remains failed until direct status proof succeeds; stitch evidence by named scenario/dependencies, never relabel the earlier whole T15 rc1 as PASS. Static inspect the e2e argv propagation and argument validation; a platform/path branch not exercised stays UNVERIFIED. Preserve independent T21 S2/T32 requirements.

**Commit ordering:** no standalone T38 source commit before the untracked T37 Python file exists in history. Finish focused T38 proof; owning developer then commits T37's test harness with this necessary T38 correction absorbed, exact test paths plus generated manifests, labeling both task IDs and retained failed-then-passed evidence. T36 source commit remains separate if already committed; do not restage it. Hook stamp precedes managed stamp after final test bytes. No docs closeout or release claim before T21/T22. No commit/test/source change in this Architect turn.

**Residual:** direct status selection proves the repaired launch/status seam, not a new complete recovery run or another platform's executable resolution. Validating a file path alone is not proof of shell identity; the explicit parent-selected executable and successful real shell action are the evidence. No production-shell resolution or ownership semantics changed.

## T39-T47 - Completed corrective work and retained failure evidence

Final implementation: `008ade7553009f38ebf0d9ee29c83df8be64d50b` (T46 commit absorbs T39/T40 harness and T41 optimization). Exact source scope is the commit diff; no deleted experimental helper test is shipped. Final validation is owned by `gate-report.md`.

| Slice | Material outcome / failure retained | Disposition |
|---|---|---|
| T39 | Tiny real fixture; three independent no-op attempts; convergence55s timeout before attempts | Harness retained; no acceptance from timeout |
| T40 | Convergence80s timeout near Step5b | Bounds fixed80/45/240/270 thereafter |
| T41 | Move parent mkdir into Python; builtin output predicates; one verification parse; PATH observer missed calls at10.467s | Runtime retained; observer failure not runtime verdict |
| T42 | Sourced forwarding calibration timeout12s;22.512s overall; launcher rc0 contradicted traceback | Failed instrumentation; no T20 |
| T43 | Five forwarded commands ended; subprocess timeout12s;14.496s overall | ~5.1s command sum versus9.982s span; no proved exit cause |
| T44 | Structural assertion passed; second real status shell timeout12s;20.867s overall | Later semantic assertions never executed |
| T45 | Removed uncommitted helper tests; T20 convergence72.813s then attempt1 timeout45s/49.203s | Receipt sole changed target; no no-op acceptance |
| T46 | Lazy bootstrap baseline, stable same-hash receipt metadata, authoritative writer manifests remove duplicate work; first run child_copy/selector124 | Environment-inconclusive, not PASS; no convergence END |
| T47 |11 identity-validated orphan loop roots cleaned; unrelated processes preserved; one environment-corrected T20 run green | No new test family; shared current-source evidence, see gate report |

Historical raw logs stay in the existing smoke directory and recorded temporary evidence directories. Earlier108-minute prefix reached414 PASS/0 FAIL but never terminal completion; it is partial historical evidence only. Do not restart it. Runtime safety invariants remain complete preflight, conservative ownership/bootstrap proof, per-target atomic receipts, durable checkpoints and fresh final verification. Anti-overtesting disposition remains: no dynamic tracer or implementation-mirroring helper suite; scoped review plus existing composed behavior oracle.

## T21 - Final technical gate report

**Files:** `docs/specs/flow-performance-and-recovery-hardening/gate-report.md`; uncommitted smoke JSON/log evidence under the existing smoke directory; durable `state/audit/` outputs only where existing commands own them.
**Work/tests:** report reconciliation complete at `008ade7`; no new source/test execution. gate-report.md owns evidence and verification-gate.md owns the current scoped ledger. Remaining negative-path sufficiency is T22 review input, not an instruction to launch more tests. No full-prefix restart.
**Acceptance:** every B1-B8/N1-N2 has direct closure evidence or remains open; exact T11-T20/T24-T33 SHAs/timing and failed-then-passed evidence recorded; real Git verification and affected wrapper/liveness contracts proved; spec remains DRAFT; stop at gate.
**Module size:** N/A; report/evidence only.
**Worker-undisturbed:** verify all task boundaries and shared workspace hash/status; do not stage `docs/wasted-code/` or existing smoke `.log` files.

## T22 - Repeat the GPT-6 Astra whole-implementation review

**Files:** read-only implementation/evidence review; review result prepared for `adversarial-review.md` but committed only in T23.
**Work/tests:** no implementation commit. GPT-6 Astra reviews `2217a9c..008ade7`, T21 coverage/evidence, smoke, ownership/authority boundaries, and B1-B8/N1-N2 closure. Replay targeted mutations/false-claim cases, manifest parity and probe-budget negative controls; consume T21 scoped AC/dependency ledger rather than rerunning the whole suite. Any new source correction invalidates affected dependency rows only; rerun those rows and targeted review, never the complete prefix.
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

**Serialization:** implementation through T47 complete -> T21 reconciled -> T22 independent final review OPEN -> T23 docs-only closeout OPEN. No automatic test restart.
