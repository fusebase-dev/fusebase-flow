# gate-bounds-lack-headroom

**Status:** OPEN - real gate-infrastructure defect, independent of any feature ticket. **The healthy duration is no longer unknown:** `cli-flow-recovery` completes at **1659s rc=0** on a quiet MSYS host at `a795902`, i.e. **1.085x** headroom against the 1800s ceiling; a run preceded by two other phases on the same host was censored at 1805s. Attribution: section 2026-09-12b
**Filed:** 2026-08-05

## Defect

Bounded test phases carry no deliberate headroom against their watchdog wall on an ordinary
developer host, so the gate's verdict is decided by ambient load rather than by the code under
test. **Current state, measured 2026-09-12 at `a795902`: `cli-flow-recovery` DOES complete, at
1659s against the 1800s ceiling (1.085x headroom), and was censored at 1805s in the very next run
on the same host.** `bootstrap-exception` clears it by 77s. Numbers, method and raw logs:
sections 2026-09-12 and 2026-09-12b.

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

> SUPERSEDED IN PART (section 2026-09-12b): it COMPLETES at 1659s on a quiet host. Everything
> below stands as the record of THAT run; the healthy duration it calls unknown is now known.

`[run-tests] END tag=cli-flow-recovery elapsed=1810s rc=124 timeout_budget=1800s`. 82 predicate
rows were counted before the kill (41 DISTINCT: section 2026-09-12b shows the watcher
double-counted them); the phase was mid-operation when the watchdog fired. **This is another
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
- **SUPERSEDED (2026-09-12b):** "41 of 82 rows flushed late, so these intervals bound operations
  without attributing them" is WITHDRAWN as a measurement artifact, and the attribution it
  blocked is now done. See the next section.

## 2026-09-12b — the phase COMPLETES, and the time is attributed (`a795902`)

**Headline: `cli-flow-recovery` finishes.** Three green runs on a quiet MSYS host at `a795902`+:
**1659s**, **1559s**, **1571s**, all `rc=0` / 44-44 PASS. That is the first UNCENSORED healthy
duration at this commit, and the input every decision in this ticket was waiting on. Headroom
against the 1800s ceiling: **1.08-1.15x**.

**It is not reliable headroom.** A run of the same phase preceded in the same invocation by
`signal-reap` and `cli-flow-recovery-selectors` hit `elapsed=1805s rc=124`. Same commit, same
host, same hour: **1659s green and 1805s censored**, decided by what else had just run on the box.
That is this ticket's thesis reproduced with an uncensored number instead of a guess.

**Attribution no longer needs an external watcher.** Every bounded operation now reports its own
duration and the runner echoes those markers on GREEN runs too, so the phase's own log answers the
question this ticket kept having to reconstruct:

```
[cli-flow-recovery] engine U16 END rc=0 elapsed=57s      (watchdog 180s -> 3.2x)
[cli-flow-recovery] engine U17 END rc=0 elapsed=55s
[cli-flow-recovery] engine U18 END rc=0 elapsed=52s
[cli-flow-recovery] op U20 upgrade (migration)   END rc=0 elapsed=140s   (deadline 600s -> 4.3x)
[cli-flow-recovery] op U20 upgrade (idempotency) END rc=0 elapsed=111s   (deadline 600s -> 5.4x)
```

Before this, `run_shell_phase` printed only `^(PASS|FAIL|N/A): <tag> ` on a green run and replayed
the rest ONLY on a failure, and the END markers carried no elapsed at all. That, not any buffering,
is why the 2026-09-12 measurement needed a watcher timestamping capture tempfiles from outside.

### The "late flush" finding is withdrawn — it was a watcher artifact, not a runner defect

The `e39cd37` capture holds exactly **41 distinct** `PASS: cli-flow-recovery` messages, and **all
41 reached the log in real time**. The 52 rows timestamped after the wall are duplicates: the
external watcher re-read each bounded-capture tempfile from the beginning when its identity
changed. The set difference between the post-wall message texts and the pre-wall message texts is
**empty** — not one row arrived late. The recorded intervals were therefore attributable all
along, and the v4.17.1 `cli-flow-recovery-selectors` shape (score each row at its own deadline,
keep evidence outside cleanup) does **not** apply here: there was no buffering to fix.

**The real progress-signal gap is a different one, and it is real.** `[bounded] still running
(Ns/1800s)` is a LIVENESS heartbeat, not progress. It printed six more times after the last
predicate at 1655.2s, all the way to the wall, while the phase scored nothing. No stall detector
can be built on it, and nothing else in the phase reports progress between predicates.

### Where the time goes — per module (from the `e39cd37` real-time rows)

| Segment | `e39cd37` (29% load) | quiet (`a795902`) | ratio |
|---|---:|---:|---:|
| start -> first predicate | 102.3s | ~50s | ~2.0x |
| `cli-flow-recovery-e2e` | 493.1s | 294.6s | 1.67x |
| `cli-flow-recovery-classify` | 263.8s | 109.7s | 2.40x |
| `cli-flow-recovery-engine` | 316.5s | 146.8s | 2.16x |
| `preflight` + `direct` | 443.8s | 275.5s | 1.61x |
| `ffcf_u20_migration` | **censored, >190.6s** | **190.9s** | — |
| `ffcf_t34_bootstrap` | never reached | 70.2s | — |
| `ffcf_t89_eol` | never reached | 61.6s | — |

### Where the time goes — per operation (unmodified driver under `bash -x`, EPOCHREALTIME in PS4)

