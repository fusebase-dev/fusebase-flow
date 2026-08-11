# gate-bounds-lack-headroom

**Status:** parked — real gate-infrastructure defect, independent of any feature ticket
**Filed:** 2026-08-05

## Defect

Multiple bounded test phases sit within **0.5%** of their watchdog walls on an ordinary developer host, so the gate's verdict is decided by ambient load rather than by the code under test.

Measured at `5696d8f` (Windows/MSYS, ordinary desktop load — GPU software, editor, browser, Defender, WSL; no competing suite, verified via Win32 `CommandLine`):

| Phase | Bound | Actual | Over by |
|---|---|---|---|
| `cli-flow-recovery` | 900s | 903s | 0.3% |
| `bootstrap-exception` | 600s | 602s | 0.3% |
| `upgrade-repair-managed` | 600s | 603s | 0.5% |

All three exited **124** — the watchdog, not an assertion. **Zero assertions failed.** `bootstrap-exception` passed at **577s** on the same code in an earlier run. Linux was **746/746** on that identical commit.

## Why it matters

A gate whose result flips on background load teaches the reader to explain away non-passes — which is how a real failure eventually gets waved through. It has already cost multiple release cycles on this repo: `cli-flow-recovery` alone has crossed its wall **four times**, each time after a bound was re-set from a single clean-host measurement (240s → 480s → 900s).

## The rule this needs

**A bound is a liveness backstop, not a performance assertion.** It should sit far enough above the measured worst case that ordinary load cannot reach it — deliberate headroom (2–3×), never a rounded-up observation. If a phase's runtime is the concern, that is a performance ticket, not a tighter wall.

Two candidate fixes, not exclusive:
1. Give every bounded phase headroom against its *loaded-host* worst case, not its quiet-host best case.
2. Make the expensive phases cheaper — `cli-flow-recovery` copies a whole skill tree; `bootstrap-exception` and `upgrade-repair-managed` build full fixture trees per case.

## 2026-08-05 — attempted, reverted, and what the review found

An attempt raised both walls (`FF_PHASE_TIMEOUT` 600→1800s, `FF_CLI_RECOVERY_TIMEOUT` 900→5400s) and was **reverted** after adversarial review (Codex 5.6-Sol, xhigh) returned `STOP-AND-ZOOM-OUT`. Only the 1800s generic bound survives, as a reviewed value.

**The cost driver named in this ticket is wrong.** `cli-flow-recovery` does not grow with the skill tree: between the 542s and 1813s revisions the copied `flow-skills` tree stayed at **49 files / ~441 KB**. The actual driver is `test-cli-flow-recovery.sh` recursively copying **`$PROJECT` ten times**, plus several direct `flow-skills` copies — which on MSYS meets filesystem/Defender amplification. Any tripwire comment claiming the bound "tracks repo SIZE" is factually false and must not be reintroduced.

**Why 5400s was rejected.** No single scalar wall gives both generous headroom and prompt hang detection once the healthy path is ~30 min: a 90-minute wall technically satisfies FR-27 but wastes an hour before declaring a genuine hang, and it removes the pressure that has repeatedly exposed the scaling defect. The correct design is **cheap isolated fixtures + a short no-progress (stall) deadline + a larger absolute ceiling** — not a bigger scalar.

**Measured 2026-08-05 (Windows/MSYS, no competing suite, raw logs NOT retained):** `bootstrap-exception` 680s · `upgrade-repair` 527s · `cli-flow-recovery` 1813s (a **fifth** crossing of the 900s wall). Retain raw logs next time; the review could not verify these.

Candidate fix 2 is **not blocked on an operator decision** — it needs profiling and a performance contract. It is the root cause and should be scheduled ahead of any further wall change.

## 2026-08-06 — this now BLOCKS full-gate verification

A full unscoped gate passed **768/768, exit 0** (Windows/MSYS, 2h02m) — but only with `FF_CLI_RECOVERY_TIMEOUT=2700` supplied in the environment. `cli-flow-recovery` took **1568s** against its committed **900s** default.

| Run | `cli-flow-recovery` wall | vs committed 900s |
|---|---:|---|
| 2026-08-05 | 1813s | would fail |
| 2026-08-06 | 1568s | would fail |

**The repository cannot produce a clean full-gate run on an ordinary developer host without a hand-supplied override.** That promotes candidate fix 2 from an optimization to a prerequisite for release verification: the gate that a release claim rests on cannot pass as shipped.

The 1568–1813s spread (16%) on identical code also re-confirms why a wall set to any single observation keeps being crossed. The fix remains cheap fixtures + a stall deadline, **not** a larger scalar — 2700s was reviewed down and is deliberately not committed.

**Caution on future measurements:** timings taken after a killed run are unreliable — see `harness-kill-leaves-orphan-children`, where a terminated gate left CPU-consuming children alive for 38 minutes. Verify no orphans before trusting a phase time.

## 2026-08-10 — B3 added work to this phase, and the bound was deliberately NOT raised

`cli-flow-recovery` predicate 32 now runs production recovery/**write** mode over the full
canonical corpus (B3 — a read-only parity check on an already-mirrored tree cannot reach a
write-only defect). That is real added cost. Measured:

| Measurement | Wall | Conditions |
|---|---:|---|
| `mirror-skills.sh` write mode, 34 skills / 98 mirror files | **6m49s** | loaded MSYS desktop, isolated temp tree, no competing suite — the one clean, attributable number |
| `cli-flow-recovery`, full phase, post-B3 | ~89m | same host under **heavy** concurrent load (11 `claude.exe`, 7 `codex.exe`, Docker, 64 `Code.exe`) |
| `cli-flow-recovery`, full phase, pre-B3 (recorded 2026-08-08) | 1099s | quieter host |
| fast local default, 9 phases | 27m03s | same loaded host; ~5m56s recorded on a quiet one |

**The ~89m figure is not a bound input.** The fast default ran **4.5x** slower than its recorded
value on that same host, so the phase measurement carries roughly the same contamination and
cannot separate "B3 made this expensive" from "this box was busy". Setting a wall from it would
repeat the exact error this ticket documents — a bound re-set from one unrepresentative
observation, four times over.

**`FF_PHASE_TIMEOUT` stays at 1800s.** Raising the scalar is the act `plan-review-2.md` reviewed
down (2700s was "deliberately not committed"), and that review reserved the architecture choice —
larger absolute wall plus a short no-progress watchdog, or complete sharding — for a hosted
measurement that did not exist. `.github/workflows/fusebase-flow-measure-windows.yml` now exists
to produce it on `windows-latest` at an exact SHA, non-publishing. Decide after it runs.

**Status: OPEN and worse, not closed.** Headroom was 1.64x before B3 and is lower now by whatever
the full-corpus write costs on the gate host. The ranked candidate remains **making the write
cheaper** — it is ~2 process spawns per mirrored file x 98 files, which is the documented MSYS
spawn cost, not bytes — and then re-measuring. Recording that honestly is the whole point:
`docs/specs/backlog-triage-execution/final-architecture-review.md` MAJOR 8 asked for a raise with
justification **or** a recorded reason; there is no justification available yet that is not a
guess.

## Related

- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — the MSYS-vs-Linux divergence family
- decisions.md M15 — raised `cli-flow-recovery` 480s → 900s and warned in writing that a bound set from one clean-host measurement is "a latent failure with a delay fuse". It was, three releases later.
