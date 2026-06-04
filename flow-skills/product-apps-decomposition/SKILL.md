---
name: product-apps-decomposition
description: Use when planning how to structure a product — deciding whether to build one large app or several focused apps. Gives generic decomposition guidance always (reliability + token economy), and steers to the specific app breakdown when docs/<app>/product.md defines one. Do NOT use for single-file edits or for app-internal component structure.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.5
risk_level: low
invocation: automatic
expected_outputs:
  - a product->apps decomposition recommendation
  - app boundaries (one product = several focused apps) with rationale
related_workflows:
  - eight-phase-flow.md
  - implementation-planning.md
hook_dependencies:
  - none
---

# Product → Apps Decomposition

> **Style:** Mode-B-lite. Generic guidance always; **steers to the product breakdown when `docs/<app>/product.md` defines one** (generic-with-enhancement, not pure no-op — E3).

## Purpose

Encode the "a product is composed of focused apps" model: breaking a product into smaller, focused apps (vs one monolith) improves reliability (one app's failure can't sink the rest) and token economy (the LLM loads only the relevant app's context). Apps talk via internal API; complexity per app stays low.

## When to invoke

- Planning a new product/app and deciding scope/structure.
- Operator says "should this be one app or several", "how do I split this product".
- `docs/<app>/product.md` exists with an apps breakdown (steer to it).

## Do not invoke when

- Single-file edits / bug fixes.
- App-internal component/folder structure (that's implementation detail, not product decomposition).

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Product breakdown (optional) | `docs/<app>/product.md` | give generic guidance; do not invent a breakdown |
| Reliability/scale needs | operator / North Star | ask if scope-critical (FR-19) |

## Procedure

1. **If `docs/<app>/product.md` defines an apps breakdown → read and steer to it.** Otherwise give generic guidance (do not fabricate a specific breakdown).
2. **Apply the heuristic:** split when areas have distinct jobs/data/lifecycles, when one area's failure shouldn't affect others, or when combined context would bloat the LLM window.
3. **Keep apps focused:** each app = one coherent job; apps integrate via internal API / webhooks.
4. **Recommend boundaries** with rationale (reliability, token economy, independent deploy).
5. **Hand to planning** (`implementation-planning`) per app.
6. **Ambiguity → ask** operator (FR-19).

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Decomposition recommendation | chat / product doc | Mode A / Mode-B-lite |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Over-splitting (too many tiny apps) | step 2 | consolidate; split has a cost too |
| Monolith pressure | step 2 | flag reliability/token risk; recommend split |

## Escalation path

- Cross-app architecture concern → `workflows/architect-escalation.md`.
- Product intent unclear → `product-docs-first` / ask operator.

## Anti-patterns

- Do not invent a specific app breakdown when `product.md` has none — give generic guidance.
- Do not over-split into unmaintainable micro-apps.
- Do not apply this to app-internal component structure.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
