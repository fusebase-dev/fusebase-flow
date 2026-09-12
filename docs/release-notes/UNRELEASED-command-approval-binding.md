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

"Existing" means every artifact on disk, in both senses: the schema 1/2 artifacts consumers
hold, and — for anyone who ran an unreleased development build — schema-3 artifacts written
before the binding semantics were finalised. Those carry no `binding_revision` and are rejected
on sight, because the pre-push boundary compares ref updates rather than the command that was
approved, so a stale one could otherwise still authorize a real push.

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
   Each one is named with its reason, verbatim as printed: `production_deploy-t-20260911.json:
   LEGACY_SCHEMA - schema_version 2; command approvals require 3; missing repo_id,
   command_digest, created_at, binding_profile`. Nothing is changed or deleted.
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
`--inventory` says so directly: *"git_push_v1 binding: NO active rule - pushes are bound by
command text only (check policies/command-policy*.yml)"*. Approvals still require mandatory command + repository binding; only the
ref-update binding is missing.

## Behaviour changes to expect

- **A new commit needs a new push approval.** Retrying the *same* push (same commit, same
  destination, same remote URL) keeps working until the approval expires.
- **A gated push must be its own plain command:** `git push <remote> <refspec>...`. A push
  chained with other commands (`git commit ... && git push origin main`), a quoted or expanded
  refspec, a forced refspec (`+main`), an unqualified destination (`HEAD:main` — use
  `HEAD:refs/heads/main`), a `HEAD` source shadowed by a ref of that name, or config that can
  add or remap refs (`push.followTags`, `remote.<name>.mirror` and `push.recurseSubmodules` on
  every push; `remote.<name>.push` and `push.default=upstream` where a refspec omits its
  destination) is refused with the reason; it cannot be approved as written.
- **Terminal pushes are checked too where the Flow `pre-push` hook is installed.** In
  `direct_to_main`, a push that updates `main`/`master` needs a matching approval whether an
  agent or a person runs it. The upgrade installs the hook next to `pre-commit`; a custom
  `.git/hooks/pre-push` is preserved and reported, and the boundary is then not active.
- **The remote URL is compared byte for byte, exactly as git reports it.** Nothing is
  lower-cased, trimmed, re-encoded or split on its way from git's output into the approval.
  Flow asks git one question and takes one answer: the URL comes from a single-value
  `git remote get-url --push <remote>` whose output must be exactly one record, so a URL that
  itself contains a line or record separator is refused rather than trimmed or split into two
  endpoints. Two spellings of "the same" remote are two different endpoints: `SSH://host/x` is not `ssh://host/x`, an explicit `:22`
  is not an omitted port, `host:path` (relative) is not `ssh://host/path` (absolute), and two
  host aliases stay distinct. If your remote URL changes in any way, the approval stops
  matching and you reissue it — one clear error, one command. That is deliberate: a rewrite
  applied before a comparison is how an approval ends up matching a repository nobody approved.
- **A shadowed `HEAD` cannot be bound.** `git push origin HEAD` means the checked-out branch
  only while no ref is named `HEAD`. With `refs/tags/HEAD` present git pushes that tag and
  takes the destination from it (`* [new tag] HEAD -> HEAD`), leaving the branch untouched, so
  the approval refuses and names the shadowing ref instead of binding the branch. Name the
  source and destination explicitly, or delete the shadowing ref.
- **A remote with more than one push URL cannot be bound.** One push then updates several
  repositories, and an approval names one destination. Push through a single-URL remote and
  approve each destination separately; the denial says so.
- **An ambiguous SOURCE ref cannot be bound.** If `topic` names both a branch and a tag, git
  itself refuses that push (`src refspec topic matches more than one`), and so does the
  approval rather than guessing which you meant. **Qualify the source** — `git push origin
  refs/heads/topic:refs/heads/main` — since qualifying only the destination does not resolve
  it. Source refs are looked up by exact ref name rather than resolved as a revision, so a
  source is bound to the ref git's push matcher would actually select — including the case
  where the only ref strongly matching `refs/heads/topic` is a tag named
  `refs/tags/refs/heads/topic`, which git does push and which binds to that tag's object.
