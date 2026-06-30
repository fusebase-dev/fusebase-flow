---
name: app-api-contract-testing
description: "Author, validate, publish, and centrally verify consumer-driven contracts for cross-app API calls. Use when: 1. An app's runtime calls another app via AppApisApi.callAppApi(...), 2. Authoring or editing *.contract.json files, 3. Confirming a provider you depend on still behaves as expected, 4. Checking whether a provider change would break dependent apps."
---

# Cross-App API Contract Testing

When this app calls another app via Gate `AppApisApi.callAppApi(...)`, it becomes a
**consumer** that depends on the **provider** operation behaving a certain way. A
*contract* captures that expectation. Contracts are **authored and validated
locally, then verified centrally** (`public-api → Gate` runs the real provider
call) — there is no local runtime verification command.

A contract is identified by **`providerAppId + operationId`** — the business
contract is the provider *operation*, not the HTTP transport.

## When to do this (during app development)

- After adding or changing a `callAppApi(...)` dependency in runtime code.
- Before relying on a provider, or after a provider you depend on is upgraded
  (run `verify-consumer`).
- Before shipping a change to an app **other apps call** (run `verify-provider`
  to catch every dependent consumer org-wide).

## Prerequisites

- `fusebase auth --api-key=<id>.<key>` (an API key is required).
- `orgId`/`productId` in `fusebase.json`, and the app configured with a `path`.
- The `cross-app-api-calls-analysis` flag (already enabled — this skill is only
  present when it is).

## Workflow

```bash
# 1. Discover dependencies — scans runtime TS for callAppApi(...) and writes
#    fusebaseAppApiDependenciesMeta into fusebase.json
fusebase analyze app-apis --feature <appId>

# 2. Scaffold draft contracts from the resolved callsites
fusebase app-api-contracts scaffold --app <appId>
#    → drafts are bare { "expect": { "status": 200 } } with input inferred from
#      the call payload. EDIT them into real assertions (see "Contract files").
#    Existing *.contract.json files are SKIPPED (your edits are safe); only missing
#    ones are created. Pass --force to overwrite existing files back to fresh
#    drafts (discards your edits).

# 3. Validate offline — structure + that each contract maps to a real dependency.
#    No provider call.
fusebase app-api-contracts validate --app <appId>

# 4. Publish the validated set to central storage (full replacement, idempotent;
#    aborts and uploads nothing if any contract is invalid)
fusebase app-api-contracts publish --app <appId>

# 5. Verify centrally against the live provider
fusebase app-api-contracts verify-consumer --app <appId>          # this app's contracts
fusebase app-api-contracts verify-provider --app <providerAppId>  # org-wide inbound check
```

### Review and complete every draft (required, not optional)

Scaffolding is a **starting point, not a finished contract**. It seeds only the
**request side** (`input`, inferred from the call payload). The **response
assertion is NOT generated** — each draft gets only `expect.status: 200`, never an
`expect.body` or `expect.error`. An unedited draft therefore asserts almost
nothing (just "the call returned 200").

So after every `scaffold`, open each generated `*.contract.json` and edit it to
match **what this app actually relies on**:

- **Define `expect` by hand** — add `expect.body` matchers for the response fields
  the app reads, and add the error cases the app handles
  (`expect.status` + `expect.error` for the 4xx/5xx paths). This is the core of the
  contract and is never produced by scaffolding.
- **Check `input`** — fix or complete the inferred payload if it doesn't reflect a
  real call the app makes (and add cases for other meaningful inputs).
- **Rename cases** — give each `case.name` a meaningful description of the scenario.
- **Remove** any scaffolded contract for a dependency the app doesn't truly depend
  on.

Treat a scaffolded-but-unreviewed contract as incomplete: validate/publish/verify
only after the `expect` blocks express the app's real expectations.

**Key rule:** `verify-*` read the **published** set, not local files. After editing
a contract, re-run `publish` before verifying — otherwise the old published version
is tested.

Add `--json` to `validate` / `verify-consumer` / `verify-provider` for CI: a single
JSON document with a top-level `ok` flag mirroring the exit code. `publish` is an
action, not a check — branch on its exit code.

### Dynamic (unresolved) calls

When `callAppApi(...)` is dynamic and static analysis cannot resolve the target,
declare it by hand, then scaffold that one:

```bash
fusebase app-api-contracts unresolved --app <appId>
fusebase app-api-contracts add-manual-dependency --app <appId> --provider <providerAppId> --operation <operationId>
fusebase app-api-contracts scaffold --app <appId> --provider <providerAppId> --operation <operationId> --force
```

## Contract files

Discovered under `<app-path>/contracts/app-apis/<providerAppId>/<operationId>.contract.json`:

```json
{
  "kind": "app-api-consumer-contract",
  "schemaVersion": "2026-06-03",
  "providerAppId": "<provider app id>",
  "operationId": "listTasks",
  "cases": [
    {
      "name": "lists open tasks",
      "input":  { "query": { "status": "open" } },
      "expect": { "status": 200, "body": { "tasks": [ { "id": { "$matcher": "string" } } ] } }
    }
  ]
}
```

- `input` → the Gate request envelope (`path`/`query`/`body`); omit to send `{}`.
  `input` is **sent, not asserted**. A matcher left in `input` is **synthesized**
  into a concrete sample before the call (`{"$matcher":"string"}` → `"contract-draft"`,
  `number` → `1`, `enum` → first `$value`, `$optional` → omitted). Scaffolding may
  seed a matcher for a value it couldn't read from your code (e.g. a dynamic path
  `id`) — the synthesized sample is almost certainly not a real record, so
  **replace `input` placeholders with real values** before `publish`. Matchers are
  meaningful only in `expect`.
- `expect.status` is required; `expect.body` and `expect.error` are optional.
  `expect.error` matches `data.error` on non-2xx responses.
- **Matchers** (type-only): `{"$matcher":"string"|"number"|"boolean"}`,
  `{"$matcher":"enum","$value":[...]}`. Add `"$optional":true` to allow absence,
  `"$nullable":true` to allow an explicit `null` (combinable). Plain JSON = exact
  match; objects match partially (only listed keys checked); a length-1 array
  `[ X ]` matches every element (so a nullable element needs
  `[{"$matcher":"string","$nullable":true}]`), a length-N array expects exactly N
  positional elements.
- **Not supported** (ignored-with-warning if seen in the provider schema): regex,
  ranges/lengths, formats (date/uuid/email), `oneOf`/`anyOf`/`allOf`.

When the provider publishes a manifest, verification **also** checks responses
against its OpenAPI schema automatically — even a bare `{ "status": 200 }` draft
gets that check. Missing manifest / unsupported keywords surface as warnings, never
failures.

## Notes

- Verification runs the **real** provider handler, so it can cause side effects
  (writes, emails). There is no fixture/sandbox environment.
- `verify-provider` runs every targeting consumer's contracts as the triggering
  user; it is org-wide (sees consumers beyond the local `fusebase.json`).
