---
version: "1.5.0"
mcp_prompt: billing
last_synced: "2026-04-16"
title: "Fusebase Gate Billing And Stripe Flows"
category: specialized
---
# Fusebase Gate Billing And Stripe Flows

> **MARKER**: `mcp-billing-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `billing` for latest content.

---
## Fusebase Gate Billing And Stripe Flows

These operations manage organization-scoped Stripe setup, Stripe-backed products, subscription cancellation, checkout links, and webhook-backed payment state through Gate.

## Relevant Operations

- getStripeOauth: verify whether the organization has a connected Stripe OAuth account.
- updateStripeMode: Gate billing currently operates in live mode only, so do not treat this endpoint as a user-facing live/test mode switch.
- findStripeProduct: look up the current Stripe product/link by Stripe account, mode, or kind identity.
- createStripeProduct: create a one-time payment or subscription product.
- updateStripeProduct: replace a product by deleting the old record and creating a new one.
- deleteStripeProduct: mark an existing product as deleted.
- getStripePaymentLink: create or retrieve a checkout URL for a buyer.
- cancelStripeSubscription: cancel a buyer subscription immediately or at the end of the billing period.
- getStripePaymentState: read the latest active state stored from Stripe webhook processing.

## Working Rules

- Always use `getStripeOauth` before product or checkout flows when the org may not be connected to Stripe yet.
- Gate billing currently runs in live mode only. Do not build product, checkout, or admin flows that depend on switching Stripe between test and live modes through Gate.
- Treat `oauth.liveMode` as informational state for now and expect connected accounts to be live-mode only.
- Treat `stripeAccountId` as the source-of-truth Stripe connection identifier for product and checkout calls.
- Use stable `kind` and `kindId` values from your own system. Keep `kind` at 32 chars max and `kindId` at 64 chars max so webhook-backed payment state can be mapped back to your product or entitlement.
- Treat `stripeAccountId` + `kind` + `kindId` as the unique identity for a Gate-managed Stripe product. Use `findStripeProduct` before `createStripeProduct`, and only create when nothing already exists for that identity.
- `buyerId` for `getStripePaymentLink` and `getStripePaymentState` must be a numeric buyer identifier. Pass `buyerId: user.id`, not `buyerId: String(user.id)`.
- For `mode: "subscription"`, send both `interval` and `intervalCount`.
- For `mode: "payment"`, omit `interval` and `intervalCount`.
- `updateStripeProduct` is implemented as delete plus create. Do not assume Stripe products are edited in place.
- Treat `createStripeProduct`, `updateStripeProduct`, and `deleteStripeProduct` as owner-admin setup flows, not end-user self-service actions for arbitrary registered users.
- `getStripePaymentLink` expects all of: `stripeAccountId`, `kind`, `kindId`, numeric `buyerId`, `successUrl`, and `cancelUrl`.
- If `getStripePaymentLink` returns `url: null`, first verify those checkout inputs are present, non-empty, and match an existing Gate product identity before retrying.
- Use `getStripePaymentLink` to obtain the redirect URL. The user still pays on Stripe-hosted checkout.
- `cancelStripeSubscription` expects all of: `stripeAccountId`, `kind`, `kindId`, and numeric `buyerId` for an existing subscription identity.
- Omitting `cancelAtPeriodEnd` or setting it to `true` is the safe default: the subscription stays active until the current billing period ends.
- Set `cancelAtPeriodEnd: false` only when you need immediate cancellation and immediate access removal.
- After a scheduled period-end cancellation, do not flip the buyer inactive immediately. Wait for webhook-backed payment state to turn inactive near the period boundary.
- After checkout returns to your success page, do not unlock access immediately. Poll `getStripePaymentState` in a short loop because payment activation is processed asynchronously from Stripe webhooks.
- Use `getStripePaymentState` after checkout or webhook processing to confirm whether the buyer is currently active.

## Access Model

- Read flows require `billing.read` and org access.
- The `updateStripeMode` endpoint, product creation, replacement, deletion, checkout-link generation, and subscription cancellation require `billing.write` and org access.
- Even when a caller has `billing.write`, prefer app-level policy that limits product-management flows to owner-admin actors.
- If billing-service rejects a call, investigate org access, token permissions, and Stripe connection state before changing payload shape.
---

## Version

- **Version**: 1.5.0
- **Category**: specialized
- **Last synced**: 2026-04-16
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
