# `` — framework directory

The framework lives here. Provider and IDE compatibility files (`.claude/`, `.codex/`, `.cursor/`, `.github/`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) point back to this directory.

## What's in here

| Path | Purpose |
|---|---|
| `FLOW_RULES.md` | Always-on rules (FR-01..FR-15). Every session loads this. |
| `VERSION` | Framework version (semver). |
| `workflows/` | Repeatable procedures (eight-phase flow, greenlight-implement, greenlight-deploy, verification-gate, smoke, knowledge-curation, architect-escalation). |
| `skills/` | Two mandatory skills (`communication`, `role-discipline`) plus seven on-demand expertise areas: `requirements-specification`, `repo-onboarding-context-map`, `implementation-planning`, `validation-and-qa`, `code-review`, `security-permissions-review`, `release-deploy-reporting`. Canonical source; mirrored into `.claude/skills/` (Anthropic Claude Code) and `.agents/skills/` (OpenAI/ChatGPT Codex) for provider consumption. |
| `policies/` | Machine-readable YAML policies hooks read (protected paths, command policy, required artifacts, gate contracts, secret patterns, local approval). |
| `hooks/` | Deterministic enforcement. Python handlers (`handlers/`), shared utilities (`shared/`), git fallback (`git/`), local install/preflight scripts (`local/`). |
| `templates/` | Substrate documents new artifacts copy from (spec, decisions, tasks, gate, etc.). |
| `audit/` | Paper trail: implementation audit, source map, license attestation, compatibility matrix, hook coverage, test results, rail mapping. |
| `state/` | Runtime state (audit log, approvals, context summary). Git-ignored. |

## How sessions consume this

1. On start: load `FLOW_RULES.md` plus the active workflow.
2. On code-write request: check `policies/required-artifacts.yml`. If spec/tasks missing, redirect.
3. On tool call: `hooks/handlers/pre_tool_use.py` reads `policies/command-policy.yml` and `policies/protected-paths.yml`.
4. On task complete or stop: `hooks/handlers/stop.py` checks `policies/gate-contracts.yml`.
5. On context compaction: `hooks/handlers/pre_compact.py` writes `state/context-summary.md`.

## How to extend

- **Add a rule:** add to `FLOW_RULES.md` table; if enforceable, add to `policies/`; if deterministic, add to `hooks/handlers/`.
- **Add a skill:** copy `templates/skill-template.md` into `skills/<slug>/SKILL.md`; mirror into approved provider folders via `hooks/local/mirror-skills.sh`.
- **Add a workflow:** put procedure in `workflows/<slug>.md`; reference from skills or rules that use it.
- **Add a policy:** YAML under `policies/`; update `hooks/shared/policy_loader.py` if needed; document in `docs/rail-mapping.md`.

Do NOT modify files inside this directory in ways that break the canonical-source guarantee for `.claude/skills/` and `.agents/skills/` mirrors. Use `hooks/local/mirror-skills.sh` to re-sync after edits.
