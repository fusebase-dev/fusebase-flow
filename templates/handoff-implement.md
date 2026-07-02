# Implement handoff template (v2.5.0+)

> **Mode B (full).** Dense, tabular, front-loaded. The Product Owner authors this file in `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-implement.md` and points the AI Developer session at it. The role-bootstrap prelude at the top makes the file self-bootstrapping in any agent (Claude Code, Codex, etc.) — fresh chat or follow-up.
>
> **Procedure freshness:** before executing any reused/copied procedural block, check whether a capability shipped since it was written supersedes the procedure (e.g., self-recording deploys obsolete poll-watching) — CHANGELOG / skill catalog vs this template's cited version.

---

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v3.30.4.

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-27), naming AI Developer as the role and the IM.1..IM.18 role-discipline section. (v2.9.0+ uses reference-by-citation instead of embedding the full attestation paragraph here — the canonical text lives in FLOW_RULES.md and you've already loaded it; duplication here would be ~250 tokens of waste per handoff.)

**Hard invariants** are the FR rules cited in `FLOW_RULES.md` table. Particularly load-bearing for AI Developer Implement-phase work: FR-03 (one task = one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-10 (reproducibility before fix), FR-13 (lint+typecheck per commit). **Liveness (FR-27)** — any long/silent background work (your own probe/script/deploy/fetch-loop/browser-automation, a sub-agent, or a workflow) gets ≥1 liveness guarantee BEFORE launch: bound it (`source hooks/local/lib/bounded-run.sh`), complete it in-turn, or return `BLOCKED-AT-<gate>` + a record-then-read pointer — never launch bare; a hung task emits no completion event and the session idles silently (`flow-skills/liveness-discipline`). **Write-time discipline (FR-24)** — apply the `role-discipline` § Write-time discipline digest on every artifact/code write: FR-23 (doc-budget/tier + pointers), FR-09 (Mode B), FR-18 (supersede), FR-22 (comments: tripwire + pointer only; do NOT match density upward), FR-25 (module-size ratchet: don't grow over-ceiling files; extract along a responsibility seam — in-scope, not creep), FR-26 (token-efficient execution: no re-reads of unchanged files, two-strike retry rule, targeted edits — quality outranks tokens). Don't paraphrase these here — read them in FLOW_RULES.md / the cited skills.

**Refusal phrasing** for any rule violation request:

> "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01 through FR-27 (stop at `## Amendment log` — dated history)
2. `AGENTS.md` (project-specific section, especially worker-undisturbed paths and project invariants)
3. `docs/specs/<slug>/spec.md` — locked spec
4. `docs/specs/<slug>/decisions.md` — every decision with `Lock status: LOCKED`
5. `docs/specs/<slug>/tasks.md` — T-numbered task list
6. `docs/specs/<slug>/verification-gate.md` — gate contract you'll have to satisfy
7. `policies/protected-paths.yml` — worker-undisturbed list
8. `flow-skills/role-discipline/references/ai-developer.md` (mirrored under `.claude/skills/`) — IM.1..IM.18 don't-list; shared protocols in `flow-skills/role-discipline/SKILL.md`

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

When delegating a code-writing slice, inline the **Write-time discipline digest** + the **Comment policy (FR-22) — Delegation push block** rendered verbatim in the § below into the sub-agent prompt (FR-24 / FR-22 push; sub-agents don't auto-load skills or the always-on digest), plus the **Delegation contract push block** (`task-delegation` §3): *"complete within this turn (no self-resume; poll in-turn or read durable records); write durable facts into your owed artifacts AS THEY OCCUR — skeleton first, rows as earned; on an unbounded wait (human gate, no-ETA event) return `BLOCKED-AT-<gate>` + where reality is recorded; return verdict · SHAs · deltas · artifact pointers, never re-pasted bodies; state-change claims cite the ground-truth check performed."*

---

## Comment policy (FR-22) — applies to all code written under this handoff
<!-- prevents: fr22-undelivered-to-sub-agents — taxonomy: docs/specs/fr22-delivery-guarantee/spec.md -->

> **Present-by-construction (not "remember to inline").** This block ships in the template, so every authored handoff carries the FR-22 rule by construction — it is NOT an optional reminder the PO must recall. Single source of truth for the rule body: `flow-skills/comment-policy/SKILL.md` § Delegation push block; rendered here verbatim so the AI Developer (and any code-writing sub-agent — paste this block into its prompt, FR-24) sees it at write time. Do NOT delete this section.

```
COMMENT POLICY (FR-22) — applies to all code you write:
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision B2)" or "backlog 156".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```

After your code passes, emit the review-ran marker in chat (per `policies/required-artifacts.yml: comment_policy_review_applied`):
- `comment-policy review: applied (FR-22)` — when this handoff produced a code diff.
- `comment-policy review: N/A (FR-22; no code diff)` — for a no-source task.

This records that the review RAN; it never inspects comment content (FR-22 forbids a content gate). Absence of the marker → a non-blocking warn at the done gate, not a deny.

---

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| Zero diff expected | <paths from policies/protected-paths.yml> |
| Bounded-additive expected | <paths that may grow but only with new files / appends> |

---

## Stop at gate
<!-- prevents: false-green-deploy, unauthorized-deploy — taxonomy: policies/ratchet-governance.yml (A3) -->

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

<!-- prevents: broken-main (lint/typecheck), regression-attribution-loss (one task scope), silent-protected-path-drift (worker-undisturbed) — taxonomy: policies/ratchet-governance.yml -->
```
T<n> pre-commit check:
☐ Lint clean
☐ Typecheck clean
☐ Worker-undisturbed unchanged
☐ One task scope (no bundling)
☐ No TODO/FIXME/WIP markers
☐ Comments: tripwire + pointer only (FR-22) — no WHAT-restating/changelog; density not matched upward; pointers kept
☐ Module size (FR-25): no gated file grew past ceiling/baseline; extraction on a responsibility seam if needed
☐ Commit message cites T<n>

→ Committing T<n>: <scope>
```

If any check fails, STOP and fix before commit. No "fix in next commit" patterns.

---

## Gate report contract (when you reach `T<gate>`)

Produce the gate report from `templates/gate-report.md` (incl. the section-9 operator-relay block); required fields per `policies/gate-contracts.yml: gate_report`.

Paste the report back to operator. Then **halt**. Do not run any post-gate task.

---

## Notes / context (PO-authored)

<free-form section for PO to add ticket-specific context: known pitfalls, related tickets, design rationale not in decisions.md, etc.>