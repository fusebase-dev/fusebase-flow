# Verification gate — flow-performance-and-recovery-hardening

**Linked spec:** `docs/specs/flow-performance-and-recovery-hardening/spec.md`
**Linked tasks:** `docs/specs/flow-performance-and-recovery-hardening/tasks.md`
**Gate task:** T10
**Report path:** `docs/specs/flow-performance-and-recovery-hardening/gate-report.md` (filled from `templates/gate-report.md`)
**Smoke threshold:** S1–S3 each reproduced 3/3 PASS; persist each attempt, investigate any failed-then-passed result
**Rollback surface:** code-only framework/template changes; no migration, secret, sidecar, app, or cross-app contract

## Acceptance-criterion → task mapping

| AC | Implemented in | Evidence |
|---|---|---|
| AC1 | T1 | focused overlay mutation/round-trip fixtures |
| AC2, AC4 | T2 | settings ownership/config/ordering/idempotence matrix |
| AC3, AC11 | T3, T9 | A2 surface/legacy-intent matrix, prevalidation/fault/interruption/retry fixtures, recovery E2E, disposable CLI attempt |
| AC5, AC12 | T4 | skill/agent and whole-recovery no-op/one-drift/fallback tests + all target manifests |
| AC6 | T5 | native Stop fixtures + read-count benchmark |
| AC8 | T6 | path-router unit tests plus separate semantic-assessment/workflow artifact evidence under A4 |
| AC7 | T7 | invariant inventory + provider bootstrap + delivered-context measurement |
| AC9 | T8 | actual pre-commit counted-validator reuse/rerun, forgery/staleness/concurrency matrix + live safety checks |
| AC10 | T9 | temporal-linkage fixtures + benchmark report |
| AC1..AC12 | T10 | integrated suite and adversarial review |

## Required gate-report fields

Per `policies/gate-contracts.yml: gate_report`; produce the report from `templates/gate-report.md`.

## Commands

| Layer | Command / condition |
|---|---|
| Targeted | each T-task runs its named focused test(s) |
| Registered suite | `bash hooks/tests/run-tests.sh` once after final source state |
| Preflight | `bash hooks/local/preflight.sh` |
| Mirror integrity | `bash hooks/local/mirror-skills.sh --check` plus agent/managed/hook manifest checks from preflight |
| Module size | `bash hooks/local/check-module-size.sh --all` |
| Whitespace/markers | focused recovery and overlay tests; no unbalanced Flow/CUSTOM/FLOW:PRESERVE markers |
| Secrets | staged secret scanner through the normal pre-commit gate; detected values never printed |
| Protected paths | exact staged diff + digest-bound bootstrap approval for `FLOW_RULES.md`, policies, handlers/shared paths if touched |
| CLI ownership | before/after hashes and parsed semantic comparison for every fixture CLI-owned surface |
| Current CLI | bounded disposable project refresh attempt; no workspace update |

## Worker-undisturbed and ownership boundaries

| Boundary | Required result |
|---|---|
| Configured worker-undisturbed paths | none |
| `.claude/hooks/**` | zero byte change |
| CLI provider skills and app agents | zero byte change |
| `fusebase.json`, `.mcp.json`, `.codex/config.toml` | zero semantic/byte change unless the fixture simulates CLI writing them before Flow recovery |
| Consumer settings, permissions, custom hooks | preserved; only exact Flow-owned hook entries repaired |
| Flow provider mirrors | exact canonical bytes; zero drift |
| Pre-existing `docs/wasted-code/` | untouched and excluded from all commits |

## Smoke contract

Evidence directory: `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/`.
Mode: record-then-read; each scenario runs in a disposable directory with a hard timeout and writes its result before inspection.

| ID | Operator-facing scenario | Visible success | Ground truth | Adversarial falsifier | Evidence |
|---|---|---|---|---|---|
| S1 | Run recovery on CLI-overwritten fixture with valid prior intent | report says complete; Flow hooks/overlays restored | parsed settings + exact hashes/markers after recovery | trailing CLI instruction missing, MCP list changed, duplicate hook, or CLI byte drift | `S1-recovery.log`, `S1-state.json` |
| S2 | Run recovery again on the restored fixture | report says no repair needed; timing distribution reported without a hard speed threshold | zero changed recovery-target mtimes/hashes/copies, including agent manifests/settings receipts/intent/backups | any unchanged destination or manifest rewritten | `S2-noop.log`, `S2-mtimes.json` |
| S3 | Run an ordinary low-risk diagnosis→fix routing fixture and a sensitive fixture | ordinary case stays one-pass lightweight; sensitive case escalates with named trigger | router output + evidenced semantic assessment + workflow fixture artifact/decision/relay inventory | ordinary case creates Full pack/relay or sensitive case enters lightweight | `S3-lanes.log`, `S3-artifacts.json` |

