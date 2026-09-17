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
   - Scope and simplicity: the change matches the *intent* of the `tasks.md` description, not just the listed files, and meets `flow-skills/zoom-out/references/karpathy-guidelines.md` §§2–3 (read it unless its exact body is already in context)
   - Decision adherence in meaning: the gate checks decisions are *cited*; review checks the code *does what the locked decision means* (cite letter+number on divergence)
   - Quality-pattern ACs (QP-xx, `flow-skills/app-quality-patterns`): the cited pattern's Requirement is actually met by the implementation (semantic, by reading — e.g., is the filter state really in the URL, does the delete really handle children)
4. Maintainability scan:
   - Type safety (no broad casts on external JSON, no `any`)
   - **Comment policy (FR-22)** — see the dedicated dimension in step 4b

4b. Comment-policy dimension (FR-22) — enforce in BOTH directions:
   - **Scope:** comments this diff introduced or necessarily changed; untouched pre-existing
     comments are not findings (`flow-skills/zoom-out/references/karpathy-guidelines.md` §3).
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

## Review depth and severity

**Severity.** BLOCKER = a mandatory-stop failure. HIGH = a serious, reachable correctness or security risk. MEDIUM = a bounded functional defect. LOW = a non-blocking improvement. These GRADE findings; they never downgrade a blocker § Failure cases already names, and a known correctness/safety blocker does not become acceptable because a review already ran once.

**Depth follows the change, not habit.**

| Change | Review |
|---|---|
| **Security-relevant** — code that EXECUTES on an auth, session, token, permission or CSRF path (docs, copy, tests or comments that merely mention those topics are not) | independent adversarial review of code and tests (`adversarial_review` tier — `task-delegation` § Model routing) |
| **Cross-cutting** — three or more slices or a shared module | independent adversarial review |
| **HIGH risk** — set per slice in the plan and confirmed at plan review | independent adversarial review |
| Ordinary change | focused review of the diff |
| Prose and doc claims | not per change — one consolidated claim-vs-evidence pass at final acceptance |

These are review-DEPTH triggers only. They never narrow the FR-21 Full-lane triggers or `security-permissions-review`'s scope.

**Rereview by severity.** BLOCKER/HIGH correction → rereview the affected boundary. MEDIUM → focused check of that diff. LOW → the implementer's evidence, unless new evidence changes the classification. A reviewer does not reopen a fixed LOW on the same finding and the same evidence; a newly demonstrated defect is a NEW finding, not a reopened one.

**Round bound.** Round 1 is the initial review, round 2 the correction review — default maximum two per change.

**Round accounting is durable and checked BEFORE dispatch (binding).** A bound that exists only in chat cannot be checked before the next dispatch — it is unenforceable the moment the chat rolls over or a successor takes the work (`docs/problem-catalog/adversarial-review-convergence/problem.md`). So:

- The count lives in an artifact this work ALREADY owns — `docs/verification/<slug>-review.md` when a review record is persisted, otherwise the run-ledger `docs/tmp/handoff.md` § Constraints and Guardrails. **Never a new file** (FR-23).
- One compact line, three fields: change identity (ticket/task + reviewed SHA) · limit · rounds dispatched. Example: `T42 @ 3b1bfaa — review rounds: 1 of 2`.
- **Read it before launching any review round, and update it as part of that dispatch.** No record found for this change → this is round 1; write the line first.
- A successor agent INHERITS the count; starting a fresh session, a fresh reviewer, or a fresh chat does not reset it.
- Only **explicit operator authorization** raises the limit. Not the actor that declared it, not the actor that hit it, and not an agent that merely inherited it — an agent never extends a bound it is subject to.
- On exhaustion, unresolved findings stay blocked or deferred WITH their evidence, never implicitly accepted. A BLOCKER is still a BLOCKER after round 2; exhaustion returns the work for a budget or scope decision, it does not make anything shippable.

**Persistent LOW work.** Optional and scoped. A LOW cleanup may be one commit only when it is one independently reversible outcome; otherwise leave it parked. Persistent LOW findings go to `docs/backlog/<slug>-low/README.md`, indexed once in `docs/backlog/index.md` — an existing matching ticket wins over a new aggregate.

**Persisted review record.** `docs/verification/<slug>-review.md` SUPERSEDES the prior verdict in place (FR-18; git owns the revisions) and names the round and the reviewed SHA. Open it with a header of at most ten lines: severity counts, one line per BLOCKER and HIGH, verdict. The header is a routing aid, not the authority — read the finding body before deciding anything the header does not settle (`token-economy`).

## Worked example

Diff for T42 adds a retry cap to `sync.ts`; the gate verdict is recorded.
- Step 1: cite the gate's AC↔task map; no re-verification.
- Step 3: an unrequested configurable backoff class and a reformatted untouched function fail §§2–3 → findings naming the lines that don't trace to T42.
- Step 4b: a new WHAT-restating comment on the edited line → non-blocker; comment-heavy untouched blocks elsewhere → not a finding.
- Step 4d: cap = 0 and retry after a partial write examined; both hold.
- Step 7: blockers / non-blockers classified per § Failure cases, plus the alignment matrix.

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Review summary | chat output | Mode A |
| Persistent record — optional, EXCEPT it must carry the round-accounting line whenever it exists (§ Round bound); when it does not exist that line lives in the run-ledger | `docs/verification/<slug>-review.md` | Mode B (full) |
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
