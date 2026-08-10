# Plan — close the 4 BLOCKERs, split CI by platform, and find the remaining test time

**Status:** DRAFT, pending adversarial review. **Base:** `3089f09`.
**Source of findings:** `docs/specs/backlog-triage-execution/final-architecture-review.md`
(`SOUND-WITH-CORRECTIONS`, 4 BLOCKERs + 8 MAJORs).

## 1. The four BLOCKERs

| ID | Fix | Why this shape |
|---|---|---|
| **B2** — force-moved tag publishes unverified code | Before creating the Release, resolve the tag's target SHA and compare it to the SHA the `verify` workflow passed on. Mismatch ⇒ refuse, loudly. | `gh release create --verify-tag` matches on tag NAME only. This is the exact bypass the whole change exists to close |
| **B4** — 3 of 4 discriminators can `skip()` while the phase exits 0 | A skipped **discriminator** is a non-pass and must affect exit status. Controls may still skip. Report skips separately and never as passes. | Precedent already exists: `signal-reap` prints "skips and inconclusives are NOT passes" — the counter just is not wired to the exit |
| **B1** — 60-min wall vs ~88m35s estimate | **Per-platform tier.** Windows runs only phases that genuinely exercise platform behaviour; Linux keeps the full set. | 45 phases exist; a name-based split suggests ~12 are platform-specific. Running the other 33 twice pays MSYS spawn cost to re-prove what Linux proved |
| **B3** — predicate 32 checks mirror parity, never production recovery/write | Extend it to exercise production **recovery/write** mode over the full corpus, not just compare an already-mirrored tree. | Otherwise the 4-skill fixture can miss a production-only regression — the fixture-substitution class under review |

### B1 is the one that can go wrong

**The split must be derived from evidence, not from my grep.** Assigning a phase to "Linux only"
because its *name* looks platform-neutral is the same reasoning error as a fixture chosen from what
assertions happen to mention. This repo has a documented `ci-linux-msys-test-divergence` family:
Linux green while MSYS red.

Required method: run both platforms once, and for each phase record whether it touches process
spawning, path separators, line endings, symlinks, or the filesystem. A phase moves to Linux-only
**only** with a recorded reason. Anything uncertain stays on both.

Acceptance: Windows leg fits its committed wall with real headroom, **and** every phase dropped
from Windows has a written justification. `ci-linux-msys-test-divergence` must be re-read first —
it lists cases that passed on Linux and failed on MSYS.

## 2. MAJORs to fix alongside (cheap, and two are my own errors)

| # | Fix |
|---|---|
| 7 | Restore the load-vs-defect distinction: rc 124/137 must not land in the generic crash branch. Removing `INCONCLUSIVE` deleted a real signal; reinstate the *distinction* without reinstating an escape hatch |
| 12 | `hooks/git/pre-commit` fails open when `python3` is absent — "the scanner runs on every commit" (step 3's safety argument) is false. Make it fail closed |
| 9 | Dual-platform verify runs on ordinary pushes/PRs, so template consumers inherit maintainer-grade runner cost with no opt-in — a direct North Star hit. Scope triggers to release/maintainer paths |
| 8 | Recovery bound headroom is 1.64x against documented 2–3x guidance |
| 10 | `release-authority` anchors are still comment-blind in places |
| 11 | No shipped writer can mint the Step-6 FR-07 approval as documented (`approve-local.sh` emits no `paths`, records an unverifiable `repo_id`) |

## 3. Where else test time is spent — survey, not assumption

Measured so far (this host, MSYS):

| Phase | Wall | Note |
|---|---|---|
| `cli-flow-recovery` | 1099s | already cut from 36m42s; still the largest |
| `signal-reap` | ~165s | cut from 1075s |
| `secret-scan-staged` | 456s | moved out of the local default at step 3 |
| `release-authority` | 25–28s | grew from 14s; one MSYS `grep` spawn per anchor |
| fast local default (9 phases) | ~356s | 116/116 |

**Everything else is unmeasured.** The known root cause is MSYS **process-spawn count**, not bytes
or CPU — established at step 4 (`mirror-skills`: 98 files × ~0.6s/spawn).

Method before optimising anything: emit per-phase wall times for a full run on both platforms,
rank by cost, and attack spawn count in the top few. **Do not optimise from this table** — it is
five phases out of 45, and every cost claim in this project that was not measured turned out
wrong.

Candidate levers, unranked until measured: batching `mkdir`/`cp` loops into single spawns;
replacing per-item `grep`/`sed` invocations with one pass; reusing fixtures within a phase where
isolation permits; and the `$PROJECT` clone pattern wherever it survives.

## 4. Documentation to update (operator asked explicitly)

- `docs/maintainer-execution.md` — add what this week established: measure before claiming a cost
  driver; a fixture must contain the mechanism under test; one AI Developer session per branch;
  poll file mtime and process count, never transcript size; a scoped run is never release evidence.
- `docs/backlog/gate-bounds-lack-headroom/` — record the measured spawn-cost root cause and the
  step-4 result so the next reader does not re-derive it.
- `docs/compatibility.md` / `docs/hook-coverage.md` — reflect the per-platform tier once B1 lands.
- `PUBLISHING.md` — the tag-vs-verified-SHA check (B2) becomes part of the stated contract.

## 5. Explicitly NOT in this plan

- No new FR, rule, or skill.
- No raising any bound to make a gate pass.
- No release, tag, or VERSION bump.
- No re-opening C0/M1A or the classifier.
- No change to the Linux phase set — it is the one that currently works.