- **Config that can add or remap pushed refs refuses while it is set.** `remote.<name>.mirror`,
  `push.recurseSubmodules` and `push.followTags` are refused on presence — their value is not
  interpreted — on **every** push, because they can add or remap refs no refspec mentions, so
  an explicit refspec does not bypass them. `remote.<name>.push` is different: it is consulted
  only where it can supply a destination, so it is checked when a refspec omits one and the
  push is not a deletion; a fully explicit `<source>:<destination>` is **not** checked against
  it. (A bare `git push <remote>` never reaches that check — it is refused earlier, because
  every refspec must be named.) Remedy in every case: unset the key for that push; `push.followTags`
  also accepts `--no-follow-tags`. `push.default` is compared against git's own spellings, so
  `upstream`/`tracking` refuse and anything git itself rejects refuses too; name the
  destination explicitly or unset it.
- **A remote URL carrying credentials cannot be bound at all — it is refused, not cleaned up.**
  `https://<token>@host/x` and any `user:password@` form (in any scheme, percent-encoded or
  not) are rejected with the endpoint named as unusable. Use a credential helper, or a remote
  without embedded credentials, and reissue. Because nothing is stripped, no credential can
  reach a stored approval by any path.
- **An SSH login is not a credential and stays part of the destination.**
  `alice@host:repo.git` and `bob@host:repo.git` are different users' repositories (`~` expands
  per principal), so they bind separately in every SSH spelling, and changing the login
  invalidates the approval.
- **Bindable forms, and nothing else:** `[user@]host:path`, `ssh://`, `git+ssh://`,
  `ssh+git://`, `http(s)://` and `git://` without userinfo, `file:///path` and
  `file://C:/path`, and local filesystem paths. Unlisted schemes, `transport::address` remote
  helpers, percent-encoding in the authority, whitespace, and query/fragment URLs are all
  refused.

## What this does NOT protect

Stated plainly, because each of these is easy to assume from the section above.

- **The pre-push boundary is conditional protection, not a bypass-proof gate.** `git push
  --no-verify` skips it entirely — that is git's documented behavior — and an absent or custom
  `.git/hooks/pre-push` is no boundary at all. `--inventory` tells you which of those you are
  in. The agent command gate still applies on hook-wired agent routes.
- **The boundary does not enforce FR-06's force-push rule.** It binds the source object and the
  destination; it does not read the remote's prior value, so it cannot tell a forced overwrite
  from any other update to the approved object. Force-push denial remains a command-policy
  `deny` rule at the command layer only, and the resolver refuses forced refspecs (`+main`,
  `--force*`) when minting.
- **A push whose gated destination is already up to date is not gated.** git omits up-to-date
  refs from the pre-push stream, so a push carrying only an extra (ungated) ref does not
  activate the rule and the boundary allows it. An explicit multi-ref command still requires
  every update to be bound at the command gate. This is destination scope, tracked in
  `docs/backlog/destination-aware-push-coverage/`.
- **A dry run cannot be approved.** `git push --dry-run` / `-n` performs no update, and git
  hands the boundary the same refs for it as for the real push, so an approval minted for a dry
  run would have authorized the real one. Minting for a dry run is refused; inspect with
  `git log <remote>/<branch>..<branch>` instead.
- **Approvals are audit metadata, not authenticated consent** (decision K3, unchanged): a
  process running as the same OS user can write a correctly bound artifact.

## Not in this release

Destination-aware coverage for a plain `git push` at the agent layer
(`docs/backlog/destination-aware-push-coverage/`), deploy and migration content binding
(`docs/backlog/deploy-and-migration-input-binding/`), shorter default lifetimes and provenance
fields (`docs/backlog/approval-ttl-and-provenance/`), and single-use approvals
(`docs/backlog/approval-single-use-consumption/`).
