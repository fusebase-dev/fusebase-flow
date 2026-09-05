# Implement handoff — flow-performance-and-recovery-hardening

## Role bootstrap

Operate as the **AI Developer** under Fusebase Flow v4.14.1. Self-attest from `FLOW_RULES.md`, apply IM.1..IM.18, and execute T1..T10 one task at a time. Stop at T10 with the canonical gate report; do not perform T11.

**Model assignment:** GPT-5.6 Sol, xhigh reasoning, implements T1–T9; GPT-6 Astra Medium performs independent review. Do not silently substitute models.

Long/silent commands must complete in-turn with a hard timeout or use the bounded runner with durable incremental evidence. Delegated/API-limit work follows `flow-skills/liveness-discipline/SKILL.md`; proactively poll process/activity/git progress every 60–90 seconds, never rely solely on a completion ping. Retry transient API-limit/no-start failures on the same agent within at most 3 attempts / 5 minutes with labeled backoff; then successor or `BLOCKED-AT-delegate-no-start` with durable evidence pointer. Blocking waits stay ≤60 seconds.

## Mandatory reads

1. `FLOW_RULES.md` through `## Amendment log`
2. `AGENTS.md`
3. `docs/specs/flow-performance-and-recovery-hardening/spec.md`
4. `docs/specs/flow-performance-and-recovery-hardening/decisions.md`
5. `docs/specs/flow-performance-and-recovery-hardening/tasks.md`
6. `docs/specs/flow-performance-and-recovery-hardening/verification-gate.md`
7. `docs/fusebase-cli-edition.md`
8. `policies/protected-paths.yml`
9. `flow-skills/communication/SKILL.md`, `flow-skills/role-discipline/SKILL.md` and `flow-skills/role-discipline/references/ai-developer.md`
10. `flow-skills/comment-policy/SKILL.md`, `flow-skills/module-size-discipline/SKILL.md`, `flow-skills/liveness-discipline/SKILL.md`
11. `.agents/skills/git-workflow/SKILL.md`
12. `docs/north-star.md` and `workflows/greenlight-implement.md`; use approved ticket exceptions where that generic workflow still prescribes an extra relay

## Ticket

| Field | Value |
|---|---|
| Slug | `flow-performance-and-recovery-hardening` |
| Status | ready for AI Developer after documentation review |
| Source | `docs/specs/flow-performance-and-recovery-hardening/` |
| Decisions | A1..A7 LOCKED by operator instruction, 2026-09-05 |
| Task range | T1..T10; stop at T10 |
| T-counter going in | T0 |
| Baseline | `521c5fe` on `main`; v4.14.1 tree |
| Installed CLI observed | FuseBase CLI `2026.090207.3341`, Launcher `2026.081107.4925`, dev channel |
| Pre-existing unrelated state | untracked `docs/wasted-code/`; preserve, exclude from all commits, do not clean/revert |

## Pre-cached identifiers

No app/store/user/token/base-URL identifiers apply. Stable evidence paths:

- `state/audit/adversarial-review-2026-09-05.md`
- `state/audit/adversarial-review-2026-09-05-probes.json`
- `state/audit/find-wasted-effort-2026-09-05.md`

## Production state

No app or production deployment exists. The delivery surface is this framework/template repository. T11 will close documentation after independent review; publication/tag/push is outside this handoff.

## UI implementation brief

N/A. This ticket changes scripts, hooks, instruction assets, tests, and reports. It creates no internal/client UI, route, component, prompt interaction, or browser flow.

## Execution order

Serial: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10.

Shared-file edits must not be parallelized. Each T1..T9 produces one focused commit citing its T-number. T10 produces the gate report without a commit.

## CLI ownership

Zero change unless a fixture explicitly simulates the CLI write before Flow recovery:

- `.claude/hooks/**`
- CLI provider skills and app agents
- `fusebase.json`, `.mcp.json`, `.codex/config.toml`
- consumer permissions, custom hooks, MCP enablement, and unrelated settings

Flow may update its canonical `flow-skills/**`, `agents/**`, exact marked overlays, provider mirrors, commands, handlers, policies, tests, and manifests only as scoped in tasks.

## Comment policy

```
COMMENT POLICY (FR-22) — applies to all code you write:
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision B2)" or "backlog 156".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```

Emit `comment-policy review: applied (FR-22)` with the final gate report.

## Protected-path authorization

The operator explicitly authorized all recommended implementation in this thread. Before each commit touching `FLOW_RULES.md`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`, or a protected policy path, stage the exact T-task files, mint the digest-bound single-use bootstrap approval, commit, and consume it. Never broaden staging and never use `--no-verify`.

## Verification

- Run focused RED/green tests inside each T-task.
- Keep the working tree attributable; stage exact paths only.
- Run the full registered suite once at final source state in T10, plus preflight, mirror, module-size, protected-path, secret, CLI-ownership, no-op recovery, and smoke S1..S3 checks from `verification-gate.md`.
- Bound the disposable installed-CLI refresh. Never run `fusebase update` in the shared workspace.
- A failed then passed smoke remains FLAKY until reproduced or explained with evidence.

## Gate contract

At T10 fill `templates/gate-report.md` into `docs/specs/flow-performance-and-recovery-hardening/gate-report.md` with per-task SHAs, test counts, lint/typecheck status, ownership/protected-path results, measurements, deviations, and the exact commands/evidence used. Stop after the report. GPT-6 Astra Medium will independently review the complete diff before T11.
