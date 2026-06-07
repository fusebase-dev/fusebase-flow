# `docs/tmp/handoff/` README — handoff convention

This file is the substrate for the project's `docs/tmp/handoff/README.md`. The setup workflow copies this in (or projects can author their own).

---

# `docs/tmp/handoff/` — cross-session prompts

Every prompt that hands work between two AI sessions is saved here as a dated file BEFORE it is shown in chat.

## Naming convention

```
docs/tmp/handoff/<YYYY-MM-DD>-<slug>-<stage>.md
```

| Stage | Producer | Consumer | Example |
|---|---|---|---|
| `architect` | Product Owner | escalated Architect | `2026-05-08-skip-already-fetched-fields-architect.md` |
| `implement` | Product Owner | AI Developer | `2026-05-08-skip-already-fetched-fields-implement.md` |
| `deploy` | Product Owner | Deploy phase | `2026-05-08-skip-already-fetched-fields-deploy.md` |

If two handoffs of the same stage occur on the same date for the same slug, append `-2`, `-3`, etc. to disambiguate.

## Contents

Per-stage handoff content templates live in:

- `workflows/architect-escalation.md` — architect handoff template
- `workflows/greenlight-implement.md` — implement handoff template
- `workflows/greenlight-deploy.md` — deploy handoff template

## Why on disk

Per FR-04 (persist handoffs):

- **Replay-able** — paste the same file again to restart a crashed session.
- **Audit trail** — `git log docs/tmp/handoff/` shows every cross-session prompt that ever ran.
- **Searchable** — grep for a topic across all past handoffs.

## Style

Mode B (full): dense, tabular, front-loaded, no narrative padding. See `FLOW_RULES.md` for full Mode B principles.

## Retention

Handoff files are kept indefinitely. They form the per-ticket paper trail. Smoke-evidence subdirs (`<date>-<slug>-smoke/`) are kept with their parent handoff and may be pruned by operator on a per-ticket basis after the spec is DONE for >90 days.
