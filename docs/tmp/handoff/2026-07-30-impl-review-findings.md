| Severity | Axis | file:line | Problem | Concrete fix |
|---|---:|---|---|---|
| **BLOCKER** | 2 | `hooks/local/lib/materialize-managed-source.sh:128-155` | Manifest-bearing sources can become `UNVERIFIED_LEGACY_SOURCE` when the verifier is missing, unusable, returns no verdict, or exits unexpectedly. M10 permits fallback only when the manifest is absent. `BROKEN` also fails to name `audit/managed-content-manifest.json`. | If a manifest exists, require a usable verifier and exactly `MATCH`; abort every other outcome, naming the manifest and reported paths. Add missing-verifier, empty-verifier, unexpected-rc, and `BROKEN` fixtures. |
| **BLOCKER** | 3 | `hooks/local/lib/materialize-managed-source.sh:246-275` | Repair follows destination symlinks: a verifier-reported managed path symlinked outside the repo passes validation and `cp "$tree/$p" "$root/$p"` overwrites the external target. Multi-path repair is also non-atomic: a later `mkdir`/`cp` failure leaves earlier paths replaced. | Before any write, reject symlinks in the path and every parent, verify resolved containment, preflight all destinations, stage replacements, then atomically apply with rollback. Test outside-repo symlink and second-path failure. |
| **MAJOR** | 1, 2 | `hooks/local/bootstrap-upgrade.sh:113-122`; `hooks/local/upgrade.sh:212-217` | Both entry points source `materialize-managed-source.sh` from the mutable source worktree before materialization or verification. The code deciding whether the source is canonical is therefore itself unverified, contradicting AC2’s “before any source-derived file is sourced or read” boundary. | Bootstrap using trusted local code or minimal embedded archive logic; source the helper only from the materialized selected commit. Direct upgrade should prefer its installed trusted helper and reject unsupported pre-boundary execution. |
| **MAJOR** | 4 | `hooks/local/cleanup-flow-backups.sh:92-105,143` | Exact authority is widened by adding bare basenames for nested managed paths. For example, root-level `hook-layer-manifest.json.pre-upgrade-<ts>` is accepted even though only `audit/hook-layer-manifest.json` is authorized. | Keep only exact repo-relative stems; remove the basename expansions and root `module-size-baseline.txt` alias. Add misplaced-basename refusal cases. |
| **MAJOR** | 5, 9 | `hooks/shared/policy_loader.py:154-166`; `hooks/local/lib/active-approvals.sh:67-75`; `hooks/shared/path_policy.py:72-77` | The new tighten-only validation raises correctly, but consumers swallow that error and use `strict=False`/threshold 7. A local file that enables strict approvals and contains an invalid or raised threshold therefore disables its own strict mode—an actual fail-open path. | Propagate/report the policy error. Approval enforcement must deny on load failure; health must expose a configuration error rather than silently substituting compatibility defaults. Add consumer-level tests, not only direct loader tests. |
| MINOR | 6 | `hooks/tests/test-upgrade-source-boundary.sh:139-143`; `hooks/tests/test-msys-tree-cleanup.sh:415-430`; `hooks/tests/test-sync-allowlist.sh:212-215` | Several assertions overclaim: the “absolute handoff” test checks only log messages; cleanup never tests misplaced nested basenames; the `FLOW_RULES.md` backup absence assertion checks a fixture that was never created. | Capture and inspect the engine argv; add wrong-directory basename fixtures; create the `FLOW_RULES.md` backup before asserting it was pruned. |
| MINOR | 6 | `hooks/tests/run-tests.sh:151-162` | `emit_phase_diagnostics` has no always-running regression test. Reverting it leaves the normal green suite green; its behavior is exercised only when another phase already fails. | Run a synthetic failing phase in a harness test and assert its stderr-only sentinel reaches both composed stderr and the result artifact. |
| MINOR | 8 | `hooks/local/cleanup-flow-backups.sh:19-23,51-60` | M5 locked exactly two forms—`--all` or explicit targets—but shipped code adds `--list` and `--dry-run` without redirecting the decision. | Remove the extra forms or explicitly redirect M5/spec before release. |
| MINOR | 10 | `hooks/local/lib/materialize-managed-source.sh:4-29`; `hooks/local/cleanup-flow-backups.sh:19-37` | New production files contain provenance, changelog, usage, and WHAT-restating comment blocks beyond FR-22’s tripwire/pointer policy. | Retain concise load-bearing tripwires and decision pointers; remove provenance and code-restating commentary. |

