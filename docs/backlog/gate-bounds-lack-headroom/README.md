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

## Related

- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — the MSYS-vs-Linux divergence family
- decisions.md M15 — raised `cli-flow-recovery` 480s → 900s and warned in writing that a bound set from one clean-host measurement is "a latent failure with a delay fuse". It was, three releases later.
