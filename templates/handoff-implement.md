# Implement handoff template (v2.5.0+)

> **Mode B (full).** Dense, tabular, front-loaded. The Product Owner authors this file in `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md` and points the AI Developer session at it. The role-bootstrap prelude at the top makes the file self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up.

---

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v2.1.

**Self-attest in your first response, verbatim:**

> "Operating as AI Developer under Fusebase Flow v2.1. I will follow FR-01 through FR-15 — including spec-before-code, plan-before-edit, one-task-one-commit, persist handoffs, stop-at-gate, reversible-by-default, worker-undisturbed verification, Mode-A chat / Mode-B docs, reproducibility-before-fix, stop-and-ask, approval-gated side effects, lint+typecheck per commit, single docs commit on deploy, and knowledge-curation triggers. I will apply the role-discipline skill section for AI Developer (IM.1..IM.10) and use its refusal phrasing when an action would violate a rule. Reading required files now."

**Hard invariants (do NOT violate):**

- **Stop at the verification gate.** Do NOT proceed to deploy. Wait for an explicit deploy handoff (FR-05).
- **One task = one commit** (FR-03). Each commit cites a `T<number>`.
- **Lint + typecheck clean per commit** (FR-13).
- **Worker-undisturbed paths** show empty diff per `policies/protected-paths.yml` (FR-07).
- **Mode A** (visual, concrete, brief) on chat output. **Mode B** (dense, tabular, front-loaded) on every file written to disk.
- **Reproducibility before fix** (FR-09). For any observed failure, reproduce locally before claiming a fix.
- **Stop and ask** (FR-10) on any ambiguity. Do not guess.

**Refusal phrasing** when a request would violate a rule:

> "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01 through FR-15
2. `AGENTS.md` (project-specific section, especially worker-undisturbed paths and project invariants)
3. `docs/specs/<slug>/spec.md` — locked spec
4. `docs/specs/<slug>/decisions.md` — every decision with `Lock status: LOCKED`
5. `docs/specs/<slug>/tasks.md` — T-numbered task list
6. `docs/specs/<slug>/verification-gate.md` — gate contract you'll have to satisfy
7. `policies/protected-paths.yml` — worker-undisturbed list
8. `skills/role-discipline/SKILL.md` (or `.claude/skills/role-discipline/SKILL.md`) — IM.1..IM.10 don't-list

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `<slug>` |
| **Status** | ready for AI Developer |
| **Source spec** | `docs/specs/<slug>/spec.md` |
| **Decisions locked** | `<Letter>1..<Letter>N` |
| **Task range (this handoff)** | `T<first>..T<gate>` (stop at gate) |
| **Decision letter prefix** | `<Letter>` (e.g., `G`) |
| **T-counter going in** | `T<first - 1>`; first task is `T<first>` |
| **Last shipped slice** | `<previous-slug>` (deploy `<hash>`, `<date>`) |

---

## Pre-cached identifiers

> **Discipline:** the AI Developer should not waste cycles discovering stable IDs the operator already knows. The PO bakes them in. AI Developer verifies (one quick read) but does not re-derive.

| Identifier | Value | Why it's pre-cached |
|---|---|---|
| Database / store IDs | `<store-id>`, `<dashboard-id>`, `<view-id>`, etc. | Avoid round-trip discovery via MCP / API every session |
| Test fixture user / account | `<identifier>` | Reuse the same fixture across runs for deterministic results |
| Worker / API tokens (env var name only — never the value) | `WORKER_TOKEN`, `FEATURE_TOKEN`, etc. | AI Developer reads from env; PO does not paste secrets |
| API base URL | `<url>` (dev / staging / prod as appropriate) | Smoke probes hit a known surface |
| Other project-stable IDs | `<...>` | Anything the operator already knows that the AI Developer would otherwise re-derive |

If an identifier needs verification (e.g., the dashboard was renamed), note it: `Dashboard "Operator Console" — verify view_id is current; was vw9ka2sl as of 2026-05-08`.

**Anti-patterns:**
- ❌ AI Developer queries the API for IDs that were already known. Wasted tokens; risk of grabbing the wrong ID.
- ❌ PO embeds secret VALUES in the handoff. Use env var NAMES; the value lives in the environment.
- ❌ PO pre-caches a "should-be-stable" ID without verifying it. Verify before pasting; stale IDs are worse than missing IDs.

---

## Production state going in

<concrete pre-work production state for rollback comparison; e.g., commit SHA, deploy hash, table row counts, last-known-good probe outputs>

---

## Tracks (if parallel)

1. **Track A (T<a1>..T<a2>)** — <scope>
2. **Track B (T<b1>..T<b2>)** — <scope>

Verification gate (T<gate>) and deploy (T<deploy>) serialize after all tracks land.

---

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| Zero diff expected | <paths from policies/protected-paths.yml> |
| Bounded-additive expected | <paths that may grow but only with new files / appends> |

---

## Stop at gate

Per FR-05, stop at `T<gate>`. Do NOT run deploy. Report gate per `verification-gate.md` contract; operator will draft deploy handoff after review.

---

## Per-output state announcement (every chat reply)

```
---
📍 Phase: Implement
🎯 Ticket: <slug>
✅ Completed: T<first>..T<n-1> (<SHAs>)
📍 Current: T<n> (<task name>)
⏭️ Next: <next task OR "stopping at gate; reporting">
```

## Per-commit pre-attestation

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

---

## Gate report contract (when you reach `T<gate>`)

Produce a Mode B report containing:

- Every commit SHA per task (T<first>..T<gate>)
- Test counts (before / after / delta per layer)
- Lint + typecheck status per commit
- Worker-undisturbed git diff confirmation (literal `git diff` output truncated to "no changes")
- Manifest version (if applicable)
- Deviations from architect/PO plan with reasoning
- Pointer to the gate satisfaction in `verification-gate.md`

Paste the report back to operator. Then **halt**. Do not run any post-gate task.

---

## Notes / context (PO-authored)

<free-form section for PO to add ticket-specific context: known pitfalls, related tickets, design rationale not in decisions.md, etc.>
