# Pre-commit trusted-tool contract verification gate

Status: `PENDING — STOP AT GATE`  
Decision basis: `A2 + B1 LOCKED` (`decisions.md`)  
Deploy/release: `OUT OF SCOPE`

## Entry conditions

- T1, T2, T3 exist as three serial verified commits; each message cites its T-number.
- Each commit contains its control change and mutation discriminator; no fix-only or test-later commit exists.
- FR-07 approval was minted through a sanctioned writer for each protected-path commit, used by a normal commit, and consumed. `--no-verify` was not used.
- Planned paths only are changed; pre-existing `?? docs/wasted-code/` remains untouched/untracked.

## Required proof

| ID | Probe | Pass condition |
|---|---|---|
| P1 | `bash -n hooks/git/pre-commit` | rc=0 on the final T3 SHA. |
| P2 | Run the S2d version contract and mutation harness. | Supported paths pass; unsupported primary blocks; discriminator proves one unique target, exact named-row RED, identical controls, rejected unmutated negative. |
| P3 | Run the S2b Git-context contract and mutation harness. | AC2-AC4 matrix passes; discriminator satisfies the same four-clause proof. |
| P4 | Run the S2c verdict contract and mutation harness. | All four absent-artifact/rc=0 rows block; each of four independent mutants fails exactly its own row with identical controls and rejected unmutated negative. |
| P5 | Wrong/stale verdict probes | Wrong ID, wrong/stale nonce, cross-control artifact, and prior-run artifact all block; verdict files remain after neither success nor failure. |
| P6 | Mitigation inventory against T1 parent and final SHA | Environment scrub, `PYTHONSAFEPATH=1`, `-S` everywhere, controlled `PYTHONPATH`, file-script wrappers, `git ls-tree` sentinels, and trusted-HEAD extraction are present and exercised. |
| P7 | `bash hooks/local/preflight.sh` | rc=0. |
| P8 | `bash hooks/tests/run-tests.sh` | Full committed suite GREEN; report total/total, not only rc. |
| P9 | `python hooks/tests/run_hook_tests.py --compare-subprocess` | In-process/subprocess parity GREEN. |
| P10 | `bash hooks/local/check-module-size.sh --all` plus line count | Gate GREEN; `hooks/git/pre-commit` ≤800, or named verdict-protocol extraction seam landed and is covered. |
| P11 | Mutation production-integrity rows | Every harness byte-compares its baseline and production hook; no harness writes the tracked hook. |
| P12 | Claim-boundary review | No new text implies Git/Python authentication, trust-root creation, tamper-proofing, or executable identity proof. |
| P13 | Git/worktree audit | Diff contains only T1-T3 targets; unrelated `docs/wasted-code/` unchanged; three SHAs are linear. |

## Mutation evidence contract

Record one row for each discriminator: `python3-version`, `git-context`, `s2-head-extract`, `s2-secret-scan`, `s3-head-extract`, `s3-protected-path`.

| Field | Required value |
|---|---|
| Unique target | Exact file/line or stable anchor; occurrence count = 1. |
| Baseline | Unmutated copy GREEN; row set and total recorded. |
| Mutant | Exactly the named row changes PASS→FAIL; mutant FAIL count = 1. |
| Controls | Every other prerequisite/control row byte-identical after normalization. |
| Negative control | Unmutated copy presented as mutant is rejected; harness returns failure for the false claim. |
| Production integrity | Tracked production hook unchanged by the harness. |

Aggregate suite GREEN without all six complete records is `BLOCKED-AT-mutation-proof`.

## Compatibility matrix

| Context | Git works | Git unavailable/unusable |
|---|---|---|
| Normal repo / nested directory (`.git` directory) | Existing controls run | Attributable BLOCK |
| Linked worktree (`.git` file) | Existing controls run | Attributable BLOCK |
| Submodule (`.git` file) | Existing controls run | Attributable BLOCK |
| Explicit `GIT_DIR` / `GIT_WORK_TREE` | Existing behavior retained | Attributable BLOCK |
| Bare repository | Current no-worktree non-blocking behavior retained | Attributable BLOCK |
| Genuine outside-repo, no evidence | Existing skip, rc=0 | Existing skip, rc=0 |

Every row is required on the platforms where the context is supported; any platform-specific setup must be reported, not silently skipped.

## Exact-SHA dual-platform gate

1. Trigger `.github/workflows/fusebase-flow-verify.yml` with `workflow_dispatch` on the final T3 SHA.
2. Record run URL, requested SHA, checked-out SHA, and results for `verify-linux`, `verify-windows-msys`, and `verify-gate`.
3. All three jobs must be GREEN on the same SHA. Cancelled, skipped, timed-out, or different-SHA evidence is failure.
4. Confirm workflow triggers remain only `workflow_dispatch` and `workflow_call`; `push` and `pull_request` remain absent. A push is not verification evidence and must start no run.

## Gate report

```text
final_sha:
commits: T1=<sha> T2=<sha> T3=<sha>
fr07_approval: <mint/use/consume evidence per commit>; no_verify=absent
line_count: before=731 after=<n> ceiling=800 extraction=<none|path+seam>
targeted_contracts: <P2-P5 results>
mutation_proof: <six records or BLOCKED-AT-mutation-proof>
mitigations: <P6 inventory>
local_suite: <P1,P7-P11 totals/results>
compatibility: <matrix results>
workflow_dispatch: <url> sha=<sha> linux=<result> windows-msys=<result> gate=<result>
trigger_audit: push=absent pull_request=absent
claim_boundary: <P12 result>
worktree: <P13 result; unrelated pre-existing state>
verdict: PASS | BLOCKED-AT-<probe>
```

## Rollback

Revert T3, then T2, then T1 in separate newest-first commits. Each revert touching `hooks/git/pre-commit` requires a newly minted sanctioned FR-07 approval, normal verification, and consumption; never use reset, checkout discard, force push, or `--no-verify`. Re-run P1-P13 and the exact-SHA workflow gate on the rollback tip.
