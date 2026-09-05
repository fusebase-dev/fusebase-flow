<!-- CUSTOM:SKILL:BEGIN -->

---

## FuseBase Flow — workflow lifecycle overlay

Fusebase Flow owns the development lifecycle; existing Fusebase CLI runtime, MCP, SDK, provider, and project rules remain authoritative for their domains. Project-specific rules win on conflict. Full boundary map: `docs/fusebase-cli-edition.md`.

### Session bootstrap

1. Read `FLOW_RULES.md` through `## Amendment log`; it is the single resident safety/ownership core.
2. Read `flow-skills/communication/SKILL.md` and `flow-skills/role-discipline/SKILL.md` once unless each exact body is already in context. A skill name or description does not count as its body.
3. Self-attest one role using `FLOW_RULES.md`, then read `flow-skills/role-discipline/references/<role>.md`.
4. Read the active workflow and ticket/handoff artifacts. If `docs/north-star.md`, an applicable product doc, or a business-logic index/doc exists, read it; do not create absent onboarding artifacts.

| Surface | Startup delivery | Required action |
|---|---|---|
| Claude Code | skill descriptions/metadata, not bodies | read both mandatory bodies + role reference |
| Codex | optional skill descriptions/metadata, not bodies | read both mandatory bodies + role reference |
| Cursor | always-on adapter text, not skill bodies | read both mandatory bodies + role reference |
| Copilot / VS Code | repository instruction adapters, not skill bodies | read both mandatory bodies + role reference |
| Gemini-style IDEs | no Flow skill bodies | read both mandatory bodies + role reference |
| Delegated sub-agent | inherits no mandatory body | delegating prompt supplies required digest; sub-agent reads both bodies + role reference |

Provider adapters point here and to canonical owners; they do not reprint protocol bodies. On-demand skills live in `flow-skills/`; workflows in `workflows/`; policies in `policies/`; hooks in `hooks/`; templates in `templates/`. Portable commands map to their same-named skills; provider command adapters live under `hooks/local/fusebase-flow-overlays/commands/`.

### Safety and Git

- Follow FR-01 through FR-27 and the attested role's don't-list. Operator questions and approvals stay in chat text.
- One T-task per commit. Stage exact paths; never `git add .`, `git add -A`, `--no-verify`, force-push, hard-reset, clean, or recursive-delete without the explicit authorization required by `FLOW_RULES.md` and policy.
- Save cross-session handoffs before chat output. Stop at the verification gate; deploy requires the owning role and authorization contract.
- Runtime/domain rules from CLI provider skills override generic implementation guidance. Flow still owns specs, decisions, tasks, gates, reviews, deploy handoffs, and smoke contracts.

### Portable commands

| Command | Claude Code | Codex (`/prompts:<cmd>` if installed) | Portable (any agent) |
|---|---|---|---|
| `/product-owner` | `/product-owner` | `/prompts:product-owner` | invoke the `product-owner` skill |
| `/onboard` | `/onboard` | `/prompts:onboard` | invoke the `project-onboarding` skill |
| `/handoff` | `/handoff` | `/prompts:handoff` | invoke the `handoff` skill |
| `/fusebase-health` | `/fusebase-health` | `/prompts:fusebase-health` | invoke the `fusebase-flow-health-check` skill |
| `/token-waste-audit` | `/token-waste-audit` | `/prompts:token-waste-audit` | invoke the `token-economy` skill |
| `/find-wasted-effort` | `/find-wasted-effort` | `/prompts:find-wasted-effort` | invoke the `find-wasted-effort` skill |
| `/find-wasted-code` | `/find-wasted-code` | `/prompts:find-wasted-code` | invoke the `find-wasted-code` skill |

### Installation and update safety

Merge existing consumer content; never overwrite `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.claude/settings.json`, `.mcp.json`, `.cursor/mcp.json`, `fusebase.json`, `.codex-plugin/plugin.json`, `skills-lock.json`, existing `.agents/skills/`, `.claude/skills/`, or `.github/workflows/`. Procedure: `docs/install-fusebase-cli-project.md`.

- Flow ≤4.6.1 → only `bash hooks/local/bootstrap-upgrade.sh -- --auto-yes`; Flow 4.7.0+ → `bash hooks/local/upgrade.sh`.
- Routine CLI refresh → `fusebase update --skip-skills`.
- Full CLI refresh → `fusebase update`, then `bash hooks/local/post-fusebase-update.sh` to restore the Flow overlay and wiring. Use only in an authorized/disposable target; never infer permission from this documentation.
- `.fusebase-flow-source/` is transient and can affect flat-config lint; see `docs/fusebase-cli-edition.md` for the supported cleanup/ignore path.

<!-- FLOW:PRESERVE:BEGIN (operator-owned — overlay refresh carries this region forward verbatim; edit freely) -->
### Project-specific values

| Field | Value | Where enforced |
|---|---|---|
| Project name | (run `/onboard` or edit) | informational |
| Stack | (run `/onboard` or edit) | informational |
| Workflow mode | `direct_to_main` | `policies/approval-policy.yml` |
| Worker-undisturbed paths | `none` (extend if needed) | `policies/protected-paths.yml` |
| Decision letter prefix | `A` | `templates/decisions.md` |
| T-counter | `0` | `templates/tasks.md` |

**Where Fusebase Flow and project-specific rules conflict, project-specific rules win.**
<!-- FLOW:PRESERVE:END -->

<!-- CUSTOM:SKILL:END -->
