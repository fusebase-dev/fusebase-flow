# Roadmap — MSYS and harness hardening

| Field | Value |
|---|---|
| Status | DRAFT |
| Created | 2026-08-10 |
| Execution rule | Create a slice's implementation artifacts only when that slice reaches its scheduled position (`FLOW_RULES.md:30`). |
| Current blocker | S0 truth correction before any fresh S1 implementation handoff |
| Scope | Framework hooks, tests, approvals, adapters, install/recovery docs; no app/UI/database/account/deploy slices (`docs/constitution.md:16-23,35-37`). |

## Prioritized slices

| ID | Title | Why now | Blocking / blocked by | Lane | Size | Evidence anchor |
|---|---|---|---|---|---|---|
| S0 | Correct active handoff truth | The handoff marks four repair rows fixed without mutation proof or hosted rerun and lists B3, MAJOR 9, and MAJOR 11 as open after their mechanisms closed | Operational prerequisite before any fresh implementation handoff; blocks no code | Lightweight | XS | `docs/tmp/handoff.md:35-45,114-124`; `hooks/tests/cli-flow-recovery-direct.sh:40,46,69,257`; `.github/workflows/fusebase-flow-verify.yml:3,16,21`; `hooks/local/write-bootstrap-approval.sh:113,123,132`; `hooks/local/approve-local.sh:168,218`; `docs/tmp/handoff.md:63-65`; `c11d4e2` |
| S1 | Shared minimal-PATH fixture + mutation discriminator | Current absent-interpreter rows remain green after deleting the missing-interpreter exit; two host-directory masks and an arbitrary cap duplicate the wrong layer | Blocked only by S0; blocks only S2c's interpreter-absence test reuse, not S2a/S2b | Full | M | `hooks/git/pre-commit:93-96`; `hooks/tests/test-bootstrap-exception.sh:255-300`; `hooks/tests/test-git-hooks-smoke.sh:78-130`; `bd47aed`; `800bf36`; `6ffd8da` |
| S2a | Lock trusted Git/Python verdict contract | The trusted-tool definition is unmade: executable presence, version, invocation success, and positive-verdict evidence have different failure surfaces | DESIGN-first; independent of S1; blocks S2b, S2c, and S3 | Full | S | `hooks/git/pre-commit:20,87,213,316,503,678` |
| S2b | Make missing Git fail closed | Missing Git at repository discovery exits 0 before the hook can enforce controls | Blocked by S2a; requires its own missing-Git seam because S1 deliberately preserves Git | Full | S | `hooks/git/pre-commit:20-26` |
| S2c | Enforce positive Python verdicts at all four controls | Any reachable `python3` process can currently supply a successful shell rc without a trusted positive-verdict contract | Blocked by S2a; only interpreter-absence tests are additionally blocked by/reuse S1 | Full | M | `hooks/git/pre-commit:213,316,503,678` |
| S3 | Preflight dependency residual | Preflight silently skips Python checks when Python is absent, so the dependency-preflight requirement remains unsatisfied | Blocks closure of MAJOR 12; blocked by the locked S2a trusted-interpreter decision, not S2b/S2c implementation | Full | S | `hooks/local/preflight.sh:42`; `docs/specs/backlog-triage-execution/plan-review-2.md:69` |
| S4 | Reject self-granting health deferrals | Newline-bearing JSON values split into multiple Bash deferrals, and non-list objects remain iterable | Independent security slice after S1; not blocked by `compat-approval-surfacing` | Full | S | `hooks/local/lib/active-approvals.sh:190,194,196,201`; `docs/backlog/index.md:35`; `382a05e` |
| S5 | Reproduce externally killed harness orphans | External termination has left bounded children running and can corrupt later timing evidence; backlog requires a red reproduction first | Blocks S6a/S6b and S8 timing trust; does not block S7a/S7b | Full | M | `docs/backlog/index.md:32` |
| S6a | Lock SIGINT/EXIT cleanup precedence | Exit 130, INT handling, EXIT cleanup, and sentinel teardown precedence are unmade decisions | DESIGN-first; blocked by S5 retained reproduction; blocks S6b | Full | S | `docs/tmp/handoff.md:118`; `hooks/tests/run-tests.sh:219-270,596-599` |
| S6b | Implement and preserve SIGINT exit 130 | The runner has no INT trap and no explicit 130 result contract | Blocked by S6a; must not run in parallel with S7b because both edit `hooks/tests/run-tests.sh`; does not block S8 | Full | S | `hooks/tests/run-tests.sh:219-270,596-599` |
| S7a | Lock watchdog timeout causal-marker contract | Rc-only classification cannot prove whether the watchdog or the test generated 124/137 | DESIGN-first; independent of S5/S6; blocks S7b | Full | S | `hooks/tests/run-tests.sh:299-310`; `hooks/local/lib/run-with-timeout.sh:49-55` |
| S7b | Implement watchdog timeout causality | Current labels distinguish 124/137 from `crashed` but still infer cause from rc alone | Blocked by S7a; blocks S8; must not run in parallel with S6b because both edit `hooks/tests/run-tests.sh` | Full | M | `hooks/tests/run-tests.sh:299-310`; `hooks/local/lib/run-with-timeout.sh:49-55` |
| S8 | Instrument gate-bound headroom before changing bounds | Ambient load has driven phases to watchdog walls with zero assertion failures; timing cannot be trusted while orphans or timeout-causality ambiguity remain | Blocked by S5 and S7b only; S6b is independent; instrument first; no scalar-only patch | Full | M | `docs/backlog/index.md:33` |
| S9 | Restore adapter overlay-refresh parity | Secondary adapters receive version updates without full marker-anchored overlay refresh parity | Independent after safety/harness cluster | Full | M | `docs/backlog/index.md:19` |
| S10 | Command-gate shell-evasion corpus + decision | Raw-string regex matching permits shell constructions that evade gates; the backlog explicitly forbids a parser patch before the contract is chosen | DESIGN-only slice; implementation blocked on shell-aware-parser vs conservative-deny decision | Full | M | `docs/backlog/index.md:10` |
| S11 | Add maintainer-lane manifest freshness proof | Local full tests can miss a stale managed-content manifest that hosted CI rejects | Independent, known-root, mechanically verifiable maintainer-lane change | Lightweight | S | `docs/backlog/index.md:12`; `eca925b` |
| S12 | Complete existing-CLI install documentation audit | Automation remains parked while the documentation audit is the active T9 scope | Doc-audit slice only; automation remains unscheduled pending separate design | Lightweight | S | `docs/backlog/index.md:13` |
| S13 | Design compat-approval carrier table | Three implementation rounds failed because command, path, and health carriers do not share one gate-judgment input contract | DESIGN-only; all implementation blocked until carrier inputs/verdicts are tabulated and operator-locked | Full | M | `docs/backlog/index.md:34`; `3ae1feb` |
| S14 | Design stable host call identity for approval consumption | True single-use consumption needs one call identity across hook entry points, finalization, TTL, and filesystem atomicity | DESIGN-only; implementation blocked on stable host call ID | Full | L | `docs/backlog/index.md:7` |

