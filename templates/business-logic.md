# Business logic — <project name or feature area>

> **Style:** human-readable. This document is intentionally narrative because it captures the WHY of the system for human readers (operators, stakeholders, new team members). It is NOT Mode-B — that's by design.

**Last reviewed:** <YYYY-MM-DD>
**Maintainer:** <operator name or role>

## Purpose

This document describes how the product behaves from a domain / user perspective — independent of implementation details. When code and this document drift, both should be revalidated.

## Domain overview

<2–4 paragraphs introducing the system in plain language. Who uses it? What problem does it solve? What are the main concepts a new reader needs to know?>

## Key concepts

### <Concept 1>

<2–3 sentences explaining what this is and why it matters in the system. Refer to other concepts in the system by their canonical names.>

### <Concept 2>

...

### <Concept 3>

...

## Workflows / scenarios

### <Scenario 1: Operator does X>

1. <Step from operator's perspective>
2. <Step>
3. <Step>

Edge cases:
- <case>
- <case>

### <Scenario 2: System reacts to Y>

...

## Business rules

| Rule | Why | What violates it |
|---|---|---|
| <rule> | <reason> | <example violation> |
| <rule> | <reason> | <example> |

## Light code map

For human readers who want to peek at the code, here are the load-bearing files for each concept above. This map drifts; treat as a starting point, not authoritative.

| Concept | Code locations |
|---|---|
| <concept 1> | `<path>`, `<path>` |
| <concept 2> | `<path>` |
| <concept 3> | `<path>` |

## When to update this doc

- After material domain or workflow changes (new concept added, existing concept renamed, scenario flow changed)
- During debugging if you find the doc and code disagree (revalidate both)
- Quarterly review even if no changes felt warranted (catches drift)

## Out of scope

This doc does NOT cover:
- Implementation details (use specs and code)
- Operational runbooks (separate doc)
- API reference (generated from code)
- Performance characteristics (separate doc)
