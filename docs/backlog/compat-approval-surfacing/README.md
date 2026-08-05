# compat-approval-surfacing

**Status:** parked — needs a designed contract before any further implementation
**Filed:** 2026-08-04, after three implementation rounds failed three adversarial reviews
**Source:** consumer escalation `docs/tmp/handoff/2026-08-04-paperclip-escalation.md` § 1
**Prior decisions:** M18, M20, M21 — all locked, all *almost* right, each half-specification produced the next round's defect

> **Where to find them.** Only **M18** and **M19** are on `main` (`docs/specs/upgrade-source-integrity-and-observability/decisions.md`, locked at `5b5578f`). **M20 and M21 were withdrawn with the feature** and are NOT in that file — their full text, the three implementation rounds, and all three review reports live on the parked ref:
>
> ```
> git show parked-v471-surfacing:docs/specs/upgrade-source-integrity-and-observability/decisions.md
> git log --oneline 5b5578f..parked-v471-surfacing
> ```
>
> (branch `parked/compat-approval-surfacing-v471`, tag `parked-v471-surfacing`, tip `8417b8a`). This note exists because the sections below cite M20/M21 by name; without it those are references to decisions this repo does not contain.

## The need is real

A consumer measured K7's compat default as a **live open deploy gate**: 98 accumulated artifacts, several expiry-less, one satisfying `production_deploy` permanently — reached by the documented upgrade path in one command with no warning. `--inventory` exists but requires knowing to run it. Discoverable is not surfaced.

## Why three rounds failed

| Round | The fix | What it broke |
|---|---|---|
| 1 | surface compat-accepted artifacts | judged without `repo_id`, so the repo-bound expiry-less artifact the gate *accepts* was reported `BINDING_MISMATCH` and silently dropped — the tool missed the exact thing it exists to catch |
| 2 | judge with `repo_id` (M21) | fixed `command_policy`, broke `path_policy`: `path_policy.py:268` supplies **neither** `repo_id` nor `command_digest`, so repo-bound artifacts it *rejects* were reported active. Same class, opposite direction |
| 3 | filter to `require_approval` actions (B2) | `health_check_deferral` is a real carrier absent from `require_approval`, so it was dropped from reporting — B1's defect reintroduced through B2's fix |

## The design requirement nobody specified

**"Judge as the gate judges" has no single answer, because there is no single gate.** Each carrier supplies different inputs:

| Carrier | `repo_id` | `command_digest` | Evidence |
|---|---|---|---|
| `command_policy` | yes | yes | `command_policy.py:92` |
| `path_policy` | no | no | `path_policy.py:268` |
| health deferrals | n/a — not in `require_approval` at all | | |

A correct reporter needs a **carrier table** derived from the carriers themselves — which actions exist, which gate evaluates each, and which binding inputs that gate supplies — not from `require_approval`, and not one uniform rule. Build that table first; the reporting is easy afterwards.

## Also unresolved when this resumes

- **Character handling must be validate-and-reject, never repair.** Deleting disallowed characters *manufactures* identifiers: `claude\n_md_overlay` → `claude_md_overlay`, a canonical `check_id`. Full-match the charset and reject; never repair a string into validity.
- **Traversal must be NUL-delimited** (`find -print0`) — a newline in a *filename* splits the protocol before any sanitization runs. `--inventory` prints raw basenames too.
- **A separate, pre-existing defect found in passing:** an artifact can grant itself a health-check deferral for a canonical `check_id` via a newline in `deferred_checks`, moving the verdict to `EXCEPTION_IN_EFFECT`/exit 3. Predates this work (`382a05e`). It deserves its own ticket and its own fix — it is not blocked on the surfacing design.

## Correction to M20(a) — the claim is too wide as written

M20 says "a body with no `action` is not compat." Strictly false: such an artifact **is** compat when it also lacks `expires_at` (via `MISSING_EXPIRY`). The true claim is **"missing `action` alone is not a compat criterion."** Fix the wording wherever it is mirrored before any of this ships.

## What was NOT wrong

The consumer's measurement, K7's compat default (they explicitly do not ask us to change it), and M19's recovery-hint fix — that one is independent, small and correct, and can ship separately.

---

## M19 residual — CLOSED, shipped in v4.7.1 (2026-08-05)

**Status: done.** Split out of this ticket and released on its own as `m19-recovery-hint-honesty` — deploy hash `3ae1feb`, <https://github.com/fusebase-dev/fusebase-flow/releases/tag/v4.7.1>. **The surfacing feature below remains parked and unstarted**; only this residual shipped.

| Specified | Shipped |
|---|---|
| Delete the inline `# re-run; completes remaining steps`, do not qualify it; command stays; same for the `:63` sibling | `d9856fc` — both deleted, nothing hedged |
| Narrow four assertion names to their predicates, or widen the predicate to the name | `9bfba78` — #2 predicate widened to one shared `CONTINUITY_RE` family (now also guards the header, so the two carriers cannot drift apart); #3/#4/#6 renamed to what they actually check |
| Prove the continuity assertion RED against `02d14f7` | Old test 6/6 green on that tree; widened test **4/6**, failing on the exact missed literal `completes remaining steps` and the header's `also finishes the remaining steps` |
| Correct the release notes' overstatement and the wrong control | `c6ebf68` — per-assertion RED/PASS table; control corrected to **assertion 4** (verified against `5b5578f`: 5 RED, #4 the only PASS) |

**The prediction in the old note held.** Review found the same class *inside the fix for it*: three findings, all class (a) text-only — #2/#6 named the general absence of continuity claims while testing one finite regex family, and #4 claimed all recovery commands present while never anchoring `fusebase-flow-health-check.sh`. Fixed in `961d9f8`; #4 was renamed rather than strengthened, since strengthening the predicate would have been a logic change.

**The durable lesson, unchanged:** the class did not appear because the work was hard — it appeared in a six-line change, then again in the correction to it. Assume it is present and grep for it deliberately rather than trusting a green suite. A test name is a claim, and an unexamined one is the easiest place for a wider-than-true claim to hide.
