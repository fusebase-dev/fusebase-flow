# v5.11 — Onboarding consumer review of Flow 5.10 (handoff 2026-10-14)

**Outcome:** ship the verified, narrowed Tier A of the FuseBase onboarding change program as v5.11; park Tier B behind its own evidence gates. **Inputs** (`c:/tmp/flow-review-2026-10-14/`): `handoff.md` (consumer program; source `FuseBase Product and SaaS/outputs/flow-5.10-dual-review-2026-10-14/flow-handoff-2026-10-14.md`); `journal-results.json` (13 per-item verifiers vs HEAD `07417d1`, Claude Code docs fact check, Tier B map); `plan.json` (synthesis O0..O20); `critic.json` (completeness gaps); `astra-premise.md` (GPT-6 Astra premise review F1..F12); `design-{A11,A51,O3,O17}.md` (reworked contracts); `corrections-for-handoff-author.md` (reply to the consumer). **Authorization:** operator chat reply 2026-10-14 (`operator-decisions.md`): A ship as v5.11 with pushes for focused hosted checks · B FR-07 edits to `hooks/git/pre-commit`, `policies/command-policy.yml`, `policies/gate-contracts.yml`, `hooks/handlers/stop.py` + `policies/required-artifacts.yml`, `FLOW_RULES.md` status line at release · C hard deny incl. `--unset`, conditional on Flow's `install-git-hooks.sh` / `post-fusebase-update.sh` invocations staying allowed · D heartbeat ignored via `.git/info/exclude` (T130 writer), not `.gitignore` · E gate rounds share the code-review bound · F computed 1h-TTL break-even · G continue authorized independent work while an answer is pending, not PO sessions · H repeated Stop refusal → warning + unresolved record · I conditional (re-asked: no single-use deploy approval exists) · additions: committed project tool profile for Flow agents (protected under `policies/`), docs-only commit tier with an empty-by-default project allowlist, corrections to the operator. One single-use digest-bound approval per protected commit, minted by the integrator only, consumed after. Release: "tag 5.11 only after the release checks pass and row 13 is in" — read as the v5.9-style pre-tag hosted verification, granted for v5.11 only (reading to confirm). **Review round cap** (declared 2026-10-15, before dispatch): 2 per boundary — per outcome build→review→fix→review, then `BLOCKED-AT-review-budget` to the integrator; premise boundary for O3/O17/tier/profile = Astra round 1 (done) + one re-check of the reworked designs; independent diff review for O1+O2, O3, O17, tier, profile. **Host:** CPU 100% from other sessions, bare `bash -c` start 46 s (2026-10-15) → no local bash phases; Python-only checks locally; bash phases via `fusebase-flow-maintainer.yml` `groups=` dispatch.

| Item | Outcome | Status |
|---|---|---|
| O14 | FR-10 partial-reproduction carriers point at validation-and-qa Sub-mode C | DONE T142 `548f3ee` |
| O18 | ROADMAP / hooks README / smoke template / framework.md truth | DONE T143 `5044c2a` |
| O7 | Gate contract: PASS/FAIL rows with evidence; label hints; `self_attestation` removed; value validator (advisory); new deferred phase `gate-contract` | DONE T144 `5551b26` (FR-07 mint/consume) |
| O11 | Unattended ordering, own-brief re-dispatch, successor brief, grant ≠ approval artifact (scope `command_only_v1` vs `git_push_v1`) | DONE T145 `4b70752` |
| O4 | FR-27 premise corrected: watched from outside; watcher default for wakeable sessions; verified host wake paths only | DONE T146 `cb04186` |
| O13 | Smoke live-run discipline; product criterion binding over harness attribution (Astra F6) | DONE T147 `dbfc515` |
| O16 | token-waste-audit: advisor calls priced (past totals omitted them); wall-time lens; sub-agent rewrite share + threshold | DONE T148 `520337c` |
| O12 | Continue authorized independent work while an answer is pending (not PO); scope close with carry-over is forward | DONE T149 `f569392` |
| O1+O2 | One lint/typecheck run per commit; receipt reuse removed (helper path + 2-arg function kept); effective-hook fallback (Astra F1); named repair; per-stage timings incl. blocking stages (Astra diff F2) | DONE T150 `b5236ef` (one outcome: shared hook/helper/test; FR-07 mint/consume; independent review) |
| O6 | 1h sub-agent cache TTL: computed break-even R/W > 0.75/(2−r) (supersedes T127 flat rejection) | DONE T151 `a96baaf` |
| O9 | Declared task inputs (`**Inputs:**`) + agent tool reach (judged guidance) | DONE T152 `9875f88` |
| O9b | Committed project tool profile `policies/agent-tools.yml` → `.claude/agents/<agent>-project.md` variants; base mirrors untouched; preflight 5b2 | DONE T153 `35ae1c6` (independent review, 2 rounds: orphan F1 fixed) |
| O19 | Pre-5.0 CHANGELOG archived to `docs/release-notes/CHANGELOG-pre-5.md` | DONE T154 `7f99fa4` |
| O5 | `bounded_run` heartbeat (`state/audit/liveness/`, `.git/info/exclude`); `bounded_wait`; liveness phase reviewed | DONE T155 `11d9b08` |
| O8 | Gate verdict is the PO side's; gate rounds counted against the round bound (Astra F4); any over-limit redirect → `BLOCKED-AT-gate-budget` | DONE T156 `3db790e` |
| — | `liveness` promoted to `FF_RELEASE_TAGS` (46→47; 25 s hosted MSYS, run 38707275006) | DONE T157 `b1c73e5` |
| O10 | Slice-first reading for the AI Developer (handoff full; spec AC/Out of scope/invariants + cited; decision matrix full) | DONE T158 `904a05a` |
| O-tier | Docs-only commit tier: project-declared `policies/validator-free-paths.yml`, absent by default, read from HEAD; FR-13 wording | DONE T160 `3d19861` (FR-13 operator option 2, 2026-10-15; FR-07 mint/consume) |
| O3 | Deny `git commit -n` clusters, `--no-veri*`, `core.hooksPath` setting forms (hard deny incl. `--unset`) | DONE T162 `2a84c22` (operator R: one extra round; Astra r3 SHIP; FR-07 mint/consume) |
| O17 | Stop hook: evidence from agent-authored text; obligations keep full scan; repeat-deny guard; host-valid output | NOT SHIPPED (operator R: one extra round; Astra r3 FIX, forgeable status-label provenance → next release; the rebuild removes the Stop gate) |
| O15 | find-wasted-effort links Flow's gate-report template; rounds by recorded Task range | DONE T161 `09002dd` (operator R: one extra round; Astra r3 SHIP) |
| O20 | `FLOW_RULES.md` status line → FR range (release version-sweep approval) | DONE in T160 `3d19861`; version strings swept in `fded06b` |

