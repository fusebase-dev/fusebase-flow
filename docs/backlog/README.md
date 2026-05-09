# `docs/backlog/` — backlog of parked tickets

Tickets the operator surfaced but isn't shipping right now live here. Each ticket is one folder.

```
docs/backlog/
├── README.md                           ← this file
├── index.md                            ← table of all backlog tickets
└── <slug>/
    └── README.md                       ← per-ticket scope (use templates/backlog-ticket-README.md)
```

## index.md format

```markdown
# Product Backlog Index

| Slug | Status | One-liner |
|---|---|---|
| <slug> | parked | <one-liner> |
| <slug> | promoted | <one-liner> |
| <slug> | DONE | <one-liner> (deploy hash) |
```

## Lifecycle

```
parked (filed) → promoted (spec drafted) → DONE (deployed)
```

When a backlog ticket is promoted, the `requirements-specification` skill creates `docs/specs/<slug>/spec.md` and the index status flips to `promoted`. After deploy, the spec status flips DRAFT → DONE and the index status flips to `DONE` with the deploy hash.

## Style

Mode B (full). Use `templates/backlog-ticket-README.md` as substrate.
