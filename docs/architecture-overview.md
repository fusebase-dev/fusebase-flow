# Architecture overview

> Reference visual for how Fusebase Flow Local fits together. Human-readable; does not need to be loaded into agent context. For the always-on rules see `FLOW_RULES.md`. For per-component detail see `docs/framework.md`.

## Three roles, one workflow

```
┌─────────────────┐                ┌─────────────────┐                ┌─────────────────┐
│  Product Owner  │ ─── handoff ─► │   AI Developer   │ ─── handoff ─► │  Deploy phase   │
│ (drafts spec,   │                │ (executes T1..  │                │ (runs probes,   │
│  decisions,     │ ◄── gate ───── │  Tn, stops at   │ ◄── deploy ─── │  flips spec     │
│  tasks, gate)   │                │  verification)  │                │  DRAFT → DONE)  │
└─────────────────┘                └─────────────────┘                └─────────────────┘
        ▲                                                                        │
        │ (escalation, optional)                                                 │
        │                                                                        ▼
┌─────────────────┐                                                  ┌─────────────────┐
│   Architect     │                                                  │    Operator     │
│ (fresh-eyes     │                                                  │ (locks decisions│
│  investigation) │                                                  │  approves       │
└─────────────────┘                                                  │  deploys)       │
                                                                     └─────────────────┘
```

## Eight-phase ticket lifecycle

```
1. Specify     ─────► docs/backlog/<slug>/README.md filed; or docs/specs/<slug>/spec.md drafted
2. Clarify     ─────► docs/specs/<slug>/clarify-conversation.md resolves Q-A's
3. Plan        ─────► spec.md filled out
4. Decisions   ─────► docs/specs/<slug>/decisions.md (LOCKED after operator confirms)
5. Tasks       ─────► docs/specs/<slug>/tasks.md (T-numbered chain)
6. Verify      ─────► docs/specs/<slug>/verification-gate.md drafted
7. Implement   ─────► AI Developer session runs T1..T<gate>; stops at gate
8. Deploy      ─────► Deploy session runs probes + smoke; spec flips DRAFT → DONE
```

Each transition updates the `📍 Phase:` state-announcement footer.

## Cross-session handoff folder

```
docs/handoff/
├── <YYYY-MM-DD>-<slug>-architect.md     ← Product Owner → escalated Architect
├── <YYYY-MM-DD>-<slug>-implement.md     ← Product Owner → AI Developer
└── <YYYY-MM-DD>-<slug>-deploy.md        ← Product Owner → Deploy phase
```

Every cross-session prompt is saved here BEFORE being shown in chat (FR-04). Replay-able, audit-grep-able.

## Enforcement layers

```
                                        ┌─────────────────────┐
                                        │   FLOW_RULES.md     │
                                        │   (FR-01..FR-16)    │
                                        │   always-on         │
                                        └──────────┬──────────┘
                                                   │
                ┌──────────────────────────────────┼──────────────────────────────────┐
                ▼                                  ▼                                  ▼
       ┌────────────────┐                 ┌────────────────┐                 ┌────────────────┐
       │   skills/      │                 │  workflows/    │                 │   policies/    │
       │  (on-demand    │                 │  (procedural)  │                 │  (machine-     │
       │   + 2 mandatory)│                 │                │                 │   readable)    │
       │                │                 │                │                 │                │
       │ communication  │                 │ eight-phase-   │                 │ approval-      │
       │ role-discipline│                 │ flow           │                 │ command-       │
       │ requirements-* │                 │ greenlight-*   │                 │ protected-     │
       │ implementation-│                 │ verification-  │                 │ required-      │
       │ validation-*   │                 │ smoke-         │                 │ gate-contracts │
       │ code-review    │                 │ knowledge-     │                 │ secret-patterns│
       │ security-*     │                 │ ...            │                 │                │
       │ release-deploy │                 │                │                 │                │
       └────────────────┘                 └────────────────┘                 └────────┬───────┘
                                                                                      │
                                                                                      ▼
                                                                            ┌────────────────┐
                                                                            │    hooks/      │
                                                                            │  (deterministic│
                                                                            │   enforcement) │
                                                                            │                │
                                                                            │ session_start  │
                                                                            │ user_prompt    │
                                                                            │ pre_tool_use   │
                                                                            │ post_tool_use  │
                                                                            │ permission_req │
                                                                            │ stop           │
                                                                            │ task_complete  │
                                                                            │ pre_compact    │
                                                                            │ + git pre-     │
                                                                            │   commit /     │
                                                                            │   commit-msg   │
                                                                            └────────────────┘
```

## Why each surface exists

| Surface | When to add new content here |
|---|---|
| **Rule (FLOW_RULES.md)** | Always-on baseline; every session attests |
| **Skill** | Behavioral guidance, role-specific, or expertise-area; loaded by description match (or mandatory) |
| **Workflow** | Multi-step procedure executed in sequence |
| **Policy (YAML)** | Machine-readable data hooks consult |
| **Hook** | Deterministically checkable enforcement at lifecycle events |
| **Template** | Substrate for a per-ticket artifact |
| **`docs/`** | Human-readable reference; not actionable for the agent |

See `docs/rail-mapping.md` for the canonical FR-NN → surface mapping.

## Skill mirror flow

```
                  skills/<name>/SKILL.md         ← canonical
                            │
                            │ bash hooks/local/mirror-skills.sh
                            ▼
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
   .agents/skills/<name>/SKILL.md   .claude/skills/<name>/SKILL.md
   (OpenAI / ChatGPT Codex)         (Anthropic Claude Code)
              │                           │
              └─────────── ┬ ─────────────┘
                           │
                           ▼
                  audit/skill-mirror-manifest.txt
                  (sha256 manifest)

                  preflight.sh + GitHub Action
                  verify mirrors match canonical (drift = 0)
```

## Approval-artifact flow (FR-12)

```
operator                   approve-local.sh                    state/approvals/
   │                              │                                   │
   ├── "approve <action>" ───────►│                                   │
   │                              ├── reads approval-policy.yml ─────►│
   │                              │   (TTL, action name)              │
   │                              │                                   │
   │                              └── writes JSON artifact ──────────►│
   │                                                                  │
   │                                                                  │
   agent                          pre_tool_use hook                   │
   │                              │                                   │
   ├── runs deploy command ──────►│                                   │
   │                              ├── command_policy.py ◄── check ────┤
   │                              │   evaluate(command)               │
   │                              │   → require_approval              │
   │                              │   → look up artifact              │
   │                              │                                   │
   │                              ├── artifact present + unexpired? ──┤
   │                              │   yes → allow                     │
   │                              │   no  → deny + reason             │
   │                              │                                   │
   ├──◄── decision returned ──────┤                                   │
```

## Where to read next

- `README.md` — quickstart, install paths, supported surfaces
- `FLOW_RULES.md` — the 15 always-on rules
- `docs/framework.md` — the framework directory structure entry point
- `docs/compatibility.md` — supported provider / IDE matrix
- `docs/hook-coverage.md` — handler × surface coverage
- `docs/rail-mapping.md` — FR-NN → enforcement surface map
- `docs/operator-discipline.md` — expectations for the human operator
- `docs/tradeoffs.md` — key tensions to manage
- `docs/constitution.md` — project identity narrative
