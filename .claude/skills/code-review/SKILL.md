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
- Clarifications are unresolved or scope is not yet locked — review against an incomplete contract is noise
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

1. **Trust the recorded gate verdict (review boundary).** When `validation-and-qa` has recorded a gate verdict ("Gate verified. Phase advances to Deploy."), trust it for the deterministic/cross-artifact fields — AC↔task map, decisions-cited-in-tasks, lint/typecheck status, TODO/FIXME/WIP scan, protected-path diff. Do not re-verify them; carry the gate's AC↔task verdict into the review's spec-alignment matrix by citation. If no gate verdict exists, route to `validation-and-qa` first — do not absorb its checks here.
2. Run `git diff <baseline>..HEAD --stat` to get changed files. For Fusebase Apps diffs, read `docs/fusebase-cli-edition.md` and load the relevant CLI provider skills as review standards for app/runtime/domain behavior.
3. Semantic review per task T<n>: read the corresponding commit (or accumulated diff). Judge:
   - Scope-creep: does the change match the *intent* of the `tasks.md` description, not just touch the listed files?
   - Decision adherence in meaning: the gate checks decisions are *cited*; review checks the code *does what the locked decision means* (cite letter+number on divergence)
   - Quality-pattern ACs (QP-xx, `flow-skills/app-quality-patterns`): the cited pattern's Requirement is actually met by the implementation (semantic, by reading — e.g., is the filter state really in the URL, does the delete really handle children)
4. Maintainability scan:
   - Type safety (no broad casts on external JSON, no `any`)
   - **Comment policy (FR-22)** — see the dedicated dimension in step 4b
   - Function size and complexity reasonable

4b. Comment-policy dimension (FR-22) — enforce in BOTH directions:
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
4c. Module-size dimension (FR-25):
   - **Growth check:** did this diff grow a file past the ceiling in `policies/module-size.yml`
     (default 800), or grow an already-over-ceiling file? The pre-commit ratchet blocks this
     when a baseline is committed — in warn-only installs (no baseline yet), review is the
     only line of defense: flag it as a blocker with the extraction remedy.
   - **Split-quality check (semantic):** if the diff extracted code to satisfy the ratchet,
     verify the seam is a nameable responsibility. Observable blocker criterion: the extraction
     lands in a file whose NAME does not state a responsibility (`utils2.*`, `helpers2.*`,
     `misc.*`, `extra.*`, `more.*`-style) — no intent inference needed. Named seams are judged
     by reading; a poor-but-named seam is a non-blocker improvement.
   - **Exemption check:** new `exempt_globs` entries or baseline edits must be operator-approved
     and justified (generated / vendored / data-as-code) — an agent-initiated baseline raise or
     exemption for ordinary source is a blocker.
   - Reference: `flow-skills/module-size-discipline/SKILL.md`.
4d. Correctness / defect-hunt dimension — actively hunt a bug in the CHANGED logic before
   certifying "safe"; scope is the diff, not the whole codebase. Per changed function/branch:
   - **Edge cases:** empty/zero/one/max inputs, boundary indices, off-by-one in loops/slices,
     empty collections, first/last element, unicode/whitespace in string handling.
   - **Error & failure paths:** a call inside the change throws / returns error / times out —
     is the failure surfaced, swallowed, or half-applied (partial write, no cleanup)?
   - **Concurrency / races:** shared state without ordering guarantees, check-then-act (TOCTOU)
     windows, interleaving async handlers, retries that double-apply.
   - **Input validation:** external input (API params, file content, env, user text) reaching
     the changed logic unvalidated; unchecked coercion of external JSON.
   - **State & lifecycle:** resources closed on ALL paths incl. the error path; re-run idempotency.
   Verdict discipline: "no defect found" is claimable only after the hunt ran — name the top-2
   suspect paths examined and why they hold (1 line each in the review summary). A found defect
   is a blocker when reachable on a production path; non-blocker in test/dev scaffolding.
5. Test coverage scan (the deterministic AC-coverage map is the gate's; this is the semantic
   half). Blocker criteria — flag any of:
   - **No test at all** for a changed production behavior that has a testable seam.
   - **Meaningless assertion:** only asserts "no exception" / truthy / blind snapshot-update —
     observed output never compared to expected.
   - **Tests the mock:** assertions verify mock wiring, not the changed logic's outcome.
   - **Happy-path only** where the diff itself added error/edge branches (the new branch is
     dead code to the suite).
   Each is a blocker when the changed behavior is production-path; non-blocker for dev
   tooling/scaffolding. Remedy: name the missing case — do NOT write the test yourself.
