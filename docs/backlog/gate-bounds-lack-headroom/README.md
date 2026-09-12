# gate-bounds-lack-headroom

**Status:** parked — real gate-infrastructure defect, independent of any feature ticket
**Filed:** 2026-08-05

## Defect

Bounded test phases carry no deliberate headroom against their watchdog wall on an ordinary
developer host, so the gate's verdict is decided by ambient load rather than by the code under
test. **Current state, measured 2026-09-12 at `e39cd37` against the common 1800s ceiling: the
defect is confirmed and worse — `cli-flow-recovery` no longer completes inside the ceiling at
all, and `bootstrap-exception` clears it by 77s.** Numbers, method and raw logs: § 2026-09-12.

**Historical crossings — censored watchdog exits, NOT runtimes.** Recorded at `5696d8f`
(Windows/MSYS, ordinary desktop load; no competing suite, verified via Win32 `CommandLine`):

| Phase | Bound then | Observation | What the number is |
|---|---|---|---|
| `cli-flow-recovery` | 900s | exit 124 at 903s | kill time; true runtime unknown, only `>=903s` |
| `bootstrap-exception` | 600s | exit 124 at 602s | kill time; true runtime unknown, only `>=602s` |
| `upgrade-repair-managed` | 600s | exit 124 at 603s | kill time; true runtime unknown, only `>=603s` |

TRIPWIRE: 903/602/603 are **kill times, not completion times** — each phase was still running when
the watchdog fired. Zero assertions failed, but zero-failed-assertions on a censored run does not
establish that the unfinished assertions would have passed. Never quote these as "the phase takes
~900s"; a censored observation cannot set a bound. `bootstrap-exception` did complete at **577s**
on that code in an earlier run (a real completion); Linux was **746/746** on the identical commit.

## Why it matters

A gate whose result flips on background load teaches the reader to explain away non-passes — which is how a real failure eventually gets waved through. It has already cost multiple release cycles on this repo: `cli-flow-recovery` alone has crossed its wall repeatedly, each time after a bound was re-set from a single clean-host measurement (240s → 480s → 900s → the common 1800s, crossed again on 2026-09-12).

## The rule this needs

**A bound is a liveness backstop, not a performance assertion.** It should sit far enough above the measured worst case that ordinary load cannot reach it — deliberate headroom (2–3×), never a rounded-up observation. If a phase's runtime is the concern, that is a performance ticket, not a tighter wall.

Two candidate fixes, not exclusive:
1. Give every bounded phase headroom against its *loaded-host* worst case, not its quiet-host best case.
2. Make the expensive phases cheaper. **The specific cost drivers named here in 2026-08 are
   stale** — reduced fixtures already landed. What is actually on the path now: § 2026-09-12.

## 2026-08-05 — attempted, reverted, and what the review found

An attempt raised both walls (`FF_PHASE_TIMEOUT` 600→1800s, `FF_CLI_RECOVERY_TIMEOUT` 900→5400s)
and was **reverted** after adversarial review (Codex 5.6-Sol, xhigh) returned `STOP-AND-ZOOM-OUT`.
Only the 1800s generic bound survives, as a reviewed value.

**`FF_CLI_RECOVERY_TIMEOUT` is RETIRED** (`hooks/tests/run-tests.sh:724`). There is no
phase-specific recovery wall and no `FF_SKIP_CLI_RECOVERY` escape: `cli-flow-recovery` is bounded
by the same **1800s** `FF_PHASE_TIMEOUT` as every other phase. Every reference to a 900s recovery
default or a recovery-specific override below is history, not current configuration.

**The cost driver named in this ticket is wrong.** `cli-flow-recovery` does not grow with the
skill tree: between the 542s and 1813s revisions the copied `flow-skills` tree stayed at **49
files / ~441 KB**. Any tripwire comment claiming the bound "tracks repo SIZE" is factually false
and must not be reintroduced.

