# Workflow: greenlight-implement

> **Style:** Mode-B-lite. The handoff from Product Owner session to Implementer session.

## When to run

After `implementation-planning` has produced `decisions.md` (all locked), `tasks.md`, `verification-gate.md`, and the operator confirms decisions are locked.

## Procedure (Product Owner side)

1. Verify pre-handoff checklist:
   - [ ] All decisions in `decisions.md` show `Lock status: LOCKED`
   - [ ] All clarify Q-A's resolved (none remain in `spec.md`)
   - [ ] `tasks.md` has T-numbers from current counter (not placeholders)
   - [ ] `verification-gate.md` exists and is complete
   - [ ] Constitution invariants explicitly affirmed in spec.md (worker-undisturbed list, mixed-fleet, etc.)
   - [ ] Letter prefix incremented in `AGENTS.md` (if a new ticket)
   - [ ] T-counter updated in `AGENTS.md`
2. Draft handoff content using the template at the bottom of this workflow.
3. Save to `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md` BEFORE outputting in chat (FR-04).
4. Tell operator: "Implement handoff saved to <path>. Open and paste into a fresh AI agent session."

## Procedure (Implementer side)

1. Read mandatory pre-execution files (per the handoff's reads list).
2. Self-attest: "Operating as Implementer under Fusebase Flow v0.1. I will follow FR-01 through FR-15. I will apply Mode A on chat output and Mode B on every file I write."
3. Pre-task git checkpoint: `git status --short`. If non-empty, STOP and ask operator.
4. Execute tasks T<first>..T<gate> per `tasks.md`. One task = one commit (FR-03). Each commit:
   - Lint + typecheck clean (FR-13)
   - Worker-undisturbed paths show empty diff (FR-07)
   - Commit message cites T-number (FR-03)
5. Stop at T<gate>. Do NOT proceed to T<deploy>. Wait for an explicit deploy handoff (FR-05).
6. Produce the gate report per `verification-gate.md` contract:
   - Every commit SHA per task
   - Test counts (before / after / delta per layer)
   - Lint + typecheck status
   - Worker-undisturbed git diff confirmation
   - Manifest version (if applicable)
   - Deviations from architect/PO plan with reasoning
7. Paste gate report back to operator.

## Implementer self-attestation

Implementer's first response must include:

> "Operating as Implementer under Fusebase Flow v0.1. I will follow FR-01 through FR-15 — including spec-before-code, plan-before-edit, one-task-one-commit, persist handoffs, stop-at-gate, reversible-by-default, worker-undisturbed verification, Mode-A chat / Mode-B docs, reproducibility-before-fix, stop-and-ask, approval-gated side effects, lint+typecheck per commit, single docs commit on deploy, and knowledge-curation triggers. Reading required files now."

## State announcement (every output)

```
---
📍 Phase: Implement
🎯 Ticket: <slug>
✅ Completed: T<first>..T<n-1> (<SHAs>)
📍 Current: T<n> (<task name>)
⏭️ Next: <next task OR "stopping at gate; reporting">
```

## Pre-commit attestation (every commit)

```
T<n> pre-commit check:
☐ Lint clean
☐ Typecheck clean
☐ Worker-undisturbed unchanged
☐ One task scope (no bundling)
☐ No TODO/FIXME/WIP markers
☐ Commit message cites T<n>

→ Committing T<n>: <scope>
```

If any check fails, STOP and fix before commit. No "fix in next commit" patterns.

## Handoff content template

```markdown
# Implement handoff — <slug> (<YYYY-MM-DD>)

**Status:** ready for Implementer
**Source spec:** `docs/specs/<slug>/spec.md`
**Decisions locked:** <Letter>1..<Letter>N
**Task range:** T<first>..T<gate> (stop at gate)

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md`
2. `AGENTS.md` (project-specific section)
3. `docs/specs/<slug>/spec.md`
4. `docs/specs/<slug>/decisions.md`
5. `docs/specs/<slug>/tasks.md`
6. `docs/specs/<slug>/verification-gate.md`

## Pre-cached identifiers

| Identifier | Value |
|---|---|
| Decision letter prefix | <Letter> |
| T-counter going in | T<first - 1>; first task is T<first> |
| Last shipped slice | <slug> (deploy <hash>, <date>) |

## Production state going in

<concrete pre-work production state for rollback comparison>

## Tracks (if parallel)

1. **Track A (T<a1>..T<a2>)** — <scope>
2. **Track B (T<b1>..T<b2>)** — <scope>

Verification gate (T<gate>) and deploy (T<deploy>) serialize after all tracks land.

## Worker-undisturbed posture

Zero diff expected on: <protected paths from policies/protected-paths.yml>
Bounded-additive expected on: <paths that may grow>

## Stop at gate

Per FR-05, stop at T<gate>. Do NOT run deploy. Report gate per `verification-gate.md` contract; operator will draft deploy handoff after review.
```

## Related

- `skills/implementation-planning/SKILL.md` — produces this handoff
- `workflows/verification-gate.md` — gate contract
- `workflows/greenlight-deploy.md` — next handoff after gate verifies
- `policies/protected-paths.yml` — worker-undisturbed list
