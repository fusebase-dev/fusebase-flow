# Corrective implement handoff - flow-performance-and-recovery-hardening

## Role and stop contract

Operate as AI Developer under Fusebase Flow v4.14.1. Execute T11-T20 serially, one task/commit. Produce T21 as report-only and stop at the gate. Do not perform T22 review or T23 closeout in the implementation session. No production deploy/publication exists.

| Field | Value |
|---|---|
| Starting source | `2217a9c631300e510b18437548ed4bccb5f31036` |
| Review verdict | CHANGES REQUIRED; B1-B8, N1-N2; zero-blocker approval withheld |
| Canonical plan | `docs/specs/flow-performance-and-recovery-hardening/tasks.md` |
| Gate contract | `docs/specs/flow-performance-and-recovery-hardening/verification-gate.md` |
| Review record | `docs/specs/flow-performance-and-recovery-hardening/adversarial-review.md` |
| Final implementation task | T20 |
| Technical gate | T21, no source commit |
| Repeated independent review | T22, GPT-6 Astra |
| Final closeout | T23, docs-only after zero blockers |
| UI/client | N/A |
| Deploy/publication/migration | N/A |

## Mandatory reads

1. `AGENTS.md`; `FLOW_RULES.md` through `## Amendment log`.
2. `flow-skills/communication/SKILL.md`; `flow-skills/role-discipline/SKILL.md`; `flow-skills/role-discipline/references/ai-developer.md`.
3. `flow-skills/comment-policy/SKILL.md`; `flow-skills/module-size-discipline/SKILL.md`; `flow-skills/liveness-discipline/SKILL.md`; `flow-skills/validation-and-qa/SKILL.md`; `flow-skills/code-review/SKILL.md`.
4. Whole `docs/specs/flow-performance-and-recovery-hardening/` pack, including this correction review and superseded gate report.
5. `docs/north-star.md`; `docs/fusebase-cli-edition.md`; `policies/protected-paths.yml`; `policies/approval-policy.yml`; `workflows/greenlight-implement.md`.

## Task chain

| Task | Outcome | Required focused command(s) |
|---|---|---|
| T11 | complete validator-visible identity; portable/no-`cygpath` fixture | `bash hooks/tests/test-validator-evidence.sh` plus Linux/CI execution when available |
| T12 | trusted runner owns validation/signing; direct mint/substitution fails | validator evidence + `bash hooks/tests/test-validation-instructions.sh` |
| T13 | collision-safe atomic skill/agent/command/health repair | recovery direct + E2E |
| T14 | complete recovery preflight and retained progress/retry ledger | recovery direct + E2E |
| T15 | authoritative final provider/settings/Git verification | recovery direct + E2E + hook-intent test |
| T16 | exact Flow hook ownership and isolated matcher scope | wire-hooks + hook-intent + focused recovery |
| T17 | bounded markerless overlay or zero-write refusal | focused recovery overlay matrix |
| T18 | executed lane workflow/actions/artifacts with mutation controls | lane workflow + consumer benchmark |
| T19 | outcome/task/commit-specific temporal linkage | wasted-effort windowing selftest |
| T20 | three independent write-mode no-op attempts and corrected labels | consumer benchmark + recovery E2E |
| T21 | full technical verification and replacement gate report | full registered suite/preflight/manifests/module-size/pre-commit/smoke |

Dependencies and exact files/tests/acceptance/module-size/worker-undisturbed rules are authoritative in `tasks.md`; do not merge tasks or broaden files without updating the plan first.

## Blocker closure contract

| Finding | Required closure |
|---|---|
| B1 | ignored dependency/input, followed symlink target, custom environment, and wrapped toolchain changes rerun; incomplete identity disables reuse |
| B2 | runner executes validators and signs only their observed success; direct mint/substituted runner cannot produce reusable evidence |
| B3 | unowned skill/agent/command/health/symlink preserved as partial; owned writes retained and atomic |
| B4 | whole plan validates before writes; authoritative final verification; truthful interruption/retry/provider/Git inventory and exit 2/1/0 |
| B5 | exact command identity; mixed/custom matcher order/timeout/scope preserved; restrictive-first dedup yields one correct Flow block |
| B6 | markerless suffix/custom heading refuses zero-write unless end boundary is proven |
| B7 | fixture executes diagnosis/action/artifact writes; mutations catch extra relay/artifact/skipped diagnosis; S2 has three process runs |
| B8 | conclusions link by outcome/task/commit; cosmetic footer/SHA mention/mixed report cannot promote history |
| N1 | path conversion conditional; Linux execution where available |
| N2 | `--check` labeled read-only; write/mtime claims use repeated write-mode evidence |

