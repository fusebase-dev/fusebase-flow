
<!-- CUSTOM:SKILL:BEGIN -->

---

## Fusebase Flow — workflow lifecycle overlay

This repository follows **Fusebase Flow** (https://github.com/fusebase-dev/fusebase-flow) for AI agent workflow discipline. The Fusebase Flow framework governs the workflow lifecycle (specification → planning → decisions → tasks → verification → implementation → review → deploy readiness). Existing project rules (Fusebase CLI, MCP, SDK, runtime conventions) remain authoritative for runtime behavior.

Fusebase Flow ships:

- **Always-on rules:** `FLOW_RULES.md` (FR-01..FR-21)
- **Mandatory skills (auto-loaded via `.claude/skills/` and `.agents/skills/`):** `communication`, `role-discipline`
- **On-demand skills (description-matched):** `code-review`, `design-discovery-ideation`, `implementation-planning`, `release-deploy-reporting`, `repo-onboarding-context-map`, `requirements-specification`, `security-permissions-review`, `smoke-testing`, `task-delegation`, `validation-and-qa`, `skill-authoring`, `fusebase-flow-health-check`, `zoom-out`, `phase-audit`, `git-history-diagnostic`, `project-onboarding`, `north-star`, `client-vs-internal`, `product-docs-first`, `business-logic-guardian`, `product-apps-decomposition`, `lightweight-lane` (24 canonical skills total)
- **Sub-agents (description-matched from `.claude/agents/`):** `product-owner` (phases 1–6 + Architect inline), `ai-developer` (phase 7 AI Developer + phase 8b Deploy attestation)
- **Workflows:** `workflows/*.md`
- **Policies:** `policies/*.yml` (machine-readable; consumed by hooks)
- **Hooks:** `hooks/handlers/*.py` (lifecycle events wired in `.claude/settings.json`)
- **Templates:** `templates/*.md`

**Self-attestation (every session's first response):**

> "Operating as {role} under Fusebase Flow v3.8.0. I will follow FR-01 through FR-21. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

**Operator questions:** per FR-19, ask questions in chat text, not popup / clickable menu tools. Use short option tables or numbered lists so the operator can copy, forward, quote, and follow up.

**Slash commands:** `/fusebase-health` (overlay health), `/onboard` (capture project vision), `/product-owner` (start a PO session). All in `.claude/commands/`.

### Active project context — read first

Check whether this project has been onboarded. These artifacts are **absent by default** (created only by `/onboard` or manually):

| Artifact | If present → | If absent → |
|---|---|---|
| `docs/north-star.md` | read it; keep work aligned to the vision (`north-star` skill) | run generically; do not create it |
| `docs/<app>/product.md` | read it for that app's product intent | run generically |
| `docs/<app>/business-logic.md` | treat documented logic as a guard during fixes | run generically |

This check is universal across every surface (it lives in this file, which every agent reads). On Claude Code the `SessionStart` hook also surfaces these automatically, but discovery does not depend on hooks. If an artifact is absent, Fusebase Flow runs as a generic install — no clutter. Run `/onboard` to capture project vision.

### Maintenance posture (Fusebase CLI ↔ Fusebase Flow coexistence)

`.claude/skills/`, `.claude/agents/`, `.claude/hooks/`, `.claude/settings.json`, and `AGENTS.md` are touched by `fusebase update` (without `--skip-skills`). Use either:

**Option A (recommended for routine updates):**

```bash
fusebase update --skip-skills
```

Skips the Fusebase Flow regeneration entirely. Doesn't get CLI-side skill / hook updates but keeps Fusebase Flow overlay intact.

**Option B (when you want full CLI updates):**

```bash
fusebase update                              # let CLI regenerate; Fusebase Flow overlay is destroyed
bash hooks/local/post-fusebase-update.sh     # idempotent recovery: re-mirrors skills+agents,
                                             # re-appends AGENTS.md/CLAUDE.md overlays,
                                             # re-merges settings.json hook chain,
                                             # re-applies Windows shell:true patch
```

The recovery script is self-detecting: it skips parts that don't need restoration (idempotent; safe to run multiple times).

**Or use the in-chat health check:** type `/fusebase-health` (or ask "is Fusebase Flow healthy?") — the skill diagnoses any drift and offers to run recovery on your confirmation.

<!-- FLOW:PRESERVE:BEGIN (operator-owned — overlay refresh carries this region forward verbatim; edit freely) -->
### Project-specific values

| Field | Value | Where the data is enforced |
|---|---|---|
| Project name | (customize during install) | (informational) |
| Stack | (customize during install) | (informational) |
| Workflow mode | `direct_to_main` | `policies/approval-policy.yml: workflow_mode` |
| Worker-undisturbed paths | `none` (extend if needed) | `policies/protected-paths.yml: worker_undisturbed` |
| Decision letter prefix | `A` | `templates/decisions.md` |
| T-counter | `0` | `templates/tasks.md` |

**Where Fusebase Flow and project-specific rules conflict, project-specific rules win.**
<!-- FLOW:PRESERVE:END -->

<!-- CUSTOM:SKILL:END -->