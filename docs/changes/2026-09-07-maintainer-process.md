# Maintainer process simplification

**Authorization:** operator approved the process-review recommendation on 2026-09-07: “proceed with your recomerndations”. **Scope:** this repository's maintenance and testing; preserve consumer runtime contracts and publication safety. **Baseline:** `cd2f90f`. **Status:** local implementation complete; hosted execution pending push.

| Task | Outcome / files | Acceptance |
|---|---|---|
| T62 | Project-specific process: AGENTS.md, docs/maintainer-execution.md, this note | One outcome record; focused proof; no redundant validator ritual; independent review for consequential boundaries; consumer workflow unchanged |
| T63 | Test consolidation: hooks/tests/run-tests.sh, test-release-evidence-authority.sh, test-validation-instructions.sh, test-ff-only.sh and focused helpers; docs/maintainer-testing.md; manifests | Required executable safety checks retained; editorial/profiling diagnostics selectable; release graph checked structurally; validator behavior exercised; selection rejects unknown/empty groups |
| T64 | Early feedback: maintainer CI workflow, workflow graph tests, PUBLISHING.md | Upstream-only push/PR feedback on both platforms; no consumer automatic heavy CI; release verification remains exact-SHA and fail-closed; dispatch candidate verification before tagging |

**Decision:** use existing runner selection and reusable release verification rather than a new scheduler/cache/receipt system. Preserve existing tag-triggered publication and its checks; candidate verification is available before tagging, and release CI rechecks the tagged SHA. A one-run candidate-to-publication redesign would add new publication authority; retain the existing publication path while removing late platform surprises.

**Verification:** focused changed tests, YAML/Python/shell syntax, diff hygiene, manifest freshness, normal commit controls, independent review of test exclusions and CI boundary. Hosted CI execution and publication are separate from local implementation evidence. No blanket full-suite replay for this ticket.

**Safety:** no auth/secrets/migration/user-data changes; CI permission scope and release binding require review. Worker-undisturbed list empty; secret/protected-path rules stay active. T61 `7a3bd74` remains on its separate worktree; overlap is checked without incorporating unrelated changes. Revert each task commit normally to roll back; never move `v4.15.0`.

## Results

| Task / check | Result |
|---|---|
| T62 | `8a3247a`; normal pre-commit passed; project-specific process adopted |
| T63 commit | `702a86f`; normal pre-commit passed; 109 insertions / 412 deletions across eight files |
| T63 validator behavior | `bash hooks/tests/test-validation-instructions.sh`: 5/5; actual helper execution/order and lint/typecheck failure propagation |
| T63 release graph | `python hooks/tests/lib/workflow_graph_check.py --root .`: 36/36 including negative mutations |
| T63 selection | `bash hooks/tests/test-ff-only.sh --only selection`: 27/27 under 180s watchdog; `state/audit/T63-selection-focused.log` |
| T63 registry | 75 registered, 68 required, 7 explicit diagnostics; `state/audit/T63-required-selection.log`, `T63-diagnostic-selection.log` |
| T63 review | Independent Architect REVIEW_CLEAR after correcting required-tier fixture; `state/audit/T63-independent-review.md` |
| T63 earlier failure | Broad selector phase interrupted after stale START assertion; `state/audit/T63-selector-tests.log`; changed to isolated synthetic dispatch fixtures, no unchanged broad rerun. Known watchdog processes exited; injected root fixture absent. |
| T64 workflow graph | 52/52 PASS including eight new contract checks and eight unsafe-mutation controls; Python compilation passed |
| T64 review | Independent Architect REVIEW_CLEAR on final workflow, checker integration and publication instructions; `state/audit/T64-independent-review.md` |
| T64 integrity | Hook manifest 212/212 MATCH; managed-content manifest 376 assets MATCH; diff hygiene passed |
| T64 preflight | 0 errors / 0 warnings under 120s watchdog; `state/audit/T64-preflight.log` |
| T64 completion | Recorded in this task's commit, subject to normal Git controls; hosted execution and publication not performed |
| T64 first commit attempt | FR-07 correctly blocked absent workflow approval artifact; recorded the operator's existing approval with the standard digest-bound writer for the two staged CI paths, then retried normally |

**Release state:** these are local maintainer improvements. The v4.15.0 release run failed before publication; T61's separate repair commit is not merged by this work. Preserve that worktree and the existing tag. Next release work must resolve the portability failure and pass the full candidate workflow before an authorized new tag; do not interpret the focused results above as that evidence.

No standalone lint/typecheck command is configured for this framework; Python/shell/YAML checks cover the touched languages. Normal Git controls remain active. Comment-policy review: applied (FR-22).