## Explicit ordering

| Order | Slice(s) | Exit condition before next order |
|---|---|---|
| 0 | S0 | Active handoff is superseded in place with B3/MAJOR 9/MAJOR 11 closed, MAJOR 10 attributed to `c11d4e2`, and all four `6ffd8da` repair rows marked **INVALIDATED / UNVERIFIED**—not fixed—pending both S1 mutation proof and hosted exact-SHA two-platform GREEN |
| 1 | S1 and S2a | May proceed independently after S0: S1 exits on causal mutation proof plus exact-SHA two-platform GREEN; S2a exits on the operator-locked trusted Git/Python verdict contract |
| 2 | S2b, S2c, S3 | S2b follows S2a and supplies its own missing-Git seam; S2c follows S2a, while only its interpreter-absence tests also await/reuse S1; S3 follows the locked S2a decision and does not await S2b/S2c implementation |
| 3 | S4 | Malformed/newline/non-list deferrals are rejected and transport preserves JSON element boundaries |
| 4 | S5, S6a/S6b, S7a/S7b, S8 | Dependency graph: `S5 → S6a → S6b`; `S7a → S7b` independently; `S5 + S7b → S8`. S6b and S7b both edit `hooks/tests/run-tests.sh` and must run serially, never in parallel; S6b does not block S8. |
| 5 | S9, S11, S12 | Independent maintenance scopes complete without expanding parked automation |
| 6 | S10, S13, S14 | Decision artifacts locked before any parser, carrier, or one-shot implementation task exists |

## Closed findings — no implementation slice

| Finding | Status | Evidence |
|---|---|---|
| B3 production-corpus recovery writer proof | CLOSED | `hooks/tests/cli-flow-recovery-direct.sh:40,46,69,257` |
| MAJOR 9 ordinary push/PR CI | CLOSED by deliberate dispatch/call-only workflow | `.github/workflows/fusebase-flow-verify.yml:3,16,21` |
| MAJOR 11 writers populate `paths` | CLOSED | `hooks/local/write-bootstrap-approval.sh:113,123,132`; `hooks/local/approve-local.sh:168,218` |
| MAJOR 10 comment-blind failing instance | CLOSED by production change, not row-16 repair | `c11d4e2`; `docs/tmp/handoff.md:63-65` |

## Out of scope — do not reopen

| Item | Reason | Evidence |
|---|---|---|
| Per-platform CI tiering | Recorded divergence direction did not justify reducing Windows coverage; it adds ownership governance without demonstrated value | `docs/specs/backlog-triage-execution/plan-review-2.md:7-24,83-91` |
| Suite sharding | Hosted Windows full-suite measurement was 15m17s under a 60-minute wall; no sharding architecture is needed | `docs/tmp/handoff.md:12-28`; run `31431353353` |
| Raising the gate scalar | S8 instruments causes/headroom; a scalar-only change would hide whether liveness or performance produced the bound hit | `docs/backlog/index.md:33` |
| `repair-trust-root-outside-workspace` | Outside the locked same-principal threat model; requires a trust root/signing seam the framework does not have | `docs/backlog/index.md:9` |
| `architect-sub-agent` | No measured Product Owner context-cost defect | `docs/backlog/index.md:14` |
| `role-path-hook-enforcement` | Proposed structural guarantee is fail-open | `docs/backlog/index.md:15` |
| `fr22-predelegation-hook` | No observed escape; shipped matcher surface would leave the proposed hook inert | `docs/backlog/index.md:22` |
| `fr27-prelaunch-nudge` | Warning prose is not a liveness guarantee and cannot be a blocking gate | `docs/backlog/index.md:24` |

## Roadmap controls

- Do not create per-slice specs/tasks/gates before the slice reaches its order; this roadmap owns scheduling, not duplicated requirements (`FLOW_RULES.md:30`).
- Lightweight rows use a change-note only; Full rows use the artifact tier justified when scheduled (`FLOW_RULES.md:28,30`).
- DESIGN-only rows may produce decisions and discriminating evidence, but no implementation tasks until operator lock (`FLOW_RULES.md:18,42`).
- No row authorizes code, test, hook, workflow, policy, release, or deploy changes; implementation authority remains with AI Developer / Deploy roles (`FLOW_RULES.md:40-45`).
