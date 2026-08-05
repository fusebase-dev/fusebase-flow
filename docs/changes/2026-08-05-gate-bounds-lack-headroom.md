```
change_tier: lightweight
ticket: gate-bounds-lack-headroom
Problem:      Bounded test phases sat within 0.5% of their watchdog walls on an ordinary
              developer host, so the gate's verdict was decided by ambient load rather than
              by the code: cli-flow-recovery 903s/900s, bootstrap-exception 602s/600s,
              upgrade-repair-managed 603s/600s — all exit 124, ZERO assertions failed,
              Linux 746/746 on the identical commit. cli-flow-recovery has crossed four
              times (240s → 480s → 900s), each bound re-set from one clean-host measurement.
Change:       hooks/tests/run-tests.sh — FF_PHASE_TIMEOUT 600s → 1800s (:42),
              FF_CLI_RECOVERY_TIMEOUT 900s → 5400s (:364, :373, doc comment :340).
              Both TRIPWIRE comments now carry the rule that was missing, not just the
              history: a bound is a LIVENESS BACKSTOP, not a performance assertion — set it
              with 2-3x headroom over a LOADED-host worst case that COMPLETED, never over a
              wall-truncated observation. Env-var names and the INCONCLUSIVE-is-not-green
              reporting contract are unchanged; only defaults move.
Verified:     FF_ONLY=bootstrap-exception,upgrade-repair,cli-flow-recovery on Windows/MSYS,
              ordinary desktop load, no competing suite (verified via Win32 CommandLine):
              78/78 PASS, exit 0. Wall times 680s / 527s / 1813s. Under the OLD bounds this
              same run would have produced TWO exit-124 INCONCLUSIVE rows (bootstrap-exception
              680s > 600s; cli-flow-recovery 1813s > 900s) with zero failed assertions — the
              defect reproduced on demand and the new bounds absorbed it. SCOPED run: a
              subset, never release proof.
Rollback:     git revert <SHA>
Commit:       <SHA>
Deploy:       <go-ahead · SHA · FR-07 check>
```

## Headroom basis (measured 2026-08-05, not inferred)

| Knob | Old | New | Loaded worst that COMPLETED | Headroom |
|---|---:|---:|---:|---:|
| `FF_PHASE_TIMEOUT` | 600s | **1800s** | 680s (`bootstrap-exception`) | 2.65x |
| `FF_CLI_RECOVERY_TIMEOUT` | 900s | **5400s** | 1813s (`cli-flow-recovery`) | 2.98x |

## The correction this ticket made to itself

The first value chosen for `FF_CLI_RECOVERY_TIMEOUT` was 2700s — 3x the *old wall* (900s),
because no completing measurement above 903s existed. The verification run then measured
1813s, which would have left 2700s at **1.49x** — outside the 2-3x band the same commit was
adding to the tripwire. The bound was raised to 5400s against the measured number.

This is the ticket's own defect class reproducing inside its own fix: a bound derived from a
wall-truncated observation rather than a completed loaded-host run. It was caught only
because the live proof measured wall time instead of asserting pass/fail. **A gate-bound
change whose verification does not report per-phase wall time cannot detect this class.**

## Growth signal for the parked performance ticket

`cli-flow-recovery`: 199s (T11) → 304s (T24) → 542s (M13) → **1813s** (2026-08-05).
3.3x since M13. The phase copies the whole skill tree, so it grows with the repo, and a
30-minute single test phase is now the dominant cost of a full gate. That is candidate fix 2
in `docs/backlog/gate-bounds-lack-headroom/` and it is now considerably better evidenced.

## Cost of the change

A bound is only reached when something is genuinely wrong, so ordinary gate wall time does
not move. The cost is paid solely on a real hang: up to 90 min instead of 15 before
`cli-flow-recovery` is declared INCONCLUSIVE, and up to 30 min instead of 10 on a shared
heavy phase. That is the intended trade — a backstop that ambient load cannot reach.

## Explicitly NOT in this change

Making the expensive phases cheaper is a performance ticket, not a bound ticket, and stays
parked. Conflating the two is what produced the 240 → 480 → 900 edge-setting sequence.