**SUPERSEDED (2026-09-12) — the ten-copy driver no longer exists.** The replacement driver named
here, "`test-cli-flow-recovery.sh` recursively copying `$PROJECT` ten times", described the
**former** implementation. Reduced synthetic fixture builders shipped in
`hooks/tests/cli-flow-recovery-fixture.sh`, and exactly ONE full `$PROJECT` snapshot remains
(`cli-flow-recovery-e2e.sh`, handed to the U20 migration). **Do not rebuild that optimization —
it is already built.** The remaining repeated handler/library copies at
`cli-flow-recovery-fixture.sh:211-233` are a measurement target, not an established driver.

**Why 5400s was rejected.** No single scalar wall gives both generous headroom and prompt hang detection once the healthy path is ~30 min: a 90-minute wall technically satisfies FR-27 but wastes an hour before declaring a genuine hang, and it removes the pressure that has repeatedly exposed the scaling defect. The correct design is **cheap isolated fixtures + a short no-progress (stall) deadline + a larger absolute ceiling** — not a bigger scalar.

**Measured 2026-08-05 (Windows/MSYS, no competing suite, raw logs NOT retained):** `bootstrap-exception` 680s · `upgrade-repair` 527s · `cli-flow-recovery` 1813s (a **fifth** crossing of the 900s wall). Retain raw logs next time; the review could not verify these.

Candidate fix 2 is **not blocked on an operator decision** — it needs profiling and a performance contract. It is the root cause and should be scheduled ahead of any further wall change.

## 2026-08-06 — this now BLOCKS full-gate verification

A full unscoped gate passed **768/768, exit 0** (Windows/MSYS, 2h02m) — but only with the
then-existing `FF_CLI_RECOVERY_TIMEOUT=2700` supplied in the environment. `cli-flow-recovery` took
**1568s** against the 900s default committed at that time. Both that default and the override
variable are now gone; the wall is the common 1800s.

| Run | `cli-flow-recovery` wall | vs the 900s default of the day |
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

**Status: OPEN and worse, not closed.** Headroom was 1.64x before B3 and is lower now.
Recording that honestly is the whole point:
`docs/specs/backlog-triage-execution/final-architecture-review.md` MAJOR 8 asked for a raise with
justification **or** a recorded reason; there is no justification available yet that is not a
guess.

**SUPERSEDED (2026-09-12) — "make the write cheaper" is no longer the ranked candidate.** It was
ranked on the estimate "~2 process spawns per mirrored file x 98 files". Measured at `e39cd37`,
the full-corpus `mirror-skills.sh` write completes in **~13s**, so it cannot account for a phase
that exceeds 1800s. The cost is elsewhere and is still unattributed; § 2026-09-12 carries the
current ranking.

## 2026-09-12 — calibration measurement at `e39cd37` (supersedes every headroom estimate above)

**No phase reaches the 2x headroom target, and `cli-flow-recovery` does not complete at all.**
Three focused runs, one host, one hour, one commit, no competing suite. Walls unchanged — this
outcome was a measurement, not a fix.

| Phase | Result | Wall | Ceiling | Headroom | Kind |
|---|---|---:|---:|---:|---|
| `cli-flow-recovery` | **exit 124 CENSORED** | 1810s (killed) | 1800s | **none — never finished** | measured |
| `bootstrap-exception` | exit 0 PASS | **1723s** | 1800s | **1.04x** | measured |
| `upgrade-repair` | exit 0 PASS | **1029s** | 1800s | **1.75x** | measured |

Method: `FF_ONLY=<tag> bash hooks/tests/run-tests.sh`, one run per phase; walls are the runner's
own `[run-tests] END tag=... elapsed=` value. Per-operation timings came from an external watcher
that timestamps the bounded-runner capture tempfile — **no instrumentation was added to the runner
or the phase, and none is committed.** Host: Windows 11 / MSYS, 24 logical cores, ~7 busy from
interactive desktop apps (editor, browser, chat clients, Defender realtime, idle Docker/WSL);
verified before the first run that no `run-tests`, `codex` or competing suite was active, and
verified between runs that no orphan descendants survived. Raw logs (gitignored):
`state/audit/gate-bounds/e39cd37/` — `<tag>-runner.log`, `<tag>-optimings.tsv`, `<tag>-meta.txt`.

### `cli-flow-recovery` did not complete

