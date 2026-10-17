# Fusebase Flow — the 8 rules

Every session, any agent. Policies: `policies/*.yml`. Steps: `workflows/lifecycle.md`.

| # | Rule | Why |
|---|---|---|
| 1 (FR-01) | Backlog item before code. Trivial tier: when every staged path is a declared docs, test or copy path, or the diff is formatting only, one `T<n>` in the subject suffices | Code without an item leaks scope, loses the audit trail and skips risk review |
| 2 (FR-03) | One task = one commit | Bundled commits hide which change caused a regression and break per-task rollback |
| 3 (FR-06) | Reversible by default | Destructive ops (`rm -rf`, force push, reset --hard, `git add -A`, `--no-verify`) erase recoverable state without operator consent |
| 4 (FR-07) | Worker-undisturbed | Paths declared protected must show empty git diff between deploys unless an approved exception is on file |
| 5 (FR-12) | Approval-gated side effects. The dev deploy approval is minted for the exact command before an unattended run; only the main session deploys | Migrations, customer-visible messages, auth changes, secrets and production deploys need an approval artifact on disk |
| 6 (FR-13) | **Lint+typecheck per code commit.** A commit whose staged paths all match the project's declared docs-only list (empty by default) skips lint and typecheck and still runs the secret scan, protected paths and module size. Any other staged path runs lint and typecheck once. | Broken state on main forces emergency rollback and breaks downstream pulls |
| 7 (FR-25) | Module-size ratchet | A gated file stays at or under the ceiling (default 800 lines); a baselined file may shrink, never grow. Extraction on a responsibility seam is in scope. Exemptions are the operator's call; never `--no-verify` |
| 8 (FR-27) | Liveness: never launch bare; the heartbeat has a reader | Long or silent work is bounded (`bounded_run`, which writes a heartbeat), finished in-turn, or returned as `BLOCKED-AT-<gate>`: a hung process sends no completion event |

## Roles

| Role | Code | Four documents | Deploy |
|---|---|---|---|
| Planner | no | yes | runs it after approval |
| Builder | one task at a time | evidence rows, as claims | no |
| Reader | no (Read, Glob, Grep) | no; returns typed | no |

## Amendment log

Starts at 6.0.0. Reads stop at this heading.
