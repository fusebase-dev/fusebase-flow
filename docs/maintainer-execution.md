# How to execute work on THIS repo (maintainer-side)

**Not part of Fusebase Flow.** Flow's rules for consumers are `FLOW_RULES.md` / `AGENTS.md`. This file is how the maintaining agent runs tickets *in this repository*. It is **not copied into consumers by default** — top-level `docs/*.md` are framework docs, staged only with `--with-framework-docs` and namespaced under `docs/_fusebase-flow/`.

Read this at session start alongside `AGENTS.md`.

## Why this exists

Measured on the v4.7.0/v4.7.1 cycle (adversarial retrospective, Codex xhigh, 2026-08-05):

| | |
|---|---|
| Source ticket elapsed | **117h12m** for ~42h active work |
| Gaps waiting on a PO ruling | **89h06m — 76% of elapsed** |
| Longest single pause | **52h32m** (M14→M16) — longer than the realistic target for the whole ticket |
| Adversarial-review *thinking* | **~2h20m** across 14 rounds |

The cost was **not** gates and **not** reviews. It was work sitting finished, waiting to be ruled on. Full evidence: `docs/problem-catalog/po-latency-dominates-elapsed-time/problem.md`.

## The seven rules

| # | Rule | What it fixes |
|---|---|---|
| 1 | **Rule in batch.** When an agent stops on a contract question, answer it *and* pre-authorize the next two likely branches | One ruling per cycle is the 76% |
| 2 | **Contract matrix before locking**, 45-min cap. Any decision saying "behave like X" enumerates every X first | "Judge as the gate judges" had three different answers (`command_policy` supplies `repo_id`+`command_digest`; `path_policy` supplies neither; health deferrals aren't in `require_approval`). Three rounds found that one at a time |
| 3 | **Review before the expensive gate**, not after | Gate → review → invalidate both runs the costly step before the informative one |
| 4 | **Tier the gate.** Scoped phases (~8 min) for intermediate rounds; one full unscoped two-platform run before release. Scoped runs are never release proof | A comment deletion took the same 45-min gate as a 400-line rewrite |
| 5 | **Lightweight-lane text-only residuals** (comments, assertion renames) | Full-lane ceremony on wording cost multiple cycles |
| 6 | **Build only what was asked** | A consumer wrote *"this is not a request to change your default"*. It was read as a feature request: 3 rounds, 3 green gates, 3 NO-SHIPs, parked unshipped |
| 7 | **Thin handoffs.** Don't restate rules the sub-agent already reads | Docs + generated artifacts were **38.5% of churn — more than production code** |

## Hard stop

A review round whose findings sit **inside the previous round's fix** means the contract is undecided. Stop implementing and decide it. See `docs/problem-catalog/undecided-contract-drives-repeat-defects/problem.md`. This fired three times before it was honoured; overriding it on a "the list is converging" argument was wrong both times it was tried.

## What NOT to cut

**The adversarial reviews.** They found 100% of real defects on that cycle; three consecutive green suites found zero. Two self-serving claims were refuted by the retrospective: reviews *did* already run before code (`a44962c`, 17 findings applied), and agent quality *was* a contributing factor — the first implementation review found a manifest fail-open, symlink escape, non-atomic repair, mutable-source trust and widened destructive authority.

## Operational notes for this host

- **Two-platform gating is mandatory before any release claim.** A green MSYS run alone has been wrong twice. Docker recipe: `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md`.
- **Before diagnosing a timing FAIL, run `ps -W | grep run-tests`** — a competing suite on this machine has caused one, and `ps -W` alone can miss it (check Win32 `CommandLine`).
- **Several gate phases sit within 0.5% of their walls** — `docs/backlog/gate-bounds-lack-headroom/`. Treat an `exit 124` with zero failed assertions as a bound problem, not a code problem, and say so explicitly rather than recording a gate as clean.
- **Write long-running agent output to `c:/tmp/`**, not the session scratchpad — another Claude Code process can wipe it mid-run.
