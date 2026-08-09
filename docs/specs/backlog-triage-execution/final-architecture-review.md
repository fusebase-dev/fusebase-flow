# Final architecture review — 2026-08-09 (Codex gpt-5.6-sol, xhigh)

**Verdict: `SOUND-WITH-CORRECTIONS`.** Reviewed `9f09cfa..ac89fc7` (the 7-step change).
Direction confirmed; 4 BLOCKERs + 8 MAJORs before any release attempt.

**Founding premise: narrowly TRUE.** CI already gated `publish` at `9f09cfa` and consumed no
local artifact. Caveat: the raw tag exists before CI and an admin can create a Release
manually, so the gate is authoritative only for the normal automated path.

VERDICT: SOUND-WITH-CORRECTIONS

## Q1 founding premise

Narrowly true. At `9f09cfa`, `.github/workflows/fusebase-flow-release.yml` already made `publish` depend on CI `verify`; it consumed no local-gate result or local audit artifact. Moving expensive local work out of the default gate was therefore directionally correct.

It is not absolute publication authority: the raw tag exists before CI, and an administrator can create a Release manually. The premise is sound only for the normal automated GitHub Release path.

## Q2 is the two-platform gate real

The current dependency graph is real:

- The fixed matrix contains Linux and Windows/MSYS, with `fail-fast: false`, no `continue-on-error`, and no job-level condition capable of removing one row.
- Both legs check out `inputs.sha || github.sha` and assert `HEAD` equals it.
- `verify-gate` uses `if: always()` and exits nonzero unless the matrix aggregate is exactly `success`.
- `publish` has `needs: verify` and no bypassing `if:`. Red, timed-out, or cancelled verification cannot publish. A force-cancel may leave the aggregate visibly cancelled rather than red, but still cannot publish. This matches GitHub’s documented [`needs` semantics](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs) and [matrix failure behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations?apiVersion=2022-11-28).

