# `docs/handoff/` — historical archive (moved to `docs/tmp/handoff/` in v3.13.0)

> **Cross-session handoffs now live under `docs/tmp/handoff/`.** This folder is a frozen archive of dated handoff prompts produced before v3.13.0. Do not add new files here.

As of **v3.13.0**, all handoff artifacts are consolidated under `docs/tmp/handoff` (handoffs are operational/transient AI-workflow artifacts, not durable product docs):

```
docs/tmp/handoff.md                            active restart state (single file, superseded each session)
docs/tmp/handoff/<YYYY-MM-DD>-<slug>-<stage>.md   formal relay prompt (implement / deploy / architect)
```

| Stage | Producer | Consumer |
|---|---|---|
| `architect` | Product Owner | escalated Architect |
| `implement` | Product Owner | AI Developer |
| `deploy` | Product Owner | Deploy phase |

Why on disk (unchanged): replay-able restart, git audit trail (`docs/tmp/` is tracked), searchable. This is the FR-04 enforcement surface; producing the handoff file is the work, the chat message just references its path. Style: Mode B — see `FLOW_RULES.md` (FR-23) and `templates/`.

The dated files remaining in this folder are preserved as history (`git log docs/handoff/`).
