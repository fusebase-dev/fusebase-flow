# `docs/handoff/` — cross-session prompts

Every prompt that hands work between two AI sessions (Product Owner → AI Developer, AI Developer → Deploy phase, Product Owner → Architect on escalation) is saved here as a dated file before it is shown in chat.

## Naming convention

```
docs/handoff/<YYYY-MM-DD>-<slug>-<stage>.md
```

| Stage | Producer | Consumer | Example |
|---|---|---|---|
| `architect` | Product Owner | escalated Architect | `2026-05-08-skip-already-fetched-fields-architect.md` |
| `implement` | Product Owner | AI Developer | `2026-05-08-skip-already-fetched-fields-implement.md` |
| `deploy` | Product Owner | Deploy phase | `2026-05-08-skip-already-fetched-fields-deploy.md` |

## Why on disk

- **Replay-able** — paste the same file again to restart a crashed session.
- **Audit trail** — `git log docs/handoff/` shows every cross-session prompt that ever ran.
- **Searchable** — grep for a topic across all past handoffs.

This is the FR-04 enforcement surface. Producing a handoff file is the work; the chat message just references its path.

## Style

Mode B (full): dense, tabular, front-loaded. See `FLOW_RULES.md` and `templates/` for substrates.
