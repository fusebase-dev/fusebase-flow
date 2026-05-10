---
name: code-review
description: Use before commit, deploy, or PR merge, or when operator asks "review this diff" / "is this safe?"; reviews diff vs spec, decisions, maintainability, scope, tests, rollback. Do NOT write or fix code — review only.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: low
invocation: manual
expected_outputs:
  - review summary (chat or docs/verification/<slug>-review.md)
  - blocker list
  - non-blocker improvement list
related_workflows:
  - verification-gate.md
hook_dependencies:
  - none
---

# Code Review

## Purpose

Independent review of a diff against the spec contract, locked decisions, and FLOW_RULES — before commit, deploy, or merge. Distinguishes blockers (must fix) from non-blockers (should fix).

## When to invoke

- Operator says "review this" / "is this safe to ship?" / "look at the diff"
- AI Developer-session gate report has been pasted and `validation-and-qa` ran clean — code-review is the next step before deploy
- About to merge a PR (team mode)
- Major refactor in flight and operator wants midpoint review

## Do not invoke when

- No diff exists yet (review needs concrete code)
- Spec is still DRAFT — review against an incomplete contract is noise
- Operator wants the code fixed — review surfaces issues; fixes go through implementation

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Diff | `git diff <baseline>..HEAD` or PR diff URL | Stop; ask which diff to review |
| Spec | `docs/specs/<slug>/spec.md` | Stop; review without spec is style-only and limited |
| Decisions | `docs/specs/<slug>/decisions.md` | Stop; cannot verify decision adherence |
| Tasks | `docs/specs/<slug>/tasks.md` | Stop; cannot verify scope adherence |

## Procedure

1. Run `git diff <baseline>..HEAD --stat` to get changed files. Confirm scope matches `tasks.md`.
2. For each task T<n>: read the corresponding commit (or accumulated diff). Verify:
   - Scope matches `tasks.md` task description (no scope creep)
   - Locked decisions from `decisions.md` honored (cite letter+number)
   - No protected-path edits unless an exception exists
   - Lint/typecheck status from gate report still holds
3. Spec alignment matrix: for each AC1..ACn, confirm at least one task implements it; flag unimplemented ACs.
4. Maintainability scan:
   - Type safety (no broad casts on external JSON, no `any`)
   - Comments only where WHY is non-obvious
   - No TODO/FIXME/WIP markers
   - Function size and complexity reasonable
5. Test coverage scan: new behavior has at least one test; tests align with ACs.
6. Rollback safety: each commit individually revertable; no commit straddles unrelated changes.
7. Output review summary in chat:
   - Blockers (must fix before deploy)
   - Non-blockers (improvement candidates; can be follow-up tickets)
   - Spec alignment matrix (table)
8. If invoked from operator chat: end with "Review complete. <N> blockers, <M> non-blockers. Operator decides whether to fix or proceed."

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Review summary | chat output | Mode A |
| Optional persistent record | `docs/verification/<slug>-review.md` | Mode B (full) |
| Spec alignment matrix | embedded in review summary | Mode B (full, table) |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Diff straddles multiple unrelated changes | Commits cover code outside current ticket scope | Flag as blocker; recommend split into separate tickets |
| Locked decision contradicted by code | Decision says X, code does Y | Flag as blocker; redirect via decisions.md update OR fix code |
| AC unimplemented | Spec AC<n> has no task touching it | Flag as blocker; either add task or remove AC explicitly |
| Protected path edited without exception | `git diff` against `protected-paths.yml` non-empty | Flag as blocker per FR-07; require approval artifact OR revert |
| Type safety regression | New `any` / broad casts on external JSON introduced | Flag as blocker if production-path; non-blocker if test fixture |

## Escalation path

- Architectural concern beyond review scope (e.g., decision should have been redirected) → recommend re-opening `decisions.md` lock
- Security-relevant finding → invoke `security-permissions-review` skill
- Performance-relevant finding → file follow-up backlog ticket; not in v0.1 review scope

## Anti-patterns

- Do NOT fix code yourself; surface findings, operator + implementer fix
- Do NOT lock-or-redirect decisions; that's the operator's call (FR-11)
- Do NOT block on stylistic preferences absent a lint rule; flag as non-blocker
- Do NOT pass without checking protected paths (FR-07)
- Do NOT pass without verifying gate report alignment

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
