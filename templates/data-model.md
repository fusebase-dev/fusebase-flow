# Data model — <slug>

> **Use when:** the ticket changes schema (new tables / columns / indexes) or wire format in non-trivial ways. This is an OPTIONAL artifact.

**Linked spec:** `docs/specs/<slug>/spec.md`
**Linked decisions:** <Letter>1..<Letter>N (specifically schema-related decisions)

## Schema delta

### Tables added

| Table | Purpose | Owner table (if isolated store) |
|---|---|---|
| `<table>` | <one-liner> | <store id> |

### Columns added

| Table | Column | Type | Nullable | Default | Index |
|---|---|---|---|---|---|
| `<table>` | `<column>` | `<type>` | yes/no | `<default>` | yes/no |

### Columns removed

| Table | Column | Why |
|---|---|---|
| `<table>` | `<column>` | <one-liner> |

### Indexes added

| Table | Columns | Type | Purpose |
|---|---|---|---|
| `<table>` | `(<col1>, <col2>)` | btree / gin / etc. | <query pattern> |

## Wire format delta

### Request shapes added/changed

```ts
type <RequestName> = {
  <existing fields>,
  <new field>: <type>,    // <description, range, default>
}
```

### Response shapes added/changed

```ts
type <ResponseName> = {
  <existing fields>,
  <new field>: <type>,
}
```

## Migration strategy

| Approach | Selected | Reason |
|---|---|---|
| No migration (additive at runtime) | yes / no | <reason> |
| Reversible migration | yes / no | <reason> |
| One-shot migration with backfill | yes / no | <reason> |
| Migration deferred (separate ticket) | yes / no | <reason> |

## Backwards-compat plan (for mixed-fleet)

| Client / consumer | Old behavior | New behavior | Compat handling |
|---|---|---|---|
| <client> | <old> | <new> | <how old clients keep working> |

## Validation rules

| Field | Rule | Where enforced |
|---|---|---|
| `<field>` | <rule> | backend handler / type system / database constraint |

## Risks

- <data risk + mitigation>
- <data risk + mitigation>

## Rollback

If schema change must be reverted:
1. <step>
2. <step>
3. <step>

## Related

- `docs/specs/<slug>/spec.md` — overall spec
- `docs/specs/<slug>/decisions.md` — schema-related decisions <Letter><n>
- `policies/protected-paths.yml` — migration/schema paths requiring approval
