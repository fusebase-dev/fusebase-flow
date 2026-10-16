# Fusebase Flow — the 8 rules

Every session, any agent. Read to `## Amendment log`. Policies: `policies/*.yml`. Steps: `docs/flow-lifecycle.md`.

| ID | Rule | Why |
|---|---|---|
| FR-01 | Backlog item before code. Trivial tier: when every staged path is a docs, test or copy path, or the diff is formatting only, one `T<n>` in the subject suffices | Code without an item leaks scope and loses the audit trail |
| FR-03 | One task = one commit | Bundled commits hide which change broke what and block per-task rollback |
| FR-06 | Reversible by default: no `rm -rf`, force push, `reset --hard`, `git add -A` or `--no-verify` without the operator's consent | They erase recoverable state |
| FR-07 | Protected paths (`policies/protected-paths.yml`) change only with an approval artifact on file | Flow, CI, deploy config and secrets stay reviewed |
| FR-12 | Side effects (deploys, migrations, auth changes, secrets, customer-visible messages) need an approval artifact for the exact command. The dev deploy approval is minted before an unattended run; only the main session deploys | A grant in chat is not an approval |
| FR-13 | Lint and typecheck per code commit. A commit whose staged paths all match the declared docs-only list (empty by default) skips them and still runs the secret scan, protected paths and module size | A broken main forces rollbacks |
| FR-25 | Module size: a source file stays at or under the ceiling (800 lines); a baselined file may shrink, never grow. Split on a responsibility seam, in scope. Exemptions are the operator's call; never `--no-verify` | A file too big to read in one pass grows into a monolith |
| FR-27 | Never launch bare: long or silent work is bounded (`bounded_run`), finished in-turn, or returned as `BLOCKED-AT-<gate>` | A hung process sends no completion event |

## Roles

| Role | Code | Four documents | Deploy |
|---|---|---|---|
| Planner | no | writes them | runs it after approval |
| Builder | one task at a time | evidence rows, as claims | no |
| Reader | no (Read, Glob, Grep) | no; returns typed | no |

## Amendment log

Starts at 6.0.0. Reads stop at this heading.
