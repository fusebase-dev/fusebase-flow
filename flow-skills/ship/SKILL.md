---
name: ship
description: Load when you deploy or hand off. The approval-gated deploy step, the rollback plan, the single ship commit and the ledger's deploy and handoff entries. Planner only.
---

# Ship

The planner runs the deploy step in its own session. A deploy, a rollback, an approval, a secret or a live-session check is never delegated.

Commit the ship commit as `ship: <what>`; `commit-msg` takes `ship:` only on the files under The ship commit below. Set an item `done` only when `python hooks/local/validate_evidence.py <phase>` passes its row.

## Before the deploy

- The phase verdict is recorded PASS in the ledger (verify). A review blocker is a finding returned as BLOCKER or one that meets the review brief's BLOCKER criteria, whatever grade it carries; it stays open until fixed or waived, and another review round does not close it. An open blocker ships only with a waiver in the ledger: the blocker line verbatim, the operator's own accept phrase and the accepted consequence. A paraphrase or "the operator said it's fine" is not a waiver.
- Re-check protected paths since the verdict: `git diff <verdict-sha>..HEAD` against `policies/protected-paths.yml`. Anything changed: stop and report.
- Classify the rollback surface from the diff and the deploy steps, one plan per class:

| Class | The deploy changes | Rollback plan |
|---|---|---|
| code-only | source, assets, config re-applied by redeploy | `git revert <sha>` and redeploy |
| migration | schema, store structure, backfill | down-migration or restore, checked against data written since; if irreversible, say so and give the forward fix |
| secret/config | secrets, env vars, keys, grants | restore the prior value (name where it lives); revoke new credentials |
| sidecar/infra | sidecars, cron, resource tiers | re-register the prior state with exact commands |
| cross-app contract | an API other apps call | compatible revert or consumer notice; check dependents first |

`git revert` alone is a valid plan only for code-only.

## Approval

- Never hand the operator a command to run. The operator decides in chat; you run every command that decision requires.
- Present the full scope first: the exact command and every side effect that needs its own approval (`database_migration`, `auth_or_permission_change`, `protected_path_edit`, and so on). Before the signal, present what the environment name resolves to (`environments/<name>.json`: backend, org, `protected`), whether the deploy provisions isolated stores or runs with `--skip-store-provision`, and that the approval covers every rerun of that exact command, whatever tree is present, until expiry (an action not presented is not covered).
- Production: the operator types `approve deploy now` (any case or spacing; a bare "yes" is not it), and nothing else. Then mint every approval you presented, `bash hooks/local/approve-local.sh <action> <slug> 'approve deploy now' --command '<exact command>'`, and run that exact command.
- Dev: the approval for the exact dev deploy command is minted before an unattended run starts, and `bash hooks/local/approve-local.sh --inventory` shows it VALID. The main session deploys at a task boundary; a helper agent never deploys.
- A hook denial or a refused mint is never "record it and proceed under the grant": a grant in chat is evidence of the conversation, not an approval artifact, so that slice returns `BLOCKED-AT-<gate>`. A worker never mints. An approval minted with `--command` authorizes only that text in this repository and stays valid for identical reruns until expiry; it does not bind the deployed content. A gated `git push` also binds the pushed commits, so a new commit needs a new approval.
- Minting with no authorization for that action, or to get past a denial, is self-approval: never.

## After the deploy

- The moment the deploy lands, add one JSON line to `state/deploys/<env>.jsonl` (`env`, `command`, `started`, `finished`, `rc`, `head`, `env_file_sha256`, `version_id`, `deploy_id`, `readiness`, `approval`) and write the deploy hash into the ledger.
- Run the live rows (verify). A failed probe or row: the item is not done; give the operator rollback (the surface plan) or fix-forward, in chat. The operator decides.
- A live run starts after the deploy it checks has finished: the validator compares its first record with `finished`. A pre-deploy baseline run, which records the state before the deploy it serves, names itself in its run-log title (`# Live run baseline-<run> <id> (<env>)`) and may start before it.

## The ship commit

One `ship:` commit after the live rows: the ledger's deploy record, the `state/deploys/<env>.jsonl` line, the evidence rows, the backlog status, `state/flags/*.tsv`, `state/gate/*.txt` and `state/done/*.json`. Nothing else, and never split.

## Ledger entries

- The first line points at `state/status.line`. `committed` is derived by `python hooks/local/done.py <slice>` into `state/done/<slice>.json`; `done` is the validator's verdict. Neither is written by hand.
- Deploy record: environment, exact command, deploy hash, approval file, rows run, rollback plan.
- Handoff entry, when work crosses sessions, at most 10 lines: branch and HEAD; the one next step; open questions and parked items with their clearing conditions; commands in flight (command, pid or output path, bound). Done work is a pointer to `git log`, never a list. A fact you do not know is `Unknown`, never a guess.
- Replace stale entries in place; git keeps the history. Never append a resumption note.

## Resuming

Compare the recorded branch and HEAD with the live ones. Equal: the next step is current. Different: re-derive from `git status --short` and `git log <recorded-head>..HEAD --oneline`, and treat the in-flight lines as history.

Never print or store a secret, session key or cookie in the ledger or in chat.
