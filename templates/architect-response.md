# Architect response template (v2.6.0+)

> **Mode B (full).** This template is what an **Architect (escalated session)** produces when responding to a PO escalation handoff. The Architect has already produced the spec / decisions (PENDING) / tasks (T-numbered) / verification-gate artifacts in `docs/specs/<slug>/` (per AR.2); this response summarizes them. Two sections: the **technical architect body** (which the PO + operator review and lock — the Architect recommends, they lock per AR.6) and the **operator relay block** at the bottom (a copy-paste-ready chunk the operator pastes into PO chat).
>
> Per FR-16, the Architect composes the operator-relay block — the operator never digests the technical body to figure out what to tell PO. Scroll → copy → paste.

---

## Use this template when

You are an Architect session that has investigated a complex / cross-cutting design problem escalated by the PO and is about to return findings + recommendations. Don't ad-hoc the architect response — copy this template, fill it in, output it as your final response.

---

## Template body

```markdown
# Architect response — <slug> (escalated investigation)

**Status:** Architect investigation complete; spec / decisions (PENDING locks) / tasks / verification-gate produced in `docs/specs/<slug>/`; awaiting PO + operator to review and lock
**Slug:** `<slug>`
**Reporting session:** Architect under Fusebase Flow v4.5.0 (FR-01..FR-27, AR.1..AR.9)
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

## 6. Decisions produced (PENDING lock)

The Architect produced `docs/specs/<slug>/decisions.md` with these letter-decisions (recommended choices + alternatives + reasoning), status PENDING. Per AR.6 the Architect does NOT lock — PO + operator review and lock.

| Letter | Decision | Recommended choice | Rationale |
|---|---|---|---|
| `<Letter>1` | <decision question> | <choice> | <reason> |
| `<Letter>2` | <decision question> | <choice> | <reason> |
| ... | ... | ... | ... |

---

## 7. Task chain produced (T-numbered in `tasks.md`)

The Architect produced `docs/specs/<slug>/tasks.md` as a T-numbered chain (per AR.2). This table summarizes it; PO + operator review, not re-number.

| T# | Task description | Component touched | Notes |
|---|---|---|---|
| T<first> | <task> | <component> | <e.g., Track A> |
| T<first+1> | <task> | <component> | <e.g., Track A, depends on prior> |
| T<first+2> | <task> | <component> | <e.g., Track B, parallel> |
| ... | ... | ... | ... |
| T<gate> | Verification gate | — | — |

---

## 8. Verification-gate criteria produced (in `verification-gate.md`)

The Architect produced `docs/specs/<slug>/verification-gate.md` (per AR.2). This table summarizes its criteria; PO + operator review.

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

Task chain: <N> tasks across <M> tracks, T-numbered in tasks.md (Architect produced the chain per AR.2; PO + operator review).

Worker-undisturbed: <e.g., "no protected paths touched"> / <e.g., "needs approval artifact for path X — see section 9">.

Out-of-scope items filed to backlog: <count> tickets (see section 11).

Risks / unknowns: <count> items, highest-impact: <one-line>.

Full architect response attached above. PO: please follow Operator Relay Protocol — brief me in Mode A, recommend whether to lock these decisions, then give me the verbatim prompt to paste back to the AI Developer when implementation begins.
````

---

📍 Phase: Decisions (architect handoff complete; artifacts produced — awaiting PO + operator review and lock)
🎯 Ticket: `<slug>`
⏭️ Next: PO + operator review the produced decisions.md / tasks.md / verification-gate.md and lock each `<Letter>1..<Letter>N` (Architect recommends, operator locks per AR.6) → PO drafts the Implement handoff to AI Developer
```

---

## Fill-in checklist

When filling this template, the Architect should consult `templates/references/architect-response-checklist.md` for the canonical fill-in checklist (v2.9.0+ -- lazy-loaded reference). Don't paraphrase the checklist into the filled artifact; it's a fill-time aid, not output content.


## Why the operator-relay block matters (FR-16 / v2.6.0)

Architect responses are dense. The operator wants to know two things: **what's the recommendation?** and **should we proceed?** The relay block answers both at the top of PO's chat. The PO digests the technical body to draft decisions / tasks / verification-gate; the operator doesn't have to read past the relay block unless they want to.