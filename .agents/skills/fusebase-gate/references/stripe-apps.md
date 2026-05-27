---
version: "1.3.0"
mcp_prompt: stripeApps
last_synced: "2026-04-16"
title: "Fusebase Gate Stripe App And Agent Integration"
category: specialized
---
# Fusebase Gate Stripe App And Agent Integration

> **MARKER**: `mcp-stripe-apps-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `stripeApps` for latest content.

---
## Fusebase Gate Stripe App And Agent Integration

Use these rules when Stripe operations are called from application code, a backend or BFF, or an agent acting on behalf of one organization.

## Current Gate Stripe Surface

- Gate currently exposes an org-scoped Stripe billing facade, not a generic Stripe passthrough.
- Current Stripe operation ids are: `getStripeOauth`, `updateStripeMode`, `findStripeProduct`, `createStripeProduct`, `updateStripeProduct`, `deleteStripeProduct`, `getStripePaymentLink`, `cancelStripeSubscription`, and `getStripePaymentState`.
- `getStripeOauth` returns the connected `stripeAccountId` and current `liveMode`, which should currently be treated as informational live-only state.
- Gate billing currently runs in live mode only. Do not build app or agent flows that depend on `updateStripeMode` switching the connected Stripe account between test and live modes.

## App Integration Rules

- Do not expose raw Stripe platform secret keys to the browser or to an agent.
- Do not build a frontend flow that calls Stripe directly for Gate-managed billing objects if your app relies on Gate product records, checkout links, or webhook-backed payment state.
- Frontend code should usually call your backend or BFF, and that backend should call Gate.
- Backend and agent calls should use org-scoped Gate credentials with only the billing permissions they need.
- Prefer short-lived, org-scoped tokens for agents instead of broad human session reuse.

## Stripe Object Identity

- Treat `stripeAccountId` as the source-of-truth connected account id for product and checkout calls.
- Treat app-owned `kind` and `kindId` as stable identifiers for the commercial object in your system. Keep `kind` at 32 chars max and `kindId` at 64 chars max. Those values must remain stable across checkout and later payment-state reads.
- Treat `stripeAccountId` + `kind` + `kindId` as the unique identity for a Gate-managed Stripe product. Call `findStripeProduct` before `createStripeProduct`, and only create when nothing already exists for that identity.
- `buyerId` for `getStripePaymentLink`, `cancelStripeSubscription`, and `getStripePaymentState` must stay numeric. Pass `buyerId: user.id`, not `buyerId: String(user.id)`.
- Treat `createStripeProduct`, `updateStripeProduct`, and `deleteStripeProduct` as owner-admin setup flows in your app or backend. Do not expose those operations to arbitrary registered end users.
- If the app changes a product materially, use `updateStripeProduct` or delete plus create. Do not assume in-place Stripe product editing is reflected in Gate billing records.
- `getStripePaymentLink` expects `stripeAccountId`, `kind`, `kindId`, numeric `buyerId`, `successUrl`, and `cancelUrl`. If it returns `url: null`, verify those inputs first before retrying.
- For subscription offboarding, prefer `cancelStripeSubscription` with the default `cancelAtPeriodEnd: true` behavior. Send `cancelAtPeriodEnd: false` only when your app intentionally removes access immediately.

## Recommended Runtime Flow

1. Call `getStripeOauth` for the org.
2. Treat `oauth.liveMode` as read-only informational state and assume Gate billing is live-mode only for now.
3. Call `findStripeProduct` using stable `stripeAccountId`, `kind`, and `kindId`.
4. Only if missing, call `createStripeProduct` once for that identity.
5. Use `getStripePaymentLink` to obtain the Stripe-hosted checkout URL.
6. After the success-page return, poll `getStripePaymentState` in a short loop before unlocking the entitlement because payment activation is webhook-async.
7. For subscription offboarding, call `cancelStripeSubscription`. Default to period-end cancellation unless the product explicitly requires immediate revocation.

## Access Model

- Read-only Stripe inspection needs `billing.read` plus org access.
- The `updateStripeMode` endpoint, product writes, deletion, checkout-link generation, and subscription cancellation need `billing.write` plus org access.
- For app design, product-management flows should still be owner-admin only even if a broader internal credential technically has `billing.write`.
- If a Stripe call fails, debug org scope, billing permissions, connection state, and `liveMode` before changing app payload semantics.

## Reference

- For a longer app-facing guide, use the generated reference copied from `docs/stripe-for-apps-and-agents.md` when it is available in the MCP skill bundle.
---

## Version

- **Version**: 1.3.0
- **Category**: specialized
- **Last synced**: 2026-04-16
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
