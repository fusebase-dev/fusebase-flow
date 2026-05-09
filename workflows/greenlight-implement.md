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
2. Self-attest: "Operating as Implementer under Fusebase Flow v0.1. I will follow FR-01 through FR-15. I will apply Mode A on chat output and Mode B on every file I write. I will apply the role-discipline skill section for Implementer (IM.1..IM.10)."
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

> "Operating as Implementer under Fusebase Flow v0.1. I will follow FR-01 through FR-15 — including spec-before-code, plan-before-edit, one-task-one-commit, persist handoffs, stop-at-gate, reversible-by-default, worker-undisturbed verification, Mode-A chat / Mode-B docs, reproducibility-before-fix, stop-and-ask, approval-gated side effects, lint+typecheck per commit, single docs commit on deploy, and knowledge-curation triggers. I will apply the role-discipline skill section for Implementer (IM.1..IM.10) and use its refusal phrasing when an action would violate a rule. Reading required files now."

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

> **Discipline:** the Implementer should not waste cycles discovering stable IDs that the operator already knows. The PO bakes them into the handoff. The Implementer verifies (one quick read) but does not re-derive.

| Identifier | Value | Why it's pre-cached |
|---|---|---|
| Decision letter prefix | `<Letter>` (e.g., `G`) | Implementer references decisions as `<Letter>1`, `<Letter>2` in commit messages and gate report |
| T-counter going in | `T<first - 1>`; first task is `T<first>` | One-task-one-commit (FR-03) requires exact T-numbers |
| Last shipped slice | `<slug>` (deploy `<hash>`, `<date>`) | Production state baseline for rollback comparison |
| Database / store IDs | `<store-id>`, `<dashboard-id>`, `<view-id>`, etc. | Avoid round-trip discovery via MCP / API every session |
| Test fixture user / account | `<identifier>` | Reuse the same fixture across runs for deterministic results |
| Worker / API tokens (env var name only — never the value) | `WORKER_TOKEN`, `FEATURE_TOKEN`, etc. | Implementer reads from env; PO does not paste secrets |
| API base URL | `<url>` (dev / staging / prod as appropriate) | Smoke probes hit a known surface |
| Other project-stable IDs | `<...>` | Anything the operator already knows that the Implementer would otherwise re-derive |

### Pre-caching examples

```markdown
| Identifier | Value |
|---|---|
| Decision letter prefix | G |
| T-counter going in | T57; first task is T58 |
| Last shipped slice | priority-fix (deploy hsq0zy6d, 2026-05-08) |
| Isolated store "enrichment" | store_id: yz81xs9a |
| Dashboard "Operator Console" | dashboard_id: dxh3p4ty, view_id: vw9ka2sl |
| Worker token env var | WORKER_TOKEN |
| API base URL | https://app-api.fusebase.dev/v4/api/proxy/dashboard-service/v1 |
```

### Anti-patterns

- ❌ Implementer queries the API for IDs that were already known. Wasted tokens; risk of grabbing the wrong ID.
- ❌ PO embeds secret VALUES in the handoff. Use env var NAMES; the value lives in the environment.
- ❌ PO pre-caches a "should-be-stable" ID without verifying it. Verify before pasting; stale IDs are worse than missing IDs.

If an identifier needs verification (e.g., the dashboard was renamed), note it: `Dashboard "Operator Console" — verify view_id is current; was vw9ka2sl as of 2026-05-08`.

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
