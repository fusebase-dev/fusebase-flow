# Gate report template (v2.6.0+)

> **Mode B (full).** This template is what the **AI Developer** produces when it reaches the verification gate (`T<gate>`) and stops per FR-05 / IM.8. The structure has two sections: the **technical gate body** (for the PO's analytical work — verifying gate satisfaction, lint+typecheck, worker-undisturbed, etc.) and the **operator relay block** at the bottom (a copy-paste-ready chunk the operator pastes into the PO chat, so the PO never has to ask the operator "what did the AI Developer say?").
>
> Per FR-16, the AI Developer composes the operator-relay block — the operator never has to digest the technical body to figure out "what to send to PO." Scroll to bottom → copy the relay block → done.

---

## Use this template when

You are an AI Developer session that has just completed `T<first>..T<gate>` and is about to halt at the gate. Don't generate ad-hoc gate reports — copy this template, fill it in, output it as your final response. The bottom block is what the operator copies to PO.

---

## Template body

```markdown
# Gate report — <slug> (T<gate>)

**Status:** Gate reached; awaiting PO review and deploy handoff
**Slug:** `<slug>`
**Task range:** T<first>..T<gate>
**Reporting session:** AI Developer (under Fusebase Flow v3.20.1, FR-01..FR-26)
**Date:** <YYYY-MM-DD>

---

## 1. Per-task commit table

| Task | Title | Commit SHA | Started (UTC) | Committed (UTC) | Wall-clock | Lint | Typecheck | Worker-undisturbed | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T<first> | <task title> | `<sha>` | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` | ✓ | ✓ | empty diff | — |
| T<first+1> | <task title> | `<sha>` | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` | ✓ | ✓ | empty diff | — |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |
| T<gate-1> | <task title> | `<sha>` | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` | ✓ | ✓ | empty diff | — |
| T<gate> | <gate task title> | `<sha>` | `<HH:MM:SS>` | `<HH:MM:SS>` | `<m:ss>` | ✓ | ✓ | empty diff | gate evidence captured |

**Per IM.11 (v2.8.0+):** wall-clock = `committed_at − started_at` per task. Net active development time = sum of wall-clocks. Wait-for-operator time happens between tasks (gate review, decisions, etc.) and is naturally excluded — the agent isn't doing work then.

---

## 1b. Time totals

| Metric | Value | Notes |
|---|---|---|
| First task started | `<YYYY-MM-DD HH:MM:SS UTC>` | T<first> |
| Gate task committed | `<YYYY-MM-DD HH:MM:SS UTC>` | T<gate> |
| **Total elapsed (wall)** | `<H:MM:SS>` | end-to-end including all waits |
| **Total active development** | `<H:MM:SS>` | sum of per-task wall-clocks; **excludes wait time** |
| Wait time (elapsed − active) | `<H:MM:SS>` | operator feedback / decision pauses between tasks |
| Tasks completed | `<count>` | T<first>..T<gate> |
| Average task wall-clock | `<m:ss>` | active dev / tasks |

These numbers feed retrospective analysis per FR-15. Historical comparison helps predict future task chains and identify task-types that consistently run over/under estimate.

---

## 2. Test counts (before / after / delta)

| Layer | Before | After | Delta | Notes |
|---|---|---|---|---|
| Unit | <N> | <N> | <±N> | <e.g., new tests added for T17> |
| Integration | <N> | <N> | <±N> | — |
| E2E | <N> | <N> | <±N> | — |
| Total | <N> | <N> | <±N> | — |

All test runs PASS / show <N> failures (list below if any).

---

## 3. Lint + typecheck status

```
$ npm run lint
<paste actual output — must show 0 errors>

$ npm run typecheck
<paste actual output — must show 0 errors>
```

---

## 4. Worker-undisturbed verification

Per `policies/protected-paths.yml`:

```
$ git diff <commit-before-T<first>> HEAD -- <protected-path-1>
<must show no changes>

$ git diff <commit-before-T<first>> HEAD -- <protected-path-2>
<must show no changes>
```

Bounded-additive paths (where applicable):
- `<path>` — added <N> lines (new files only / appended only)

---

## 5. Manifest version (if applicable)

| Field | Before | After |
|---|---|---|
| Manifest version | `<old>` | `<new>` |
| Schema version | `<old>` | `<new>` |
| Other manifest fields | ... | ... |

---

## 6. Deviations from architect / PO plan

| Deviation | Why | Approved? |
|---|---|---|
| <e.g., split T19 into T19a + T19b> | <reason> | <self-approved per FR-03 / yes per operator chat> |
| <none, if no deviations> | — | — |

If no deviations: state **"No deviations from the locked plan."**

---

## 7. Gate satisfaction

Per `docs/specs/<slug>/verification-gate.md`:

| Gate item | Required | Actual | Pass? |
|---|---|---|---|
| <gate criterion 1> | <expected> | <observed> | ✓ |
| <gate criterion 2> | <expected> | <observed> | ✓ |
| ... | ... | ... | ... |

---

## 8. Operator-side actions still pending (if any)

| Action | Owner | Why pending | Suggested timing |
|---|---|---|---|
| <e.g., PATCH the canonical agent files post-deploy> | Operator | Requires manual SSH | Post-deploy |
| <none, if all clear> | — | — | — |

---

## 9. For operator: paste this in PO chat

**Per FR-16, the operator should copy the block below verbatim and paste into the PO chat. The PO will brief, recommend next steps, and prepare your response — no need to read the technical sections above unless you want to.**

````
Gate reached for <slug> (T<gate>). AI Developer is halted at the gate per FR-05 / IM.8.

Headline: <one-line summary — e.g., "All gate items PASS. Ready for PO review and deploy handoff.">

Per-task commits: T<first>..T<gate> (<count> commits). All lint+typecheck clean. Worker-undisturbed: empty diff on all protected paths.

Time totals (per IM.11 / v2.8.0+):
  - Total elapsed (wall): <H:MM:SS>
  - Total active development: <H:MM:SS> (excludes wait time)
  - Wait time: <H:MM:SS>
  - Average task wall-clock: <m:ss>

Test deltas:
  - Unit: <N> -> <N> (<±N>)
  - Integration: <N> -> <N> (<±N>)
  - E2E: <N> -> <N> (<±N>)

Deviations from plan: <none / list>.

Pending operator actions post-deploy: <none / list>.

Full gate report attached above. PO: please follow Operator Relay Protocol — brief me in Mode A, recommend next steps with #1 marked, then give me the verbatim prompt to paste back if I need to respond to AI Developer.
````

---

📍 Phase: Implement (gate reached)
🎯 Ticket: `<slug>`
✅ Completed: T<first>..T<gate> (<commit count>)
⏭️ Next: PO review of gate report → deploy handoff (or fix-forward if any item failed)
```

---

## Fill-in checklist

When filling this template, the AI Developer should consult `templates/references/gate-report-checklist.md` for the canonical fill-in checklist (v2.9.0+ — lazy-loaded reference). Don't paraphrase the checklist into the filled artifact; it's a fill-time aid, not output content.


## Why the operator-relay block matters (FR-16 / v2.6.0)

Pre-v2.6.0, gate reports were technical Mode B documents the operator had to scan to figure out "what's the headline / what should I tell PO?" That's framework cognitive load on the operator — wrong direction.

Post-v2.6.0, the AI Developer composes the relay block as part of the report. The operator copies that block verbatim into PO chat. PO then runs the **Operator Relay Protocol** (flow-skills/role-discipline/SKILL.md § Operator Relay Protocol) on it: analyze, brief, recommend with #1 marked, await approval, generate paste-back prompt. Per FR-19, the operator's job is chat-based copy/paste relay, not clicking popup menus.

The structure is the enforcement: an AI Developer can't ship a gate report without filling section 9, because the template ends there.