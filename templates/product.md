---
artifact: product
app: <app-name>
last_updated: <YYYY-MM-DD>
onboarded_by: project-onboarding
---

# Product doc — <app-name>

> Per-app product intent, designed **before** code. Created by `project-onboarding` / `product-docs-first`. Read by planning, `product-apps-decomposition`, and `business-logic-guardian`. Lives at `docs/<app>/product.md`.

## Purpose

<What this app is for; the outcome it creates. Operator's words.>

## Users

| Audience | Need (see docs/audience.md) |
|---|---|
| <client / internal> | <core job> |

## Core jobs / key flows

- <the primary things a user does in this app>

## Key screens / surfaces

- <screen → purpose>

## Data

- <main entities/fields this app owns or reads>

## This product breaks into these apps

> Feeds `product-apps-decomposition`. A product = several focused apps that talk via internal API.

| App | Job | Why separate |
|---|---|---|
| <app-1> | <one coherent job> | <reliability / token economy / lifecycle> |

## Non-goals (anti-drift)

- <what this app deliberately does NOT do>

## Research

<link any operator research at docs/<app>/research/>

---

*Absent-by-default: this file does not ship with Fusebase Flow. If missing, `product-docs-first` is a no-op and `product-apps-decomposition` gives generic guidance only.*
