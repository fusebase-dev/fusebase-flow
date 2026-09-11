# destination-aware-push-coverage

**Status:** open — build-order step 3 of the schema-3 premise review; not in the schema-3 outcome
**Filed:** 2026-09-11, while building mandatory command/ref-update binding (`approval-binding-omits-head`)
**Surface:** `policies/command-policy.yml` git push rule (`pattern: \bgit\s+push\b.*\b(main|master)\b`), `hooks/shared/command_policy.py` `_evaluate_require_approval`
**Severity:** medium — a push that updates `main` is not approval-gated at the AGENT layer unless its text names `main`/`master`

## Defect

The command gate matches raw text. `git push`, `git push origin HEAD` (on `main`), or any refspec whose destination is `main` without the literal word, matches no rule, so `pre_tool_use` allows it with no artifact.

| Layer | After schema 3 | Gap |
|---|---|---|
| Agent command gate | gates only text naming `main`/`master` | plain / HEAD / config-mapped pushes to `main` pass ungated |
| Git pre-push boundary (`hooks/git/pre-push`) | gates every update whose destination is in `push_destinations`, any route | only where the Flow pre-push is installed; a custom `.git/hooks/pre-push` or `core.hooksPath` keeps it off |

## Open decisions (need an operator product call)

- Resolve the destination for text that names no ref: `push.default`, `branch.<b>.remote/merge`, `remote.<r>.push`, `remote.pushDefault` — or deny any unresolvable push outright.
- `branch_pr` mode: the rule is skipped by `only_when`; decide what, if anything, authorizes a push to a protected branch there.
- Whether a human terminal push should stay gated at the pre-push boundary (it is today, where installed) or be scoped to agent routes.

## Constraints

- Reuse `git_push_binding.resolve_command_updates`; fail closed on anything it cannot resolve.
- Do not widen the regex to catch `git push` alone without resolution — every push would demand `production_deploy`.

## Related

- `docs/backlog/approval-binding-omits-head/` — the schema-3 cutover this follows
- `docs/backlog/command-gate-shell-evasion/` — K21 raw-text matching limits
