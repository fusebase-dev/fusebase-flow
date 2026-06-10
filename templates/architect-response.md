# Architect response template (v2.6.0+)

> **Mode B (full).** This template is what an **Architect (escalated session)** produces when responding to a PO escalation handoff. Two sections: the **technical architect body** (for the PO to convert into locked decisions, tasks, verification gate) and the **operator relay block** at the bottom (a copy-paste-ready chunk the operator pastes into PO chat).
>
> Per FR-16, the Architect composes the operator-relay block — the operator never digests the technical body to figure out what to tell PO. Scroll → copy → paste.

---

## Use this template when

You are an Architect session that has investigated a complex / cross-cutting design problem escalated by the PO and is about to return findings + recommendations. Don't ad-hoc the architect response — copy this template, fill it in, output it as your final response.

---

## Template body

```markdown
# Architect response — <slug> (escalated investigation)

**Status:** Architect investigation complete; awaiting PO to draft decisions / tasks / verification-gate
**Slug:** `<slug>`
**Reporting session:** Architect (Fusebase Flow v3.1, FR-01..FR-25, AR.1..AR.9)
**Date:** <YYYY-MM-DD>

---

## 1. Investigation scope (what the PO asked)

<verbatim or paraphrased PO escalation question — what was I asked to investigate?>

In-scope: <list>
Out-of-scope (per AR.1): <list — these went to backlog>

---

## 2. Findings

<concise narrative or bullet list of what I found. What the system is actually doing today, what constraints apply, what surprises showed up.>

Citations (per FR-15 — knowledge curation):

| Source | What it says |
|---|---|
| `<file path>:<line>` | <relevant fact> |
| `docs/constitution.md` § <section> | <relevant rule> |
| `policies/<file>.yml` | <relevant constraint> |
| ... | ... |

---

## 3. Constraints (what limits the design space)

| Constraint | Source | Implication |
|---|---|---|
| <e.g., migrations are blocked> | `docs/constitution.md` "Critical constraints" + `policies/protected-paths.yml: migration_and_schema` | No schema changes possible in this design |
| <e.g., worker-undisturbed paths X, Y, Z> | `policies/protected-paths.yml` | Implementation must show empty diff on these |
| ... | ... | ... |

---

## 4. Recommended design

**Approach:** <one-line summary — e.g., "Adapter pattern that wraps existing schema; no migration needed.">

| Component | Where it lives | What it does |
|---|---|---|
| <component-1> | `<path>` | <function> |
| <component-2> | `<path>` | <function> |
| ... | ... | ... |

**Why this design:**
- <reason 1>
- <reason 2>
- <reason 3>

---

## 5. Alternatives considered (and why rejected)

| Alternative | Pro | Con | Why rejected |
|---|---|---|---|
| <alt A> | <pro> | <con> | <reason> |
| <alt B> | <pro> | <con> | <reason> |

---

## 6. Proposed decisions to lock (for PO)

These are recommendations only — per AR.6, the Architect doesn't lock decisions. PO + operator lock.

| Letter | Decision | Recommended choice | Rationale |
|---|---|---|---|
| `<Letter>1` | <decision question> | <choice> | <reason> |
| `<Letter>2` | <decision question> | <choice> | <reason> |
| ... | ... | ... | ... |

---

## 7. Proposed task list shape (for PO to T-number)

| # | Task description | Component touched | Notes |
|---|---|---|---|
| 1 | <task> | <component> | <e.g., Track A> |
| 2 | <task> | <component> | <e.g., Track A, depends on #1> |
| 3 | <task> | <component> | <e.g., Track B, parallel to #1-2> |
| ... | ... | ... | ... |
| N | Verification gate (T<gate>) | — | — |

---

## 8. Proposed verification-gate criteria (for PO)

| Criterion | How to verify |
|---|---|
| <criterion 1> | <verification method> |
| <criterion 2> | <verification method> |
| ... | ... |

---

## 9. Worker-undisturbed posture for this design (per AR.3)

| Posture | Paths |
|---|---|
| Zero diff expected | <paths from policies/protected-paths.yml> |
| Bounded-additive expected | <paths> |
| Not affected | <paths or "all other code paths"> |

If any protected path will need to be touched (rare): explicitly call out and propose an `approval-policy.local.yml` exception artifact.

---

## 10. Risks / unknowns

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| <risk 1> | <L/M/H> | <L/M/H> | <mitigation> |
| <risk 2> | <L/M/H> | <L/M/H> | <mitigation> |

---

## 11. Out-of-scope items filed to backlog (per AR.1)

| Backlog ticket | Why it's separate |
|---|---|
| `docs/backlog/<slug-1>/README.md` | <reason> |
| `docs/backlog/<slug-2>/README.md` | <reason> |

---

## 12. For operator: paste this in PO chat

**Per FR-16, the operator should copy the block below verbatim and paste into the PO chat. The PO will brief, recommend whether to proceed with this design, and prepare your response. No need to read the technical sections above unless you want to.**

````
Architect investigation complete for <slug>.

Headline: <one-line summary — e.g., "Recommend adapter pattern (Approach A); no migration needed; ~5 tasks across 2 tracks.">

Recommended approach: <one sentence>

Decisions to lock (for PO to formalize):
  <Letter>1: <question> -> recommended <choice>
  <Letter>2: <question> -> recommended <choice>
  ...

Task shape: <N> tasks across <M> tracks (Architect proposes structure; PO assigns T-numbers).

Worker-undisturbed: <e.g., "no protected paths touched"> / <e.g., "needs approval artifact for path X — see section 9">.

Out-of-scope items filed to backlog: <count> tickets (see section 11).

Risks / unknowns: <count> items, highest-impact: <one-line>.

Full architect response attached above. PO: please follow Operator Relay Protocol — brief me in Mode A, recommend whether to lock these decisions, then give me the verbatim prompt to paste back to the AI Developer when implementation begins.
````

---

📍 Phase: Decisions (architect handoff complete; awaiting PO formalization)
🎯 Ticket: `<slug>`
⏭️ Next: PO drafts decisions.md (locking each `<Letter>1..<Letter>N`), tasks.md (T-numbered), verification-gate.md → Implement handoff to AI Developer
```

---

## Fill-in checklist

When filling this template, the Architect should consult `templates/references/architect-response-checklist.md` for the canonical fill-in checklist (v2.9.0+ -- lazy-loaded reference). Don't paraphrase the checklist into the filled artifact; it's a fill-time aid, not output content.


## Why the operator-relay block matters (FR-16 / v2.6.0)

Architect responses are dense. The operator wants to know two things: **what's the recommendation?** and **should we proceed?** The relay block answers both at the top of PO's chat. The PO digests the technical body to draft decisions / tasks / verification-gate; the operator doesn't have to read past the relay block unless they want to.