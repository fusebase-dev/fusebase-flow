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
2. **Score the boundary** with § Split decision below — signals vs costs, both columns honestly; the worked CRM example shows the shape of a defensible verdict.
3. **Keep apps focused:** each app = one coherent job; apps integrate via internal API / webhooks. Every planned cross-app call edge is a `callAppApi` contract to author and keep green (CLI skill `app-api-contract-testing`).
4. **Recommend boundaries** with rationale (reliability, token economy, independent deploy) — and the explicit call-edge list.
5. **Record the breakdown.** A decided decomposition goes into `docs/<app>/product.md` § apps breakdown (authored via `product-docs-first`, `templates/product.md`): per app — one-line job, owned data, planned call edges. Later sessions steer to it (step 1) instead of re-deciding. Do not leave a locked breakdown chat-only.
6. **Hand to planning** (`implementation-planning`) per app.
7. **Ambiguity → ask** operator (FR-19).

## Split decision (signals vs costs)

| Split signals (favor separate apps) | Concretely |
|---|---|
| Distinct data ownership | Each app owns its dashboards/stores; peers read via API, never write the other's data directly |
| Independent deploy cadence | One area ships weekly, the other is stable — separate apps deploy without re-verifying the other |
| Failure blast radius | A crash or bad deploy in one area must not take down the other (client-facing portal vs internal admin is the classic cut) |
| Per-app context size | Combined codebase would bloat the LLM window; per-app context stays small enough for reliable edits (token economy) |

| Split costs (favor one app) | Concretely |
|---|---|
| Cross-app API + contract maintenance | Every runtime call between apps is `AppApisApi.callAppApi(...)` and needs a consumer contract kept green (CLI skill `app-api-contract-testing`); each call edge is permanent maintenance |
| Per-app auth/permission/embed overhead | Each app separately configures permissions, portal embedding, public access |
| Per-app deploy/ops overhead | Separate builds, deploys, smoke runs, and remote-log surfaces per app |
| Chatty boundary | If the areas constantly need each other's data inside one interaction, the network seam adds latency + failure modes a single app doesn't have |

Rules of thumb: **≥2 signals and ≤2–3 planned call edges → split. 0–1 signals, or a chatty seam → one app.** Undecidable → ask the operator (FR-19).

### Worked example — client CRM product

Candidate areas: pipeline board (internal sales), client portal (clients see their own deals/documents), reporting.

| Boundary | Signals | Costs | Verdict |
|---|---|---|---|
| Portal vs pipeline | Data ownership (portal reads deals, never writes); blast radius (client surface must survive internal-tool breakage); independent cadence | 1 call edge (`client-portal → crm-pipeline: getClientDeals`) + 1 contract | **Split** — `crm-pipeline` + `client-portal` |
| Reporting vs pipeline | Same data, same cadence, no blast-radius concern | Would add 3+ chatty aggregate-query edges | **Keep inside** `crm-pipeline` as a view |

Result: 2 apps, 1 contract, recorded in `docs/crm/product.md` § apps breakdown (step 5).

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Decomposition recommendation | chat / product doc | Mode A / Mode-B-lite |
| Recorded apps breakdown (job + owned data + call edges per app) | `docs/<app>/product.md` via `product-docs-first` | Mode B |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Over-splitting (too many tiny apps) | step 2 | consolidate; split has a cost too |
| Monolith pressure | step 2 | flag reliability/token risk; recommend split |

## Escalation path

- Cross-app architecture concern → `workflows/architect-escalation.md`.
- Product intent unclear → `product-docs-first` / ask operator.
- New cross-app call edge decided → author the consumer contract via the `app-api-contract-testing` CLI skill before the edge ships.

## Anti-patterns

- Do not invent a specific app breakdown when `product.md` has none — give generic guidance.
- Do not over-split into unmaintainable micro-apps.
- Do not apply this to app-internal component structure.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
