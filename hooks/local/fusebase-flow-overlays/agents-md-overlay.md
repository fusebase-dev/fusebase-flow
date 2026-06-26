
<!-- CUSTOM:SKILL:BEGIN -->

---

## Fusebase Flow — workflow lifecycle overlay

This repository follows **Fusebase Flow** (https://github.com/fusebase-dev/fusebase-flow) for AI agent workflow discipline. The Fusebase Flow framework governs the workflow lifecycle (specification → planning → decisions → tasks → verification → implementation → review → deploy readiness). Existing project rules (Fusebase CLI, MCP, SDK, runtime conventions) remain authoritative for runtime behavior.

Fusebase Flow ships:

- **Always-on rules:** `FLOW_RULES.md` (FR-01..FR-27; read it down to `## Amendment log` — the log is dated history, never load it)
- **Mandatory skills (auto-loaded via `.claude/skills/` and `.agents/skills/`):** `communication`, `role-discipline`
- **On-demand skills (description-matched):** `code-review`, `design-discovery-ideation`, `implementation-planning`, `release-deploy-reporting`, `repo-onboarding-context-map`, `requirements-specification`, `security-permissions-review`, `smoke-testing`, `task-delegation`, `validation-and-qa`, `skill-authoring`, `fusebase-flow-health-check`, `zoom-out`, `phase-audit`, `git-history-diagnostic`, `project-onboarding`, `north-star`, `client-vs-internal`, `product-docs-first`, `business-logic-guardian`, `product-apps-decomposition`, `lightweight-lane`, `comment-policy`, `documentation-budget`, `handoff`, `module-size-discipline`, `app-quality-patterns`, `token-economy`, `find-wasted-effort` (32 canonical skills total)
- **Sub-agents (description-matched from `.claude/agents/`):** `product-owner` (phases 1–6 + Architect inline), `ai-developer` (phase 7 AI Developer + phase 8b Deploy attestation)
- **Workflows:** `workflows/*.md`
- **Policies:** `policies/*.yml` (machine-readable; consumed by hooks)
- **Hooks:** `hooks/handlers/*.py` (lifecycle events wired in `.claude/settings.json`)
- **Templates:** `templates/*.md`

**Self-attestation (every session's first response):**

> "Operating as {role} under Fusebase Flow v3.28.0. I will follow FR-01 through FR-27. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

**Operator questions:** per FR-19, ask questions in chat text, not popup / clickable menu tools. Use short option tables or numbered lists so the operator can copy, forward, quote, and follow up.

**Command equivalents.** The 6 commands are native Claude Code slash commands; on every other agent invoke the named skill (or type the command as text). Canonical command bodies live in `hooks/local/fusebase-flow-overlays/commands/*.md` (no body re-paste here — pointer only).

| Command | Claude Code | Codex (`/prompts:<cmd>` if installed) | Portable (any agent) |
|---|---|---|---|
| `/product-owner` | `/product-owner` | `/prompts:product-owner` | invoke the `product-owner` agent / type `/product-owner` |
| `/onboard` | `/onboard` | `/prompts:onboard` | invoke the `project-onboarding` skill / type `/onboard` |
| `/handoff` | `/handoff` | `/prompts:handoff` | invoke the `handoff` skill / type `/handoff` |
| `/fusebase-health` | `/fusebase-health` | `/prompts:fusebase-health` | invoke the `fusebase-flow-health-check` skill / type `/fusebase-health` |
| `/token-waste-audit` | `/token-waste-audit` | `/prompts:token-waste-audit` | invoke the `token-economy` skill / type `/token-waste-audit` |
| `/find-wasted-effort` | `/find-wasted-effort` | `/prompts:find-wasted-effort` | invoke the `find-wasted-effort` skill / type `/find-wasted-effort` |

Claude Code surfaces these from `.claude/commands/`. The Codex `/prompts:<cmd>` column applies only after the per-machine opt-in install (`bash hooks/local/install-codex-prompts.sh`; user-global, Codex-deprecated). Cursor/Copilot/Gemini have no native command mechanism — use the Portable column (invoke the skill, or type the command as text and the agent follows it).

### Active project context — read first

Check whether this project has been onboarded. These artifacts are **absent by default** (created only by `/onboard` or manually):

| Artifact | If present → | If absent → |
|---|---|---|
| `docs/north-star.md` | read it; keep work aligned to the vision (`north-star` skill) | run generically; do not create it |
| `docs/<app>/product.md` | read it for that app's product intent | run generically |
| `docs/<app>/business-logic.md` | treat documented logic as a guard during fixes | run generically |

This check is universal across every surface (it lives in this file, which every agent reads). On Claude Code the `SessionStart` hook also surfaces these automatically, but discovery does not depend on hooks. If an artifact is absent, Fusebase Flow runs as a generic install — no clutter. Run `/onboard` to capture project vision.

### Maintenance posture (Fusebase CLI ↔ Fusebase Flow coexistence)

> **Flow's canonical skills live in `flow-skills/` (v3.9.0+), not root `skills/`.** The FuseBase CLI deprecates the root `./skills` folder (`⚠️ The ./skills folder is obsolete and should be deleted`); Flow now uses the Flow-namespaced `flow-skills/`, which the CLI never touches, so that warning is safe to follow. `hooks/local/mirror-skills.sh`, `hooks/local/upgrade.sh`, and the health check's mirror-count all build on `flow-skills/`. Upgrading from a pre-3.9.0 install: `bash hooks/local/upgrade.sh` auto-migrates (moves `skills/` → `flow-skills/`, retires the old dir with a backup). The health check flags an empty/absent `flow-skills/` while Flow mirrors exist, with restore steps.

> **`.fusebase-flow-source/` and ESLint (deploy lint).** The upstream staging clone `.fusebase-flow-source/` contains CLI-owned CommonJS hooks; ESLint **flat config does not read `.gitignore`**, and the CLI's `eslint.config` only ignores `.claude/**` — so if your `fusebase deploy` runs lint, the staged clone fails it (`@typescript-eslint/no-require-imports`) even with zero app errors. The clone is **transient** — either delete it after an upgrade (`rm -rf .fusebase-flow-source`; it's re-created on the next upgrade), or add `".fusebase-flow-source/**"` to your `eslint.config` `ignores` (next to `".claude/**"`). One-shot helper: `bash hooks/local/eslint-ignore-flow-paths.sh`.

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

> Fill these by running **`/onboard`** (the canonical step — the `project-onboarding` skill populates them), or just edit the table directly. Either way your values are preserved across overlay refreshes (they live inside the `FLOW:PRESERVE` markers).

| Field | Value | Where the data is enforced |
|---|---|---|
| Project name | (run `/onboard` or edit) | (informational) |
| Stack | (run `/onboard` or edit) | (informational) |
| Workflow mode | `direct_to_main` | `policies/approval-policy.yml: workflow_mode` |
| Worker-undisturbed paths | `none` (extend if needed) | `policies/protected-paths.yml: worker_undisturbed` |
| Decision letter prefix | `A` | `templates/decisions.md` |
| T-counter | `0` | `templates/tasks.md` |

**Where Fusebase Flow and project-specific rules conflict, project-specific rules win.**
<!-- FLOW:PRESERVE:END -->

<!-- CUSTOM:SKILL:END -->