## BLOCKER and MAJOR detail

### Manifest-bearing source verification fails open

The dangerous branches are not hypothetical compatibility handling:

- Manifest exists, verifier missing → lines 128-131 return success as legacy.
- Verifier emits no verdict with exit 0 → lines 137-142 return success.
- Unexpected verifier exit → lines 153-155 return success.
- Only actual `DRIFT`/`BROKEN` return failure.

A manifest-bearing source with an empty/replaced verifier can therefore reach classification and writes. This violates AC2/M10’s explicit distinction: only pre-manifest `ABSENT` may use `UNVERIFIED_LEGACY_SOURCE`.

The current test mutates a payload while leaving the verifier intact (`test-upgrade-source-boundary.sh:149-166`), so none of these bypass branches is exercised.

### Repair can write outside the repository and partially apply

`ff_managed_drift_paths` uses `Path.is_file()`/hashing, which follows a consumer symlink. The repair validation then checks only the verified source file (`:258`) and never inspects the destination. GNU `cp` follows an existing destination symlink, so:

1. A managed consumer path links to an external file.
2. The external bytes differ, so the verifier reports that exact managed path.
3. `--repair-managed` accepts the reported path.
4. Line 274 overwrites the external file.

The batch is also validation-only atomic, not write atomic. If path two has a parent that is a regular file or becomes unwritable, path one is already replaced before the command aborts.

### The source boundary trusts worktree code

All enumerated post-boundary content sites in `upgrade.sh` now use `SOURCE_TREE`; the classifier, planning, copy, docs, and baseline sites were converted correctly. Cleanup traps also cover classification abort, dry-run, attended abort, signals, errors, and success.

The remaining exception is earlier and more fundamental: both entry points source the boundary implementation from `SOURCE_REPO`/`SOURCE_CLONE`. A modified worktree helper can redefine materialization and verification before any canonical tree exists. The comments acknowledge the exception, but M1/AC2 did not authorize it.

