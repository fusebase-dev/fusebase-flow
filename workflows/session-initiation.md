# Workflow: session-initiation

> **Style:** Mode-B-lite. What every session does first, regardless of role.

## When to run

Every new AI agent session in a repo where Fusebase Flow is installed.

## Procedure

1. Read `FLOW_RULES.md` (full).
2. Read `AGENTS.md` (root, project-specific section).
3. Determine your role: Product Owner / AI Developer / Architect (escalation) / Deploy phase. If the operator's first message implies a role, attest it. If unclear, ask.
4. Self-attest: "Operating as <role> under Fusebase Flow v3.11.1. I will follow FR-01 through FR-22. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for <role>."
5. Load project state in parallel:
   - `docs/backlog/index.md` (if exists)
   - `docs/specs/` (list folders for in-flight specs)
   - `docs/tmp/handoff/` (list; read 3 most recent)
   - `git log --oneline -20`
   - `git status`
   - `docs/problem-catalog/README.md` (index only; don't load entries unless ticket-relevant)
   - `docs/skills/README.md` (project-internal skills index, if exists)
6. Output a status snapshot to operator (Mode A — visual roadmap if multi-phase project).
7. Append the state-announcement footer to every output:
   ```
   ---
   📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
   🎯 Ticket: {slug or "—"}
   ⏭️ Next: {what the operator does next}
   ```
8. Wait for operator direction.

## Inputs required

| Input | Source |
|---|---|
| Tool surface | inferred from the IDE (Claude Code / Codex / Cursor / GitHub Copilot / Gemini-style IDE / generic) |
| Repo state | git + `docs/` |
| Active ticket(s) | `docs/specs/` and `docs/tmp/handoff/` |

## Outputs

| Artifact | Where |
|---|---|
| Self-attestation | first chat response |
| Status snapshot | first chat response |
| State footer | every subsequent output |

## Failure modes

| Failure | Response |
|---|---|
| `FLOW_RULES.md` missing | STOP. Operator hasn't installed Fusebase Flow. Direct to `workflows/setup.md`. |
| `AGENTS.md` lacks project-specific values | STOP. Run `repo-onboarding-context-map` skill before proceeding. |
| Multiple in-flight tickets, unclear which is active | List them; ask operator which to resume. |

## Related

- `FLOW_RULES.md` — the rules being attested
- `workflows/setup.md` — first-time install
- `flow-skills/repo-onboarding-context-map/SKILL.md` — fills missing project-specific values