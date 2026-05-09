# Decisions — <slug>

**Letter prefix:** <Letter>
**Approval status:** PENDING all locks | Locked by <operator> on <YYYY-MM-DD>
**Linked spec:** `docs/specs/<slug>/spec.md`

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| <Letter>1 | <short title> | <option chosen> | PENDING / LOCKED / REDIRECTED |
| <Letter>2 | <short title> | <option chosen> | PENDING |
| <Letter>3 | <short title> | <option chosen> | PENDING |

## <Letter>1. <Decision title>

**Recommendation:** <option chosen>.

**Reasoning:** <why this over alternatives. Cite file:line where grounded in code, e.g., `repository.ts:1665-1706`. Explain how this serves the ticket's goal.>

**Alternatives considered:**

- **Option A:** <what it would do> — rejected: <reason>
- **Option B:** <what it would do> — rejected: <reason>

**Lock status:** PENDING

---

## <Letter>2. <Next decision title>

**Recommendation:** ...

**Reasoning:** ...

**Alternatives considered:**

- **Option A:** ...
- **Option B:** ...

**Lock status:** PENDING

---

## <Letter>N. <Last decision>

...

---

## Lock confirmation

When operator says `lock`, all PENDING decisions flip to LOCKED with date stamp. When operator says `redirect <Letter><n>`, that decision moves to discussion (recommendation re-drafted; lock re-attempted).

| ID | Final option | Locked by | Date |
|---|---|---|---|
| <Letter>1 | <option> | <operator> | <YYYY-MM-DD> |
| <Letter>2 | <option> | <operator> | <YYYY-MM-DD> |

Implementation does NOT start until every decision has a `LOCKED` status.
