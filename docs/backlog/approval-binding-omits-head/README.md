# approval-binding-omits-head

**Status:** BUILT 2026-09-11 on a branch, not yet released — schema-3 command approvals + `git_push_v1` (build-order steps 1+2 of the premise review)
**Found:** 2026-07-29, by the Deploy session while reusing a v4.7.0 approval artifact for a second push
**Surface:** `hooks/shared/approval_artifact.py` (`evaluate_command_approval`), `hooks/shared/command_policy.py`, `hooks/shared/git_push_binding.py`, `hooks/git/pre-push`
**Severity:** high at build time — an unexpired digest-less artifact authorized ANY command its action gates, even under `strict_approvals: true`

## Defect

Schema-v2 binding covered `command_digest` + `repo_id` only when the artifact carried them, and the command digest is `sha256(command.strip())` — the command *string*. Observed live: one `production_deploy` artifact bound to `git push origin HEAD:refs/heads/main` authorized two pushes of two different HEADs (`664503b`, then `85b97dd`). Premise review (verdict SOUND-WITH-FIXES) confirmed the wider hole: `_binding_ok` passed missing/empty bindings, schema absent/1/2 were accepted, and strict mode accepted `VALID`.

## Resolution (as built)

| Item | Contract |
|---|---|
| Command approval | schema 3; required `schema_version`, `action`, `repo_id`, `command_digest` (64-hex), `created_at` < `expires_at`, `binding_profile`; VALID-only in every mode |
| Legacy | schema absent/1/2 → `LEGACY_SCHEMA`, files preserved, `--inventory` names each with its reason |
| Profile | selected per `command-policy` rule (`binding_profile`, default `command_only_v1`); exact match, artifact cannot pick a weaker one |
| `git_push_v1` | `updates` = every `{push_endpoint, destination_ref, source_oid, operation}`; endpoint credential-free; deletions explicit; unresolved → deny |
| Execution boundary | `hooks/git/pre-push` re-checks the updates git sends (subset per endpoint: git omits up-to-date refs, runs once per push URL) |
| Non-Git | `command_only_v1` — command + repository only; content binding is `deploy-and-migration-input-binding` |
| Reuse | identical bound operation retryable until expiry; NOT single-use |

**Rejected:** the optional `head_sha` "enforced when present" field first proposed here — optional binding preserves the defect for every artifact that omits it; HEAD is also the wrong identity (`git push origin main` pushes local `refs/heads/main`, not HEAD, and a tree digest cannot stand in for the commit).

## Follow-ups

`destination-aware-push-coverage` (step 3) · `deploy-and-migration-input-binding` (step 4) · `approval-ttl-and-provenance` + `approval-single-use-consumption` (step 5)

## Related

- `docs/specs/approval-binding-and-upgrade-classification/decisions.md` K2 (additive binding — superseded for command approvals), K6 (digest canonicalization, retained), K19 (mandatory `--command`)
- `docs/backlog/carrier-aware-approval-binding/` — the command-carrier half is this build
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` — the parent defect class