6. Rollback safety: each commit individually revertable; no commit straddles unrelated changes.
7. Output review summary in chat:
   - Blockers (must fix before deploy)
   - Non-blockers (improvement candidates; can be follow-up tickets)
   - Spec alignment matrix (table; deterministic AC↔task statuses carried from the gate verdict by citation)
8. If invoked from operator chat: end with "Review complete. <N> blockers, <M> non-blockers. Operator decides whether to fix or proceed." Proceeding to deploy past an open blocker is not a chat-side call: it requires the per-blocker recorded waiver in the deploy handoff (`release-deploy-reporting` § When to invoke) — step-4d/step-5 safety blockers especially.

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
| AC unimplemented | Surfaced while reading the diff (the gate owns the deterministic AC↔task scan) | Flag as blocker; either add task or remove AC explicitly |
| Protected path edited without exception | Surfaced while reading the diff (the gate owns the deterministic FR-07 scan) | Flag as blocker per FR-07; require approval artifact OR revert |
| Type safety regression | New `any` / broad casts on external JSON introduced | Flag as blocker if production-path; non-blocker if test fixture |
| Comment-policy violation (FR-22) | WHAT-restating / duplicated-rationale / changelog comments added, or "matched density" upward in a comment-heavy file | Flag as non-blocker (note the lines); not a deploy blocker unless it obscures a real defect |
| Comment over-trim (FR-22) | A load-bearing tripwire or `(decision/backlog ...)` retrieval pointer was deleted | Flag as blocker — deleting the pointer orphans the external record (storage ≠ retrieval); restore it |
| Over-ceiling growth (FR-25) | Diff grows a gated file past the ceiling / grows an over-ceiling file (check `policies/module-size.yml` + baseline) | Flag as blocker; remedy = extract along a responsibility seam or explicit operator exemption |
| Mechanical split (FR-25) | Extraction lands in a file whose name states no responsibility (`utils2`/`helpers2`/`misc`/`extra`-style) | Flag as blocker (observable criterion — no intent inference); a named-but-debatable seam is a non-blocker improvement |
| Agent-raised baseline / exemption (FR-25) | Baseline values raised or `exempt_globs` widened without operator approval | Flag as blocker — exemptions are operator decisions |
| Correctness defect in changed logic | Defect-hunt (step 4d) finds a reachable edge-case / error-path / race / validation bug in the diff | Flag as blocker with a concrete failing-input → wrong-outcome scenario; production-path defects block deploy, scaffolding-only defects are non-blockers |
| Missing or meaningless tests (step 5) | Changed production behavior has no test, assertion-free tests, mock-only assertions, or happy-path-only coverage of new error/edge branches | Flag as blocker (production-path) and name the missing case; test/dev scaffolding gaps are non-blockers |

## Escalation path

- Architectural concern beyond review scope (e.g., decision should have been redirected) → recommend re-opening `decisions.md` lock
- Security-relevant finding → invoke `security-permissions-review` skill
- Performance-relevant finding → file follow-up backlog ticket; not in v0.1 review scope

## Anti-patterns

- Do NOT fix code yourself; surface findings, operator + implementer fix
- Do NOT lock-or-redirect decisions; that's the operator's call (FR-11)
- Do NOT block on stylistic preferences absent a lint rule; flag as non-blocker
- Do NOT re-verify deterministic gate fields (AC↔task map, decisions-cited, lint/typecheck, TODO scan, protected paths) when a recorded gate verdict exists — trust it; absent a verdict, route to `validation-and-qa` first
- Do NOT enforce the comment policy (FR-22) by proposing a regex/lint gate — it's a semantic call; review by reading. And don't only hunt over-commenting: a deleted tripwire/pointer is the symmetric failure (over-trim) and is a blocker.
- Do NOT judge split quality (FR-25) by line counts alone — the gate already counts lines; review checks the semantic part (is the seam a nameable responsibility), which no regex can.
- Do NOT certify "safe to ship" from scope/decision/style/size checks alone — a review without the step-4d defect hunt never looked for a bug, and "is this safe?" was the question. An empty blocker list must carry the hunt evidence (top-2 suspect paths examined).

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
