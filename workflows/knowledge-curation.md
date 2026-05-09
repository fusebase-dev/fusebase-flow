# Workflow: knowledge-curation

> **Style:** Mode-B-lite. Operator-confirmed capture of significant problems and recurring patterns.

## Purpose

Without persistent capture, every new session re-discovers the same problems. This workflow runs after non-trivial diagnosis OR mid-investigation when a trigger fires, and proposes filing either a problem-catalog entry or a project-internal skill.

## When to run

| Trigger | Propose |
|---|---|
| Ticket required > 30 min of non-obvious diagnosis | problem-catalog entry |
| Same symptom seen in 2+ recent tickets | problem-catalog entry |
| Pattern emerging across 3+ tickets | project-internal skill |
| Operator says "we always do X" | project-internal skill |
| Vendor / platform quirk surfaced | problem-catalog entry |
| Workaround applied for platform constraint | problem-catalog entry + cross-reference from project-specific section of AGENTS.md |

## Procedure

1. Detect the trigger during investigation or after deploy.
2. In chat, propose curation explicitly:
   ```
   Knowledge curation candidate: I'm noticing <observation>. Looks like a
   <problem-catalog | skill> candidate because <reasoning>. ~5–10 min to
   draft. Future tickets that hit similar territory will load this and
   avoid re-discovery. Reply 'capture' or 'skip'.
   ```
3. If operator says `capture`:
   - For problem-catalog: file at `docs/problem-catalog/<slug>/problem.md` using `templates/problem-catalog-entry.md`
   - For project-internal skill: file at `docs/skills/<slug>/SKILL.md` using `templates/skill-template.md` (NOT `skills/`; this is a project-internal skill distinct from the framework's seven core skills)
   - Update the corresponding index (`docs/problem-catalog/README.md` or `docs/skills/README.md`)
4. If operator says `skip`: note the decision in the current ticket's `decisions.md` as audit trail. Do not refile this trigger again for the same ticket.
5. For "must-capture without asking" cases (production-blocking platform bug, recurring constraint that affects future migrations): file the entry and announce: "Captured `docs/problem-catalog/<slug>/problem.md` per FR-15. Future tickets hitting this territory will inherit the context."

## Project-internal skills vs framework skills

| Type | Location | Purpose |
|---|---|---|
| Framework skill | `skills/<name>/SKILL.md` | One of the 7 core skills shipping with the template |
| Project-internal skill | `docs/skills/<slug>/SKILL.md` | Project-specific expertise capture, distinct from framework skills |

Project-internal skills are loaded by reference (operator says "load skill <slug>") not by description match. Their structure follows `templates/skill-template.md` but they don't ship in framework mirrors (`.claude/skills/`, etc.).

## Outputs

| Artifact | Path |
|---|---|
| Problem-catalog entry | `docs/problem-catalog/<slug>/problem.md` |
| Project-internal skill | `docs/skills/<slug>/SKILL.md` |
| Updated indexes | `docs/problem-catalog/README.md`, `docs/skills/README.md` |
| Skip audit | note in `docs/specs/<current-ticket>/decisions.md` |

## Failure modes

| Failure | Response |
|---|---|
| Operator says `capture` but provides no detail | Use what's already in the ticket's investigation; ask one targeted question if a critical detail is missing |
| Trigger fires multiple times in one ticket | Capture once; add subsequent observations as appendix in same file |
| Topic overlaps existing problem-catalog entry | Update the existing entry rather than creating a duplicate |

## Related

- `FLOW_RULES.md` FR-15 — knowledge curation triggers
- `templates/problem-catalog-entry.md` — substrate for catalog entries
- `templates/skill-template.md` — substrate for both framework and project-internal skills
- `skills/requirements-specification/SKILL.md` — may invoke this workflow on completion
- `skills/release-deploy-reporting/SKILL.md` — may invoke this workflow post-deploy