Focused hosted feedback (both platforms, all green): run 38698585420 (T142–T151, 25 groups), 38707275006 (T152–T155, 17 groups), 38713742244 (T156–T158, 10 groups), 38843141064 (T163), 38851478770 (T164); push runs green at each push. Release checks: § Closeout.

## Explicitly not built

- Built-in `.md/.txt` skip list (lint scripts read prose); heap cap (`NODE_OPTIONS`); "release tag runs everything" and mirror-drift tiers (not knowable / not in the hook); making receipt reuse real (decisions A6/B1, T53).
- `verdict` field inside `gate_report` (implementer would author the verdict); durable PO verdict record (deferred); mandatory/wired `verify-gate.sh`.
- `agents/`, `.claude/agents/`, `flow-skills/` under protected paths (blocks the FuseBase CLI checkpoint; CLI-owned agents); computed dispatch-time Inputs check (no Flow code at dispatch); `session_start`/health "reachable, fail fast"; TWA-5 slicer/decisions index (deferred, first decision on record).
- `verification_deploy` approval class and agent minting from a recorded grant (self-approval; `--env` literal proves nothing); delegated verification deploy (decision I pending).
- FR-10 exception in `FLOW_RULES.md`; FR-17 edit; digest trim to pointers (token-floor A2/A3); new self-description generator; `v0.30` log entry.
- `.claude/` adapter note for wake paths; `UserPromptSubmit`-on-report-back claim (docs only partly support it); `PostToolUseFailure` + Bash audit arm (→ `hook-tool-call-pairing`).
- Rotation at each merge under `/step-out`; advisor guidance (measure first via O16); A8 for deploy/architect handoffs.
- Tier B: B1 → `outside-liveness-watcher`, B3 → `gate-countable-facts-tally`, B4 → `typed-stop-claim-and-subagent-stop` (parked); B2, B5, B6 not filed (duplicate run-ledger/round accounting; contradicts token-floor A2/A3; no measured defect). T1/T2 are consumer-run; protocol in the reply.

## Residuals found, not in scope

- `docs/backlog/host-call-identity-feature-request/` is stale: `tool_use_id` is documented in the PreToolUse input (prerequisite 1 of `approval-single-use-consumption` may now be satisfiable).
- `gate-contracts.local.yml` (`policies/gate-contracts.yml:7`) is read by nothing; `command-policy.local.yml` deep-merge replaces deny lists with no tighten-only guard.
- `session_start.py` FR-24 reminder omits FR-26 (protected); `FLOW_RULES.md:43` "AI Developer deploy: no" is stale against FR-21 Lightweight; `upgrade.sh:586` comment says `policies/` is overwritten wholesale (per-file classification since 4.x).
- A6 side finding → `deploy-store-provisioning-ungated`.

## Closeout (2026-10-16)

