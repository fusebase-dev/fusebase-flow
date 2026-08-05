# gate-bounds-lack-headroom

**Status:** bounds FIXED 2026-08-05 (Lightweight lane — [`docs/changes/2026-08-05-gate-bounds-lack-headroom.md`](../../changes/2026-08-05-gate-bounds-lack-headroom.md)); **candidate fix 2 (phase cost) remains PARKED**
**Filed:** 2026-08-05

## Resolution of candidate fix 1

`FF_PHASE_TIMEOUT` 600s → **1800s**, `FF_CLI_RECOVERY_TIMEOUT` 900s → **5400s**, and both
TRIPWIRE comments now carry the rule rather than only the history. Headroom measured, not
inferred: 680s→1800s (2.65x) and 1813s→5400s (2.98x).

The verification run measured `cli-flow-recovery` at **1813s** — a **fifth** crossing of the
900s wall, on unchanged test code. The first replacement value (2700s) would have left only
1.49x and was corrected against the measurement before commit. Recorded because it is this
ticket's own defect class recurring inside its own fix: **a bound derived from a
wall-truncated observation is not a loaded-host worst case.**

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
1. ~~Give every bounded phase headroom against its *loaded-host* worst case, not its quiet-host best case.~~ **DONE 2026-08-05.**
2. **STILL OPEN.** Make the expensive phases cheaper — `cli-flow-recovery` copies a whole skill tree; `bootstrap-exception` and `upgrade-repair-managed` build full fixture trees per case.

## Why candidate fix 2 is now better evidenced

`cli-flow-recovery` measured wall time: 199s (T11) → 304s (T24) → 542s (M13) → **1813s**
(2026-08-05) — **3.3x since M13**. It copies the whole skill tree, so it grows with the repo
and is now a ~30-minute single phase dominating full-gate cost. Fix 1 stopped the phase from
deciding the verdict by ambient load; it did not make the gate cheaper, and the raised
backstop (5400s) is the ceiling this growth is now measured against.

## Related

- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — the MSYS-vs-Linux divergence family
- decisions.md M15 — raised `cli-flow-recovery` 480s → 900s and warned in writing that a bound set from one clean-host measurement is "a latent failure with a delay fuse". It was, three releases later.
