# Tasks - flow-performance-and-recovery-hardening

**T-counter going in:** T11
**Historical implementation:** T1-T10 complete provisionally; T10 gate superseded by Astra CHANGES REQUIRED
**Corrective implementation:** T11-T20 complete; T24 fixture correction pending, one commit
**Final technical gate:** T21, report-only after T24
**Repeated adversarial review:** T22, report-only
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
| T24 | initialize recovery E2E as a real disposable Git repository | T21 fixture defect | A2-A3, B2 | T20 | pending; one commit |
| T21 | final technical gate/report | B1-B8, N1-N2 | A1-A7, B1-B5 | T24 | report-only |
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
**Acceptance:** the T15 focused path and registered recovery wrapper run in a real disposable repository; `post-fusebase-update.sh --wire-hooks` no longer returns partial from Git rc128 or project-identity mismatch; exact Flow pre-commit/commit-msg destinations and same-project hook intent verify; CLI/user sentinel bytes remain identical.
**Tests:** `FFCF_T15_ONLY=1 bash hooks/tests/test-cli-flow-recovery.sh`; `bash hooks/tests/test-cli-flow-recovery.sh`; assert fixture `git rev-parse --show-toplevel` succeeds, local identity is configured, Git hooks verify exact owned content/executable state, intent root matches normalized Git root, and CLI/user before/after hashes match.
**Module size:** `hooks/tests/cli-flow-recovery-e2e.sh` is 334 lines before T24 and must remain <=800; no extraction/exemption needed.
**Worker-undisturbed:** only a disposable fixture changes. Shared `.git`, installed hooks, CLI/provider assets, consumer config, `docs/wasted-code/`, and smoke evidence remain untouched.
**Commit:** exactly one `T24` commit; stage only `hooks/tests/cli-flow-recovery-e2e.sh`; normal pre-commit; no `--no-verify`.

## T21 - Final technical gate report

**Files:** `docs/specs/flow-performance-and-recovery-hardening/gate-report.md`; uncommitted smoke JSON/log evidence under the existing smoke directory; durable `state/audit/` outputs only where existing commands own them.
**Work/tests:** no source change or commit. Replace `gate-report.md` with final evidence only after T24 is committed. Run every focused command including both T24 recovery-wrapper commands, `FF_FULL=1 FFHC_HEARTBEAT_SECS=30 bash hooks/tests/run-tests.sh`, `bash hooks/local/preflight.sh`, mirror/manifest checks, module-size `--all`, normal pre-commit, secret/protected-path checks, CLI ownership comparison, three independent S1-S3 attempts, and `verification-gate.md`.
**Acceptance:** every B1-B8/N1-N2 has direct closure evidence or remains open; exact T11-T20/T24 SHAs/timing and failed-then-passed evidence recorded; T24 proves the tightened Git verifier against a real fixture repository; spec remains DRAFT; stop at gate.
**Module size:** N/A; report/evidence only.
**Worker-undisturbed:** verify all task boundaries and shared workspace hash/status; do not stage `docs/wasted-code/` or existing smoke `.log` files.

## T22 - Repeat the GPT-6 Astra whole-implementation review

**Files:** read-only implementation/evidence review; review result prepared for `adversarial-review.md` but committed only in T23.
**Work/tests:** no implementation commit. GPT-6 Astra reviews `2217a9c..T24_HEAD`, T21 report, focused evidence, smoke attempts, ownership/authority boundaries, and every B1-B8/N1-N2 closure. Adversarially replay the named mutations and false-claim cases.
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
| AC6 | retained T5 plus full regression -> T21 |
| AC7 | retained T7; five provider hosts remain UNVERIFIED unless measured -> T21/T23 |
| AC8 / B7 | T18 -> executed actions/artifacts and mutation controls -> T21 |
| AC9 / B1-B2/N1 | T11-T12 -> identity, trust, direct-mint, portability matrix -> T21 |
| AC10 / B8/N2 | T18-T20 -> observed workflow, scoped conclusions, write-mode metrics -> T21 |
| AC11 | T13-T15/T20 -> CLI byte/semantic boundaries; full real CLI chain remains residual unless run -> T21 |
| AC12 | T13-T15 -> canonical/snapshot ownership and verified mirrors -> T21 |
| T21 fixture contract | T24 -> real Git repository/identity, registered wrapper, T15 Git verification, CLI/user byte sentinels -> T21 |
| A1-A3 | T13-T17 |
| A4-A5 | T16-T18; retained T7 regression |
| A6 / B1-B2 | T11-T12/T20 |
| A7 / B5 | T18-T20 |
| Final zero-blocker review | T22 before T23 |

**Serialization:** T11-T12 share validator files; T13-T17 share recovery files; T18-T20 share evidence consumers. Current tail is T20 -> T24 -> T21 -> T22 -> T23. No worker-undisturbed path is configured, but every task carries the stricter CLI/user zero-change boundary.
