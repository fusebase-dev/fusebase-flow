# deploy-store-provisioning-ungated

**Status:** open — not scheduled; confirm against the current FuseBase CLI first. Carried into 6.0.0 labelled, not fixed, and named in its release note; closing is the owner's call. **Filed:** 2026-10-15 (A6 verifier side finding, `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** medium (schema changes without a `database_migration` approval). **Surface:** `policies/command-policy.yml` (FR-07).

## Observed

T132 gated `fusebase isolated-store sql bundle … --apply` behind `database_migration`. Deploy-time store provisioning (`fusebase deploy` without `--skip-store-provision`) and `fusebase env provision-store` can apply migrations with no `database_migration` rule; only the deploy approval covers them.

## Ask

List the CLI's current mutating store verbs (pin the CLI version in the rule comment, as T132 did); decide whether provisioning needs `database_migration` in addition to the deploy approval; add rules + `test-command-policy.sh` rows under a single-use FR-07 approval; strictest review with a HEAD-vs-new command matrix.
