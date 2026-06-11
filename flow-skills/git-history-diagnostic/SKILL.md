---
name: git-history-diagnostic
description: Use when something worked before and is now broken (a regression), or the operator asks "when did this break", "find the commit that caused X", "it used to work", "compare to a previous version". Locates where a regression entered by comparing commits / bisecting history. Do NOT use for net-new bugs that never worked, for routine rollback (workflows/git-discipline.md), or as a substitute for reproduce-before-fix (FR-10).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.3
risk_level: low
invocation: automatic
expected_outputs:
  - the commit (or range) that introduced the regression, with evidence
  - a diff explaining the causing change
  - handoff to zoom-out / validation-and-qa for the actual fix
related_workflows:
  - git-discipline.md
  - verification-gate.md
hook_dependencies:
  - none
---

# Git History Diagnostic

> **Style:** Mode-B-lite.

## Purpose

Regression archaeology: when behavior that previously worked is now broken, locate **where** it broke by comparing commits / bisecting history — so the fix targets the actual causing change, not a guess. Read-only diagnosis; the fix is handed to `zoom-out` + `validation-and-qa`.

## When to invoke

- "It used to work" / "this is a regression" / "when did X break".
- A test that passed at an earlier commit now fails.
- Operator points to a known-good prior state and a now-broken current state.

## Do not invoke when

- The behavior never worked (net-new bug → normal debugging).
- Routine rollback of a known commit → `workflows/git-discipline.md`.
- Reproduction isn't established yet → run FR-10 reproduce-before-fix first (you need a reliable signal to bisect against).

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| A reliable broken/works signal (test or repro) | test suite / repro steps | establish via FR-10 first; bisecting needs a yes/no test |
| Last-known-good reference (commit/tag/date) | operator / git history | search backward from HEAD for the transition |
| Current broken state | HEAD | — |

## Procedure

1. **Pin the signal.** Define a deterministic check that returns good/bad (a test command, a repro). Bisection is only as reliable as this signal.
2. **Bracket.** Identify a known-good commit (or tag/date) and a known-bad commit (usually HEAD). Verify the signal at both ends.
3. **Bisect.** Narrow the range (`git bisect`, or manual binary search over the range) until the first bad commit is found.
4. **Explain.** Show that commit's diff; identify the specific change that introduced the regression (file:line).
5. **Hand off.** Pass the finding to `zoom-out` (root-cause vs revert decision) and `validation-and-qa` for the fix + regression test. Do not fix here.
6. **Capture.** If the regression class is recurring, note it in `docs/problem-catalog/`.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Regression-origin finding | chat (Mode A) + optional ticket note | Mode A / Mode-B-lite |
| Causing-commit diff excerpt | chat / handoff | Mode A |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| No deterministic signal | bisect gives inconsistent results | go back to FR-10; build a stable repro/test |
| Regression spans multiple commits | each end behaves inconsistently | report the range; treat as design issue via zoom-out |
| "Good" reference also broken | step 2 verify fails | search further back for the true good state |

## Escalation path

- Cause spans many commits / cross-cutting → `workflows/architect-escalation.md`.
- Fix design → `skills/zoom-out/SKILL.md` then `validation-and-qa`.
- Ambiguous good-reference → ask operator in chat (FR-19).

## Anti-patterns

- Do not fix in this skill (diagnosis only).
- Do not bisect without a deterministic signal (false culprit).
- Do not auto-revert the causing commit — zoom out first (it may be load-bearing).

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
