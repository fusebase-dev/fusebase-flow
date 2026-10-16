<!-- projection for measurement; WP 5 owns the final text. Projects FLOW_RULES.md (6.0.0): 5.11 text with removals, wording changed only in rules 1, 5, 6, 8 and the role table (H:134). Measured without this line. -->
# Fusebase Flow — always-on rules

**Scope:** every session, any IDE/agent, whatever skill is active. Clean-room original.
Rule + why here; the rest lazy: policies `policies/*.yml` · dated history `FLOW_RULES_HISTORY.md` (never load at session start).

| ID | Rule | Why |
|---|---|---|
| FR-01 | Backlog item before code. Trivial tier: when every staged path matches the docs, test or copy lists in `policies/evidence-classes.yml` as committed at HEAD, or the diff is formatting only, one `T<n>` in the subject suffices | Production-code edits without a backlog item leak scope, lose audit trail, and bypass risk review |
| FR-03 | One task = one commit | Bundled commits hide which change caused a regression and break per-task rollback |
| FR-06 | Reversible by default | Destructive ops (`rm -rf`, force push, reset --hard, `git add -A`, `--no-verify`) erase recoverable state without operator consent |
| FR-07 | Worker-undisturbed | Paths declared protected must show empty git diff between deploys unless an approved exception is on file |
| FR-12 | Approval-gated side effects. The dev deploy approval is minted for the exact command before an unattended run; only the main session deploys | DB migrations, customer-visible external messages, auth/permission changes, secret handling, and production deploys require an approval artifact on disk |
| FR-13 | Lint+typecheck per code commit. A commit whose staged paths all match the project's declared docs-only list (empty by default) skips lint and typecheck and still runs the secret scan, protected paths and module size. Any other staged path runs lint and typecheck once. | Broken state on main forces emergency rollback and breaks downstream pulls |
| FR-25 | Module-size ratchet | Source files are AI-read; a multi-thousand-line file can't be loaded in one pass, and monoliths form as the integral of N individually-reasonable diffs. Line count is objective → deterministic gate. Gated file ≤ ceiling (default 800, policy-set); baselined over-ceiling files may shrink, never grow; NEW over-ceiling files + growth block; no committed baseline → warn-only. Extraction on a responsibility seam is in-scope for the task — never scope creep. Exemptions/adoption are the operator's decision, given in chat and run by the agent on that go-ahead; never `--no-verify`. Not retroactive. |
| FR-27 | Liveness — never launch bare; the heartbeat has a reader | Any long/silent background work (the agent's own probe/script/deploy/fetch-loop/browser-automation, a sub-agent, or a workflow) must be made observable BEFORE launch — bounded by a timeout/watchdog, OR completed in-turn, OR returned as `BLOCKED-AT-<gate>` + a record-then-read pointer. A hung process emits no completion event, so the agent is never re-invoked and idles silently. A task that cannot signal its own completion-or-death must never be launched bare. `bounded_run` writes a heartbeat; `reader.py` turns it into `state/status.line`, read at every task boundary. |

## Role distinction

| Role | Code | Four documents | Deploy |
|---|---|---|---|
| Planner | no | yes | runs it after approval |
| Builder | one task at a time | evidence rows, as claims | no |
| Reader | no (Read, Glob, Grep) | no; returns typed | no |

## Amendment log

> **Moved to `FLOW_RULES_HISTORY.md`.** Session reads still end at this heading.
> TRIPWIRE: this heading is the `sync-version-strings.sh` sweep anchor and the stop marker ~9 surfaces name — never rename or delete it, never re-inline the log.