## Git, approval, and protected paths

- Pre-task check: `git status --short`; preserve untracked `docs/wasted-code/` and existing smoke evidence. Never clean/revert them.
- Stage exact T-task paths only; never `git add .`, `git add -A`, `--no-verify`, force push, hard reset, or recursive delete.
- T12 touches protected `hooks/git/pre-commit`. Before commit, stage exact T12 files, mint the digest-bound single-use bootstrap approval under the existing operator authorization, commit, then consume it. Apply the same flow to any later path matching `policies/protected-paths.yml`.
- Existing authorization covers the planned correction scope; it does not cover deploy/publication, new permissions, secrets, or unrelated paths.
- Keep `.claude/hooks/**`, CLI provider skills/app agents, `fusebase.json`, `.mcp.json`, `.codex/config.toml`, custom hooks/settings, and unowned collisions unchanged outside disposable fixtures.
- Preserve the three ignored smoke `.log` files and `docs/wasted-code/`; do not stage them. Generated replacement smoke JSON/logs remain gate evidence unless T23 explicitly closes docs.

## Module and comment discipline

- `hooks/git/pre-commit` starts at 800 lines: T12 must extract the validator-reuse responsibility to `hooks/local/lib/precommit-validator-reuse.sh` and shrink the hook. No exemption/baseline increase.
- `hooks/local/find_wasted_effort/evidence.py` starts at 749 lines: T19 extracts conclusion linking before adding behavior. No exemption.
- Other plan-time line counts are recorded per task; every gated source remains <=800.
- Apply FR-22: only tripwire comments and one-line retrieval pointers. Emit `comment-policy review: applied (FR-22)` in T21.

## Liveness and retry

- Give every long/silent command a <=60-second timeout or the repository bounded runner with durable incremental evidence. Never launch bare.
- Poll process/activity/evidence every 60-90 seconds; a zero-byte transcript is not liveness.
- On an API rate limit, stop and report the exact limit text. Resume only on `try again`.
- For any delegated work explicitly authorized later: maximum 3 attempts/5 minutes with labeled backoff; then successor or `BLOCKED-AT-delegate-no-start`. Verify git state before trusting output.
- A failed-then-passed test/smoke remains flaky until reproduced or explained; record the failed attempt.

## T21 gate execution

Run all task-focused tests, then once on T20 HEAD:

```text
FF_FULL=1 FFHC_HEARTBEAT_SECS=30 bash hooks/tests/run-tests.sh
bash hooks/local/preflight.sh
bash hooks/local/mirror-skills.sh --check
bash hooks/local/check-module-size.sh --all
```

Also run the normal pre-commit path, manifest checks, secret/protected-path controls, exact CLI/user byte/semantic comparison, and S1-S3 from `verification-gate.md`. Replace `gate-report.md`; do not append to the superseded report. Record T11-T20 SHAs/timing and every open residual. Stop after T21 and hand off T22 to GPT-6 Astra.

## Smoke/evidence corrections

- Existing T10 smoke files are retained but provisional.
- S1 reruns after T13-T17 and proves status from parsed/hash final state.
- S2 uses three independent write-mode recovery process executions; each records attempt ID/time/command/exit, target hashes/mtimes, writes/copies, and diagnostic exclusions.
- S3 derives decisions/relays/artifacts/actions from performed work and proves mutation controls. Any scripted-only host boundary is labeled simulation/UNVERIFIED.
- `mirror-skills.sh --check` is read-only integrity evidence only.
- The prior update-only CLI probe stays a historical fact; actual CLI install/update/recover comparison remains UNVERIFIED unless the full isolated chain runs.
- Five-provider startup telemetry, three real-symlink MSYS controls, and Windows authority ACL/isolation remain UNVERIFIED unless directly proved. No platform auth/session/permission problem-catalog item applies.

---
📍 Phase: Implement
🎯 Ticket: `flow-performance-and-recovery-hardening`
⏭️ Next: execute T11 from source `2217a9c631300e510b18437548ed4bccb5f31036`; stop after T21 report
