---
version: "1.0.0"
mcp_prompt: emails
last_synced: "2026-04-09"
title: "Fusebase Gate Email Operations"
category: specialized
---
# Fusebase Gate Email Operations

> **MARKER**: `mcp-emails-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `emails` for latest content.

---
## Fusebase Gate Email Operations

These operations send one-off emails to existing organization members through Gate.

## Relevant Operations

- sendOrgEmail sends an email to exactly one organization member in the requested org.

## Recipient Rules

- Treat `recipient` as required.
- Digit-only `recipient` strings are interpreted as user ids.
- `recipient` strings containing `@` are interpreted as email addresses.
- The resolved user must already belong to the organization. This operation is not an invite or provisioning flow.
- If you need to discover or confirm the target member first, use `listOrgUsers` before calling `sendOrgEmail`.

## Message Rules

- Send both `subject` and `body` under the request `body` payload.
- `variables` and `links` are accepted for forward compatibility, but Gate does not currently apply them during sending.
- Put the final human-readable message content in `body` instead of relying on template substitution.

## Access Model

- Sending org email requires `email.write` and org access.
- Gate resolves org membership before calling the internal mail service.
- If the call fails because the recipient is not found in the org, fix recipient selection or org membership instead of retrying the same payload.

## Response Interpretation

- A 201 means Gate accepted the send request for a resolved org member.
- `sentUserId` is the canonical recipient identity returned by the operation.
- `sentEmail` can be omitted if the resolved member record does not expose an email.

## Working Rules

- Always inspect the exact contract with `tools_describe` or `sdk_describe` before integration work.
- Treat `orgId` as required path input.
- Use this operation for one recipient at a time, not bulk mail.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-04-09
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
