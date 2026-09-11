# UNRELEASED — command approvals bind the exact operation (BREAKING)

> Draft. The version number is assigned when this ships; rename the file then.

**Who this affects:** every project with command approval artifacts in `state/approvals/` —
`production_deploy`, `lightweight_deploy`, `database_migration`, `destructive_file_delete`,
`external_customer_visible_message`, or any action your `command-policy` rules require.
Protected-path (FR-07) approvals and health-check deferrals are **not** affected.

## What changes

**Existing command approval artifacts no longer authorize commands after upgrade and must be
reissued for the intended operation. Files are preserved; no approval is automatically
reconstructed. Git push approvals bind exact source objects, destinations and push endpoints.
Identical bound operations remain retryable until expiry; approvals are not single-use. Non-Git
command-only approvals do not yet bind deployed content.**

**Before:** an approval with no `command_digest` (or no `repo_id`) still authorized every command
its action gates — in any checkout, and even with `strict_approvals: true`. One approval for
`git push origin main` authorized pushing a *different* commit later, because only the command
text was bound.

**Now:**

| | Before | Now |
|---|---|---|
| Accepted artifact | schema absent, 1 or 2; bindings optional | schema 3 only; command, repository and binding profile mandatory |
| `strict_approvals` | decided whether expiry-less artifacts pass | has no effect on command approvals — they must be complete in every mode |
| `git push` to `main`/`master` (`direct_to_main`) | bound to the command text | bound to every ref update: endpoint, destination ref, source object, update/delete |
| Where a push is checked | before the command runs | before the command runs **and** in the `pre-push` git hook, against the updates git is about to send |
| `fusebase deploy`, migrations, deletes, messages | command text + repo when present | command text + repo, always (`command_only_v1`) — the deployed content is **not** bound yet |

## What you do after upgrading

1. See which artifacts stopped authorizing, and why:
   `bash hooks/local/approve-local.sh --inventory`
   Each one is named with its reason (for example `LEGACY_SCHEMA - schema_version 2; command
   approvals require 3; missing binding_profile`). Nothing is changed or deleted.
2. Reissue approvals only for operations you still intend. Your agent runs this on your chat
   go-ahead, exactly as before:
   `bash hooks/local/approve-local.sh production_deploy <slug> '<reason>' --command 'git push origin main'`
   For a push, mint **after** the last commit you want to push: the approval records the
   commit each ref points to at that moment.

## Upgrading

Measured on a consumer tree upgraded from the previous release with `bash hooks/local/upgrade.sh --auto-yes`:

| Your tree | What the upgrade does |
|---|---|
| You never edited `policies/command-policy.yml` | It is refreshed, the new verifier and `hooks/git/pre-push` land, and the hook is installed. Your `*.local.yml` overrides, `state/approvals/*` and your own files are byte-identical afterwards |
| You edited `policies/command-policy.yml` | The run **stops before writing anything**, names that file as `changed-by-both`, and prints the resume command. Reconcile it — keep your rules, take upstream's `binding_profile` / `push_destinations` lines — then re-run. Until you do, the cutover has not landed |
| You have your own `.git/hooks/pre-push` | It is backed up and preserved, never overwritten. The upgrade then says the FR-12 push boundary is NOT live, and `--inventory` reports the same. `bash hooks/local/install-git-hooks.sh --force` installs Flow's |

If your `command-policy.yml` ends up without `binding_profile: git_push_v1` on its push rule,
`--inventory` says so directly: *"git_push_v1 binding: NO active rule — pushes are bound by
command text only"*. Approvals still require mandatory command + repository binding; only the
ref-update binding is missing.

## Behaviour changes to expect

- **A new commit needs a new push approval.** Retrying the *same* push (same commit, same
  destination, same remote URL) keeps working until the approval expires.
- **A gated push must be its own plain command:** `git push <remote> <refspec>...`. A push
  chained with other commands (`git commit ... && git push origin main`), a quoted or expanded
  refspec, a forced refspec (`+main`), an unqualified destination (`HEAD:main` — use
  `HEAD:refs/heads/main`), or config that adds or remaps refs (`push.followTags`,
  `remote.<name>.push`, `push.default=upstream`) is refused with the reason; it cannot be
  approved as written.
- **Terminal pushes are checked too where the Flow `pre-push` hook is installed.** In
  `direct_to_main`, a push that updates `main`/`master` needs a matching approval whether an
  agent or a person runs it. The upgrade installs the hook next to `pre-commit`; a custom
  `.git/hooks/pre-push` is preserved and reported, and the boundary is then not active.
- A remote URL's embedded user name or token is never written into an approval.

## Not in this release

Destination-aware coverage for a plain `git push` at the agent layer
(`docs/backlog/destination-aware-push-coverage/`), deploy and migration content binding
(`docs/backlog/deploy-and-migration-input-binding/`), shorter default lifetimes and provenance
fields (`docs/backlog/approval-ttl-and-provenance/`), and single-use approvals
(`docs/backlog/approval-single-use-consumption/`).
