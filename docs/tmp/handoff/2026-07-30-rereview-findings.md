| Finding | Verdict | Current-HEAD proof |
|---|---|---|
| R1 — manifest-bearing verification fail-open | **CLOSED** | [materialize-managed-source.sh:122](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:122>) permits `UNVERIFIED_LEGACY_SOURCE` only when the manifest is absent. Missing verifier/Python, rc-0 without literal `MATCH`, DRIFT, BROKEN, and unexpected rc all return failure while naming `audit/managed-content-manifest.json` at lines 127–152. |
| R2 — repair symlink escape and non-atomic batch | **CLOSED** | [materialize-managed-source.sh:262](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:262>) rejects leaf and parent-component symlinks and verifies resolved containment. Lines 365–419 stage every path, keep rollback copies, restore already-applied paths after a later swap failure, and remove residue. Duplicate paths are preflight-rejected at lines 347–355. |
| R3 — mutable source helper trusted | **PARTIALLY CLOSED** | Normal bootstrap uses the installed helper at [bootstrap-upgrade.sh:204](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/bootstrap-upgrade.sh:204>); direct upgrade uses the caller-verified tree or installed copy at [upgrade.sh:213](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/upgrade.sh:213>). But an old install with no local helper snapshots a **plain** source, then sources its unverified helper at bootstrap lines 167–186. That helper can redefine `ff_source_verify_tree` and approve itself. |
| R4 — cleanup basename authority widening | **CLOSED** | [cleanup-flow-backups.sh:74](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/cleanup-flow-backups.sh:74>) retains exact repo-relative stems only; lines 121–140 reconstruct and validate the whole stem. `--all` filters every candidate through the same predicate at lines 147–156. |
| R5 — invalid approval policy disables strictness | **CLOSED** | [path_policy.py:76](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/shared/path_policy.py:76>) raises `ApprovalPolicyError`; `evaluate()` converts it to an unconditional deny at lines 319–328. [active-approvals.sh:41](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/active-approvals.sh:41>) probes the policy even with zero artifacts, activates none on error, and health prints a configuration error at [fusebase-flow-health-check.sh:732](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/fusebase-flow-health-check.sh:732>). |
| MINOR — overclaiming assertions | **CLOSED** | Actual engine argv is captured and inspected at [test-upgrade-source-boundary.sh:142](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-upgrade-source-boundary.sh:142>). Misplaced cleanup basenames are created and checked in explicit and `--all` modes at [test-msys-tree-cleanup.sh:439](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-msys-tree-cleanup.sh:439>). The file-level `FLOW_RULES.md` case now creates the fixture and directly checks exact-shape authority at [test-sync-allowlist.sh:221](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-sync-allowlist.sh:221>). |
| MINOR — no always-running diagnostics regression test | **CLOSED** | [test-ff-only.sh:116](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/tests/test-ff-only.sh:116>) drives a synthetic failing phase and checks both composed stderr and the durable results artifact. |
| MINOR — unratified cleanup CLI forms | **CLOSED** | [cleanup-flow-backups.sh:35](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/cleanup-flow-backups.sh:35>) now accepts only `--all` or explicit targets; `--list` and `--dry-run` were removed. There is no explicit regression assertion for their rejection. |
| MINOR — FR-22 comment policy | **PARTIALLY CLOSED** | Provenance/changelog prose was removed, but [materialize-managed-source.sh:9](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/lib/materialize-managed-source.sh:9>) still carries a 15-line WHAT/API inventory, and [cleanup-flow-backups.sh:14](<C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/hooks/local/cleanup-flow-backups.sh:14>) retains usage/eligibility restatement beyond the load-bearing M5 tripwires. Non-blocking. |

The cited prior artifact contains four MINOR rows, not five; its first row contains three separate assertion defects, all checked above.

## New regression findings

### BLOCKER 1 — old-install + plain-source verification remains circular

When the consumer lacks an installed materializer:

1. The plain source is copied at `bootstrap-upgrade.sh:167–173`.
2. Its own unverified `materialize-managed-source.sh` is sourced at lines 175–178.
3. Only then does that source-derived code “verify” the tree at line 186.

A tampered plain-source helper can override `ff_source_verify_tree` and approve itself. The current tamper test does not exercise this matrix: it leaves the consumer’s trusted local helper installed, while the K10 plain test removes only the consumer copy and uses an untampered source helper.

This leaves R3’s original integrity boundary open for a supported plain-directory source shape.

### BLOCKER 2 — genuine pre-manifest/no-helper sources cannot complete bootstrap

For a source with neither manifest nor materializer, bootstrap correctly logs `UNVERIFIED_LEGACY_SOURCE` at `bootstrap-upgrade.sh:189–201`. It then:

