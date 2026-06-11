# Workflow: greenlight-implement

> **Style:** Mode-B-lite. The handoff from Product Owner session to AI Developer session.

## When to run

After `implementation-planning` has produced `decisions.md` (all locked), `tasks.md`, `verification-gate.md`, and the operator confirms decisions are locked.

## Procedure (Product Owner side)

1. Verify pre-handoff checklist:
   - [ ] `decisions.md` LOCKED **if present** — every decision shows `Lock status: LOCKED`; absence is valid per FR-23 when no real decision exists (spec.md records "no real decisions")
   - [ ] All clarify Q-A's resolved (none remain in `spec.md`)
   - [ ] `tasks.md` has T-numbers from current counter (not placeholders)
   - [ ] `verification-gate.md` exists and is complete
   - [ ] Constitution invariants explicitly affirmed in spec.md (worker-undisturbed list, mixed-fleet, etc.)
   - [ ] Letter prefix incremented in `AGENTS.md` (if a new ticket)
   - [ ] T-counter updated in `AGENTS.md`
2. **Author handoff from `templates/handoff-implement.md`** (v2.5.0+). The template includes a role-bootstrap prelude that makes the handoff self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up. Do NOT hand-roll the prelude; copy from the template so role-attestation language stays canonical.
3. Save to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-implement.md` BEFORE outputting in chat (FR-04). Fill in placeholders (slug, decisions range, task range, pre-cached identifiers, production state, tracks, worker-undisturbed posture).
4. Tell operator: "Implement handoff saved to `<path>`. Paste this into the AI Developer chat (fresh or existing) — the file is self-bootstrapping: `Execute docs/tmp/handoff/<path>`."

## Procedure (AI Developer side)

1. Read mandatory pre-execution files (per the handoff's reads list).
2. Self-attest: "Operating as AI Developer under Fusebase Flow v3.18.2. I will follow FR-01 through FR-25. I will apply Mode A on chat output and Mode B on every file I write. I will apply the role-discipline skill section for AI Developer (IM.1..IM.18)."
3. Pre-task git checkpoint: `git status --short`. If non-empty, STOP and ask operator.
4. Execute tasks T<first>..T<gate> per `tasks.md`. One task = one commit (FR-03). Each commit:
   - Lint + typecheck clean (FR-13)
   - Worker-undisturbed paths show empty diff (FR-07)
   - Commit message cites T-number (FR-03)
5. Stop at T<gate>. Do NOT proceed to T<deploy>. Wait for an explicit deploy handoff (FR-05).
6. Produce the gate report **using `templates/gate-report.md`** (v2.6.0+) — the canonical producer surface; required fields are machine-defined in `policies/gate-contracts.yml: gate_report`. The template includes a section-9 operator-relay block that the operator copies into PO chat — per FR-16, you (AI Developer) compose this block so the operator doesn't have to scan the technical body to figure out "what to tell PO."
7. Paste filled gate report back to operator. Operator copies section 9 block into PO chat for closeout per the **Operator Relay Protocol** (flow-skills/role-discipline/SKILL.md PO section).

## AI Developer self-attestation

Per `FLOW_RULES.md` § Self-attestation (FR-01..FR-25); name AI Developer as the role and `flow-skills/role-discipline/references/ai-developer.md` (IM.1..IM.18; entry: role-discipline SKILL.md). Canonical attestation paragraph lives in FLOW_RULES.md; don't duplicate it here.

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

The canonical implement handoff template (role-bootstrap prelude, mandatory reads, pre-cached identifiers discipline, production state, tracks, worker-undisturbed posture, stop-at-gate) lives at `templates/handoff-implement.md` — copy it and fill placeholders; never hand-roll.

## Related

- `templates/handoff-implement.md` — **canonical handoff template** (v2.5.0+); copy + fill placeholders for new handoffs
- `templates/gate-report.md` — **canonical gate report template** (v2.6.0+); AI Developer fills this when reaching T<gate>; section 9 is the operator-relay block per FR-16
- `flow-skills/implementation-planning/SKILL.md` — produces this handoff
- `flow-skills/role-discipline/SKILL.md` — PO section includes the **Operator Relay Protocol** (FR-16) used when operator pastes the gate report back to PO
- `workflows/verification-gate.md` — gate contract
- `workflows/greenlight-deploy.md` — next handoff after gate verifies
- `policies/protected-paths.yml` — worker-undisturbed list