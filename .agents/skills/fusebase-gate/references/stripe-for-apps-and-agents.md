---
version: "1.0.0"
mcp_prompt: none
source: "docs/stripe-for-apps-and-agents.md"
last_synced: "2026-04-16"
title: "Stripe for apps and agents (Gate)"
category: specialized
---
# Stripe for apps and agents (Gate)

> **SOURCE**: This file is copied from `docs/stripe-for-apps-and-agents.md` in the fusebase-gate repo. Edit that file, then run `npm run mcp:skills:generate`.

---
# Gate Stripe For Apps And Agents

This guide explains what Fusebase Gate currently supports for Stripe, how app code should call it, and how an agent should be authorized.

## What Gate Supports Today

Gate currently exposes an org-scoped Stripe billing facade, not a generic Stripe passthrough.

Available Stripe operations:

- `getStripeOauth`
  Checks whether the org has a connected Stripe account and returns `stripeAccountId` plus `liveMode`.
- `updateStripeMode`
  Gate billing currently operates in live mode only, so do not treat this as a user-facing test/live switch.
- `findStripeProduct`
  Finds a Gate-managed Stripe product or price by `stripeAccountId`, `kind`, `kindId`, or `mode`.
- `createStripeProduct`
  Creates a Gate-managed payment or subscription product. Treat `stripeAccountId` + `kind` + `kindId` as the unique product identity and create only when no product already exists for that identity.
- `updateStripeProduct`
  Replaces a product as delete plus create. Do not assume in-place Stripe edits.
- `deleteStripeProduct`
  Marks a Gate-managed product as deleted.
- `getStripePaymentLink`
  Creates or returns a Stripe-hosted checkout URL.
- `getStripePaymentState`
  Returns the latest webhook-backed active state for a buyer and product identity.

## What Gate Does Not Support Yet

- A generic Stripe API proxy
- Test/live mode switching through the current Gate billing backend
- Direct Stripe product administration outside the Gate `kind` and `kindId` model
- Stripe customer list endpoints
- Stripe invoice history endpoints
- Stripe subscription list endpoints
- Trial subscription creation through Gate

## Key Rules

- Always call `getStripeOauth` before product or checkout flows if the org may not be connected yet.
- Treat `stripeAccountId` as the source-of-truth connected Stripe account identifier.
- Use stable app-owned `kind` and `kindId` values. Keep `kind` at 32 chars max and `kindId` at 64 chars max. That is how Gate maps checkout and webhook-backed payment state back to your app concept.
- Treat `stripeAccountId` + `kind` + `kindId` as the unique identity for a Gate-managed Stripe product. Call `findStripeProduct` before `createStripeProduct`, and only create when nothing already exists for that identity.
- `buyerId` for `getStripePaymentLink` and `getStripePaymentState` must be a number. Pass `buyerId: user.id`, not `buyerId: String(user.id)`.
- For `mode: "subscription"`, send both `interval` and `intervalCount`.
- For `mode: "payment"`, omit `interval` and `intervalCount`.
- Gate billing should currently be treated as live-mode only. Do not build UI or agent flows that depend on switching Stripe between test and live modes through Gate.
- Treat `liveMode` as read-only informational state for now and expect connected accounts to be live-mode only.
- Treat `createStripeProduct`, `updateStripeProduct`, and `deleteStripeProduct` as owner-admin setup flows in your app or backend, not arbitrary registered-user self-service actions.
- `getStripePaymentLink` expects `stripeAccountId`, `kind`, `kindId`, numeric `buyerId`, `successUrl`, and `cancelUrl`.
- If `getStripePaymentLink` returns `url: null`, first verify those checkout inputs are present, non-empty, and match an existing Gate product identity.
- After Stripe redirects to your success page, do not unlock access immediately. Poll `getStripePaymentState` in a short loop because Gate payment activation is updated asynchronously from webhook processing.

## Common Checkout Mistake

If Gate returns a 400 with `body.buyerId: invalid_type`, the app probably sent `buyerId` as a string.

