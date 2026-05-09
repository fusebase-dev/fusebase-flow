# Clarify conversation — <slug>

**Status:** in progress | resolved
**Linked spec:** `docs/specs/<slug>/spec.md`

## Why this exists

The Product Owner surfaces ambiguities BEFORE drafting decisions. Each Q-A locks an answer that the spec then references. If clarify resolves to "we don't know," the spec is parked or the unknown becomes a follow-up backlog ticket — not a hidden assumption.

## Question format

```markdown
### Q-A — <short title>

**Question:** <clear, specific>

**Options:**
- **Option 1:** <description> — <trade-offs>
- **Option 2:** <description> — <trade-offs>
- **Option 3:** <description> — <trade-offs>

**PO recommendation:** Option <n> because <reasoning>.

**Operator answer:** <to be filled> | locked: Option <n> on <YYYY-MM-DD>
```

## Active questions

### Q-A — <title>

**Question:** ...

**Options:**
- **Option 1:** ...
- **Option 2:** ...

**PO recommendation:** ...

**Operator answer:** ...

### Q-B — <title>

...

## Resolved (audit log)

| ID | Question | Locked option | Reasoning | Date |
|---|---|---|---|---|
| Q-A | <short> | Option <n> | <one-liner> | <YYYY-MM-DD> |

## When to skip clarify

If the ticket is fully specified by the backlog README and there are no real ambiguities, the operator may say "skip clarify" and `requirements-specification` proceeds straight to spec drafting. The PO must explicitly note this in `spec.md` ("clarify skipped per operator request — no ambiguities surfaced").
