# Workflow: git-workflow

> **Style:** Mode-B-lite. Direct-to-main as default; branch/PR as opt-in.

## Default mode: direct-to-main

For solo / local / fast-iteration projects:

```
main (always green) → operator pulls → AI Developer commits one task at a time → push
```

Discipline that replaces branch protection:

| Discipline | Enforcement |
|---|---|
| Pre-task git checkpoint (verify clean state before T<first>) | AI Developer self-check + `pre_tool_use` hook |
| One task = one commit (FR-03) | AI Developer self-check + `commit-msg` git hook |
| Lint+typecheck per commit (FR-13) | `pre-commit` git hook |
| No `git add -A` / `git add .` for production code (FR-06) | `command-policy.yml` + `pre_tool_use` hook |
| No `--no-verify` (FR-06) | `command-policy.yml` + `pre_tool_use` hook |
| No `git reset --hard` without confirmation (FR-06) | `command-policy.yml` + `pre_tool_use` hook |
| No `git push --force` to main (FR-06) | `command-policy.yml` + `pre_tool_use` hook + recovery via `git revert` |

## Opt-in mode: feature branch + PR

For team / shared / regulated projects, switch via `policies/approval-policy.yml: workflow_mode: branch_pr` (or in local override).

| Difference | Direct-to-main | Branch + PR |
|---|---|---|
| Where commits land | main | `feature/<slug>` branch |
| Review surface | gate report → deploy | gate report → PR review → merge → deploy |
| Approval artifact | `state/approvals/production_deploy-*.json` | PR approval (GitHub/GitLab) + same artifact |
| Rollback | `git revert <hash>` on main | `git revert` on main; close PR if not merged |

The flow rules (FR-01..FR-16) are identical. Only the git surface changes.

## Per-task commit procedure

1. Pre-task checkpoint: `git status --short` must be empty. If not, STOP and ask operator.
2. Pull latest from main.
3. (Branch mode only) Create branch: `git checkout -b feature/<slug>` if not yet created.
4. Make edits for one task (T<n>).
5. Run lint + typecheck. Both must be clean.
6. Worker-undisturbed check: `git diff` against `protected-paths.yml` for paths declared protected. Must be empty.
7. Stage files explicitly by name (no `git add -A` / `git add .`).
8. Commit with message format: `<type>(<scope>): T<n> <one-liner>`. Examples:
   - `feat(spa): T17 add EnrichmentCard "Skip if already fetched" toggle`
   - `fix(extension): T18 content-script honors skipFlags from EXTRACT`
   - `test(backend): T19 cover skip-already-fetched-fields cache predicates`
   - `docs(post-deploy): T20 priority-fix DONE — sha:abc1234`
9. (Branch mode only) Push branch; do NOT merge until gate passes.

## Recovery patterns

| Situation | Recovery |
|---|---|
| Lost uncommitted work | `git reflog` → find checkpoint → `git checkout <sha>` |
| Bad merge | `git revert -m 1 <merge-sha>` (preserves history; never `--force` to main) |
| Conflict during pull | Resolve in editor; do NOT `git checkout --theirs/ours` blindly |
| Force-push happened on main | Coordinate with team immediately; reconstruct from local clones; document in `docs/problem-catalog/<date>-incident-force-push/problem.md` |

## Pre-task checkpoint phrasing

```
Pre-task checkpoint per FR-06:
`git status --short` shows: <output>
{If clean: "Pulling latest from main. Creating branch feature/<slug>" (branch mode) OR "Staying on main" (direct mode)}
{If dirty: "STOPPING. The repo has uncommitted changes — stash them (and I'll restore at end), commit them as their own task, or revert them? Reply with choice."}
```

## Commit message rules

| Rule | Example |
|---|---|
| Implementation commits cite T-number | `feat(spa): T17 ...` |
| Documentation-only commits use `docs(...)` prefix | `docs(flow): update FLOW_RULES.md` |
| Vague messages rejected by `commit-msg` git hook | `update`, `fix`, `changes` → rejected |
| Multi-line commits OK; first line is the subject (≤72 chars) | |

## Push cadence

- After each task commit (direct-to-main): push immediately so operator can pull
- After gate (branch mode): push branch; PR opens for review
- After deploy: push includes the single docs commit (FR-14)

## Related

- `policies/approval-policy.yml` — `workflow_mode` (direct_to_main / branch_pr)
- `policies/command-policy.yml` — banned commands list
- `policies/protected-paths.yml` — worker-undisturbed list
- `hooks/git/pre-commit` — local lint/typecheck gate
- `hooks/git/commit-msg` — T-number requirement
- `hooks/handlers/pre_tool_use.py` — agent-level command policy enforcement
