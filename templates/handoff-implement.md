# Implement handoff template (v2.5.0+)

> **Mode B (full).** Dense, tabular, front-loaded. The Product Owner authors this file in `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md` and points the AI Developer session at it. The role-bootstrap prelude at the top makes the file self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up.

---

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v3.6.0.

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-20), naming AI Developer as the role and the IM.1..IM.17 role-discipline section. (v2.9.0+ uses reference-by-citation instead of embedding the full attestation paragraph here — the canonical text lives in FLOW_RULES.md and you've already loaded it; duplication here would be ~250 tokens of waste per handoff.)

**Hard invariants** are the FR rules cited in `FLOW_RULES.md` table. Particularly load-bearing for AI Developer Implement-phase work: FR-03 (one task = one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-09 (Mode B for files), FR-10 (reproducibility before fix), FR-13 (lint+typecheck per commit), FR-18 (supersede, don't accumulate). Don't paraphrase these here — read them in FLOW_RULES.md.

**Refusal phrasing** for any rule violation request:

> "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01 through FR-20
2. `AGENTS.md` (project-specific section, especially worker-undisturbed paths and project invariants)
3. `docs/specs/<slug>/spec.md` — locked spec
4. `docs/specs/<slug>/decisions.md` — every decision with `Lock status: LOCKED`
5. `docs/specs/<slug>/tasks.md` — T-numbered task list
6. `docs/specs/<slug>/verification-gate.md` — gate contract you'll have to satisfy
7. `policies/protected-paths.yml` — worker-undisturbed list
8. `skills/role-discipline/SKILL.md` (or `.claude/skills/role-discipline/SKILL.md`) — IM.1..IM.17 don't-list

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

## Frontend / UI implementation brief (if applicable)

> Required for tickets that add or change a user/operator-facing UI, prompt flow, dashboard, or frontend route. If not applicable, write `N/A`.

| Field | Value |
|---|---|
| Selected design direction | `<decision ref, option name, or N/A>` |
| Product identity / target user | `<who this is for and what problem the surface solves>` |
| Routes / screens / workflows in scope | `<list>` |
| Components or files in scope | `<paths or modules>` |
| Data types and fields | `<entities, fields, state names>` |
| API/helper surfaces | `<function/hook/helper names and signatures, or N/A>` |
| Applicable stack conventions / project frontend rules | `<paths to project-local skill/docs, or N/A>` |
| Stable test selectors | `<required selector strategy for interactive and meaningful dynamic elements, or N/A>` |
| Trust-critical real interactions | `<save/send/auth/search/filter/etc.; no placeholder behavior>` |
| Brand/source assets | `<local paths or N/A; never vague remote references only>` |
| Explicit non-goals | `<routes, entities, workflows, or visual constraints AI Developer must not invent>` |

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