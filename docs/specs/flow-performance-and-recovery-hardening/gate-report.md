# Gate report - flow-performance-and-recovery-hardening (T10 superseded)

**Status:** CHANGES REQUIRED; prior technical PASS is superseded/provisional
**Slug:** `flow-performance-and-recovery-hardening`
**Task range:** T1..T10
**Reporting session:** AI Developer under Fusebase Flow v4.14.1, FR-01..FR-27
**Date:** 2026-09-06
**Baseline:** `ef6cac3`
**Final source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Independent review:** `adversarial-review.md` - 8 blockers, 2 non-blockers; zero-blocker approval withheld
**Correction chain:** T11-T20 implementation; T21 report-only gate; T22 repeated Astra review; T23 docs-only closeout

All PASS labels below record the provisional T10 fixture/check results at `2217a9c`; they do not establish current gate satisfaction. B1-B8 show that several tests asserted incomplete or simulated evidence. Existing counts, SHAs, timestamps, and residual observations are retained as historical facts.

## 1. Provisional T10 per-task commit table

| Task | Title | Commit SHA | Started (UTC) | Committed (UTC) | Wall-clock | Lint/typecheck | Ownership boundary | Focused evidence |
|---|---|---|---|---|---|---|---|---|
| T1 | Exact Flow overlay replacement | `c158b451f52c89190b6be745b4340f4cbf3a75ea` | UNAVAILABLE | 2026-09-05 19:22:24 | UNAVAILABLE | PASS | PASS | exact-span CRLF/Unicode/preserve/ambiguity/atomicity matrix |
| T2 | Ownership-safe unique settings recovery | `5bf89f8b0cf9bc2519f3693702372f708cfbbe7e` | UNAVAILABLE | 2026-09-05 19:34:05 | UNAVAILABLE | PASS | PASS | settings ownership/config/ordering/idempotence matrix |
| T3 | Valid prior hook intent restoration | `0829d169d1ddb4a39472f1836260def04e5ae4b8` | UNAVAILABLE | 2026-09-05 19:56:55 | UNAVAILABLE | PASS | PASS | intent 30/30; recovery and fault/retry fixtures PASS |
| T4 | Zero-write no-op recovery | `1b44a95dd794bc6384d85eadeb0dc95dca5e05df` | UNAVAILABLE | 2026-09-05 20:22:53 | UNAVAILABLE | PASS | PASS | recovery 39/39; full-corpus mirror no-op and one-drift repair PASS |
| T5 | One-read Stop transcript processing | `598c6670195bf2d0e95ee90abcc8a1ad23f0547f` | UNAVAILABLE | 2026-09-05 20:24:55 | UNAVAILABLE | PASS | PASS; protected approval consumed | Stop fixtures/read-count PASS; 1/10/30 MiB benchmark captured |
| T6 | Diagnosis-first lightweight consumer flow | `0db37fc1f436e6cdbf90dd8da991e1edfa459c39` | UNAVAILABLE | 2026-09-05 20:39:51 | UNAVAILABLE | PASS | PASS; protected approval consumed | router, carrier consistency, and lane workflow 9/9 PASS |
| T7 | Compact startup carriers | `7ab052af5a372017ad997b0e2749033bed4f025f` | UNAVAILABLE | 2026-09-05 21:00:15 | UNAVAILABLE | PASS | PASS; protected approval consumed | semantic inventory, provider bootstrap, prohibitions, overlay recovery PASS |
| T8 | Exact-state validator evidence | `b581d71f6a953cae5d2bf77d90fb6384a7a2dcf6` | UNAVAILABLE | 2026-09-05 21:20:06 | UNAVAILABLE | PASS | PASS; protected approval consumed | actual pre-commit counted-validator matrix and recovery hints PASS |
| T9 | Window-honest measurement | `ff941eafb1618bd061ce4ee8a6dd660304f02153` | UNAVAILABLE | 2026-09-05 21:31:49 | UNAVAILABLE | PASS | PASS | five-row temporal fixture, benchmarks, and disposable update-only CLI probe reported PASS |
| T10 | Integrated verification gate | report only | UNAVAILABLE | — | UNAVAILABLE | PASS | PASS | registered suite 1,274/1,274; smoke files labeled S1-S3 as 3/3 |