### S1 — CLI-preserving recovery

1. Create a disposable fixture carrying named CLI/user sentinels, external suffix instructions, customized MCP list, permissions/custom hooks, and a valid same-project enabled intent.
2. Simulate CLI overwrite only on documented shared provider files.
3. Run recovery bounded to 60 seconds.
4. Read persisted recovery status, settings structure, overlay markers, and hashes once.

Pass: complete status/exit 0 for recoverable fixture; every authorized surface restored exactly once; every external/CLI/user byte and semantic value preserved. Separate A2 negative fixtures assert failed/exit 2 with zero writes before apply, partial/exit 1 after injected failure, retained recovery material, missing-provider uncertainty, no Git activation from legacy settings intent, and convergent retry.
Insufficient: exit code 0 or file presence without parsed/hash comparison.

### S2 — no-op recovery

1. Record hashes and mtimes after S1.
2. Run the same recovery bounded to 60 seconds.
3. Compare hashes, mtimes, copy count, and status.

Pass: no target/manifest/backup/receipt/intent/Git-hook writes and no CLI/app validator execution. Separate new run diagnostics may be written and are identified outside the repair-target inventory.
Insufficient: “0 drift” text while mtimes changed.

### S3 — consumer lane behavior

1. Route a small unknown-cause issue through bounded read-only diagnosis that resolves to a reversible, security-neutral fix.
2. Evaluate fixtures for auth/permissions, data/schema, public contract, protected path, cross-cutting architecture, and release/deploy risk through A4's semantic assessor, including sensitive behavior in an ordinary source filename.
3. Inspect mechanical matches, evidenced semantic declarations, final lane, and actual workflow artifact/decision/relay inventory. Invalid router input or unresolved assessment never implies Lightweight.

Pass: ordinary fixture uses lightweight; every sensitive fixture uses Full with a named trigger.
Insufficient: prose claim without structured route/artifact evidence.

## Performance evidence

| Measure | Required report |
|---|---|
| Mirror | baseline/new wall time, destinations copied, target/manifest mtimes |
| Stop | 1/10/30 MiB wall time, transcript read count/bytes |
| Startup | paired actual host-delivered context per same scenario/model/settings; per-host decrease required for verified coverage; character-only estimate or missing telemetry = UNVERIFIED host coverage, never PASS |
| Workflow | tool calls, operator decisions, role relays, artifacts for representative ordinary/sensitive changes |
| Validation | command identity, runs/duration, exact state binding, reuse/mismatch outcome |

No fixed timing threshold blocks the gate. Functional no-op conditions—zero copies/writes and one transcript read—do.

## Adversarial review

After T10 evidence exists, GPT-6 Astra Medium reviews the entire diff and gate evidence for:

- CLI/user ownership loss and incomplete recovery;
- fail-open intent/config/marker parsing;
- duplicate hooks or validation;
- lost safety invariants during compaction;
- lane misrouting on sensitive changes;
- stale validation evidence;
- false performance or window-specific claims.

Any blocker returns to a new implementation task/commit and reruns affected checks plus T10.

## Rollback

Before publication, revert individual T-task commits in reverse dependency order with `git revert <sha>`. After any recovery slice revert, rerun S1 to verify prior known-good recovery. No database, app deployment, or remote rollback applies.

## Cross-artifact gate

- Every AC maps to a task and evidence row.
- Every locked A-decision is cited by at least one task.
- All Q-A..Q-F are resolved.
- Every implementation task T1–T9 has one SHA; T10 has a report only; T11 is pending until review.
- AC7 records host-by-host verified/UNVERIFIED coverage; any unavailable host remains an explicit residual risk, not a claimed measured improvement.
- No TODO/FIXME/WIP in the ticket diff.
- Spec remains DRAFT until T11.
- CLI-owned byte/semantic comparison passes.
- GPT-6 Astra final review has zero open blockers.
