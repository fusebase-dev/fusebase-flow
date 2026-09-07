# Verification gate - flow-performance-and-recovery-hardening

**Status:** operator-locked B6; T32 narrow deduplication and T33 scoped-validation policy/tooling
**Starting source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Linked tasks:** `tasks.md` T11-T47; completed/absorbed implementation, T22/T23 open
**Review findings:** `adversarial-review.md` B1-B8, N1-N2
**Gate task:** T21 report reconciled at `008ade7`; OPEN pending T22. Current ledger: 12 PASS / 3 OPEN / 1 DEFERRED; PASS labels are scoped, not full AC/release attestation.
**Independent review:** T22, zero blockers required
**Closeout:** T23, docs-only
**Smoke threshold:** S1/S3 one execution per distinct positive/negative scenario; S2 retains three independent write-mode no-op calls; repeat diagnosed races only
**Rollback:** code-only framework/template changes; no migration, secret, app deploy, or production target

## Required conditions and evidence mapping

This table defines evidence scope, not a pending execution checklist. Current reconciliation and exceptions are in gate-report.md; no automatic reruns are authorized by old command examples.

| Layer | Command / result |
|---|---|
| Local acceptance | AC/risk ledger with source/input dependencies, command, platform, result, evidence and invalidation decision; scoped reports allowed but never full PASS. Run only uncovered/invalidated affected rows; no full-prefix restart (B6) |
| Broad coverage | Existing maintainer/release CI runs full Linux and Windows/MSYS; no ordinary PR/nightly trigger. Record actual run/SHA/result or DEFERRED; local acceptance is not release evidence |
| Pre-gate T29/T30 diagnosis | `python hooks/tests/test-artifact-manifest.py`; focused PY5, then `FF_ONLY=python3-version,python3-version-mutation bash hooks/tests/run-tests.sh`; scoped evidence only; do not repeat separately during T21 |
| Focused coverage mapping | Its validator, validation-instructions, cli-flow-recovery, hook-intent, timeout, wire-hooks, lane-workflow, windowing, benchmark and selector-selftest rows satisfy corresponding task checks; do not repeat these suites separately |
| Diagnostic entry points | T28 wrapper `--only u14`, `--only legacy`, `--only engine` and task selectors are scoped evidence eligible for matching local AC rows only; never execute sourced-only direct/E2E modules as tests |
| T26 commit proof | Focused U14 1/1 and wire/settings 36/36; full wrapper reached 35 PASS through U14/U15 then stale U7; T21 records relevant wrapper groups and dependency coverage |
| Preflight | `bash hooks/local/preflight.sh`; zero errors/warnings or exact explained residual |
| Mirrors/manifests | `bash hooks/local/mirror-skills.sh --check` plus agent, hook, and managed manifest checks; `--check` labeled read-only integrity |
| Module size | `bash hooks/local/check-module-size.sh --all`; no new/grown violation; `hooks/git/pre-commit` shrinks below 800 in T12 |
| Normal commit gate | normal pre-commit on exact final staged state; no `--no-verify`; live secret/protected/release checks verified |
| CLI ownership | before/after bytes and parsed semantics for every CLI/user fixture surface |
| Git protection | exact staging and digest-bound single-use approval for protected paths; inventory shows acceptable/consumed state |
| Current CLI | only full isolated install/update/recover comparison can verify coverage; update-only probe remains UNVERIFIED |
| Diff hygiene | no TODO/FIXME/WIP; `git diff --check`; no `docs/wasted-code/` or existing smoke `.log` files staged |

## Recovery verdict matrix

| Condition | Required result |
|---|---|
| Any invalid/unavailable plan input | exit 2; zero repair-target, backup, receipt, intent, or Git writes |
| Unowned collision or symlink | target unchanged; retained classification; partial/exit 1 |
| Interrupted apply | durable accurate plan/applied/verified/pending inventory and retained originals; partial/exit 1 |
| Retry | revalidate prior record and current state; no progress reset; converge without duplicate/overwrite |
| Missing provider bytes | restore only verified backup; otherwise unchanged/uncertain and partial/exit 1 |
| Git restoration | exact per-surface intent plus exact owned installed hook verified; output text is insufficient |
| Complete | fresh parsed/hash verification of every authorized surface; complete/exit 0 |
| Engine timeout/reap uncertainty | non-success with visible scenario/phase and retained diagnostics; never fabricate HEALTHY or weaken verdict checks |

## Worker-undisturbed and ownership boundaries

