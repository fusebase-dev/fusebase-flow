# Deploy handoff — find-wasted-code-codex-release

Status: READY
Lane: Full
Release: `v4.5.1`
Release worktree: `C:\tmp\fusebase-flow-v451-release`
Release commit: `2620daee2ce15c5fac55c690ff1ab551b7221a19`

## Role

Self-attest as Deploy phase under Fusebase Flow v4.5.1. Follow DP.1–DP.12; do not edit release content.

## Scope

- Push commit `2620dae` from local `main` to `origin/main`.
- Create annotated tag `v4.5.1` on `2620dae` and push only that tag.
- Let `.github/workflows/fusebase-flow-release.yml` create the GitHub Release; never run `gh release create` manually.
- Public surface: version/tag/release only. No migration, auth, permission, secret, sidecar, or cross-app contract change.

## Preconditions

| Check | Evidence |
|---|---|
| Worktree | clean `main` at `2620dae` |
| Full suite | `hooks/tests/run-tests.sh` → `432/432 PASS` |
| Preflight | `0 errors / 0 warnings` |
| Codex parity | `19/19 PASS` |
| Analyzer | `102/102 PASS` |
| Mirrors | skills `0 drift`; agents idempotent |
| Hook manifest | `98/98 MATCH`, flow version `4.5.1` |
| Local health | `HEALTHY` |
| Review | 0 blockers; security N/A — no sensitive surface |
| Protected banner | operator-approved; digest-bound approval consumed after commit |

## Approval gate

Present this one-line scope in chat: `Publish clean commit 2620dae as v4.5.1 by pushing main + annotated tag; CI alone creates the release.`

Wait for the operator phrase `approve deploy now`. On that phrase, author the production approval artifact in the release worktree:

`bash hooks/local/approve-local.sh production_deploy find-wasted-code-codex-release 'approve deploy now'`

## Deploy

From `C:\tmp\fusebase-flow-v451-release`:

1. Re-check `git status --short` is empty, branch is `main`, and HEAD is `2620dae`.
2. Re-check no `v4.5.1` tag exists locally or remotely.
3. Push `main` to `origin`.
4. Create annotated tag `v4.5.1` at `2620dae` with message `Fusebase Flow v4.5.1`.
5. Push `v4.5.1` to `origin`.

## Post-release probes

- Remote `main` resolves to `2620daee2ce15c5fac55c690ff1ab551b7221a19`.
- Remote annotated tag `v4.5.1^{}` resolves to the same commit.
- Release workflow completes successfully.
- GitHub Release `v4.5.1` exists and uses `docs/release-notes/v4.5.1.md`.
- Local release worktree stays clean.

## Rollback

Public tags/releases are append-only. Do not force-delete or rewrite `v4.5.1`. If a post-release defect appears: revert `2620dae` on `main`, fix forward, bump to `v4.5.2`, run the full gate, and publish the new tag.

## Completion

Report deployed commit/tag, workflow result, release URL, probe results, approval artifact status, and clean worktree status.
