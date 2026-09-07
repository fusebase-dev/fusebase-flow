# Maintainer process simplification

**Authorization:** operator approved the process-review recommendation on 2026-09-07: “proceed with your recomerndations”. **Scope:** this repository's maintenance and testing; preserve consumer runtime contracts and publication safety. **Baseline:** `cd2f90f`. **Status:** implementation in progress.

| Task | Outcome / files | Acceptance |
|---|---|---|
| T62 | Project-specific process: AGENTS.md, docs/maintainer-execution.md, this note | One outcome record; focused proof; no redundant validator ritual; independent review for consequential boundaries; consumer workflow unchanged |
| T63 | Test consolidation: hooks/tests/run-tests.sh, test-release-evidence-authority.sh, test-validation-instructions.sh, test-ff-only.sh and focused helpers; docs/maintainer-testing.md; manifests | Required executable safety checks retained; editorial/profiling diagnostics selectable; release graph checked structurally; validator behavior exercised; selection rejects unknown/empty groups |
| T64 | Early feedback: maintainer CI workflow, workflow graph tests, PUBLISHING.md | Upstream-only push/PR feedback on both platforms; no consumer automatic heavy CI; release verification remains exact-SHA and fail-closed; dispatch candidate verification before tagging |

**Decision:** use existing runner selection and reusable release verification rather than a new scheduler/cache/receipt system. Preserve existing tag-triggered publication and its checks; candidate verification is available before tagging, and release CI rechecks the tagged SHA. A one-run candidate-to-publication redesign would add new publication authority; retain the existing publication path while removing late platform surprises.

**Verification:** focused changed tests, YAML/Python/shell syntax, diff hygiene, manifest freshness, normal commit controls, independent review of test exclusions and CI boundary. Hosted CI execution and publication are separate from local implementation evidence. No blanket full-suite replay for this ticket.

**Safety:** no auth/secrets/migration/user-data changes; CI permission scope and release binding require review. Worker-undisturbed list empty; secret/protected-path rules stay active. T61 `7a3bd74` remains on its separate worktree; overlap is checked without incorporating unrelated changes. Revert each task commit normally to roll back; never move `v4.15.0`.

## Results

Pending implementation verification. Commands and review result will replace this line; logs remain in `state/audit/`.
