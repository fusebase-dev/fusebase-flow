# Project constitution

## Purpose

This document records the identity and constraints for Fusebase Flow - Fusebase CLI edition. Machine-readable enforcement stays in `policies/`; structured field values stay in `AGENTS.md`; the Flow/CLI boundary map lives in `docs/fusebase-cli-edition.md`.

## Project identity

| Field | Value |
|---|---|
| Name | Fusebase Flow |
| One-line | Fusebase Flow lifecycle framework packaged with Fusebase Apps CLI domain skills and agents. |
| Origin | Created as a dedicated edition after comparing the universal Flow template with the latest Fusebase Apps CLI project template. |
| Stakeholders | Operators installing Flow into Fusebase Apps/CLI projects; Product Owner sessions planning app work; AI Developer sessions implementing app work; downstream generated Fusebase Apps projects. |

## Scope

| In scope | Out of scope |
|---|---|
| Flow rules, skills, workflows, policies, hooks, templates, and role agents | Replacing Fusebase Apps CLI runtime, SDK, MCP, or provider configuration |
| CLI provider skills in `.claude/skills/` and `.agents/skills/` | Absorbing CLI provider skills into `flow-skills/` without a clean-room Flow skill proposal |
| CLI app agents in `.claude/agents/` and `.codex/agents/` | Overwriting downstream app settings or active provider files during installation |
| CLI quality hooks in `.claude/hooks/` | Turning Flow into an agent product, SaaS, daemon, or dependency installer |

## Critical constraints

| Constraint | Practical effect |
|---|---|
| Flow is a lifecycle overlay | Flow owns specs, decisions, tasks, gates, smoke, reviews, deploy handoffs, and approvals. |
| CLI assets are the app/runtime domain layer | CLI skills inform architecture, CLI usage, dashboards, gate, secrets, routing, logs, sidecars, upload, and scaffold checks. |
| Install is append/merge only | Existing `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, MCP config, CLI config, skill folders, and workflows are inspected before merge. |
| Canonical Flow stays separate | Root `skills/` and `agents/` remain Flow canonical sources; provider CLI assets stay in provider folders. |
| Runtime rules win on runtime details | If a CLI skill conflicts with generic Flow implementation guidance, use the CLI rule for app behavior and keep Flow lifecycle artifacts intact. |

## Production safety posture

This repo is a template/edition package, not a deployed app. The default workflow is direct-to-main for framework changes unless a downstream project switches `policies/approval-policy.yml: workflow_mode` to `branch_pr`. Downstream production deploys use the receiving app's deploy command and the Flow deploy handoff/smoke discipline.

## Quality bar

| Area | Bar |
|---|---|
| Framework files | Small, scoped changes; canonical-first edits for Flow flow-skills/agents; provider mirrors regenerated afterward. |
| CLI provider assets | Copied as provider/domain assets; do not rewrite or blend into Flow canonical files without an approved skill-authoring ticket. |
| Validation | Check JSON parse, mirror consistency, provider asset presence, and source-leak scans. |
| Commits | T-numbered when executed by AI Developer under a ticket; one task per commit per FR-03. |
| Reviews | PO verifies Flow/CLI boundary, smoke sufficiency, and append/merge posture before deploy/closeout. |

## Motivation

The universal Flow template is intentionally product-neutral. Fusebase Apps CLI projects need additional domain guidance for app architecture, CLI behavior, MCP/dashboard/gate usage, secrets, routing, logs, and scaffold validation. This edition provides that guidance without weakening Flow's lifecycle discipline or duplicating the same domain rules inside multiple Flow skills.

## Amendment process

1. Draft the change as a decision in a regular Fusebase Flow ticket.
2. Lock the decision with operator approval.
3. Land the amendment as a scoped docs/framework commit, or as part of the ticket's final docs bundle.

## Last amended

```
2026-05-27 - initial Fusebase CLI edition constitution
```

## Related

| Artifact | Purpose |
|---|---|
| `AGENTS.md` | Portable always-on baseline and project-specific values |
| `docs/fusebase-cli-edition.md` | Flow/CLI boundary map and overlap table |
| `docs/operator-discipline.md` | Operator expectations |
| `docs/tradeoffs.md` | Framework tensions |
| `policies/*.yml` | Machine-readable enforcement |
| `FLOW_RULES.md` | FR-01..FR-25 always-on rules |