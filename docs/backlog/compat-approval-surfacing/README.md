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

## M19 residual — specified, not inferred (PO, 2026-08-04)

M19 is implemented and **held unshipped** on `fix/msys-v3307-hardening` (`5b5578f..fb4e376`). It does not justify a release on its own: the corrected text lives in the engine the consumer is *running*, so it only helps on the upgrade **after** adoption, and the reporting consumer is still on 4.6.1. Fold it into the next substantive release.

**The residual, answered:** `upgrade.sh`'s recovery block still prints `bash hooks/local/upgrade.sh   # re-run; completes remaining steps` four lines under a paragraph saying behaviour may differ. **Delete the inline comment. Do not qualify it.** The command stays — it is still the right recovery action. The comment is the defect: any qualification would restate what the paragraph above already says, and a shorter true line beats a longer hedged one. Same for the sibling wording at `:63` and `:95`.

**The assertion names are the wider problem.** Four M19 tests carry names claiming more than their predicates check (`m19-continuity-claim-removed` greps two literals and missed a third; `m19-recovery-commands-intact` claims "mechanism did not change"; `m19-header-comment-not-left-stale` claims the header "carries the same correction" when it does not). Narrow every name to what it actually asserts, or widen the predicate to the name. **This is the same defect class as everything else in this ticket** — a claim wider than the thing it describes — and it has now appeared in the surfacing feature, the release notes, the CHANGELOG, the problem-catalog entry, and the tests written to catch it.

**Recorded for whoever resumes:** the class did not appear because the work was hard. It appeared in a six-line change. Assume it is present and grep for it deliberately rather than trusting a green suite — three green gates produced three NO-SHIPs on this ticket.
