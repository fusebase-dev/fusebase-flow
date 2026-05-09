# `docs/problem-catalog/` — persistent record of significant problems

Problems that took non-trivial diagnosis effort, or that recur across tickets, get filed here so future sessions don't re-discover them.

```
docs/problem-catalog/
├── README.md                           ← this file (index)
└── <slug>/
    └── problem.md                      ← per-problem details (use templates/problem-catalog-entry.md)
```

## index format

```markdown
# Problem Catalog Index

| Slug | Severity | Status | One-line summary |
|---|---|---|---|
```

## When to file

Triggers (per FR-15 + `workflows/knowledge-curation.md`):

- Ticket required > 30 minutes of non-obvious diagnosis
- Same symptom seen in 2+ recent tickets
- Vendor or platform quirk surfaced
- Workaround applied for a platform constraint

The Product Owner proposes filing; the operator confirms. `Capture` files the entry; `skip` notes the decision in the current ticket's `decisions.md`.

## Skill vs problem-catalog

| Pattern | Where | Why |
|---|---|---|
| One specific incident with a specific cause | problem-catalog | Concrete, dated, reference-able |
| General expertise area that recurs across 3+ tickets | `docs/skills/<slug>/SKILL.md` (project-internal skill, distinct from `skills/`) | Reusable knowledge, not incident-bound |

## Style

Mode B (full). Use `templates/problem-catalog-entry.md` as substrate.