Task start timestamps were not durably captured, so per-task wall-clock, net active time, wait time, and average task time are `UNAVAILABLE`; commit timestamps are Git-recorded facts. The baseline-to-final-source evidence window was 6:34:38 (`ef6cac3` at 2026-09-05 18:59:28 UTC through `2217a9c` at 2026-09-06 01:34:06 UTC) and is not presented as active development time.

### T10 fix-forward commits

| Commit | Reason | Verification |
|---|---|---|
| `b42a2038d9c50308d894418318561b4ae88f3904` | Restored compacted carrier invariants exposed by the first integrated run | affected focused suites PASS; full suite rerun |
| `e300953de504633a03c071514b1ca17babad7830` | Restored preflight carrier contracts and the managed manifest | recovery 39/39 and carrier preflight PASS; full suite rerun |
| `2217a9c631300e510b18437548ed4bccb5f31036` | Restamped hook and managed integrity manifests after final-source verification | preflight 0 errors/0 warnings; hook manifest 202/202; managed manifest 358/358; normal pre-commit PASS; final full suite PASS |

These are source repair commits discovered during T10. The T10 report and smoke evidence are retained as provisional inputs. T11-T20 own corrections; T23 owns final closeout documentation after T21-T22.

## 2. Test counts

| Layer | Before | After | Delta | Evidence |
|---|---:|---:|---:|---|
| Registered suite, all fixture types | UNAVAILABLE | 1,274 | UNAVAILABLE | baseline commit has no `state/audit/hook-test-results.md`; final artifact records the aggregate without unit/integration/E2E taxonomy |
| Unit | UNAVAILABLE | UNCLASSIFIED | UNAVAILABLE | registry does not encode this taxonomy |
| Integration | UNAVAILABLE | UNCLASSIFIED | UNAVAILABLE | registry does not encode this taxonomy |
| E2E | UNAVAILABLE | UNCLASSIFIED | UNAVAILABLE | registry does not encode this taxonomy |

Final command: `FF_FULL=1 FFHC_HEARTBEAT_SECS=30 bash hooks/tests/run-tests.sh`.

Final durable result at `state/audit/hook-test-results.md`:

```text
Run: 2026-09-06T03:58:24Z
Total: 1274 — PASS: 1274 — FAIL: 0
```

Three Linux-only symlink controls were explicitly skipped because this MSYS host's `ln -s` copied instead of creating a symlink:

| Fixture | Control | Coverage |
|---|---|---|
| `test-msys-tree-cleanup.sh` | `ac4-cleanup-refuses-symlink-targets` | UNVERIFIED on this host; Linux/CI proof required |
| `test-upgrade-repair-managed.sh` | `ac3-repair-refuses-symlinked-destinations` | UNVERIFIED on this host; Linux/CI proof required |
| `test-upgrade-repair-managed.sh` | `m16-a-symlink-cannot-stand-in-for-a-bound-layer-artifact` | UNVERIFIED on this host; Linux/CI proof required |

The suite records these controls as named PASS rows because expected platform skip behavior was correct. They are not claimed as functional symlink proof.

## 3. Lint, typecheck, and validation ownership

| Check | Actual | Result |
|---|---|---|
| Normal pre-commit on final source | exited 0 for `2217a9c` | PASS |
| Lint identity | `python3 validator.py lint` | PASS |
| Typecheck identity | `python3 validator.py typecheck` | PASS |
| Validator executions | 2; 0.806315 s total | PASS |
| Receipt verification | 0.314997 s | PASS |
| Exact-state reuse | authentic matching evidence reused; mismatch/forgery/staleness cases reran or failed closed | PASS |
| Preflight | 0 errors, 0 warnings | PASS |
| Module size | registered `check-module-size.sh --all` phase PASS | PASS |
| Secret scan | normal pre-commit and registered secret-scan phases PASS; detected values never printed | PASS |

Evidence: `state/audit/flow-performance-and-recovery-hardening/consumer-benchmark.json` and `state/audit/hook-test-results.md`.

## 4. Worker-undisturbed and ownership verification

Configured worker-undisturbed paths: none.