| Boundary | Required result |
|---|---|
| Configured worker-undisturbed paths | none |
| `.claude/hooks/**` | zero byte change |
| CLI provider skills/app agents | zero byte change |
| `fusebase.json`, `.mcp.json`, `.codex/config.toml` | zero byte/semantic change outside isolated CLI fixture writes |
| Consumer settings/custom hooks | only exact Flow entries repaired; all custom order/matcher/timeout/scope preserved |
| Unowned skill/agent/command/health collisions and symlinks | zero bytes/mtime changes; partial recorded |
| Flow provider mirrors/manifests | exact canonical bytes for owned targets; collision status explicit; zero no-op drift |
| `docs/wasted-code/` and existing smoke logs | untouched and excluded from commits |

## Smoke contract

Evidence directory remains `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/`. Existing evidence is retained; T21 validates dependencies before carrying forward a row and replaces invalidated or missing claims with new attempts. Each attempt has a unique ID/timestamp, hard timeout <=60 seconds, independent process execution, saved result, and post-run inspection.

| ID | Scenario | Visible outcome | Ground truth | Falsifier |
|---|---|---|---|---|
| S1 | Recover a CLI-overwritten fixture with valid prior surface intent; also execute named negative cases | complete only for fully recoverable state; partial/failed otherwise | parsed settings/overlays/provider/Git state; hashes; plan/applied/verified/pending ledger; retained originals | unowned overwrite, suffix loss, duplicate/widened hook, missing surface, false exit 0, or inaccurate inventory |
| S2 | After convergence, run full write-mode recovery three independent times | each reports no repair required | per-attempt bytes/mtimes/write/copy counts for every repair target and manifest | any write/copy/mtime change; a read-only `--check` substituted for write mode; three assertions from one process |
| S3 | Run ordinary and sensitive fixture workflows once per distinct scenario | ordinary executes one-pass lightweight; sensitive stops in Full | actual diagnosis/action record and created artifact/relay inventory | hardcoded count, skipped diagnosis, extra relay/artifact, sensitive lightweight, or mutation surviving |

### S1 negative minimum

- malformed event array or unavailable later input: exit 2 and zero writes;
- skill/agent/command/health collision and symlink: unchanged plus partial/exit 1;
- interruption after an applied surface: retained truthful ledger/original and convergent retry;
- provider backup present/missing/tampered: verified restore or explicit uncertainty;
- settings-only legacy intent does not authorize Git; exact Git ownership/install proof required;
- markerless suffix/custom heading refuses without backup or target write.

### S2 evidence minimum

For attempts 1, 2, and 3 record process ID/attempt ID, start/end UTC, command, exit, target inventory digest, per-path before/after hash+mtime, structured writes/copies, and diagnostics excluded from targets. `mirror-skills.sh --check` may be reported separately as read-only integrity only.

### S3 evidence minimum

Record the real fixture directory before cleanup, diagnosis commands/results, router and assessor output, performed action, actual created files, relay count, final lane, and validation result. Run negative mutation modes for extra relay, extra artifact, and skipped diagnosis; all must fail the fixture assertion.

## Performance evidence labels

| Measure | Gate label |
|---|---|
| Stop transcript | measured one-read behavior and wall-time distribution; no hard timing threshold |
| Startup carriers | static character/byte estimate only unless actual same scenario/model/settings host telemetry exists |
| Workflow | executed fixture counts; host token/tool telemetry UNAVAILABLE unless exposed |
| Validation | complete identity, authority result, executions/duration, reuse/rerun outcome |
| Mirror `--check` | read-only integrity; never a write count |
| Recovery no-op | three independent write-mode attempts with bytes/mtimes/write/copy evidence |
| CLI compatibility | UNVERIFIED until actual isolated install/update/recover comparison |

## Residuals allowed at T21/T23

- five-provider actual host-delivered startup telemetry: UNVERIFIED;
- three real-symlink controls on MSYS: UNVERIFIED until Linux/CI;
- Windows validator-authority ACL/isolation: UNPROVEN; reuse unavailable there unless proved;
- actual CLI install/update/recover comparison: UNVERIFIED;
- full current-source CI completion within existing 60-minute job wall: UNVERIFIED; configured full coverage is not executed proof;
- UI/client behavior: N/A;
- platform auth/session/permission problem-catalog item: none; domain N/A.

## Gate completion rules

