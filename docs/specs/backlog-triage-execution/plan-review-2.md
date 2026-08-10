# Plan review — 2026-08-10 (Codex gpt-5.6-sol, high)

**Verdict: `WRONG-APPROACH`.** Reviewed `blocker-fix-plan.md` (`65d52da`) before any code.
The per-platform tier (B1) is the wrong fix, chosen before the measurement that should
decide the architecture.

VERDICT: WRONG-APPROACH

## Q1 per-platform tier

The proposed split would have missed **0 of the 5 recorded cases** in `ci-linux-msys-test-divergence`, because every recorded case was **MSYS-green/Linux-red** and Linux remains full. The plan states the direction backwards twice.

That does not make the split safe. Those failures came from checkout depth, PATH topology, Git file modes, fixture completeness, and inherited line-ending policy—not from phase names or intended product behavior. A single dual-platform pass cannot prove a phase has no future Windows failure mode. Worse, every shell phase already spawns processes and most manipulate files, so the plan’s own ownership criteria either retain nearly everything on Windows or become selectively ignored.

Verdict on alternatives:

1. Run a non-publishing, exact-SHA measurement with enough wall to finish.
2. Prefer the full Windows set with a larger absolute ceiling plus a short no-progress watchdog if release latency is acceptable. This preserves coverage with the least machinery.
3. If ≤60 minutes is mandatory, shard the complete Windows set into independently required jobs. This preserves coverage, though it adds setup time.
4. Use platform ownership only for phases demonstrably N/A by construction, enforced through a complete manifest and mutation tests—not written justification.

The plan chose the least defensible option before obtaining the measurement that should choose the architecture.

## Q2 tag/SHA sufficiency

The comparison is necessary but insufficient.

Surviving publication paths:

