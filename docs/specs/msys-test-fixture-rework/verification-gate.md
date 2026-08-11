# Verification gate — msys-test-fixture-rework

| Field | Value |
|---|---|
| Status | DRAFT |
| Linked spec | `docs/specs/msys-test-fixture-rework/spec.md` |
| Linked tasks | `docs/specs/msys-test-fixture-rework/tasks.md` |
| Gate owner | AI Developer produces evidence; Product Owner reviews |
| Gate outcome | PASS only when G1-G8 are GREEN on T3's exact SHA |
| Smoke | N/A — repository framework tests, no deployed app surface (`docs/constitution.md:35-37`) |

## Acceptance-criterion mapping

| AC | Implemented in | Required proof |
|---|---|---|
| AC1 | T2 | Source inspection + G1/G2: one shared fixture; both mirror loops/caps absent |
| AC2 | T1 | G2: success prerequisites GREEN; all four fixture outer assertion rows PASS after capturing their unique inner failure row/reason |
| AC3 | T2 | G2: both named row-8 assertions GREEN; source shows one captured invocation |
| AC4 | T2 | G2: normal-PATH control GREEN; fixture-PATH row blocks for interpreter diagnostic |
| AC5 | T2 | G2: all four git-smoke outer assertion rows PASS after capturing their unique inner failure row/reason; no merged precondition boolean |
| AC6 | T3 | G3: GREEN baseline, exact one-row mutant delta, identical controls, unique target, and rejected unmutated negative control |
| AC7 | T1-T2 | G1/G2/G8: no PATH-directory enumeration; both hosted platforms GREEN |
| AC8 | Gate | G8: `verify-linux`, `verify-windows-msys`, and `verify-gate` GREEN on exact SHA |
| AC9 | T1-T3 | G4: module-size scan GREEN; bootstrap file shrank |
| AC10 | T1-T3 | G6/G7: scoped diff and clean generated-manifest checks |

## Gate sequence

| ID | Command / action | Required observation | Evidence |
|---|---|---|---|
| G1 | `bash -n hooks/tests/lib/minimal-path-fixture.sh hooks/tests/test-minimal-path-fixture.sh hooks/tests/test-pre-commit-interpreter-contract.sh hooks/tests/test-pre-commit-interpreter-mutation.sh hooks/tests/test-bootstrap-exception.sh hooks/tests/test-git-hooks-smoke.sh hooks/tests/run-tests.sh` | rc 0; no syntax diagnostics | transcript |
| G2 | `FF_ONLY=minimal-path-fixture,git-smoke,bootstrap-exception,interpreter-contract bash hooks/tests/run-tests.sh` | rc 0; success-path prerequisites, `8-interpreter-absent-blocks`, `8-interpreter-absent-block-message`, normal-PATH control, and git-smoke missing-interpreter row PASS; all eight outer assertion rows from `spec.md` Diagnostic injection matrix PASS after each captures exactly its mapped inner failure row/reason; no uncaptured top-level `FAIL:` row | scoped transcript + captured inner diagnostics + `state/audit/hook-test-results-scoped.md` |
| G3 | `FF_ONLY=interpreter-mutation bash hooks/tests/run-tests.sh` | rc 0 only after the harness reports: one unique mutation target; unmutated baseline GREEN; mutant makes exactly `8-interpreter-absent-blocks` FAIL; all prerequisite/control rows identical; unmutated-as-mutant negative control makes the inner harness fail | scoped transcript + baseline/mutant/control result diff + `state/audit/hook-test-results-scoped.md` |
| G4 | `bash hooks/local/check-module-size.sh --all` | rc 0; bootstrap line count below 799; no new file above 800 | transcript |
| G5 | `bash hooks/local/preflight.sh` | rc 0; no structural, YAML, frontmatter, mirror, or action-name failure | transcript |
| G6 | Inspect `git diff --name-only <T1-parent>..<T3-SHA>` and `git diff <T1-parent>..<T3-SHA> -- hooks/git/pre-commit .github policies` | changed paths equal T1-T3 targets; scoped production/workflow/policy diff is empty | changed-path list + empty scoped diff |
| G7 | `bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code -- audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh` | rc 0; stamping produces no diff; manifest verifies | transcript + clean diff |
| G8 | Dispatch `.github/workflows/fusebase-flow-verify.yml` with `workflow_dispatch` at T3's exact branch SHA | checkout assertion names T3 SHA; `verify-linux`, `verify-windows-msys`, and `verify-gate` GREEN; audit artifacts retained | Actions run URL + job conclusions + SHA |