- T11-T20 and T24-T33 each have one exact SHA and changed-slice proof. T25 is `ef320de`; T26 commit uses its focused evidence above.
- T27 corrects legacy fixture assumptions without weakening T17; T28 adds scoped diagnostics without reducing default coverage. Preserve historical stall, U14 and U7 failures with distinct explanations.
- Tail: T32 -> T33 -> T21 -> T22 -> T23. T21 uses scoped AC acceptance plus uncovered/invalidated smoke and live repo-state checks; no source commit or full-prefix rerun. Fixture phase tests do not substitute for current repository integrity checks.
- Any failed-then-passed check is investigated and reproduced; no silent PASS.
- Every B1-B8/N1-N2 row has direct evidence or remains open.
- Spec remains DRAFT through T21.
- T22 reviews the whole correction diff/evidence and targeted counterexamples, consumes T21 scoped evidence ledger and replays named counterexamples only, and reports zero blockers before T23.
- T23 is the only final docs closeout commit; no deploy/publication command runs.

## Efficiency basis

`state/audit/execution-efficiency-review-2026-09-06.md`: ~11m full-wrapper prefix versus ~8s isolated U14; ~33m timeout-suite log activity. One coverage map removes redundant final focused execution without removing any case. Exact token savings unmeasured. New failure: isolate case, diagnose/change control, verify impacted group; never label partial/scoped runs full PASS. Normal staged secret/protected checks stay live.

## Superseded diagnostic evidence

At `e657392`: python3-version 20/21 in 516s (PY5 whole-hook wall 39s vs 16-26; functional timeout rows passed); mutation 10/11 in 1577s (baseline/mutant `budget_ok` differed). Stopped at git-context, 139 PASS/2 FAIL; owned process tree empty. These are failure/diagnostic records, not final gate proof. T29 batches identical manifest evidence; T30 separates actual probe deadline semantics from whole-hook wall variance. Preserve mutation strength and <=10s per probe; no blind bound inflation.

## T31 heartbeat proof

At `314ead3`, health-check-timeout 22/23 in 1319s; sole AC5 failure one heartbeat vs two in a ~4s child window. All T25 cleanup/reap cases passed; stopped safely before meaningful git-smoke. T31 requires synchronized actual-child markers and two real pre-release heartbeats, off/one-shot/late/capture/cleanup controls and three focused `--only ac5` processes. Default 23 predicates remain; T21 reruns only missing or invalidated heartbeat/affected dependency evidence. No production change or blind timing inflation. See tasks T31 and `state/audit/execution-efficiency-review-2026-09-06.md`.

## T32 composition proof

Full health regression and all liveness predicates execute once in composed gate; standalone liveness retains health dependency. Synthetic launch counts cover full/both-selected/liveness-only and failed/missing dependency. Core-only is partial, never standalone full proof; no trusted environment skip or cached receipt. One-call stdout/stderr/rc attribution replaces duplicate bounded command execution. Measured >19m nested cost and bounded sibling scan in efficiency audit; T32 synthetic composition plus focused core proof; T21 uses B6 scoped acceptance.

## Local acceptance ledger contract (B6 / T33)

Each AC/risk row: changed behavior; dependency files/config/toolchain/platform; exact tested source; command/selection; expected positive/negative outcome; actual exit/result; durable log; reused/new/deferred; invalidation rationale. A new SHA alone does not invalidate unrelated proof; unchanged HEAD alone never proves validity. Unknown dependencies require the affected group to rerun. Every B1-B8/N1-N2 row closes directly or remains open. Missing/zero-row/crashed selected tests remain non-success; subsets cannot satisfy strict full-summary parsing. No automatic proof cache or receipt signer is added.

Per-change syntax/lint and normal staged safety checks remain. Broad release-tag/vendor/legacy compatibility and mutation variants run in maintainer/release CI; absent execution is DEFERRED, not PASS. Full cross-platform CI success is not claimed from configuration inspection. S1/S3 equivalent existing scenario evidence avoids duplicate smoke; S2 still needs three independent write-mode calls. Record selected phase start/end/elapsed/rc/timeout and expected total before long execution; stop and diagnose unexplained cost, never blind-restart prefixes or inflate timeout defaults.

## T21 scoped acceptance ledger — `008ade7`

Platform/toolchain: Windows 11, Git Bash, PowerShell, Python 3. T47 supplied the final current-source T20 evidence and T32 supplied the remaining composition proof. Status totals: **12 PASS / 3 OPEN / 1 DEFERRED**.

