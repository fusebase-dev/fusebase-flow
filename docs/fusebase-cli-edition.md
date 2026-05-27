# Fusebase CLI edition

## Purpose

This edition layers Fusebase Flow lifecycle discipline on top of the Fusebase Apps CLI domain assets. Flow owns the ticket lifecycle, role boundaries, verification gates, deploy reporting, and smoke discipline. The CLI assets own app/runtime guidance for Fusebase Apps, MCP, dashboards, gate, routing, secrets, logs, and scaffold quality.

## Source of truth

| Area | Owner | Path |
|---|---|---|
| Flow lifecycle skills | Flow canonical | `skills/`, mirrored to `.claude/skills/` and `.agents/skills/` |
| CLI domain skills | CLI provider assets | `.claude/skills/<cli-skill>/` and `.agents/skills/<cli-skill>/` |
| Flow agents | Flow canonical | `agents/`, mirrored to `.claude/agents/` and `.codex/agents/` |
| CLI app agents | CLI provider assets | `.claude/agents/app-architect.md`, `.claude/agents/app-create-checker.md`, copied to `.codex/agents/` |
| CLI quality hooks | CLI provider assets | `.claude/hooks/*` |
| Flow hooks | Flow canonical | `hooks/handlers/*`, `hooks/git/*`, `.claude/settings.json.example` |

## Boundary rules

1. Flow governs specs, clarifies, decisions, tasks, verification gates, implementation handoffs, review, deploy handoffs, smoke contracts, and DONE flips.
2. CLI skills govern Fusebase Apps implementation/runtime/MCP/SDK/domain behavior.
3. If runtime app guidance conflicts with generic Flow guidance, follow the CLI/project-specific runtime rule and keep the Flow lifecycle artifact intact.
4. Do not copy CLI provider skills into root `skills/`; they are edition/provider assets, not canonical Flow framework skills.
5. Do not add CLI provider skills to `audit/skill-mirror-manifest.txt`; the manifest tracks canonical Flow mirror drift only.
6. If a CLI skill becomes a reusable Flow framework pattern, route it through `skills/skill-authoring/SKILL.md` as a clean-room upstream proposal.

## When to load CLI domain assets

| Flow activity | Supporting CLI asset |
|---|---|
| New/update app architecture | `app-architect`, `app-dev-practices`, `fusebase-cli` |
| UI direction or implementation | `app-ui-design` |
| Backend/API behavior | `app-backend`, `api-exploration` |
| Dashboard data and views | `fusebase-dashboards` |
| Gate, orgs, users, tokens, permissions | `fusebase-gate` |
| Secrets and authentication errors | `app-secrets`, `handling-authentication-errors` |
| File upload | `file-upload` |
| Routing | `app-routing` |
| Sidecars | `app-sidecar` |
| Local or deployed debugging | `dev-debug-logs`, `remote-logs` |
| Git/deploy traceability | `git-workflow`, `fusebase-cli` |
| Scaffold verification | `app-create-checker` |
| MCP gate debugging | `mcp-gate-debug` |
| Managed integrations | `managed-integrations` |
| Portal-specific apps | `fusebase-portal-specific-apps` |
| Business docs for apps | `app-business-docs` |

## Overlap map

| Flow skill | Overlapping CLI asset | Why it overlaps | Boundary |
|---|---|---|---|
| `requirements-specification` | `app-architect`, `app-business-docs` | All shape app intent and requirements | Flow writes spec and ACs; CLI assets inform app-domain constraints |
| `design-discovery-ideation` | `app-ui-design` | Both guide UI/product direction | Flow frames options before lock; CLI asset provides Fusebase Apps UI conventions |
| `implementation-planning` | `app-dev-practices`, `fusebase-cli`, `git-workflow` | All affect implementation sequence | Flow writes decisions/tasks/gate; CLI assets inform commands and runtime approach |
| `validation-and-qa` | `app-create-checker`, `dev-debug-logs`, `remote-logs` | All verify behavior | Flow decides gate sufficiency; CLI assets provide app-specific probes and diagnostics |
| `security-permissions-review` | `app-secrets`, `handling-authentication-errors`, `fusebase-gate`, `fusebase-dashboards` | All touch auth, tokens, secrets, data access | Flow owns approval/blocker review; CLI assets define app-specific security surfaces |
| `smoke-testing` | `remote-logs`, `dev-debug-logs`, `fusebase-cli` | Smoke needs deployed app diagnostics | Flow owns outcome-first smoke discipline; CLI assets identify ground-truth surfaces |
| `release-deploy-reporting` | `fusebase-cli`, `git-workflow`, `remote-logs` | Deploy handoff needs CLI/deploy evidence | Flow owns deploy report shape; CLI assets provide commands and runtime evidence |
| `repo-onboarding-context-map` | `fusebase-cli`, `app-dev-practices` | Both orient agents to app repos | Flow writes durable context map; CLI assets supply Fusebase Apps project conventions |
| `code-review` | `app-backend`, `app-ui-design`, `app-routing`, `file-upload`, `app-sidecar` | Reviews need domain standards | Flow reviews against spec/decisions/tasks; CLI skills supply implementation-specific review criteria |

## Agent bridge

| Role | Uses CLI assets how |
|---|---|
| Product Owner | May use `app-architect` and domain skills as supporting input while drafting specs, decisions, tasks, gates, and smoke contracts. PO still does not write production code or lock decisions without operator approval. |
| AI Developer | Uses relevant CLI skills during implementation, debugging, validation, and deploy evidence collection. AI Developer still follows one task = one commit and stops at the gate. |
| Deploy phase | Uses `fusebase-cli`, `remote-logs`, `dev-debug-logs`, and `git-workflow` for deploy probes and diagnostics. Deploy phase still cannot mark DONE. |
| App checker | `app-create-checker` is supporting validation evidence, not a replacement for Flow verification-gate and smoke evidence. |

## Settings and hooks

`.claude/settings.json.example` intentionally merges two hook families:

| Hook family | Purpose |
|---|---|
| Flow lifecycle hooks | Enforce session, prompt, tool-use, stop, and compact discipline from `hooks/handlers/*`. |
| CLI Stop hooks | Run app lint, typecheck, and quality checks from `.claude/hooks/*` before completion on Claude Code. |

Keep the merge additive. Do not overwrite an active downstream `.claude/settings.json`; append or merge after inspection.
