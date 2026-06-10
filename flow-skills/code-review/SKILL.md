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
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Continue with Flow-only review, but mark app-domain review criteria unknown |

## Procedure

1. Run `git diff <baseline>..HEAD --stat` to get changed files. Confirm scope matches `tasks.md`.
2. For Fusebase Apps diffs, read `docs/fusebase-cli-edition.md` and load the relevant CLI provider skills as review standards for app/runtime/domain behavior.
3. For each task T<n>: read the corresponding commit (or accumulated diff). Verify:
   - Scope matches `tasks.md` task description (no scope creep)
   - Locked decisions from `decisions.md` honored (cite letter+number)
   - No protected-path edits unless an exception exists
   - Lint/typecheck status from gate report still holds
4. Spec alignment matrix: for each AC1..ACn, confirm at least one task implements it; flag unimplemented ACs.
5. Maintainability scan:
   - Type safety (no broad casts on external JSON, no `any`)
   - **Comment policy (FR-22)** — see the dedicated dimension in step 5b
   - No TODO/FIXME/WIP markers
   - Function size and complexity reasonable

5b. Comment-policy dimension (FR-22) — enforce in BOTH directions:
   - **Flag for removal (findings):** comments that restate what the code does;
     rationale/diagnosis prose already recorded in a decision/ticket/memory (should be
     replaced by a ≤1-line pointer, not deleted outright); changelog/history narrative
     (it's in git); comment blocks that exist only because the surrounding file is
     comment-heavy ("matched density" upward).
   - **Verify retention (catch over-trimming):** a one-line **tripwire** (a non-obvious
     constraint an editing agent could violate) and a **retrieval pointer** (`(decision B2)`,
     `backlog 156`) must NOT have been stripped. Deleting a pointer orphans the external
     record (storage ≠ retrieval) — flag that as a blocker too, not just over-commenting.
   - **Carve-out:** files matching `policies/comment-policy.yml: trust_critical_globs`
     (auth/identity/session/gate, migrations, project-derived) keep multi-line tripwires —
     do not flag those. Apply the rule fully to CRUD/routine code.
   - This is a **semantic** judgment (tripwire vs restate-WHAT), not a regex check — review
     by reading, never propose a lint/regex gate for it. Reference: `docs/comment-policy.md`.
5c. Module-size dimension (FR-25):
   - **Growth check:** did this diff grow a file past the ceiling in `policies/module-size.yml`
     (default 800), or grow an already-over-ceiling file? The pre-commit ratchet blocks this
     when a baseline is committed — in warn-only installs (no baseline yet), review is the
     only line of defense: flag it as a blocker with the extraction remedy.
   - **Split-quality check (semantic):** if the diff extracted code to satisfy the ratchet,
     verify the seam is a nameable responsibility, not a mechanical `utils2.ts` / `helpers2.ts`
     dump — a mechanical split silences the gate while making navigation worse; flag it.
   - **Exemption check:** new `exempt_globs` entries or baseline edits must be operator-approved
     and justified (generated / vendored / data-as-code) — an agent-initiated baseline raise or
     exemption for ordinary source is a blocker.
   - Reference: `flow-skills/module-size-discipline/SKILL.md`.
6. Test coverage scan: new behavior has at least one test; tests align with ACs.
7. Rollback safety: each commit individually revertable; no commit straddles unrelated changes.
8. Output review summary in chat:
   - Blockers (must fix before deploy)
   - Non-blockers (improvement candidates; can be follow-up tickets)
   - Spec alignment matrix (table)
9. If invoked from operator chat: end with "Review complete. <N> blockers, <M> non-blockers. Operator decides whether to fix or proceed."

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
| Comment-policy violation (FR-22) | WHAT-restating / duplicated-rationale / changelog comments added, or "matched density" upward in a comment-heavy file | Flag as non-blocker (note the lines); not a deploy blocker unless it obscures a real defect |
| Comment over-trim (FR-22) | A load-bearing tripwire or `(decision/backlog ...)` retrieval pointer was deleted | Flag as blocker — deleting the pointer orphans the external record (storage ≠ retrieval); restore it |
| Over-ceiling growth (FR-25) | Diff grows a gated file past the ceiling / grows an over-ceiling file (check `policies/module-size.yml` + baseline) | Flag as blocker; remedy = extract along a responsibility seam or explicit operator exemption |
| Mechanical split (FR-25) | Extraction lands in a `utils2`/`helpers2`-style dump with no nameable responsibility | Flag as non-blocker (improvement) unless it was done solely to silence the gate — then blocker |
| Agent-raised baseline / exemption (FR-25) | Baseline values raised or `exempt_globs` widened without operator approval | Flag as blocker — exemptions are operator decisions |

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
- Do NOT enforce the comment policy (FR-22) by proposing a regex/lint gate — it's a semantic call; review by reading. And don't only hunt over-commenting: a deleted tripwire/pointer is the symmetric failure (over-trim) and is a blocker.
- Do NOT judge split quality (FR-25) by line counts alone — the gate already counts lines; review checks the semantic part (is the seam a nameable responsibility), which no regex can.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
