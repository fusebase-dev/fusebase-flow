# recovery-engine-pre-push-coverage

**Status:** open — gap left deliberately by the schema-3 outcome (`approval-binding-omits-head`)
**Filed:** 2026-09-11, while adding `hooks/git/pre-push` (the FR-12 execution boundary)
**Surface:** `hooks/local/lib/recovery-preflight.py` (`for name in ("pre-commit", "commit-msg")`), `hooks/local/lib/recovery-verify.py` (same pair), `hooks/local/lib/hook-wiring-intent.sh` (`git_hook_receipt`, `len(installed) == 2`)
**Severity:** low — reporting completeness, not enforcement

## Gap

`install-git-hooks.sh` now installs three hooks, and `ffro_git_hook_states` / the upgrade trailer report all three. The RECOVERY engine still plans, verifies and receipts two:

| Surface | Covers `pre-push`? | Consequence |
|---|---|---|
| `install-git-hooks.sh` (upgrade + `--wire-hooks`) | yes | the boundary IS installed and refreshed |
| upgrade trailer (`recovery-outcome.sh`) | yes | a custom/absent `pre-push` is reported as boundary-not-live |
| recovery plan / verify operations | no | a recovery run neither verifies nor reports the hook it just installed |
| `state/audit/flow-hook-wiring-intent.json` receipt | no | the wiring receipt attests two hooks while three are managed |

Nothing claims `pre-push` is verified, so no report is false; the recovery evidence is narrower than the managed set.

## Why not in that outcome

The three-hook set touches `recovery-preflight.py`, `recovery-verify.py`, `hook-wiring-intent.sh` and four test fixtures that encode the pair literally (`test-recovery-final-verification.py`, `test-recovery-noop.py`, `cli-flow-recovery-direct.sh`, `cli-flow-recovery-e2e.sh`), whose suites are the slowest on MSYS. Settle it as one outcome with the recovery family's owner.

## Constraint

Derive the set from ONE declaration shared by installer, states, plan and verify — a second literal list is how this drifted.