| Boundary | Actual | Result |
|---|---|---|
| `.claude/hooks/**` | zero diff from `ef6cac3` to final source | PASS |
| `fusebase.json`, `.mcp.json`, `.codex/config.toml` | zero diff from `ef6cac3` to final source | PASS |
| CLI provider skills and app agents | named recovery fixture hash/semantic comparisons report untouched and explicit CLI ownership attribution | PASS |
| Consumer settings, permissions, custom hooks | parsed recovery matrix preserved non-Flow entries and repaired only recognized Flow entries | PASS |
| Flow provider mirrors | full-corpus check reports 34 canonical skills, 98 materialized mirror files, exact manifests, and zero no-op copies | PASS |
| Protected Flow paths | exact staging and digest-bound single-use bootstrap approval used for every protected commit; approvals consumed | PASS |
| Pre-existing `docs/wasted-code/` | remains untracked and was excluded from every commit | PASS |

## 5. Manifest versions

| Manifest | Field | Before (`ef6cac3`) | After (`2217a9c`) |
|---|---|---:|---:|
| Hook layer | schema version | 1 | 1 |
| Hook layer | asset count | 193 | 202 |
| Managed content | schema version | 1 | 1 |
| Managed content | asset count | 342 | 358 |

Final verification: hook manifest 202/202 MATCH; managed manifest 358/358 MATCH; each manifest self-hash matches.

## 6. Performance and consumer evidence

| Measure | Baseline | Final measurement | Result |
|---|---|---|---|
| Mirror integrity | baseline wall time not durably captured | `mirror-skills.sh --check`: 0.680130 s | READ-ONLY INTEGRITY ONLY; writes/mtimes were not exercised (N2) |
| Stop 1 MiB | — | median 0.041924 s; 1 read; 1,048,576 bytes | PASS |
| Stop 10 MiB | — | median 0.360304 s; 1 read; 10,485,760 bytes | PASS |
| Stop 30 MiB | — | median 1.053562 s; 1 read; 31,457,280 bytes | PASS |
| Startup static carriers | 144,366 chars / 145,388 bytes | 78,469 chars / 78,966 bytes; reductions 45.65% / 45.69% | ESTIMATE ONLY |
| Ordinary workflow | — | scripted fixture reported lightweight; 1 decision; 1 artifact; 0 relays; 2 subprocess calls; 0.374636 s | SIMULATION; actions/artifacts were hardcoded (B7) |
| Sensitive auth workflow | — | scripted fixture reported Full; named `auth` trigger; 1 decision; 5 artifacts; 1 relay; 2 subprocess calls; 0.366162 s | SIMULATION; actions/artifacts were hardcoded (B7) |
| Current CLI update probe | — | CLI `2026.090207.3341`, launcher `2026.081107.4925`, dev; disposable directory validated; exit 0; 72 changed fixture files; 1.126867 s; shared workspace unchanged | UPDATE-ONLY FACT; install/update/recover comparison UNVERIFIED |

Actual host-delivered startup context telemetry was unavailable for Codex, Claude Code, Cursor, Copilot/VS Code, and Gemini under an identical scenario/model/settings pair. AC7 coverage for each host is `UNVERIFIED`; the character/byte reduction is not promoted to a host performance pass. Agent tool-call counts and token counts are also `UNAVAILABLE` because the deterministic workflow fixture records subprocesses and the host exposes neither agent tool nor model-token telemetry.

## 7. Deviations from the locked plan

| Deviation | Why | Authorization/status |
|---|---|---|
| Planning baseline used `ef6cac3` | operator corrected the implementation baseline in the handoff | operator-authorized |
| Three fix-forward commits occurred during T10 | integrated checks found real carrier/preflight/manifest regressions; affected checks and the full suite were rerun after repairs | required by gate contract; covered by existing implementation and protected-path authorization |
| Mirror baseline timing missing | no durable baseline measurement exists | read-only integrity was observed; write-mode zero-write condition remains UNVERIFIED pending T20 |
| Actual startup telemetry missing for five provider hosts | current host does not expose comparable delivered-context telemetry | reported as UNVERIFIED residual, per A5/AC7 |
| Linux symlink controls unavailable | MSYS `ln -s` copied instead of linking | three controls explicitly UNVERIFIED; no false pass claimed |

No production publish/deploy, migration, CLI runtime/SDK/MCP behavior change, app UI change, or real shared-workspace CLI refresh occurred.

## 8. Current gate disposition