The intended incoming-`U` and K13-`B` archive configurations are otherwise distinct at `materialize-managed-source.sh:76-85` and `bootstrap-upgrade.sh:234-250`; Git’s archive implementation does run working-tree conversion before emitting regular files ([Git `archive.c`](https://chromium.googlesource.com/external/github.com/git/git/+/HEAD/archive.c)).

### Cleanup authority is broader than the contract

The script correctly:

- Fails closed without the manifest-derived authority list.
- Uses exact timestamp parsing.
- Rejects absolute/traversal/glob/symlink/outside-root targets.
- Validates an explicit mixed batch before deletion.
- Leaves the FR-06 `rm -rf` command-policy deny unchanged.

But lines 95, 99, and 105 turn nested authorities into root-level authorities. Removing those lines would not break any current cleanup test—direct mutation evidence that the exact-set contract is untested.

### Threshold rejection can disable strict approval handling

`policy_loader.py` correctly rejects higher and invalid values. The failure appears at its consumers:

- `active-approvals.sh` catches all exceptions and sets `strict=False`.
- `path_policy.py` independently catches approval-policy load errors and returns `False`.

Thus a consumer-local policy containing:

```yaml
strict_approvals: true
stale_approval_warn_after_days: 30
```

raises during merge, then is interpreted by FR-07 approval evaluation as compatibility mode. Command-policy loading fails closed, but path-policy approval evaluation does not.

## Test reality

| Test | Mutation that genuinely goes red | Remaining weakness |
|---|---|---|
| `test-upgrade-source-boundary.sh` | Replacing the object archive at `materialize-managed-source.sh:81` with worktree copying breaks AC1. | Missing/unusable verifier, repair symlinks, partial repair, and actual absolute argv are untested. |
| `test-msys-tree-cleanup.sh` | Removing exact membership at cleanup line 143 makes unmanaged/string-prefix controls fail. | Misplaced nested basenames remain accepted and untested. |
| `test-health-check-timeout.sh` | Removing `_ffhc_heartbeat_start` at `run-with-timeout.sh:545` breaks the mid-run heartbeat assertion; moving warnings into verdict arrays breaks M9 checks. | Policy-loader exception behavior in actual consumers is untested. |
| `test-sync-allowlist.sh` | Removing the prune at line 151 makes real timestamped backup fixtures reappear. | The `FLOW_RULES.md` case is vacuous because that fixture is absent. |
| `test-approval-writer.sh` | Removing `created_at` from `approve-local.sh` breaks its parsing/freshness assertion; relaxing loader validation breaks tighten-only cases. | It tests the loader directly, not the fail-open consumers. |
| `run-tests.sh` diagnostics | No ordinary green-run mutation test covers removal of `emit_phase_diagnostics`. | Requires a synthetic failing phase. |

C1’s restructure currently holds: the portable AC4 group is above the off-MSYS unconditional `finish`; no portable assertion group remains below it. The symlink group now pins its refusal reason and reports honest all-or-nothing platform coverage. The AC5 heartbeat test no longer self-matches comments and has real timing margin.

Assertions that also pass at `85b97dd` are appropriately negative/control evidence, not defect proof: byte-exact M2 hashing, K13 consumer-EOL preservation, malformed backup visibility, heartbeat-off payload behavior, and fresh/expired approval controls.

## Axis disposition

| Axis | Verdict |
|---:|---|
| 1 | **Dirty** — three-byte implementation and copy-site conversion hold, but the boundary sources mutable worktree code first. |
| 2 | **Dirty** — manifest-bearing fallback is over-broad; pre-manifest compatibility itself remains intact. |
| 3 | **Dirty** — outside-repo symlink write and partial batch application. |
| 4 | **Dirty** — refusal mechanics are otherwise sound, but exact authority is widened by basenames. |
| 5 | **Dirty** — heartbeat/M3 and warning neutrality hold; threshold error handling fails open. |
| 6 | **Dirty** — core discriminators are real, but material gaps and two vacuous assertions remain. C1 is clean. |
| 7 | **Clean** — both hashers, `.gitattributes`, `templates/**`, and `.claude/settings.json.example` have empty diffs. |
| 8 | **Clean for excluded production scope** — no F1/F3/F4 code, F7 parser, hasher normalization, secret-scan bypass, or FR-06 exception leaked in. Extra cleanup CLI forms are minor decision drift. |
| 9 | **Dirty only through approval-policy failure handling** — DP.6, Lightweight lane, health deferrals, hooks-off installs, and pre-classifier compatibility otherwise show no regression in this range. |
| 10 | **Dirty on FR-22 only** — module sizes remain below 800, no added implementation TODO/FIXME/WIP, and no dead implementation branch found. |

## Verdict

**NO-SHIP for v4.7.0.**

Must fix before repeating T7/T8:

1. Fail closed for every manifest-bearing source verification failure.
2. Make repair reject symlinked/outside destinations and apply multi-path repairs atomically.
3. Remove the mutable-worktree bootstrap of the source verifier.
4. Restore exact repo-relative cleanup authority.
5. Make approval-policy validation errors fail closed through health and FR-07 consumers.
6. Add regression tests for each corrected failure path.

No files were modified. The supplied green gate is not accepted as release evidence because these reachable branches are absent from it.

---
Phase: Verify
Ticket: upgrade-source-integrity-and-observability
Next: Implementer fixes the five BLOCKER/MAJOR areas, then reruns the full Windows/Linux gate and both T8 reviews on the corrected commit.