- points `ENGINE_SRC` into the temporary tree at line 268;
- detects that the old engine lacks `--source-tree` support;
- deletes that temporary tree at lines 362–365;
- tries to execute the now-deleted engine at line 369.

Thus a genuine pre-4.7.0/plain source does not upgrade. The new K10 test misses this because its source still contains the new materializer; only the consumer copy is deleted at `test-upgrade-source-boundary.sh:345–346`.

### M11 sanity

`--unsafe-legacy-copy` no longer bypasses verification: the source boundary runs at `upgrade.sh:207–241`, before the flag can affect classifier handling at lines 295–320. That ratification is implemented correctly.

However, it does strand a real historical source shape indirectly. The currently visible old `v4.7.0` tag contains:

- `audit/managed-content-manifest.json`
- `hooks/local/lib/managed_content_manifest.py`
- no `materialize-managed-source.sh`

An old consumer with no installed materializer is refused at `bootstrap-upgrade.sh:189–196`, even though that source contains the actual verifier and is provable. The spec records that this tag was fetched by a prerelease tester. Per the task’s explicit M11 criterion, this is a release blocker.

## Test reality

| Added/changed assertion group | Would pass at `ee9e887`? | Assessment |
|---|---:|---|
| Manifest missing/empty/rc-9/no-verdict/BROKEN handling | No | Real discriminator. DRIFT was already rejected, but the other outcomes and manifest-naming check fail at baseline. |
| Repair duplicate path | No | Real discriminator. |
| Repair leaf/parent symlink | No on Linux; SKIP on MSYS | Real Linux proof: both links are precondition-checked with `-L`, must be verifier-reported, and must be refused specifically for “symlink.” |
| Repair second-path preflight and swap rollback | No | Real write-atomicity discriminators. |
| Mutable-worktree tamper/direct refusal | No | Real for the tested installed-helper configuration; incomplete for old-install/plain source. |
| K10 embedded hop | No | New engine hop is real, but the fixture retains the source materializer and misses genuine pre-manifest/no-helper sources. |
| Exact cleanup basenames | No | Real discriminator, including `--all` survival. |
| Path-policy and health policy-load failure | No | Real consumer-level discriminators with valid-policy preconditions. |
| Actual argv inspection | Yes | Coverage repair, non-vacuous: it inspects recorded argv rather than logs. |
| `emit_phase_diagnostics` harness | Yes | Coverage repair, non-vacuous: deleting diagnostics replay makes it fail. |
| File-level allowlist authority | Yes | Coverage repair, non-vacuous direct predicate check. |
| Corrected pre-classifier fixtures | Yes | Fixture correction/negative control, not defect proof. |

No current added assertion is outright vacuous. The K10 assertion is materially incomplete, not vacuous.

Portable cleanup assertions run at `test-msys-tree-cleanup.sh:391–630`; the off-MSYS unconditional `finish` is later at line 638. No portable group is stranded below it. Both repair and cleanup symlink classes execute before any platform exit; on Linux, ordinary `ln -s` produces actual links and the expected-class count must be exactly two. The reported Linux run is therefore real symlink proof for the covered classes.

## Regression posture

- DP.6, Lightweight lane, command-policy enforcement, bootstrap writer, pre-commit wrapper, and deploy-role rules have empty diffs.
- Valid FR-07 approvals still pass; the R5 control proves the same artifact authorizes under a valid policy.
- Health deferrals remain unchanged under a valid policy; an invalid approval policy now activates none and reports the configuration error.
- The new `ApprovalPolicyError` does not escape the pre-commit path: `evaluate()` converts it to deny, and pre-commit retains its outer fail-closed `BaseException` wrapper.
- Repair’s `set -e` and rollback paths are guarded correctly.
- No secret-shaped additions, auth widening, external messaging, or data movement were found.
- The only existing-consumer regression is the pre-boundary bootstrap matrix above.

## Verdict

**NO-SHIP for v4.7.0.**

Must fix:

1. Verify a manifest-bearing plain snapshot without first sourcing code from that snapshot; add an old-install tamper fixture that overrides `ff_source_verify_tree`.
2. Preserve the named `UNVERIFIED_LEGACY_SOURCE` route for a source that lacks both manifest and materializer, without deleting its engine before execution. Add plain and git fixtures for that exact source shape, plus the real manifest+verifier/no-materializer shape represented by the old `v4.7.0` tag.

Then rerun the unscoped Windows/Linux gates and both reviews. The reported 698/699 and 696/696 gates do not exercise these source matrices.

Comment-policy review: applied (FR-22). No files were modified.

---
🔄 Phase: Verify  
🎫 Ticket: upgrade-source-integrity-and-observability  
➡️ Next: fix the two bootstrap blockers, rerun both platform gates, then repeat code and security review