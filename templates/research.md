# Research — <slug>

> **Use when:** the ticket needs tech-stack validation, vendor-API exploration, or library evaluation BEFORE drafting decisions. This is an OPTIONAL artifact.

**Status:** in progress | complete
**Linked spec:** `docs/specs/<slug>/spec.md`
**Created:** <YYYY-MM-DD>

## Question being researched

<1–2 sentences: what unknown does this research resolve.>

## Sources consulted

| Source | URL / path | Date accessed | Reliability |
|---|---|---|---|
| <vendor doc> | `<url>` | <YYYY-MM-DD> | official |
| <code in repo> | `<path>` | — | direct |
| <community thread> | `<url>` | <YYYY-MM-DD> | second-party |

## Key findings

Numbered. Each finding cites a source.

1. **<one-liner>** — <details>. Source: <table row>.
2. **<one-liner>** — <details>. Source: <table row>.

## Implications for the ticket

- <how finding 1 affects design>
- <how finding 2 affects design>

## Recommendation for `decisions.md`

If research resolves an architectural choice, surface as a candidate decision <Letter><n>:

> Decision <Letter><n>: <recommendation>. Reasoning: <one-liner from research>. See `research.md` finding <#>.

## Open questions

Items research did not resolve. May escalate to clarify Q-A or follow-up backlog ticket.

- <unresolved question>
- <unresolved question>

## When to skip research.md

- Decision is straightforward from existing repo patterns
- Ticket is a minor scope change with no new tech surface
- Operator has direct knowledge and provides answer in clarify
