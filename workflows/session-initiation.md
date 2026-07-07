# Workflow: session-initiation

> **Style:** Mode-B-lite. What every session does first, regardless of role.

## When to run

Every new AI agent session in a repo where Fusebase Flow is installed.

## Procedure

1. Read `FLOW_RULES.md` down to `## Amendment log` (the log is dated history — skip it; ~40% of the file pays zero operative instruction).
2. Read `AGENTS.md` (root, project-specific section).
3. Determine your role: Product Owner / AI Developer / Architect (escalation) / Deploy phase. If the operator's first message implies a role, attest it. If unclear, ask.
4. Self-attest: "Operating as <role> under Fusebase Flow v3.30.8. I will follow FR-01 through FR-27. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for <role>."
5. Load project state in parallel:
   - `docs/tmp/handoff.md` (if present — the ACTIVE restart/run-ledger state; read it first, then apply step 5a before trusting its file table)
   - `docs/specs/repo-context.md` (if present and <90 days old — the durable repo context map; read it INSTEAD of re-investigating structure/commands/protected paths. Older than 90 days or repo restructured since → treat as stale, note it in the status snapshot, offer `repo-onboarding-context-map`)
   - `docs/backlog/index.md` (if exists)
   - `docs/specs/` (list folders for in-flight specs)
   - `docs/tmp/handoff/` (list; read 3 most recent)
   - `git log --oneline -20`
   - `git status`
   - `docs/problem-catalog/README.md` (index only; don't load entries unless ticket-relevant)
   - `docs/skills/README.md` (project-internal skills index, if exists)
   - `state/context-summary.md` (if present — pre-compact context snapshot from a prior session)
5a. **Resuming from a handoff (trust gate).** If `docs/tmp/handoff.md` exists: diff its header `Branch:` / `HEAD:` against live `git branch --show-current` / `git rev-parse --short HEAD`.
   - **Match** → the snapshot is current: trust `Active Files in Flight`, resume from `Next Step`.
   - **Mismatch** → the repo moved after the write: re-derive in-flight state from `git status --short` + `git log <recorded-HEAD>..HEAD --oneline`; treat the handoff's file table as historical; keep `Key Decisions Made` / `Failed Attempts` (they don't decay with HEAD). Say so in the step-6 status snapshot.
   - `Mode: run-ledger` → resume from records: read the ledger's cited artifacts first, resume from the last durable fact (`flow-skills/handoff/SKILL.md` § Resuming from a handoff).
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
- `flow-skills/repo-onboarding-context-map/SKILL.md` — fills missing project-specific values; produces `docs/specs/repo-context.md` read in step 5
- `flow-skills/handoff/SKILL.md` — produces `docs/tmp/handoff.md` consumed in steps 5/5a (§ Resuming from a handoff)