**Decisions after the record above.** 2026-10-15: R one extra review round for O3, O17 and O15, anything still failing ships next release; R2 with no readable history the Stop hook keeps refusing (moot: O17 not shipped); 1 keep "no" for helper deploys; 2 FR-13 option 2, shortened to the boot ceiling, why column kept (full text in `workflows/git-discipline.md` and `docs/rail-mapping.md`); 3 a full release check on the release commit before tagging, v5.11 only; 4 and 5 no; 6 refuse the abbreviated `--no-veri…` options; 7 yes (not shipped, with O17; confirmed 2026-10-16); 8 fix the four handlers' output. 2026-10-16: one protected-path approval for the `FLOW_RULES.md` attestation line in the version sweep, that edit only.

| Item | Outcome | Status |
|---|---|---|
| O4 follow-up | `UserPromptSubmit`-driven wake paths named, each "never the only wake" | DONE T159 `f77edc5` |
| — | One Git Bash locator for the Python tests that spawn bash (hosted Windows image change broke T34) | DONE T163 `ee2d617` |
| O22 | `pre_tool_use`, `user_prompt_submit`, `post_tool_use`, `session_start` reply in the host's format; `stop`, `pre_compact`, `permission_request` remain (`hook-output-host-validity`) | DONE T164 `c7fd55e` (decision 8; Astra: implementation passed, unsupported doc counts removed; FR-07 mint/consume) |
| Release | Version 5.10 → 5.11, string sweep, CHANGELOG, `docs/release-notes/v5.11.md` | `fded06b` (FR-07 mint for the attestation line only, consumed) and `fa3ece5` (managed-content manifest restamped after the hook-layer manifest) |

**Release evidence.** Pre-tag `fusebase-flow-verify` (decision 3): run 38853138045 on `fded06b` was cancelled after Linux failed "Managed-content manifest freshness" (preflight, the essential tests, runner parity and hook-layer freshness had passed); the maintainer's commit helper stamped managed-content before hook-layer, so the release commit carried the 5.10 hook-layer hash. Fixed in `fa3ece5`; run 38854904576 green on Linux, Windows/MSYS and the gate. Tag `v5.11` → `fa3ece5`; release run 38857732510 green on both platforms, Release published 2026-10-16T06:19:08Z; fingerprint row appended.

**Approval records.** Six FR-07 single-use approvals were minted for this program (T144, T150, T160, T162, T164, `fded06b`), each bound to its staged protected paths and consumed after its commit. Each push to `main` had a schema-3 `git_push_v1` approval bound to its commits, removed after the push, with one exception:

- **`fded06b` was pushed without its push approval.** The missing record is the FR-12 push approval, not an FR-07 one: a schema-3 `production_deploy` artifact with binding profile `git_push_v1` for `update refs/heads/main <- fded06b8` at `https://github.com/fusebase-dev/fusebase-flow.git`, which would have been `state/approvals/production_deploy-v511-release-commit-20261016.json`. The maintainer's PowerShell push wrapper passed a reason containing double quotes; PowerShell 5.1 split it, `approve-local.sh` exited 2 (`unexpected argument: with`), and the wrapper pushed anyway. The FR-07 approval for the commit's one protected path (`FLOW_RULES.md`) was minted and consumed, and the commit-time FR-07 check passed under it.
- **Would wired hooks have blocked it?** Tested in a throwaway repository (`c:/tmp/probe-fded06b8`) and by a read-only replay against this clone, then checked by an independent skeptic: the **FR-07 check would not have**, because FR-07 runs only at commit time and on Edit/Write tool calls, never at push time (`hooks/git/pre-push`, `command_policy.evaluate_push_boundary` and the PreToolUse command branch contain no protected-path check). The **PreToolUse FR-12 check would not have** either: the tool call was the wrapper (`& '…push.ps1' …`), which contains no literal `git push … main`, so no rule matched and the policy fell to `default: allow`; the `git push` ran as the script's child process, which no tool hook sees (`policies/command-policy.yml:20-33`). A direct `git push origin main` with no artifact is denied (FR-12, `NO_ARTIFACT`). **Only the git `pre-push` hook would have blocked it** (sandbox: exit 1, `BLOCKED (FR-12 pre-push)`, remote ref unchanged; replay against `c7fd55ee..fded06b8`: deny, `UPDATE_MISMATCH`). That hook is not installed in this maintainer clone. The wrapper now stops when the mint fails.
- **Superseded:** the "Explicitly not built" item "`UserPromptSubmit`-on-report-back claim (docs only partly support it)" was corrected by the operator on 2026-10-15; T159 names those wake paths, each "never the only wake".

**T1/T2:** no separate protocol was sent; the consumer runs them as its handoff defines them (`corrections-for-handoff-author.md`, Requests 1).

**Kept for the operator's review, not deleted:** 24 older artifacts in `state/approvals/` (2026-06-15 to 2026-10-05), including `production_deploy-upgrade-baseline-bootstrap-hop-20260615.json` and the `flow-v55` to `flow-v57` main and closeout pushes.

**Not shipped:** O17 (Stop rework; patch kept outside the repository) and decision 7. Tier B stays parked as filed above. Worktrees for the lanes were removed after their diffs were saved outside the repository.
