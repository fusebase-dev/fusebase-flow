---
name: product-docs-first
description: Use when starting a new app and the operator wants product documentation designed before code, OR docs/<app>/product.md exists. Ingests operator research and the North Star, then designs per-app product docs that planning builds from. If no product.md exists and the operator did not ask to create one, this skill does nothing (silent no-op) — do NOT auto-create. Not for mid-implementation edits.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.5
risk_level: low
invocation: automatic
expected_outputs:
  - docs/<app>/product.md (per-app product intent, before code)
  - a planning handoff grounded in the product doc
related_workflows:
  - eight-phase-flow.md
  - session-initiation.md
hook_dependencies:
  - none
---

# Product Docs First

> **Style:** Mode-B-lite. **Artifact-gated** — acts only when `docs/<app>/product.md` exists or the operator asks to create one.

## Purpose

Design product documentation per app *before* writing code, so planning and implementation build from a clear product intent instead of guessing. Ingests operator research and the North Star (if present).

## When to invoke

- Operator starts a new app and says "design the product docs first", "write product documentation", "what should this app do".
- `docs/<app>/product.md` already exists (read it to ground planning).
- Operator dropped research in `docs/<app>/research/` and asks to turn it into product docs.

## Do not invoke when

- No `docs/<app>/product.md` AND the operator did not ask to create one → silent no-op; do not auto-create.
- Mid-implementation edits (planning already done).

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Product intent (operator answers) | chat | ask in chat (FR-19); do not invent |
| Research (optional) | `docs/<app>/research/` | proceed without; note it |
| North Star (optional) | `docs/north-star.md` | proceed; align if present |
| Template | `templates/product.md` | stop; template missing |

## Procedure

1. **Gate.** If no `docs/<app>/product.md` and no operator request to create one → exit silently.
2. **Ingest** any research + the North Star; summarize, cite, never invent domain facts.
3. **Design** the product doc from `templates/product.md`: purpose, users, core jobs, key screens/flows, data, the apps this product breaks into (feeds `product-apps-decomposition`), non-goals.
4. **Write** `docs/<app>/product.md` with `last_updated` today (only operator-provided content).
5. **Hand to planning** (`implementation-planning`) grounded in the product doc.
6. **Ambiguity → ask** operator (FR-19).

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| Product doc | `docs/<app>/product.md` | Mode B |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact absent + no request | step 1 | silent no-op |
| Vague product intent | can't fill sections | capture only what's given; no fabrication |
| Template missing | step 4 | stop; report missing `templates/product.md` |

## Escalation path

- Domain expertise needed → `skill-authoring` (domain-expert mode).
- Vision conflict → `north-star` / ask operator (FR-11).

## Anti-patterns

- Do not auto-create product docs unprompted.
- Do not write code (FR-01) — this designs the product, not the implementation.
- Do not invent product intent the operator didn't supply.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
