# Verification gate - flow-performance-and-recovery-hardening

**Status:** BLOCKED at T26 U14 fixture; T25 timeout 23/23 and bounded engines rc0 permit its commit
**Starting source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Linked tasks:** `tasks.md` T11-T26
**Review findings:** `adversarial-review.md` B1-B8, N1-N2
**Gate task:** T21, report-only after T26
**Independent review:** T22, zero blockers required
**Closeout:** T23, docs-only
**Smoke threshold:** S1-S3 each requires three independent process executions; three assertions from one run are not three repetitions
**Rollback:** code-only framework/template changes; no migration, secret, app deploy, or production target

## AC and review mapping

| Requirement | Implementation | Required evidence |
|---|---|---|
| AC1 / B6 | T17 | bounded legacy span; unrelated/custom suffix refusal; exit 2 zero-write; marker round-trip |
| AC2 | T14 | complete settings/config plan rejects malformed/unavailable input before target writes |
| AC3 / B3-B4 | T13-T15 | ownership matrix; atomic retained originals; interruption/retry ledger; authoritative provider/Git verification |
| AC4 / B5 | T15-T16 | exact handler parsing; dedicated Flow blocks; custom order/matcher/timeout/scope preservation |
| AC5 / N2 | T13, T20 | collision preservation plus three independent write-mode no-op snapshots/counts |
| AC6 | retained T5 | Stop fixture regression and one-read 1/10/30 MiB evidence |
| AC7 | retained T7 | semantic inventory; host-by-host telemetry status, with unavailable hosts UNVERIFIED |
| AC8 / B7 | T18 | executed diagnosis/action/artifact records; extra relay/artifact/skipped diagnosis mutation controls |
| AC9 / B1-B2/N1 | T11-T12 | ignored/symlink/env/wrapped tool identity; direct-mint/substituted-runner rejection; Linux-portable fixture |
| AC10 / B8/N2 | T18-T20 | per-conclusion task/commit linkage; mixed-history tests; observed workflow/write metrics |
| AC11 | T13-T15, T20 | CLI/user zero-change hashes/semantics; actual CLI install/update/recover stays UNVERIFIED unless executed |
| AC12 | T13-T15 | canonical source precedence, verified snapshot fallback, zero mirror/manifest drift |
| T21 fixture contract | T24 | real disposable Git repo/identity; focused T15 path rc0; exact Git verification; CLI/user sentinels; permits fixture-only commit |
| Registered wrapper liveness | T25 | timeout selftest 23/23; bounded U16/U17/U18 rc0; preserve failed wrapper evidence |
| Stop fixture / wrapper closure | T26 | exact Flow identity/count across all Stop blocks; unique CLI entries and matcher isolation preserved; full wrapper PASS |
| B1-B8/N1-N2 closure | T21-T22 | final report plus independent repeated Astra review with zero blockers |

## Required commands and conditions

| Layer | Command / result |
|---|---|
| Validator identity/trust | `bash hooks/tests/test-validator-evidence.sh`; `bash hooks/tests/test-validation-instructions.sh`; Linux/CI same validator test where available |
| Recovery ownership/preflight/verification | `bash hooks/tests/cli-flow-recovery-direct.sh`; `bash hooks/tests/cli-flow-recovery-e2e.sh`; `bash hooks/tests/test-hook-wiring-intent.sh` |
| Real Git fixture | `FFCF_T15_ONLY=1 bash hooks/tests/test-cli-flow-recovery.sh` PASS at T24; terminal wrapper proof owned by T26 |
| Timeout/recovery liveness | `bash hooks/tests/test-health-check-timeout.sh`; bounded U16/U17/U18 rc0 before T25 commit; each engine call bounded below outer watchdog with cleanup margin and durable phase identity |
| U14 fixture/status | focused U14 asserts exact runtime `Fusebase Flow stop hook…` and rejects mojibake; wire-hooks PASS; full `bash hooks/tests/test-cli-flow-recovery.sh` PASS before T26 commit; production edit restricted to status literal |
| Hook matcher ownership | `bash hooks/tests/test-wire-hooks-add-beside.sh`; exact/mixed/restrictive-first matrix PASS |
| Workflow behavior | `bash hooks/tests/test-lane-workflow.sh`; real fixture actions plus all mutation controls PASS |
| Temporal evidence | `bash hooks/tests/test-wasted-effort-windowing.sh`; old-footer/SHA/mixed-report cases PASS |
| Consumer benchmark | `bash hooks/tests/test-flow-consumer-benchmark.sh`; read-only/write-mode labels correct |
| Registered suite | `FF_FULL=1 FFHC_HEARTBEAT_SECS=30 bash hooks/tests/run-tests.sh` once on final T26 source |
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

Evidence directory remains `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/`. Existing evidence is provisional and retained; T21 replaces claims only after new attempts. Each attempt has a unique ID/timestamp, hard timeout <=60 seconds, independent process execution, saved result, and post-run inspection.

| ID | Scenario | Visible outcome | Ground truth | Falsifier |
|---|---|---|---|---|
| S1 | Recover a CLI-overwritten fixture with valid prior surface intent; also execute named negative cases | complete only for fully recoverable state; partial/failed otherwise | parsed settings/overlays/provider/Git state; hashes; plan/applied/verified/pending ledger; retained originals | unowned overwrite, suffix loss, duplicate/widened hook, missing surface, false exit 0, or inaccurate inventory |
| S2 | After convergence, run full write-mode recovery three independent times | each reports no repair required | per-attempt bytes/mtimes/write/copy counts for every repair target and manifest | any write/copy/mtime change; a read-only `--check` substituted for write mode; three assertions from one process |
| S3 | Run ordinary and sensitive fixture workflows three independent times | ordinary executes one-pass lightweight; sensitive stops in Full | actual diagnosis/action record and created artifact/relay inventory | hardcoded count, skipped diagnosis, extra relay/artifact, sensitive lightweight, or mutation surviving |

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
- UI/client behavior: N/A;
- platform auth/session/permission problem-catalog item: none; domain N/A.

## Gate completion rules

- T11-T20 and T24-T26 each have one exact SHA and passed focused checks. T25 may commit after timeout 23/23 and bounded engine proof; full wrapper advanced to 33 PASS then failed the independent U14 stale assertion.
- T26 requires exact multi-block Stop assertions and full registered recovery wrapper PASS. Keep the historical stall and U14 failure evidence with their distinct explanations.
- Dependency tail: T20 -> T24 -> T25 -> T26 -> T21 -> T22 -> T23. T21 resumes only after T26; it replaces the provisional T10/T21-blocked report and does not commit source.
- Any failed-then-passed check is investigated and reproduced; no silent PASS.
- Every B1-B8/N1-N2 row has direct evidence or remains open.
- Spec remains DRAFT through T21.
- T22 reviews the whole correction diff/evidence and reports zero blockers before T23.
- T23 is the only final docs closeout commit; no deploy/publication command runs.
