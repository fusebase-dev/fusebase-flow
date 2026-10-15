# v5.11 — Onboarding consumer review of Flow 5.10 (handoff 2026-10-14)

**Outcome:** ship the verified, narrowed Tier A of the FuseBase onboarding change program as v5.11; park Tier B behind its own evidence gates. **Inputs** (`c:/tmp/flow-review-2026-10-14/`): `handoff.md` (consumer program; source `FuseBase Product and SaaS/outputs/flow-5.10-dual-review-2026-10-14/flow-handoff-2026-10-14.md`); `journal-results.json` (13 per-item verifiers vs HEAD `07417d1`, Claude Code docs fact check, Tier B map); `plan.json` (synthesis O0..O20); `critic.json` (completeness gaps); `astra-premise.md` (GPT-6 Astra premise review F1..F12); `design-{A11,A51,O3,O17}.md` (reworked contracts); `corrections-for-handoff-author.md` (reply to the consumer). **Authorization:** operator chat reply 2026-10-14 (`operator-decisions.md`): A ship as v5.11 with pushes for focused hosted checks · B FR-07 edits to `hooks/git/pre-commit`, `policies/command-policy.yml`, `policies/gate-contracts.yml`, `hooks/handlers/stop.py` + `policies/required-artifacts.yml`, `FLOW_RULES.md` status line at release · C hard deny incl. `--unset`, conditional on Flow's `install-git-hooks.sh` / `post-fusebase-update.sh` invocations staying allowed · D heartbeat ignored via `.git/info/exclude` (T130 writer), not `.gitignore` · E gate rounds share the code-review bound · F computed 1h-TTL break-even · G continue authorized independent work while an answer is pending, not PO sessions · H repeated Stop refusal → warning + unresolved record · I conditional (re-asked: no single-use deploy approval exists) · additions: committed project tool profile for Flow agents (protected under `policies/`), docs-only commit tier with an empty-by-default project allowlist, corrections to the operator. One single-use digest-bound approval per protected commit, minted by the integrator only, consumed after. Release: "tag 5.11 only after the release checks pass and row 13 is in" — read as the v5.9-style pre-tag hosted verification, granted for v5.11 only (reading to confirm). **Review round cap** (declared 2026-10-15, before dispatch): 2 per boundary — per outcome build→review→fix→review, then `BLOCKED-AT-review-budget` to the integrator; premise boundary for O3/O17/tier/profile = Astra round 1 (done) + one re-check of the reworked designs; independent diff review for O1+O2, O3, O17, tier, profile. **Host:** CPU 100% from other sessions, bare `bash -c` start 46 s (2026-10-15) → no local bash phases; Python-only checks locally; bash phases via `fusebase-flow-maintainer.yml` `groups=` dispatch.

| Item | Outcome | Status |
|---|---|---|
| O14 | FR-10 partial-reproduction carriers point at validation-and-qa Sub-mode C | in build |
| O1 | One lint/typecheck run per commit (pre-commit); receipt-reuse machinery removed (helper path + 2-arg function kept for installed copies); effective-hook fallback (Astra F1) | in build |
| O2 | `hooks/git/pre-commit`: named repair for a missing runner; per-stage timings (builtins) | in build |
| O-tier | Docs-only commit tier: project-declared allowlist, empty by default, read from HEAD; FR-13 wording | design |
| O3 | Deny `git commit -n` clusters and `core.hooksPath` setting forms (hard deny incl. `--unset`); narrow heuristic contract (Astra F2) | design |
| O4 | FR-27 premise corrected: watched from outside; watcher default for wakeable sessions; verified host wake paths only | in build |
| O5 | `bounded_run` heartbeat (`state/audit/liveness/`, `.git/info/exclude`); `bounded_wait`; liveness phase reviewed | in build |
| O6 | 1h sub-agent cache TTL: computed break-even R/W > 0.75/(2−r) (supersedes T127 flat rejection) | in build |
| O7 | Gate contract: PASS/FAIL rows with evidence; label hints; `self_attestation` removed; value validator (advisory) | in build |
| O8 | Gate verdict is the PO side's; gate rounds counted against the round bound (Astra F4) | in build |
| O9 | Declared task inputs + agent tool reach (judged guidance) | after profile design |
| O-profile | Committed project tool profile for Flow agents (`policies/agent-tools.yml`, protected), survives upgrade + preflight | design |
| O10 | Slice-first reading for the AI Developer | in build |
| O11 | Unattended ordering, own-brief re-dispatch, successor brief, grant ≠ approval artifact | in build |
| O12 | Continue authorized independent work while an answer is pending (not PO); scope close with carry-over is forward | in build |
| O13 | Smoke live-run discipline; product criterion binding over harness attribution (Astra F6) | in build |
| O15 | find-wasted-effort links Flow's gate-report template; rounds by recorded Task range | in build |
| O16 | token-waste-audit: advisor calls priced; wall-time lens; sub-agent rewrite share + threshold | in build |
| O17 | Stop hook: completion evidence from agent-authored text only, obligations keep full scan; repeat-deny guard (Astra F7–F11) | design |
| O18 | ROADMAP / hooks README / smoke template / framework.md truth | in build |
| O19 | Pre-5.0 CHANGELOG archived to `docs/release-notes/CHANGELOG-pre-5.md` | release prep |
| O20 | `FLOW_RULES.md` status line → FR range (release version-sweep approval) | release prep |

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