## Full local developer gate

Before G8, run the full unscoped suite with the committed watchdogs:

```bash
FF_FULL=1 bash hooks/tests/run-tests.sh
```

Required observation: rc 0 and the strict `[run-tests] N/N PASS` summary; `state/audit/hook-test-results.md` records zero FAIL rows (`hooks/tests/run-tests.sh:4-25,585-599`). This local result is implementation feedback only, never release evidence (`hooks/tests/run-tests.sh:4-8`).

## Hosted verification contract

- Dispatch explicitly: `gh workflow run fusebase-flow-verify.yml --ref fix/msys-v3307-hardening`.
- Record the resolved run SHA and require it to equal T3's commit SHA; the workflow checks out and asserts the requested/event SHA before tests (`.github/workflows/fusebase-flow-verify.yml:67-85`).
- A push or pull request starts no verification workflow; only `workflow_dispatch` and `workflow_call` are configured (`.github/workflows/fusebase-flow-verify.yml:3-21`).
- G8 is required hosted acceptance evidence. It is not an app deploy or publication authorization; publication remains separately gated through the release caller on a tagged SHA (`.github/workflows/fusebase-flow-verify.yml:16-33`; `docs/constitution.md:35-37`).

## Mutation evidence contract

| Field | Required value |
|---|---|
| Production source | `hooks/git/pre-commit` unchanged |
| Baseline source | isolated unmutated temporary copy; complete contract run GREEN |
| Mutant source | separate isolated temporary copy |
| Mutation | exactly one diagnostic-adjacent `exit 1` removed at `hooks/git/pre-commit:93-96`; zero/multiple matches fail |
| Required mutant delta | exactly `8-interpreter-absent-blocks` changes from PASS to FAIL; no additional FAIL row |
| Control invariance | every prerequisite/control row has the same name and result in baseline and mutant |
| Negative control | presenting another unmutated copy as the mutant makes the inner mutation harness fail |
| Harness result | PASS only after observing the GREEN baseline, exact mutant delta, control invariance, and expected negative-control rejection |
| Failure conditions | baseline non-GREEN; zero/multiple mutation matches; missing/extra FAIL row; changed prerequisite/control; unmutated negative control accepted |

## Required gate-report fields

Use `templates/gate-report.md` and `policies/gate-contracts.yml: gate_report`; do not replace the report with a summary. Add these ticket-specific fields:

| Field | Required content |
|---|---|
| `task_shas` | T1 SHA; T2 SHA; T3 SHA |
| `source_scope` | changed-path list proving `hooks/git/pre-commit`, `.github/**`, and `policies/**` unchanged |
| `fixture_proof` | absolute Git path; absolute shell path; interpreter-absence checks; no directory mirroring; all eight Diagnostic injection matrix outer rows plus their captured inner row/reason |
| `mutation_proof` | target count; baseline result set; mutant result set; exact delta; prerequisite/control equality; unmutated negative-control inner rc |
| `module_size` | before/after bootstrap line count; each new shell file line count |
| `local_full` | command, rc, strict summary; labeled non-release evidence |
| `hosted_run` | URL, exact SHA, three job conclusions |
| `worker_undisturbed` | empty configured set confirmed (`policies/protected-paths.yml:46-48`) |
| `unresolved_risks` | none, or explicit blocker; no PASS with unresolved mutation/platform evidence |

## Rollback

1. Revert T3; rerun T2's task-local verification plus G4-G7 against T2's SHA.
2. Revert T2 if consumer migration/direct assertions must also be removed; rerun the T1 fixture self-test.
3. Revert T1 only if the shared fixture and self-tests must also be removed; rerun the pre-change `git-smoke` and `bootstrap-exception` phases.
4. Do not alter or revert production `hooks/git/pre-commit`; it is outside this slice.
5. A failed hosted run leaves the spec DRAFT and the gate RED; no release/deploy state changes.

## Stop conditions

- The baseline is non-GREEN, the mutant has any FAIL other than `8-interpreter-absent-blocks`, any prerequisite/control result changes, or the unmutated negative control is accepted.
- The diagnostic-adjacent mutation target count is not exactly one.
- Any platform cannot establish the minimal fixture prerequisites.
- Any non-interpreter gate can supply the asserted rc/message.
- `test-bootstrap-exception.sh` grows or any new file crosses 800 lines.
- The diff touches `hooks/git/pre-commit`, `.github/**`, or `policies/**`.
- Hosted SHA differs from T3 SHA or any required hosted job is non-success.
