---
description: Write the active session restart state to docs/tmp/handoff.md so a fresh AI session continues from the exact current point. Triggers the handoff skill — inspects repo state, reconstructs goal/decisions/failures/next-step, and writes the 16-section handoff for the next coding agent (not a human report). (FuseBase Flow)
---

# /handoff

Invoke the **handoff** skill (`flow-skills/handoff/SKILL.md`).

1. Confirm a handoff is warranted (FR-23 Tier 2): meaningful code/test/schema/config/decision change this session. If nothing meaningful changed, say so and stop — do not write a hollow file.
2. Inspect repo state (`git status --short`, branch, short HEAD, `git diff --stat`); detect real build/test commands from manifests.
3. If `docs/tmp/handoff.md` exists, archive it to `docs/tmp/handoff/archive/<YYYY-MM-DD-HHMM>-handoff.md` first (paper trail; archiving a live `Mode: run-ledger` file here is the sanctioned supersede). Then write `docs/tmp/handoff.md` fresh (FR-18) using `templates/handoff.md` — all 16 sections, header stamped `Mode: restart`, `Unknown` not guesses, `None` for empty, pointers to canonical spec/decisions/tasks instead of reprinting (FR-23). Exactly one concrete Next Step.
4. Report a short Mode A summary in chat (goal, current state, active files, next step, validation). Do not paste the full file unless asked.

For a formal implement/deploy relay (not active restart state), use `implementation-planning` / `release-deploy-reporting` → `docs/tmp/handoff/<date>-<slug>-{implement,deploy}.md` instead.
