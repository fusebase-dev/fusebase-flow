# approval-binding-omits-head

**Status:** parked
**Found:** 2026-07-29, by the Deploy session while reusing a v4.7.0 approval artifact for a second push
**Surface:** `hooks/shared/approval_artifact.py:103-115` (`compute_command_digest`), K2/AC9 binding contract
**Severity:** medium — narrows, but does not close, the replay window K2 claims to close

## Defect

Schema-v2 binding covers `command_digest` + `repo_id`. It does **not** cover the commit being acted on. `compute_command_digest` is `sha256(command.strip())` — a hash of the command *string* and nothing else: no HEAD, no tree digest, no ref target.

Consequence, observed live: one `production_deploy` artifact bound to `git push origin HEAD:refs/heads/main` authorized that push **twice, against two different HEADs** (`664503b`, then `85b97dd`). The second push was legitimate and operator-approved — but the artifact did not constrain *what* was pushed. Only operator consent did.

So for any command whose effect depends on ambient repo state rather than on its own argv (`git push HEAD:...`, `fusebase deploy`, `prisma migrate deploy`), the binding proves *which command* was approved and **not** *which change* was approved.

## Why it was not fixed in-ticket

Out of scope for `approval-binding-and-upgrade-classification`. That ticket's K2 deliberately scoped binding to "enforceable ambient facts" available at mint time and shipped `command_digest` + `repo_id` additively. The original scope review did list "repository identity **and current HEAD/staged digest**" as enforceable; only the first half landed. Adding HEAD binding changes what an existing artifact authorizes, so it needs its own lane, a compat decision, and a release note.

## Design notes for whoever picks this up

- `hooks/shared/path_policy.py:197-211` already has the right primitive: `compute_staged_tree_digest` binds an approval to exact staged content+mode, and `write-bootstrap-approval.sh` mints with the same function so writer and verifier cannot drift. Mirror that pattern rather than inventing a second one.
- **Do not** bind naively to HEAD for every action. A deploy approval that dies because an unrelated docs commit landed between mint and deploy is friction with no safety gain, and it collides with DP.6's low-friction retry flow (the same reasoning that deferred single-use consumption — see `approval-single-use-consumption`).
- Likely shape: an **optional** `head_sha` / `tree_digest` field, enforced when present (the K2 additive pattern), which the writer sets only for actions declared HEAD-sensitive in `policies/approval-policy.yml`. Retry-after-failure must not require a fresh approval when HEAD has not moved.
- Decide explicitly whether a *later* push of a *different* HEAD should require re-approval. Arguably yes for `production_deploy`; arguably no for `destructive_file_delete`. This is a per-action property, not a global one.

## Related

- `docs/specs/approval-binding-and-upgrade-classification/decisions.md` K2 (additive binding), K6 (digest canonicalization, revised), K19 (mandatory `--command`)
- `docs/backlog/approval-single-use-consumption/README.md` — the other half of the replay story; both are needed for "this artifact authorizes exactly one action once"
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` — the parent defect class