Use:

```ts
buyerId: user.id;
```

Do not use:

```ts
buyerId: String(user.id);
```

## Required Checkout Inputs

For `getStripePaymentLink`, always send:

- `stripeAccountId`
- `kind` as a stable app-owned type key, max 32 chars
- `kindId` as a stable app-owned object key, max 64 chars
- `buyerId` as a number
- `successUrl`
- `cancelUrl`

If the returned `url` is `null`, verify all six values before assuming the Stripe side failed.

## MCP Prompt Groups

Current Stripe billing operations attach these MCP prompt groups:

- `authz`
- `sdk`
- `billing`
- `stripeApps`

## Permissions

Stripe operations are org-scoped and require org access plus billing permissions.

- `billing.read`
  `getStripeOauth`, `findStripeProduct`, `getStripePaymentState`
- `billing.write`
  `updateStripeMode`, `createStripeProduct`, `updateStripeProduct`, `deleteStripeProduct`, `getStripePaymentLink`

App policy recommendation:

- Keep product-management flows owner-admin only in your own UI, backend, or agent policy, even though the current Gate permission check is based on `billing.write`.

## Recommended Auth Model

### Frontend

Do not give the browser raw Stripe platform keys and do not use Gate internal auth from the browser.

Recommended pattern:

1. Browser authenticates into your app.
2. Browser calls your backend or BFF.
3. Your backend calls Gate using the current user context or a short-lived scoped token.
4. Your backend returns the result the UI needs, such as Stripe connection state, checkout URL, or payment state.

This keeps Stripe connection state and product management behind your application boundary.

### Backend Or BFF

Use the Gate SDK and call `BillingApi`.

Use a credential that is both:

- scoped to the target org
- limited to `billing.read` and or `billing.write` as needed

### Agent

For an agent, the safest pattern is:

1. Your backend mints or provides a short-lived Gate token for one org.
2. The token only includes the billing permissions the agent actually needs.
3. The agent calls Gate through the SDK or MCP.

Do not give the agent raw Stripe API secrets. Let Gate enforce org scope and billing permissions.

## SDK Example

```ts
import { BillingApi, createClient } from "@fusebase/fusebase-gate-sdk";

const client = createClient({
  baseUrl: process.env.GATE_BASE_URL!,
  auth: {
    token: process.env.GATE_TOKEN!,
  },
});

const billingApi = new BillingApi(client);
```

Check Stripe connection:

```ts
const oauth = await billingApi.getStripeOauth({
  path: { orgId },
  body: {},
});

if (!oauth.oauth?.stripeAccountId) {
  throw new Error("Org is not connected to Stripe");
}
```

Read Stripe connection state:

```ts
if (oauth.oauth?.liveMode !== true) {
  throw new Error("Gate Stripe billing is expected to run in live mode");
}
```

Find or create a one-time payment product:

```ts
const existing = await billingApi.findStripeProduct({
  path: { orgId },
  body: {
    stripeAccountId: oauth.oauth!.stripeAccountId!,
    kind: "course",
    kindId: "course_123",
  },
});

const product =
  existing.product ??
  (
    await billingApi.createStripeProduct({
      path: { orgId },
      body: {
        stripeAccountId: oauth.oauth!.stripeAccountId!,
        mode: "payment",
        amountCents: 1999,
        currency: "usd",
        title: "Premium Course",
        kind: "course",
        kindId: "course_123",
      },
    })
  ).product;
```

Create a subscription product:

```ts
const existing = await billingApi.findStripeProduct({
  path: { orgId },
  body: {
    stripeAccountId: oauth.oauth!.stripeAccountId!,
    kind: "plan",
    kindId: "plan_pro",
  },
});

const product =
  existing.product ??
  (
    await billingApi.createStripeProduct({
      path: { orgId },
      body: {
        stripeAccountId: oauth.oauth!.stripeAccountId!,
        mode: "subscription",
        amountCents: 9900,
        currency: "usd",
        title: "Pro Plan",
        kind: "plan",
        kindId: "plan_pro",
        interval: "month",
        intervalCount: 1,
      },
    })
  ).product;
```

