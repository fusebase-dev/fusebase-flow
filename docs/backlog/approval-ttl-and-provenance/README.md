# approval-ttl-and-provenance

**Status:** open — build-order step 5 (first half) of the schema-3 premise review; not in the schema-3 outcome
**Filed:** 2026-09-11, while building mandatory command/ref-update binding (`approval-binding-omits-head`)
**Surface:** `policies/approval-policy.yml` `artifact_ttl_minutes`, `hooks/local/approve-local.sh` TTL at issuance, `hooks/shared/approval_artifact.py` (reader checks only the recorded expiry)
**Severity:** medium — risk amplifier for reusable approvals; does not repair binding

## Findings (premise review § D)

- `production_deploy` / `lightweight_deploy` default to 129600 min (90 days) in `direct_to_main`; a reusable approval stays live for a quarter.
- TTL is enforced only at issuance; the reader accepts any recorded `expires_at`, so a hand-written or edited artifact can carry any lifetime.
- `approved_by` conflates the claimed consenting person with the tool that wrote the record.

## Proposed (undecided — operator product call)

| Item | Proposal |
|---|---|
| Default deploy TTL | 60 minutes, explicit longer lifetime on request |
| Reader maximum | reader rejects `expires_at - created_at` above a policy maximum (schema 3 already requires both fields) |
| Provenance fields | `authorized_by` (claimed person) · `minted_by` (agent/tool) · `authorization_source` (direct chat or relay + evidence reference) · `created_at` |

## Constraints

- Provenance is AUDIT METADATA, never authenticated authority (K3): a same-principal process can write any of these fields.
- No inspected evidence establishes an optimal duration; measure deploy-retry windows first.

## Related

- `docs/backlog/approval-binding-omits-head/` · `docs/backlog/approval-single-use-consumption/`
