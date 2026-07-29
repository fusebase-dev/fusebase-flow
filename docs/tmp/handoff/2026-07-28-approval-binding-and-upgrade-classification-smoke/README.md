# Smoke evidence — approval-binding-and-upgrade-classification (v4.7.0)

**Result: 6/6 PASS** (threshold 6/6). Released state: `6224bbe`, tag `v4.7.0` (local only).
Surface: fresh clones in `/c/tmp/ff470/`, hooks wired (`.claude/settings.json` from example) — never the dev tree.

| ID | Verdict | Operator-visible outcome observed | Ground-truth diagnostic | Adversarial control | Evidence |
|---|---|---|---|---|---|
| S1 | PASS | 4.7.0 denies `fusebase deploy`; message names `production_deploy [ACTION_MISMATCH]` and states filename/body action disagree | `state/audit.log.jsonl` → `"approval_verdict":"ACTION_MISMATCH"`, `action_verdicts={"production_deploy":"ACTION_MISMATCH"}` | 4.6.1, identical artifact + payload → `decision=allow` | `S1-4.7.0.md`, `S1-4.6.1-adversarial.md` |
| S2 | PASS | inventory row `legacy-no-expiry` / `REJECT (MISSING_EXPIRY)`; compat allows; strict denies `MISSING_EXPIRY` | 3 audit entries incl. `event:"approval_legacy_accepted"` naming the artifact | compat allow IS logged (not silent) | `S2-legacy-expiry.md` |
| S3 | PASS | allow/allow (LL artifact) → deny/deny (removed) → allow/allow (`production_deploy`), both handlers = 6/6 observations | decision entries from `pre_tool_use.py` and `permission_request.py` | K19: mint without `--command` → exit 2, 0 files written | `S3-lightweight-parity.md` |
| S4a | PASS | abort `EXIT=3`; report lists `hooks/shared/command_policy.py` under `changed-by-both (1)`; "NOTHING was written" | pre/post `sha256` identical `88682ed6…`; sentinel grep = 1 | consumer's own 4.6.1 `upgrade.sh` → sentinel = 0, hash → `69e8b62a…` (patch destroyed) | `S4a-preservation.md`, `S4a-adversarial-old-engine.md` |
| S4b | PASS | run completes `EXIT=0`; `upstream-only 46`, `unknown-base 0`; VERSION → 4.7.0 | control `hooks/local/upgrade.sh` `51c13460…` → `2a52bdb5…` = byte-identical to 4.7.0 source; `command_policy.py` → `69e8b62a…` likewise | VERSION=4.6.99 (unresolvable base tag) → `unknown-base 46`, control file unchanged `51c13460…` | `S4b-delivery.md`, `S4b-adversarial-unresolvable-base.md` |
| S5 | PASS | single message: `production_deploy [SATISFIED], database_migration [NO_ARTIFACT]` | audit entry `all_required_actions=["production_deploy","database_migration"]`, `action_verdicts` both present | 4.6.1, same compound command + deploy artifact → `decision=allow` | `S5-4.7.0.md`, `S5-4.6.1-adversarial.md` |

## Recorded execution deviations (neither weakens a pass criterion)

| # | Gate text | Executed as | Why |
|---|---|---|---|
| E1 | S3 step 1 `approve-local.sh lightweight_deploy smoke-ll 'ship it'` | same + `--command 'fusebase deploy'` | K19/AC22 shipped by THIS ticket makes `--command` mandatory; the literal line now exits 2. The exit-2 of the literal line is captured first in `S3-lightweight-parity.md` as case 0, then the correct post-K19 invocation runs. |
| E2 | S4a/S4b "run `bash hooks/local/bootstrap-upgrade.sh`" | the **4.7.0** `bootstrap-upgrade.sh` installed into the 4.6.1 consumer first, then run with `--repo <local repo> --ref fix/msys-v3307-hardening` | Matches the documented adoption route and the AC13b/AC16 harness (`test-upgrade-conflict-classification.sh:362`). Base synthesis (K13a) ships IN 4.7.0; the consumer's stale 4.6.1 copy cannot synthesize. See § Operator note. |
| E3 | clone `--branch v4.7.0` | clone the local repo at `6224bbe` (the tagged commit) | Tag is created after smoke per the handoff's step order; `6224bbe` IS the tagged commit. |

## Operator note — stale-bootstrap adoption (observed, not a defect)

A 4.6.1 consumer who runs their **own installed** `bootstrap-upgrade.sh` (rather than fetching 4.7.0's) gets no base synthesis: classification returned `unknown-base (41)` and the run **completed without aborting**. Behaviour is still safe — every `unknown-base` path is PRESERVED (K9 row 10, which by design never aborts), so the consumer's patched `command_policy.py` survived. But the AC16 `changed-by-both` report is NOT produced on that route. Release notes / upgrade docs should state that adopting 4.7.0 requires the 4.7.0 `bootstrap-upgrade.sh` (the README one-liner), not the stale local copy. Filed as an operator-visible documentation point, not a code defect.