The end-to-end SHA binding is incomplete. `publish` creates the Release by mutable tag name without re-resolving that tag against the verified SHA. `gh release create --verify-tag` only checks that the remote tag exists; it does not verify its target. A force-moved tag can therefore attach a Release to an unverified commit. [GitHub CLI documentation](https://cli.github.com/manual/gh_release_create).

## Q3 coverage lost while numbers improved

Step 4 preserved all 31 old PASS labels and added a 32nd. It did not preserve equivalent behavior:

- The full production recovery exercise was replaced by a four-skill synthetic fixture.
- Predicate 32 checks that the already-clean production mirrors have zero drift; it never runs recovery/write mode over that corpus.
- U9 now ignores the recovery command’s return code, so a partially successful but ultimately failed recovery can still satisfy U7 and U9.

Step 5’s four discriminators are credible red-before cases by source comparison. No retained mutation output independently proves the claimed runs, however. The removed rows also covered distinct behavior: fallback EXIT reaping without a sentinel, real TERM/INT lifecycle, wrapper-death cleanup, TERM status 143, and output-byte noninterference. Those are not equivalent to the retained SIGKILL discriminator. Worse, three discriminators can report `SKIP` while the phase exits zero.

Step 3 retains release coverage: CI selects the full suite and still runs `secret-scan-staged`. The tracked pre-commit hook runs the real staged scanner when `python3` exists. Without `python3`, it silently skips content scanning. The scenario phase covers substantially more than an ordinary commit: exclusions, trusted-HEAD tamper resistance, first-adoption behavior, transient-error fail-closed behavior, module-shadow attacks, and full-tree self-scanning.

## Q4 override deletion — better or worse

Worse diagnostically, neutral for release strictness.

Before Step 7, both `FF_SKIP_CLI_RECOVERY` and the recovery timeout already incremented the failure count and made the suite exit nonzero. They were not green release bypasses.

Now timeout exit codes 124/137 are reported as “crashed,” erasing the distinction between a liveness bound and a failed assertion. That distinction should be restored as `TIMEOUT` or `INCONCLUSIVE`, while remaining a non-pass.

There is still local operator recourse through `FF_PHASE_TIMEOUT`; required CI intentionally supplies no override. The 1800-second bound has only 1.64× headroom over the reported 1099 seconds, below this repository’s own 2–3× loaded-host guidance and after repeated ordinary-growth crossings.

## Q5 the 60-minute wall

The 60-minute wall is not defensible with the available evidence. The ~88-minute estimate is not a hosted-runner measurement, but it is a strong adverse prior. A knowingly likely-red gate is not rigor.

Refusing a skip was correct. Refusing either measurement headroom or architectural decomposition was not.

The correct sequence is:

1. Run the exact SHA in a non-publishing measurement workflow with enough aggregate time to finish and retain per-phase timings.
2. Define a mechanically checked platform-ownership map so Windows does not repeat phases that provide no Windows-specific evidence.
3. Shard any remaining Windows-owned set that exceeds the design target into independently required exact-SHA jobs.
4. Use a larger aggregate wall only as a measured interim measure; retain a shorter stall/no-progress watchdog.

## Q6 north star

Exact-SHA release verification belongs in the North Star’s safety kernel. The fast 5m30s local default also aligns.

Step 6 nevertheless applies the full Linux-plus-Windows matrix to every `push main` and `pull_request main`, and `.github/` ships with the template. Solo builders therefore inherit long, costly dual-platform CI for ordinary work without opting into advanced release governance. That is North-Star drift. No new human approval ceremony was imposed, but substantial CI latency and runner cost were.

North-star: Drift  
Dimension: constraint — release safety aligns, but mandatory full dual-platform CI on ordinary pushes and PRs violates low-friction and cost-first defaults.  
Recommendation: separate fast consumer CI from the full reusable release-verification workflow.

## Q7 what is still wrong

The release-authority phase remains grep-based and structurally weak. The earlier `needs:` comment bug was fixed, but matrix anchors remain comment-blind and unrelated matches can satisfy the test. It does not require `verify-gate.if: always()`, require the publish tripwire, or prohibit `publish.if: always()`. An in-memory mutation commenting out the Windows row retained every existing anchor.

The Step-6 FR-07 approval claim is not reproducible:

- `approve-local.sh` emits no `paths` and emits a `repo_id` the real consumer does not supply while validating.
- `write-bootstrap-approval.sh` handles only `fusebase_flow_internals`, not `ci_cd_config`.
- `path_policy.py` ignores `tree_digest` for workflow paths, so the claimed digest-bound, single-use property could not have been enforced.
- The consumed artifact and audit evidence are absent.

The active handoff also contradicts the resulting tree: it says workflows were untouched and that no environment variable can make the gate pass.

## Findings

1. BLOCKER | `.github/workflows/fusebase-flow-verify.yml:46-50`; `PUBLISHING.md:76-79` | Required Windows verification has a 60-minute wall against an evidence-based ~88-minute estimate and no hosted-runner measurement | Publication is knowingly likely to be permanently red | Verified by workflow trace and `122m − 18m15s − 15m10s = 88m35s`.

2. BLOCKER | `.github/workflows/fusebase-flow-release.yml:35-49` | Release creation does not compare the current tag target with the SHA that passed CI | A force-moved tag can publish an unverified commit | Verified by tracing the tag-name-only `gh release create --verify-tag` call against the CLI’s documented semantics.

3. BLOCKER | `hooks/tests/cli-flow-recovery-direct.sh:13-25`; `hooks/tests/cli-flow-recovery-fixture.sh:22-32`; `hooks/local/mirror-skills.sh:156-257` | Predicate 32 checks existing production mirror parity but never exercises production recovery/write mode | The four-skill fixture can miss a production-only recovery regression—the exact fixture-substitution failure class under review | Verified by comparing the current four-skill lifecycle with the full-corpus recovery at `0365884:hooks/tests/test-cli-flow-recovery.sh:44-55`.

4. BLOCKER | `hooks/tests/test-run-tests-signal-reap.sh:47-53,225-277`; `hooks/tests/run-tests.sh:439-460` | Three of four claimed discriminators may SKIP while the phase exits zero | A loaded Windows run can silently lose most defect coverage and remain green | Verified by tracing each topology-failure branch to `skip()`, whose counter is excluded from `finish()`’s exit status.

5. MAJOR | `hooks/tests/cli-flow-recovery-direct.sh:118-130` | U7/U9 run recovery under `set +e` and discard its return code | Recovery may fail after making the asserted edits, yet both predicates pass | Verified against `0365884:hooks/tests/test-cli-flow-recovery.sh:689-696`, where nonzero recovery terminated the test.

6. MAJOR | `hooks/tests/test-run-tests-signal-reap.sh:20-29`; `b4b7baa^:hooks/tests/test-run-tests-signal-reap.sh:252-260,467,492` | Eleven deleted rows included unique lifecycle, fallback, exit-status, and byte-integrity coverage | The 19→8 reduction was not coverage-equivalent | Verified by mapping removed behavior repository-wide; no surviving equivalent tests were found.

7. MAJOR | `hooks/tests/run-tests.sh:439-460,516-520`; `hooks/local/lib/run-with-timeout.sh:49-54` | Timeout exit codes are mislabeled as crashes | Operators can no longer distinguish host load or a liveness bound from a broken assertion harness | Verified by tracing rc 124/137 from the timeout wrapper into the generic crash branch.

8. MAJOR | `hooks/tests/run-tests.sh:55-61`; `docs/backlog/gate-bounds-lack-headroom/README.md:22-26,40,46-55` | The recovery bound has 1.64× reported headroom despite documented 2–3× guidance and repeated bound crossings | Ordinary load can produce false red release gates again | Verified from the reported 1099-second duration, committed 1800-second bound, and recorded crossing history.

9. MAJOR | `.github/workflows/fusebase-flow-verify.yml:3-13,33-50,118-122`; `docs/north-star.md:7-19` | Full dual-platform verification runs on ordinary pushes and PRs, not only release calls | Template consumers inherit maintainer-grade latency and runner cost without opt-in | Verified by trigger-to-matrix trace and the documented shipped `.github/` surface.

10. MAJOR | `hooks/tests/test-release-evidence-authority.sh:85-97,123-130,158-171` | Release-architecture assertions remain comment-blind, distributed grep checks; as many as eleven declared surfaces may also disappear | Future workflow weakening can remain green while prose still claims enforcement | Verified by in-memory mutations: commenting the Windows row and adding an unsafe publish condition retained the existing anchors.

11. MAJOR | `hooks/local/approve-local.sh:165-222`; `hooks/local/write-bootstrap-approval.sh:73-80`; `hooks/shared/path_policy.py:268-310`; `policies/protected-paths.yml:74-117` | No shipped writer/consumer path can enforce the Step-6 approval exactly as claimed | The protected release-workflow edit lacks reproducible FR-07 provenance, and the general approval helper produces an artifact the actual gate rejects | Verified by tracing emitted fields, repository binding, category selection, path matching, and digest enforcement; no matching durable audit record remains.

12. MAJOR | `hooks/tests/run-tests.sh:116-126`; `hooks/git/pre-commit:79-271` | “Scanner runs on every commit” is false when `python3` is unavailable | Step 3’s local-safety justification relies on a fail-open condition | Verified by following the hook’s `command -v python3` branch; there is no blocking `else`.

13. MINOR | `docs/tmp/handoff.md:31-32,83-87` | The active handoff says workflows were untouched and no environment override remains | A fresh session receives materially false operating state | Verified against Step 6’s workflow diff and the surviving `FF_PHASE_TIMEOUT`.

## Required before a release attempt

- Measure the exact successor SHA on `windows-latest` in a non-publishing run with retained raw per-phase timings.
- Replace the current Windows monolith with a mechanically complete platform-owned/sharded gate, or justify an aggregate wall from measured worst-case headroom. Do not add a release skip.
- Re-resolve and peel the remote tag immediately before publication, compare it with the verified SHA, and abort on mismatch.
- Restore one full-production recovery/write lifecycle, propagate U9’s recovery return code, and retain the synthetic fast cases.
- Restore or relocate the removed signal lifecycle controls; required Windows discriminators must treat topology failure as non-pass, not SKIP-success.
- Restore an explicit non-green `TIMEOUT`/`INCONCLUSIVE` state and set phase bounds from loaded-host evidence plus a stall watchdog.
- Replace workflow grep anchors with semantic YAML/job-graph validation and mutation tests.
- Split ordinary fast push/PR CI from full reusable release verification.
- Repair the FR-07 writer/consumer contract and obtain durable operator ratification of the exact Step-6 workflow diff.
- Make missing-Python secret scanning fail closed or narrow the “every commit” claim and provide an equivalent guard.
- Correct the active handoff before another session relies on it.

## What I could NOT verify

- Actual `windows-latest` runtime, variance, or whether any exact-SHA two-platform run completes.
- Live GitHub behavior for forced cancellation or an artificially skipped aggregate; the workflow graph and documented semantics were traced statically.
- The reported Step-4/Step-5 timing logs or claimed red-before mutation outputs; neither was retained.
- The consumed Step-6 approval artifact, its paths, digest, `repo_id`, or provenance.
- Whether live repository tag rulesets, branch protection, or immutable-release settings close the tag-movement boundary.
- The write-heavy shell suites in this read-only review environment; direct Git Bash execution also encountered `CreateFileMapping` Win32 error 5.