| Gate item | Provisional T10 fact | Current result / owner |
|---|---|---|
| AC1 | focused overlay fixtures passed | BLOCKED by B6; T17 |
| AC2/AC4 | settings matrix passed | BLOCKED by B4-B5; T14-T16 |
| AC3/AC11 | recovery fixtures and update-only CLI probe passed | BLOCKED by B3-B4; T13-T15; real install/update/recover UNVERIFIED |
| AC5/AC12 | mirror/recovery checks reported no-op/current | BLOCKED by B3 and N2; T13/T20 |
| AC6 | all measured transcript sizes read once | PROVISIONAL PASS; regress at T21 |
| AC7 | invariant tests passed; static carrier bytes reduced 45.65% | PARTIAL; five-provider delivered-context telemetry UNVERIFIED |
| AC8 | fixture reported ordinary/sensitive lane outcomes | BLOCKED by B7; hardcoded simulation; T18 |
| AC9 | pre-commit matrix reported reuse/rerun behavior | BLOCKED by B1-B2/N1; T11-T12 |
| AC10 | temporal fixture and benchmark reported PASS | BLOCKED by B8/N2 and B7-derived counts; T18-T20 |
| Registered suite | 1,274/1,274 passed at `2217a9c` | PROVISIONAL only; incomplete assertions did not close review findings |
| Preflight/manifests | 0 errors/0 warnings; 202/202 and 358/358 MATCH | PROVISIONAL only; recovery preflight/final verification incomplete (B4) |
| S1 | prior log labeled 3/3 | PROVISIONAL; rerun after T13-T17 |
| S2 | one evidence set carried three different assertions | INVALID repetition claim under B7; T20/T21 require three independent write-mode attempts |
| S3 | same scripted fixture output repeated 3 times | SIMULATION; AC8 coverage UNVERIFIED until T18/T21 executes actions and mutations |
| CLI ownership | named fixture comparisons passed | BLOCKED by collision and final-verification gaps; T13-T15 |
| Adversarial review | GPT-6 Astra whole-implementation review completed | CHANGES REQUIRED: 8 blockers, 2 non-blockers; zero-blocker approval withheld |

Smoke evidence:

- `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S1-recovery.log`
- `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S1-state.json`
- `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S2-noop.log`
- `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S2-mtimes.json`
- `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S3-lanes.log`
- `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S3-artifacts.json`

## 9. Residuals and pending actions

| Item | Owner | Required next action |
|---|---|---|
| B1-B2 validator completeness/authority | T11-T12 | implement and prove complete identity plus trusted runner; otherwise reuse unavailable |
| B3-B6 recovery ownership/correctness | T13-T17 | implement collision, preflight, final verification, exact hook, and bounded overlay corrections |
| B7-B8/N2 evidence validity | T18-T20 | execute real fixture actions, scope outcomes, and run independent write-mode attempts |
| GPT-6 Astra repeated review | T22 | review correction diff and T21 evidence; zero blockers required |
| Five-provider delivered-context measurement | provider-capable verification environment | run identical scenario/model/settings pairs; retain UNVERIFIED until telemetry exists |
| Three symlink controls | Linux/CI | execute fixtures on a host that creates real symlinks |
| Windows validator-authority ACL/isolation | Windows authority-capable environment | prove external authority or keep reuse unavailable |
| Actual CLI install/update/recover comparison | isolated CLI environment | run full comparison; update-only probe is insufficient |
| T23 closeout | AI Developer after T22 | update final docs in one docs-only commit; no production deploy is planned |

## 10. Operator relay

```text
The T10 gate at source 2217a9c is superseded. GPT-6 Astra returned CHANGES REQUIRED with B1-B8 and N1-N2; zero-blocker approval was withheld.

The 1,274/1,274 suite result, source SHAs, and recorded timings remain historical facts. They are insufficient for approval because validator identity/signing, recovery ownership/preflight/verification, hook/overlay ownership, workflow execution, temporal linkage, and write-mode no-op evidence have open defects.

Execute T11-T20 one commit each. T21 replaces this provisional report, T22 repeats the independent Astra review, and T23 performs docs-only closeout only after zero blockers.

Residuals remain UNVERIFIED: five-provider delivered-context telemetry, three real-symlink controls on MSYS, Windows authority ACL/isolation, and actual CLI install/update/recover comparison. UI/client and production deploy are N/A.
```

---
📍 Phase: Plan (corrective implementation)
🎯 Ticket: `flow-performance-and-recovery-hardening`
✅ Historical: T1-T10 source/evidence at `2217a9c`; provisional gate superseded
⏭️ Next: execute T11-T20, then T21 gate and T22 Astra review
