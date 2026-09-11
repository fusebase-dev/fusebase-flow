# deploy-and-migration-input-binding

**Status:** open — build-order step 4 of the schema-3 premise review; not in the schema-3 outcome
**Filed:** 2026-09-11, while building mandatory command/ref-update binding (`approval-binding-omits-head`)
**Surface:** `policies/command-policy.yml` rules labelled `binding_profile: command_only_v1` (`fusebase deploy`, `vercel`, `netlify`, `prisma`/`sequelize`/`knex`/`psql`)
**Severity:** medium — an approval binds the command TEXT, not what the command deploys or migrates

## Defect

`command_only_v1` binds `command_digest` + `repo_id`. `fusebase deploy` run twice deploys whatever the tree holds each time; `npx prisma migrate deploy` applies whatever migrations are pending. Git HEAD proves neither.

## Required per-profile inputs (premise review § B)

| Profile (new) | Must bind | Fails closed when |
|---|---|---|
| `deploy_input_v1` | the deployable package digest + destination + execution-relevant config | package cannot be built/hashed identically at mint and execution |
| `migration_input_v1` | ordered pending migration set + checksums, target database identity, expected migration baseline | pending set or baseline cannot be read without side effects |

## Constraints

- One input adapter per operation, shared by writer and verifier (the `git_push_binding` shape).
- Validate at the execution boundary, not only before the command (a pre-command check races a build or an interleaved migration).
- Until an adapter exists the rule stays `command_only_v1`; never label it content-bound.

## Related

- `docs/backlog/approval-binding-omits-head/` — schema 3 and the `git_push_v1` precedent