No instrumentation was added to the driver or the phase, and none is committed. Every line below
is the wall spent ON that line; everything not listed is under 3.5s.

| Operation | Wall (quiet) |
|---|---:|
| `post-fusebase-update.sh --refresh-overlays` (drifted block) | **71.5s** |
| `post-fusebase-update.sh --wire-hooks` (2nd) | **51.5s** |
| `post-fusebase-update.sh --wire-hooks` (1st) | **40.7s** |
| `post-fusebase-update.sh` (first full recovery) | **39.9s** |
| whole fixture build before the first recovery | 17.5s |
| `cp -R hooks/handlers` per tree | 1.1s |
| `ffcf_derive_providers` (one python spawn) | 1.0s |

**The ~102.3s to the first predicate is now attributed: ~17.5s of fixture build plus ONE
`post-fusebase-update.sh` recovery run.** The fixture is not the cost; the recovery engine is. The
four recovery invocations in the E2E module are ~204s of the phase on a quiet host by themselves.

**The 161.5s interval is attributed: 33.2s of `ffcf_engine_tree` build + 127.4s of U16.** The same
U16 on a quiet host is **41.5s** (U17 40.1s, U18 40.1s) — so 127.4s was a loaded outlier, not a
property of the operation.

**The censored 190.6s tail is now NAMED: `ffcf_u20_migration`,** which runs `upgrade.sh --auto-yes`
twice and emitted nothing for **190.9s on a quiet host** (direct driver) / **251s under the runner**
(140s migration + 111s idempotency, now reported per invocation). It was the single largest blind interval in
the phase and the operation the wall was killing mid-flight. It is now bounded at its owner
(`ffcf_bounded_op`, 600s default, `FFCF_U20_WATCHDOG_SECS`) with START/END markers and a distinct
named deadline failure, matching what the secret-scan hook run and the selectors cases already do.

### 1099s -> >1810s on the same host: LOAD, not phase growth

Same code, same host, one day apart. Every operation measured on both sides sits between **1.6x
and 3.1x** (median ~1.8x). Applying that band to the quiet 1099s recorded on 2026-08-08 gives
**1760-3410s** under the `e39cd37` conditions, and the observed `>=1810s` censored value sits
inside it. **No growth term is needed to explain the observation**, and the ~110s of named
additions since (F1 ~31-37s, schema-3 ~42s, the eol group ~35s) account for the gap between that
1099s and today's quiet number, with the rest inside normal same-host variance.

The earlier question "is the host slower than in August?" therefore resolves to: the host is not
slower, the MEASUREMENT was taken under load. Primitives measured on this host for the record:
one MSYS process spawn **643ms**, one whole-table `ps` **562ms**, one `/proc/<pid>/stat` builtin
read **185ms**. The phase is spawn-bound, so ambient load multiplies it directly.

### A universal 180s stall deadline is refuted with a NAME, not just a number

`ffcf_u20_migration` is **190.9s before any load**, and
`post-fusebase-update.sh --refresh-overlays` is 71.5s quiet, i.e. ~220s at the 3.07x worst
observed multiplier. The 180s watchdog already shipped in `ffcf_engine_out` is correctly sized
**for that operation** (41.5s quiet = 4.3x headroom, 127.4s worst observed = 1.41x) and must not
be generalised. Calibrate per operation; `ffcf_bounded_op` is the shared shape for doing it.

### Cost regression found and fixed inside this outcome

`T83`'s orphan-sentinel leader-token refresh ran on every poll tick for the life of every bounded
phase: **202ms/tick against 4ms** (measured), i.e. ~330s of background `/proc` work across one
1659s phase. The token settles exactly once, so refreshing forever bought nothing. Bounded to a
12-tick settle window.

### The 1800s wall stays at 1800s

The healthy duration is now known and it is **under** the ceiling, so there is no justification to
raise the scalar — and this ticket's own history is that every raise from a single measurement was
crossed again. What the measurement does establish is that headroom is **1.085x**, far below the
2-3x this ticket asks for, so the ceiling is decided by ambient load rather than by the code under
test. The lever is the ~204s of repeated `post-fusebase-update.sh` recoveries plus the 190.9s U20
migration, not the wall.

### Next steps, with the measured input each now has

| # | Outcome | Measured input that justifies it |
|---|---|---|
| 2 | Cut the repeated full recovery runs in `cli-flow-recovery-e2e` | Four `post-fusebase-update.sh` invocations cost 39.9 + 40.7 + 51.5 + 71.5 = **203.6s quiet**, the largest single block in the phase |
| 3 | Calibrated per-operation bounds at the remaining shared call sites; keep the 1800s ceiling | `ffcf_bounded_op` now exists and U20 uses it; the four E2E recoveries and `ffcf_engine_tree` are the remaining unbounded blocks |
| 4 | Cut `ffcf_u20_migration`'s 251s | Now split and reported: 140s migration + **111s for an idempotency re-run** on a full-tree clone |
| 5 | Hosted-CI headroom assessment for the other two phases | `bootstrap-exception` 1.04x and `upgrade-repair` 1.75x locally; both still need a hosted number to separate host from phase |

**Step 2 is the ranked next action**, and it is now a performance ticket with a number rather than
a bound question.

## Related

- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — the MSYS-vs-Linux divergence family
- decisions.md M15 — raised `cli-flow-recovery` 480s → 900s and warned in writing that a bound set from one clean-host measurement is "a latent failure with a delay fuse". It was, three releases later.
