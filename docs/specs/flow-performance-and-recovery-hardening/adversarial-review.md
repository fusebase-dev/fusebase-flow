# Adversarial review - flow-performance-and-recovery-hardening

**Reviewer:** GPT-6 Astra, whole-implementation review
**Reviewed source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Verdict:** CHANGES REQUIRED
**Approval:** withheld; zero-blocker approval was not reached
**Findings:** 8 blockers, 2 non-blockers
**Gate effect:** supersedes the provisional T10 technical PASS; spec remains DRAFT

## Blockers

| ID | Finding | Compact evidence | Corrective proof required |
|---|---|---|---|
| B1 | Validator identity is incomplete. Ignored validator dependencies/inputs and symlink-target changes are excluded, arbitrary validator-affecting environment is filtered out, and only the first executable is hashed. Reuse must be complete or unavailable. | `hooks/local/lib/validator-evidence.py:161-169` enumerates tracked plus non-ignored untracked files; `:148-149` records only symlink text; `:184-191` allowlists environment; `:194-205` hashes one command token. | Ignored dependency/input, symlink target, custom environment, and wrapped/multi-tool toolchain mutations force rerun; inability to prove complete identity disables reuse. |
| B2 | Public `begin` plus `finish` can mint a signed success without validators running. The trusted runner must own execution and signing; direct mint and substituted runner paths must fail. | `hooks/local/lib/validator-evidence.py:247-275` exposes token begin/finish and signs success without child-process evidence; `hooks/local/run-validators.sh:33-48` runs validators outside the signer. | One trusted execution/signing boundary; no public success-mint API; failed, skipped, direct-mint, and substituted-runner cases cannot create reusable evidence. |
| B3 | Recovery overwrites unowned colliding skill mirrors, agent mirrors, commands, and health-skill targets without ownership classification, retained originals, or atomic replacement. | `hooks/local/mirror-skills.sh:233-240`, `hooks/local/mirror-agents.sh:95-102`, and `hooks/local/post-fusebase-update.sh:503-510,534-545` copy over differing targets. | Per-target ownership classification; unowned collision and symlink remain untouched with partial/exit 1; owned repair is atomic and retains the original; interruption is retryable. |
| B4 | Recovery lacks a complete preflight and authoritative final verification. Malformed event arrays may still return success; intent detection is substring-based; progress can reset or be reported ahead of completed work; missing providers and Git intent/install proof are insufficient. | Preflight checks only broad prerequisites at `hooks/local/post-fusebase-update.sh:143-169`; malformed events warn/continue at `hooks/local/fusebase-flow-overlays/settings-json-merge.py:267-275,316-335`; progress is static/in-memory at `hooks/local/lib/flow-recovery-plan.sh:44-64`; final success is asserted at `hooks/local/post-fusebase-update.sh:597` without parsed end-state verification; intent presence uses grep at `hooks/local/lib/hook-wiring-intent.sh:214-219`. | Whole-plan validation before target writes; invalid plan exit 2 with zero writes; authoritative parsed/hash post-apply verification; truthful retained interruption/retry ledger; verified provider backup restore or explicit uncertainty; per-surface Git intent and installed-hook proof; partial exit 1 when incomplete. |
| B5 | Matcher ownership uses `hooks/handlers/` substring recognition and can widen custom or mixed blocks, changing custom command scope. | `hooks/local/fusebase-flow-overlays/settings-json-merge.py:212-232` treats any command containing that substring as Flow-owned before widening; intent uses the same substring at `hooks/local/lib/hook-wiring-intent.sh:19-24,214-219`. | Exact Flow command recognition and dedicated Flow-block isolation; preserve custom block order, matcher, timeout, and scope; cover substring lookalike, mixed block, and restrictive-first dedup cases. |
| B6 | Markerless overlay migration claims from the Flow heading through EOF and can delete an unrelated suffix. | `hooks/local/fusebase-flow-overlays/overlay-block-replace.py:57-88` returns `len(data)` for a markerless legacy span. | Prove a bounded legacy span or refuse ambiguous markerless input with zero writes; cover unrelated suffix and custom-heading suffix. |
| B7 | The workflow fixture hardcodes decisions, relays, artifacts, and diagnosis instead of executing them. S2 labels three assertions from one run as three repetitions. | `hooks/tests/lane-workflow-fixture.py:58-88` assigns outcomes; `hooks/tests/test-lane-workflow.sh:27-116` asserts those assignments. `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/S2-noop.log` records three different assertions as attempts. | Execute fixture actions and create/inspect real artifacts, or label simulation and keep coverage UNVERIFIED. Record three independent no-op recovery attempts. Mutation must catch an extra relay, extra artifact, and skipped diagnosis. Correct performance claims from observed actions. |
| B8 | Windowing links an entire historical artifact/body when the file has a current cosmetic edit or mentions a selected SHA, so old outcomes can affect the current window. | `hooks/local/find_wasted_effort/windowing.py:39-53` promotes the whole artifact by last commit or any SHA reference. | Outcome/task-specific linkage; mixed outcomes stay historical unless each conclusion is linked; cover old outcome plus current footer and mixed reports. |

## Non-blockers

| ID | Finding | Evidence / correction |
|---|---|---|
| N1 | Validator fixture assumes `cygpath`; portability is incomplete. | `hooks/tests/test-validator-evidence.sh:32,51,70`. Make conversion conditional and exercise the matrix on Linux where available. |
| N2 | The benchmark calls `mirror-skills.sh --check` and reports zero writes, but `--check` is read-only. | `hooks/tests/benchmark-flow-consumers.py:157-169`. Label this read-only integrity evidence and use repeated write-mode recovery with byte/mtime/write evidence for no-op claims. |

## Security and CLI safety

| Surface | Review result |
|---|---|
| Validation authority | BLOCKED by B2. The receipt can assert successful lint/typecheck without trusted execution. Secret and protected-path checks remain separate live pre-commit steps, but their presence does not authenticate validator success. |
| Hook enforcement scope | BLOCKED by B4-B5. Substring ownership can both miss authoritative installed-state proof and widen custom command scope. |
| Consumer/CLI bytes | BLOCKED by B3-B4. Unowned collisions can be overwritten, and the final status does not prove every provider/Git surface. |
| Platform auth/session/permissions | N/A. This review found no platform auth, session, or permission behavior change; no problem-catalog item is warranted for that domain. |
| Secrets/production/deploy | No secret, database, app deploy, or production mutation is part of the correction plan. Publication/deploy remains N/A. |

## Residuals retained after correction

| Residual | Status |
|---|---|
| Actual host-delivered startup telemetry for Codex, Claude Code, Cursor, Copilot/VS Code, and Gemini | UNVERIFIED |
| Three real-symlink controls on MSYS | UNVERIFIED until Linux/CI executes real symlinks |
| Windows validator-authority ACL/isolation | UNPROVEN; reuse unavailable unless independently proved |
| Actual CLI install/update/recover comparison | UNVERIFIED |
| UI/client behavior | N/A |

## Required disposition

Implement T11-T20 from `tasks.md`; rerun the report-only technical gate at T21; repeat the independent Astra review at T22. T23 may close the spec only after T22 reports zero blockers.