- Manual UI/API/CLI release creation remains open to repository users with write permission. GitHub explicitly permits write collaborators to create releases. The current `gh release view` early-exit would then report success without proving that release passed verification. [GitHub release permissions](https://docs.github.com/enterprise-cloud%40latest/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- A re-run of a pre-fix release workflow remains dangerous for up to 30 days. GitHub re-runs retain the original `GITHUB_SHA` and `GITHUB_REF`, and workflow runs use the workflow definition associated with that event. The old workflow can therefore verify the original SHA and publish a force-moved current tag without executing the new check. [Re-run semantics](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs), [workflow-version semantics](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflows)
- Any credential or workflow with `contents: write` can call the Releases API directly. No other such workflow exists in the current tree, but the proposed check does not enforce repository-wide exclusivity.
- There is a TOCTOU interval between resolving the tag and `gh release create`: the tag can move again unless tag updates are restricted.
- Annotated tags must be fetched from the remote and peeled to a commit; “resolve the tag target SHA” is too ambiguous.

The existing `workflow_dispatch` belongs only to verification and cannot currently publish, so it is not a bypass. Adding dispatch to the release workflow later would create one unless it uses the same exact-tag contract.

The real closure requires an explicit trust boundary, protected `v*` tag updates, remote fetch-and-peel immediately before publication, comparison with the verified commit, audit/removal of eligible old release runs, and preferably immutable releases. Tag rulesets can restrict updates; immutable releases lock the tag after publication. [Tag rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets), [immutable releases](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes)

## Q3 skip semantics

“Skipped discriminator fails” is directionally correct but semantically crude.

The correct states are:

- `PASS`: mechanism ran and produced the expected result.
- `FAIL`: mechanism ran and produced the wrong result.
- `ERROR`/`INCONCLUSIVE`: required mechanism could not be established; non-green.
- `N/A`: statically unsupported on this platform, declared in the ownership contract; not a runtime escape and covered on another required platform.
- `SKIP`: permitted only for explicitly optional diagnostics, never a required discriminator or required regression control.

On Windows/MSYS, failure to establish a required topology must be non-green. Off MSYS, the whole phase may be declared N/A. “Controls may still skip” is unsafe: an essential collateral control that did not run proves nothing and must also be non-green.

## Q4 time survey discipline

One instrumented full run per platform is the right discipline, not over-caution. It can double as the required exact-SHA baseline; it need not be a separate manual profiling campaign. Raw logs, per-phase status, wall time, and process/fixture counts must be retained, and orphan processes must be excluded before trusting timings.

However, the plan violates its own discipline by declaring process-spawn count the known global root cause. The recorded recovery analysis identified repeated full-tree copying plus filesystem/Defender amplification; the mirror-skills measurement does not prove the same driver across 45 phases.

The larger lever for the 60-minute job wall is parallel execution of the complete Windows set. For phase cost, attack measured fixture construction, repeated recovery invocations, project copies, and spawn count in that order of observed contribution. Re-measure after restoring B3 and the deleted signal coverage, because those corrections change the successor runtime.

## Q5 wrong fixes

- **B2:** Necessary shape, incomplete boundary. Add remote peeling, old-run invalidation, tag protection, manual-release threat model, and TOCTOU treatment.
- **B4:** Correct root area, wrong state model. Required inability is `ERROR/INCONCLUSIVE`; platform N/A must be static.
- **B1:** Wrong fix now. Drop the Windows coverage reduction as the committed answer; measure, then use a larger ceiling plus stall watchdog or complete sharding.
- **B3:** Correct root fix only if production recovery actually runs over the full corpus, its return code is asserted, and a retained red-before mutation proves the production-only defect is caught.
- **MAJOR 7:** Correct. Restore `TIMEOUT` as a distinct non-green result; do not revive a green `INCONCLUSIVE`.
- **MAJOR 12:** Correct intent but incomplete. Missing Python currently disables both secret scanning and FR-07 protected-path enforcement. Define supported interpreter discovery, preflight dependencies, and a clear blocking error.
- **MAJOR 9:** Correct direction. Ordinary push/PR CI should be fast; full dual-platform verification should be reusable for exact-SHA release and explicit maintainer runs.
- **MAJOR 8:** No fix is proposed. It merely restates the defect while “no raising any bound” contradicts the recorded larger-ceiling-plus-stall design. Resolve from successor measurements.
- **MAJOR 10:** No fix is proposed. Replace distributed grep anchors with semantic workflow-graph validation and red mutation cases.
- **MAJOR 11:** No fix is proposed, and a new one-off CI approval writer would patch the wrong layer. Unify the protected-path writer/consumer contract across categories, then obtain durable ratification tied to the exact workflow diff. New machinery cannot retroactively prove the old approval.
- **Documentation:** Defer wording until mechanisms and measurements are final. Keep measured lessons in their canonical problem entries; do not turn them into additional consumer governance.

Symptom:    blocker closure can still publish around verification or omit Windows coverage  
Root cause: publication trust boundaries and test-ownership semantics were not defined before fixes were selected  
Layer:      config/test architecture — fixing there? yes, but the proposed controls are incomplete  
Drift risk: prose will again claim stronger release and platform guarantees than machinery enforces  
Decision:   root-cause fix — rewrite the plan around exclusive publication authority and mechanically complete coverage

## Q6 north star

The plan adds no new human approval step, but B1 adds an ownership registry, per-phase justification, and permanent classification maintenance while risking weaker coverage. That is governance cost without demonstrated consumer value.

MAJOR 9 is in scope and its direction is right: ship fast ordinary CI and invoke full exact-SHA dual-platform verification only for releases or explicit maintainer use. Do not solve its runner-cost problem by weakening release coverage.

North-star: Drift  
Dimension: constraint — the safety kernel requires exact published-SHA verification, while the proposed Windows reduction adds governance and weakens evidence to preserve an arbitrary wall  
Recommendation: keep ordinary CI fast; preserve complete release coverage through measured ceiling/watchdog separation or sharding

## Q7 missing

- MAJOR 5: recovery return codes are still discarded.
- MAJOR 6: unique deleted signal lifecycle, wrapper-death, exit-status, fallback, and byte-integrity coverage is not restored or relocated.
- MINOR 13: the false active handoff remains uncorrected.
- A non-publishing measurement workflow with enough aggregate wall, retained raw timing artifacts, and exact-SHA identity.
- A mechanically exhaustive shard/platform manifest and aggregate gate; written reasons are insufficient.
- Measurement after coverage restoration, not only before it.
- Red-before retained mutations for B2, B3, B4, workflow graph validation, and each restored signal behavior.
- Audit of re-runnable old release workflows and existing manual/draft releases.
- An explicit publication threat model: trusted administrators, write collaborators, Actions tokens, tag mutation, and manual/API releases.
- Post-implementation security/permissions review for workflow permissions, approval machinery, and fail-closed scanning.

## Findings

1. BLOCKER | `blocker-fix-plan.md:18-29` | The cited platform evidence is reversed; all five recorded pitfalls were MSYS-green/Linux-red | The plan uses a nonexistent evidence direction to justify reducing Windows coverage | Verified against `ci-linux-msys-test-divergence/problem.md:1,11,24-31,56`.

2. BLOCKER | `blocker-fix-plan.md:13,23-28` | A one-run, written-justification ownership split cannot prove Windows non-ownership | Environment and harness behavior can diverge independently of phase intent | Verified from the five recorded mechanisms and `run-tests.sh:439-521`, where every shell phase executes through the platform-sensitive bounded runner.

3. BLOCKER | `blocker-fix-plan.md:13,79` | The plan commits to coverage reduction and forbids raising a wall before hosted measurement | It can replace a visible timeout with invisible missing evidence | Verified against `final-architecture-review.md:57-62,117-122` and `gate-bounds-lack-headroom/README.md:38`.

4. BLOCKER | `blocker-fix-plan.md:11` | Tag/SHA comparison covers only the current automated workflow invocation | Manual releases, old workflow re-runs, direct API calls, and tag movement during the check/create interval survive | Verified from `.github/workflows/fusebase-flow-release.yml:35-49` and GitHub’s release/re-run documentation cited in Q2.

5. BLOCKER | `blocker-fix-plan.md:12` | “Controls may still skip” permits required regression evidence to disappear green | A control that did not execute cannot establish non-collateral behavior | Verified against `test-run-tests-signal-reap.sh:13-25,47-53,225-277`.

6. BLOCKER | `blocker-fix-plan.md:14,31-40` | MAJOR 5 is omitted and B3 does not require recovery rc propagation | A partially successful recovery can satisfy assertions and still exit green | Verified at `cli-flow-recovery-direct.sh:118-130` and `final-architecture-review.md:97,120`.

7. BLOCKER | `blocker-fix-plan.md:31-40` | MAJOR 6 is omitted entirely | Unique lifecycle and integrity coverage remains deleted | Verified against `final-architecture-review.md:99,121`.

8. MAJOR | `blocker-fix-plan.md:38,79` | MAJOR 8 has no executable fix and conflicts with the no-bound-raise rule | The existing 1.64× ceiling remains load-sensitive | Verified against `gate-bounds-lack-headroom/README.md:24-40,55`.

9. MAJOR | `blocker-fix-plan.md:39` | MAJOR 10 is a finding restatement, not a fix | Comment-blind grep checks can continue certifying weakened workflows | Verified at `test-release-evidence-authority.sh:123-180` and by the retained mutation result in `final-architecture-review.md:76,107`.

10. MAJOR | `blocker-fix-plan.md:40` | MAJOR 11 is a finding restatement with no canonical writer/consumer design | Another category-specific helper would deepen the inconsistent approval contract | Verified at `approve-local.sh:165-221`, `write-bootstrap-approval.sh:73-96`, and `path_policy.py:236-310`.

11. MAJOR | `blocker-fix-plan.md:54-64` | The plan labels spawn count the established global cause before the survey | Optimisation can again target the wrong mechanism | Verified against `gate-bounds-lack-headroom/README.md:34-42`, which records full-tree copy/filesystem amplification as the recovery driver.

12. MAJOR | `blocker-fix-plan.md:36` | Missing Python affects more than the scanner | FR-07 also warns and proceeds, so the proposed closure understates the fail-open surface | Verified at `hooks/git/pre-commit:79-271,332-339,632-637`.

13. MAJOR | `blocker-fix-plan.md:37` | “Scope triggers to release/maintainer paths” does not define the ordinary fast workflow, exact release caller, or dispatch contract | MAJOR 9 can be closed in prose while expensive triggers remain | Verified against `.github/workflows/fusebase-flow-verify.yml:3-13,118-125`.

14. MAJOR | `blocker-fix-plan.md:27-29` | Acceptance requires only written platform-drop reasons, not mechanical completeness | A new or renamed phase can silently escape Windows ownership | Verified against the stronger mechanically checked map required by `final-architecture-review.md:57-62`.

15. MINOR | `blocker-fix-plan.md:31-74` | The active-handoff correction is absent | A later session can still consume false workflow and override state | Verified at `final-architecture-review.md:85,113,127`.

## Required changes before implementation

1. Replace B1 with: instrumented exact-SHA measurement first; complete Windows coverage by larger ceiling plus stall watchdog or mechanically complete sharding. Treat platform omission as a later measured optimisation.
2. Define the publication trust boundary and close B2 across remote peeled tags, protected updates, old re-runs, existing releases, manual/API publication, and TOCTOU.
3. Replace skip handling with the `PASS`/`FAIL`/`ERROR`/`N/A`/optional-`SKIP` model.
4. Make B3 explicitly assert the recovery command rc and retain a production-corpus red-before mutation.
5. Restore or relocate every unique behavior from MAJOR 6.
6. Give MAJORs 8, 10, and 11 concrete mechanisms and acceptance tests.
7. Expand MAJOR 12 to one fail-closed interpreter/dependency contract covering both secret scanning and FR-07.
8. Define separate ordinary fast CI, reusable full release verification, shard aggregation, and safe manual-dispatch semantics.
9. Re-measure the successor after coverage is restored; retain raw per-phase artifacts and orphan checks.
10. Correct the false divergence claims and active handoff before any implementation session consumes them.

## What I could NOT verify

- Live tag rulesets, release immutability, repository write permissions, or administrator bypass settings.
- Whether eligible pre-fix release workflow runs or manually created draft/releases currently exist.
- Actual `windows-latest`/`ubuntu-latest` phase timings, variance, billed minutes, or shard balance.
- Which phases can be proved platform-independent after a full static mechanism audit.
- Historical timing and red-before outputs that were not retained.
- Implementation correctness or security behavior; no implementation diff exists.

---
🧭 Phase: Verify  
🎫 Ticket: backlog-triage-execution  
➡️ Next: replace the blocker-fix plan before any implementation begins.