| Risk / AC | Changed behavior and dependencies | Exact command/source/platform | Expected positive / negative | Actual result and evidence | Status / invalidation rationale |
|---|---|---|---|---|---|
| AC1 / B6 | bounded overlay replacement; `overlay-block-replace.py`, recovery direct legacy fixtures | `test-cli-flow-recovery.sh --only legacy`; T28 source on Windows Git Bash | bounded recognized span passes; ambiguity refuses zero-write | `t28-legacy-diagnostic.log`; production/helper dependencies unchanged afterward | REUSED — PASS |
| AC2 | settings source/ownership; `settings-json-merge.py`, wire fixtures | T26 `t26-wire-hooks.log`, Windows Git Bash | custom/CLI settings preserved; malformed input red | wire/settings 36/36; dependencies unchanged after T26 | REUSED — PASS |
| AC3 / B3-B4 | ownership, complete plan and final verification | T47 T20 current-source convergence complete/8 verified; prior T37/T38 negative evidence | current positive composition PASS | T46 changes lazy bootstrap orchestration; fresh negative-path closure awaits T22 review; no claim those negatives reran | OPEN |
| AC4 / B5 | exact dedicated Flow hook and matcher isolation; hook-intent/settings fixtures | T26 U14 + `t26-wire-hooks.log`, Windows Git Bash | exact Flow+CLI entries; duplicate/lookalike/widening red | focused U14 1/1 and wire/settings 36/36; exact parser inputs unchanged | REUSED — PASS |
| AC5 / N2 / S2 | three independent no-op recoveries | T47 T20, Windows Git Bash; final-source dependency recorded in gate report | all three zero changed targets/copies, receipt and manifest mtimes stable; mutation changed 1/refusals 2 | PASS for S2 current-source no-op; collision/bootstrap negative review remains under AC3/AC12 | PASS (scoped S2) |
| AC6 | one Stop transcript read; `hooks/handlers/stop.py`, fixture handler tests | T5 evidence plus stopped current-prefix log; Windows | one read with final-assistant and corrupt-input controls | Stop implementation unchanged; affected fixtures passed before the stopped prefix reached later phases | REUSED — PASS |
| AC7 | compact carriers and host-delivered context | T7 static evidence; supported-host telemetry unavailable | deterministic carrier behavior retained; same-host input decreases | later carrier text changed and five-provider delivered-token telemetry is unavailable | DEFERRED |
| AC8 / B7 / S3 | executed diagnosis/actions/artifacts; lane fixture, router, assessor, carriers | `t21-lane.log` 12/12 at post-T18 source, Windows Git Bash | ordinary lightweight; sensitive full; three mutations rejected | executed artifact/relay counts and extra-relay/extra-artifact/skip-diagnosis controls passed; dependencies unchanged | REUSED — PASS |
| AC9 / B1-B2 / N1 | complete validator identity and trusted signer; validator runner/evidence/pre-commit | `t21-validator.log`, Windows Git Bash | direct mint/substitution/state mutations red; unavailable authority reruns | focused validator matrix passed; validator sources unchanged; Windows authority remains safely unavailable | REUSED — PASS |
| AC10 / B8 | task/outcome temporal linkage and honest benchmark labels | `t21-window.log`; `t21-benchmark.log`, Windows | exact outcome/task link passes; generic/mixed history red; unavailable metrics labeled | window focused proof and benchmark 5/5 passed; source dependencies unchanged | REUSED — PASS |
| AC11 / S1 | CLI/user preservation | T47 T20 current-source fixture and prior T37 evidence | synthetic CLI/user preservation PASS | actual full CLI install/update/recover absent; do not promote fixture evidence to current-CLI verification | OPEN; real CLI DEFERRED |
| AC12 | canonical/fallback and ownership bootstrap convergence | T34/T36 prior focused proof; T47 current-source convergence and no-ops | normal canonical/mirror convergence PASS | T46 lazy baseline changes orchestration; prior bootstrap proof is dependency-limited pending T22 assessment | OPEN |
| T24-T30 support | real-Git fixture, selectors, batched manifests, timeout semantics | T24-T30 focused logs and commits on Windows | named positive/negative groups pass without broad-prefix replay | task-specific focused proofs retained; no dependency change for their isolated assertions | REUSED — PASS |
| T31-T32 liveness | heartbeat and single composed launch/status | T31 retained evidence; T32-final-composition.log current 9/9, rc0, 85.777s | coupled failure/missing/partial controls pass; survivors 0 reported | scoped composition closure; not every platform/process-tree path | PASS |
| T33 / B6 | scoped ledger, phase visibility, fail-closed missing/zero/crash/timeout | T33 6/6 + carriers 15/15 + real selected phase 8/8 at `fb156aa` | scoped proof stays non-attesting; every abnormal phase red | all focused checks passed; real phase emitted START/END/tag/33s/rc0/120s | NEW — PASS |
| Current integrity/safety | committed manifests and normal commit checks | `008ade7`: hook 209/209, managed 372/372, normal precommit 18.3s; executor report | current manifests and commit gate PASS | no claim new standalone full preflight/release CI or platform proof ran | PASS (scoped) |
