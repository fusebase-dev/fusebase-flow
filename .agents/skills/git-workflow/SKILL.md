---
name: git-workflow
description: "General Git workflow for generated apps: safe local commits, clean history, and rollback guidance. Includes strict debug/deploy traceability section when git-debug-commits flag is enabled."
---

# Git Workflow

## Purpose

Use this skill for day-to-day Git work in generated apps:

- keep commits focused and understandable,
- avoid committing secrets,
- keep rollback simple.

## Baseline Workflow

1. Check current state:
   - `git status --short`
   - `git rev-parse --abbrev-ref HEAD`
2. Group related changes.
3. Commit with reason-focused message.
4. Keep unrelated changes in separate commits.

## Commit Rules

- Prefer small, scoped commits.
- Message should explain **why**.
- Do not commit `.env`, credentials, or token files.
- Avoid history rewrite unless explicitly requested.

Suggested message patterns:

- `feat: <why>`
- `fix: <why>`
- `chore: <why>`

## Rollback Guidance

Preferred shared-history rollback:

- `git revert <commit_sha>`

Temporary local rollback during active iteration:

- `git reset --hard <commit_sha_before_change>`

Use `revert` by default on shared branches.

## Operations That Commonly Need Separate Commits

- `fusebase app create/update` (`fusebase.json` changes)
- `fusebase update --skip-mcp --skip-deps --skip-cli-update --skip-commit` (`AGENTS.md`, `.claude/*` changes)
- `fusebase config ide` / `fusebase integrations` (IDE MCP config changes)
- `fusebase env create` (`.env` local changes; usually not committed)

Always review `git status --short` after these operations.

<% if (it.flags?.includes("git-debug-commits")) { %>
## Strict Debug/Deploy Traceability (Flag: git-debug-commits)

When `git-debug-commits` is enabled, apply these stricter rules.

These are **mandatory** rules (not recommendations).

### Deploy Preflight (Required)

Before `fusebase deploy`:

- `git status --short`
- `git rev-parse --abbrev-ref HEAD`
- `git rev-parse HEAD`

If tree is dirty, block deploy by default and continue only with explicit user approval.

### Commit Per Verified Fix (Required)

For each verified debug fix:

1. `git add -A`
2. `git commit -m "fix(debug): <why>"`
3. record `git rev-parse --short HEAD`

Do not batch unrelated fixes.
Do not continue to the next fix until the current verified fix is committed.
If a fix was verified but not committed, deploy is blocked until the commit exists.

### Deploy Trace Marker

After successful deploy:

- record deployed `git rev-parse HEAD` in report,
- optionally add tag:
  - `git tag -a deploy/<app-or-app>/<timestamp> -m "Deploy trace marker"`

### Report Requirements

For each fix:

- issue summary,
- verification done,
- commit SHA,
- rollback command (`git revert <sha>`).

For each deploy:

- target,
- preflight result (clean or approved-dirty),
- deployed SHA,
- optional tag.
<% } %>