`[run-tests] END tag=cli-flow-recovery elapsed=1810s rc=124 timeout_budget=1800s`. 82 predicate
rows landed before the kill; the phase was mid-operation when the watchdog fired. **This is another
censored observation — the healthy duration at this commit on this host is unknown, and is known
only to be `>1810s`.** Prior recorded green durations for this phase, for contrast and NOT as a
substitute: **1099s** (2026-08-08, pre-B3, quieter host) and **1117s** (v4.16.4 hosted CI,
user-supplied). Per this ticket's own rule the run was not retried.

### Longest silent operations actually on the path

Progress = a named predicate completing with its expected outcome validated. Each interval below
is between consecutive observed progress events, so it is an **upper bound** on any single
operation — and it is the value a stall deadline would have to tolerate.

| Observation | Value | Kind |
|---|---:|---|
| Longest COMPLETED silent interval | **161.5s** | measured |
| Final interval, still running when the wall hit | **>190.6s** | censored |
| Time to first progress event (fixture build + first recovery + assertions) | **102.3s** | measured |
| Median / p90 inter-progress interval | 19.2s / 86.9s | measured |
| Engine classification `U16` (explicit START/END markers) | **127.4s** | measured |
| Engine classification `U18` | 72.1s | measured |
| Engine classification `U17` | 55.7s | measured |

**The 409s full-corpus mirror write is NOT still on the path at that cost.** `mirror-skills.sh`
write mode over all 34 canonical skills now completes in **~13s** (`--check` 5.1s, write 13.0s,
agent mirrors 17.2s). The B3 full-corpus write is no longer the expensive thing, and the review's
"known counterexample" is resolved: it does not block a sub-180s operation budget.

**A 180s universal stall deadline is unsafe today, on measured grounds.** The per-operation
watchdog already shipped inside `ffcf_engine_out` is 180s, and `U16` consumed **127.4s** of it —
1.41x headroom on a quiet host. The final censored interval exceeded **190.6s** while the phase was
demonstrably still doing work. Both sit at or inside the proposed deadline. No honest universal
stall value follows from these phase totals; calibrate per operation.

### What this settles and what it does not

- **Settled:** all three phases now have a same-host, same-hour, uncontended number at one commit.
- **Settled:** the dominant cost is neither the retired ten-copy fixture nor the full-corpus
  mirror write.
- **NOT settled:** where `cli-flow-recovery` time actually goes. 41 of 82 predicate rows reached
  the log in real time; the rest flushed late, so these intervals bound operations without
  attributing them.
- **NOT settled:** whether 1723s / 1029s reflect phase growth or this host. Historical
  `bootstrap-exception` completions were 577s and 680s on other hosts/commits — this run is ~2.5x
  that. Cross-host attribution needs the hosted
  `.github/workflows/fusebase-flow-measure-windows.yml` run.

### Next steps, with the measured input each now has

| # | Outcome | Measured input that justifies it |
|---|---|---|
| 2 | Remove the largest remaining fixture/process cost in `cli-flow-recovery` | Phase exceeds 1800s; ~102s elapses before the FIRST predicate; longest completed silent interval 161.5s |
| 3 | Calibrated per-operation bounds at shared call sites; keep the 1800s ceiling | `U16` = 127.4s against a shipped 180s watchdog (1.41x); a universal 180s is refuted |
| 4 | Fault-test silent/chatty hangs, expected refusal, owned-descendant cleanup | The rc-124 path fired for real here and produced a counted FAIL, not a green partial — regression-lock that |
| 5 | Hosted-CI headroom assessment for the other two phases | `bootstrap-exception` 1.04x and `upgrade-repair` 1.75x locally; both need a hosted number to separate host from phase |

**Step 2 is the ranked next action.** No bound change is defensible while the healthy duration of
`cli-flow-recovery` is unknown — and it is unknown precisely because the phase can no longer
finish inside its wall.

## Related

- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — the MSYS-vs-Linux divergence family
- decisions.md M15 — raised `cli-flow-recovery` 480s → 900s and warned in writing that a bound set from one clean-host measurement is "a latent failure with a delay fuse". It was, three releases later.
