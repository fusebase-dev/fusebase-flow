---
version: "1.0.0"
mcp_prompt: orgs
last_synced: "2026-06-08"
title: "Fusebase Gate Organization URLs"
category: specialized
---
# Fusebase Gate Organization URLs

> **MARKER**: `mcp-orgs-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `orgs` for latest content.

---
## Fusebase Gate Organization URLs

Use getOrgUrl when you need the canonical HTTPS base URL for an organization (dashboard, studio, or other org-scoped links on the main org host).

## Relevant Operation

- getOrgUrl: `GET /:orgId/url` — returns the org base URL and hostname metadata.

## Hostname Resolution

Gate mirrors org-service org-info hostname rules:

1. **Custom CNAME domain** — when the org has a configured custom domain, the response uses that hostname.
   - `kind: "cname"`
   - `customDomain` is set
   - Example: `https://docs.example.com`
2. **Subdomain** — when no custom domain is configured, Gate uses the org subdomain on the environment Fusebase host.
   - `kind: "subdomain"`
   - `customDomain: null`
   - Example: `https://{sub}.dev-thefusebase.com`

The response always includes:

- `url` — canonical HTTPS base URL with no trailing path
- `host` — hostname used in `url`
- `sub` — org subdomain slug (always present)
- `domainShorter` — org branding flag from org-service; it does **not** change hostname resolution

## Do Not Confuse With

- **Portal domains** from listPortals/getPortal — portal hosts such as `my-portal.p.dev-thefusebase.com` are separate from the main org URL.
- **App subdomains** from app magic links — app feature hosts are product-scoped, not the org homepage URL.
- **Invite URLs** from addOrgUser — those are one-time membership links, not the org base URL.

## Usage Rules

- Call getOrgUrl with the target `orgId` before constructing org-scoped deep links when you do not already know the hostname.
- Append paths after `url` (for example `/dashboard/{orgId}` or `/studio/{orgId}/...`).
- Do not hardcode `dev-thefusebase.com` or `thefusebase.com` in product code; resolve through getOrgUrl or environment config.
- Requires `org.read` and org access, same as listWorkspaces and listPortals.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-06-08
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