Get checkout URL:

```ts
const checkout = await billingApi.getStripePaymentLink({
  path: { orgId },
  body: {
    stripeAccountId: oauth.oauth!.stripeAccountId!,
    kind: "course",
    kindId: "course_123",
    buyerId: memberId, // number, not String(memberId)
    successUrl: "https://app.example.com/billing/success",
    cancelUrl: "https://app.example.com/billing/cancel",
    customerEmail: "member@example.com",
  },
});

window.location.href = checkout.url!;
```

Check webhook-backed payment state:

```ts
const state = await billingApi.getStripePaymentState({
  path: { orgId },
  body: {
    stripeAccountId: oauth.oauth!.stripeAccountId!,
    mode: "payment",
    kind: "course",
    kindId: "course_123",
    buyerId: memberId, // number, not String(memberId)
  },
});

if (state.active) {
  // unlock entitlement
}
```

Poll from the success page while webhook processing catches up:

```ts
async function waitForStripeActivation() {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const state = await billingApi.getStripePaymentState({
      path: { orgId },
      body: {
        stripeAccountId: oauth.oauth!.stripeAccountId!,
        mode: "payment",
        kind: "course",
        kindId: "course_123",
        buyerId: memberId,
      },
    });

    if (state.active) {
      return true;
    }

    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  return false;
}
```

## Recommended App Flows

### Stripe Setup Flow

1. Call `getStripeOauth`.
2. If `oauth` is `null`, show Stripe connection UI in your app.
3. If connected, use returned `stripeAccountId` for billing flows and treat `liveMode` as read-only informational status that should currently be `true`.

### Product And Checkout Flow

1. Call `getStripeOauth`.
2. Call `findStripeProduct` with stable `stripeAccountId`, `kind`, and `kindId`.
3. If missing, call `createStripeProduct` once for that identity.
4. Call `getStripePaymentLink` with `stripeAccountId`, `kind`, `kindId`, numeric `buyerId`, `successUrl`, and `cancelUrl`.
5. Redirect the user to the Stripe-hosted checkout URL only when `checkout.url` is present.
6. After return to the success page, poll `getStripePaymentState` until active or timeout because webhook processing is async.

### Connection State Display

1. Call `getStripeOauth`.
2. Show current `liveMode` as read-only status.
3. Do not build a user-facing live/test toggle through Gate for now.
4. Treat product setup, checkout, and payment-state flows as live-mode only.

## Agent Pattern

If an agent only needs to inspect Stripe state:

- org-scoped token
- `billing.read`

If an agent needs to prepare checkout or manage products:

- org-scoped token
- `billing.write`
- owner-admin app policy for product-management actions

If an agent needs both:

- org-scoped token
- `billing.read`
- `billing.write`

Recommended constraints:

- one token per org
- short TTL
- no broader permissions than needed
- do not reuse a human session token if a narrower agent token can be minted

## MCP Tool Names

If the agent uses MCP instead of the SDK, the current Stripe tool ids are:

- `getStripeOauth`
- `updateStripeMode`
- `findStripeProduct`
- `createStripeProduct`
- `updateStripeProduct`
- `deleteStripeProduct`
- `getStripePaymentLink`
- `getStripePaymentState`

## When To Use Gate Vs Stripe Directly

Use Gate when the flow needs:

- org-scoped auth and permissions
- app-owned `kind` and `kindId`
- live Stripe account handling through Gate
- checkout creation
- webhook-backed payment state

Do not bypass Gate for the same commercial object if your app expects Gate billing webhooks and payment-state tracking to stay correct.

## Likely Next Additions

If app teams need more Stripe surface soon, these are the best next Gate additions:

- list Stripe catalog for the connected account
- list customers by org or member mapping
- list subscriptions for a member or customer
- list invoices with Stripe invoice links

Those should still be curated Gate operations rather than a raw Stripe passthrough.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-04-16
