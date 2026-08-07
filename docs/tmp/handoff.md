# Active handoff

Mode: restart  (`restart` — operator-triggered)
**Updated:** 2026-08-07T07:20Z
**Branch:** `fix/msys-v3307-hardening`
**HEAD at write time:** `0b13b2f`
**Authoritative plan:** `docs/specs/backlog-triage-execution/execution-plan.md` (T1–T10, gates G0–G4)
**Blocking review:** `docs/specs/backlog-triage-execution/implementation-review.md` — **`DO-NOT-SHIP`, 8 BLOCKERs**
**Prior reviews:** `docs/specs/v5-c0-contracts/reviews.md`

## Next action

**Close B1 — it is the one blocker the correction round did NOT fix, and its own discriminator
proves it.** Scoped run at `0b13b2f`:

```
FAIL: signal-reap exit-path-reaps-group-without-sentinel
  EXIT trap ran (trap-ran winpid=..., child=...) but child_gone=-1s grandchild_gone=-1s
  (-1 = alive at the 8s deadline) — the EXIT path disarmed the guard before cleanup completed
19/20 PASS, 1 FAIL, 0 SKIP     (run-tests: 42/43, SCOPED — not release evidence)
```

`_ff_exit_reap` in `hooks/tests/run-tests.sh` still clears/stops the reap guard before cleanup has
finished, so on an EXIT path that does run, descendants survive. Fix the ordering, then re-run
`FF_ONLY=signal-reap`. Everything else in the correction round is green.

**Then**: re-review (the prior review was against `b0b33b3`, before these three commits), then the
full unscoped gate + Linux on one SHA with committed defaults.

## What landed (T1–T5, T9 — all committed, none gated)

| Commit | Task | State |
|---|---|---|
| `8917bc2` | T1 governance truth reset | 15 statuses restated; handoff archived w/ sha256 |
| `0550d37` | T9 install-document audit | 6/6 scoped; **2 BLOCKERs open** (F20, F21) |
| `685ed77` | T2 instrumentation seam | 8/8 scoped, mutation-tested; 954→953 lines; **4 MAJORs open** |
| `d229cff` | T3 S2 red arm | reproduction + topology retained |
| `15f4126` | — | a correction that was itself wrong (see below) |
| `6deb143` | T4 S2 sentinel | 8/8 scoped; **6 BLOCKERs open** — do not trust this fix |
| `b0b33b3` | T5 FR-06 corpus | 132 cases; no parser touched |

## The three-measurement lesson — do not repeat it

| # | Claim | Fixture | Verdict |
|---|---|---|---|
| 1 | trap never fires in 12s | real harness, FIFO nap active | correct |
| 2 | trap fires in 0.9s, so use a trap | simplified `sleep 0.2` loop | **wrong** |
| 3 | never with the nap; 1s without | real harness, both arms | correct |

`_ffhc_nap` is `read -t` on an RW-opened FIFO; bash does not deliver the trap during it.
Measurement 2 was made by the orchestrating session and used to override a correct finding.
**A fixture must contain the mechanism under test.**

## Highest-value BLOCKERs (full list in the review)

1. `run-tests.sh:118` — `_ff_exit_reap` stops the sentinel **before** the known-insufficient
   `taskkill //T`, disabling the stronger cleanup on any EXIT path that does run.
2. `orphan-sentinel.sh:45` — identity is only PID/WinPID/PGID; all three are recyclable.
3. `orphan-sentinel.sh:52` — group guards **fail open** when a PGID lookup returns empty.
4. `orphan-sentinel.sh:56` — cleanup requires the group leader alive, but the leaked topology has
   the leader dead — the exact case T3 demonstrated.
5. `orphan-sentinel.sh:72` — native sweep `taskkill`s every current group member without
   revalidation (collateral risk; `bounded-run-msys-collateral-kill` class).
6. `run-with-timeout.sh:553` — child launched **before** its identity record exists, and the state
   write is truncate-then-printf, not atomic. A signal in that window recreates the original leak.
7. `install-fusebase-cli-project.md:164` — plugin dirs documented "never copied" while the upgrade
   engine still owns them (`managed_content_manifest.py:38-41`).
8. `preflight.sh:335` — compares any existing consumer plugin's version to Flow's `VERSION`, with
   no `name == fusebase-flow` guard, so following the guide can produce a false preflight error.

Also: `signal-reap` "8/8" overstates coverage — 4 rows are controls that passed pre-fix, and
off-MSYS skips increment PASS.

## Standing constraints

- Scoped `FF_ONLY=` runs are **not** release evidence. Only `state/audit/hook-test-results.md`
  from a full unscoped run may be cited. This was misread as release proof twice on 2026-08-05.
- `cli-flow-recovery` measured 1568s/1813s against a committed 900s bound; the last full pass
  (`88f7286`, 768/768) required `FF_CLI_RECOVERY_TIMEOUT=2700` in the environment. Do not commit
  that value; `FF_SKIP_CLI_RECOVERY=1` is not a pass (it records INCONCLUSIVE).
- Timings taken after a killed run are void until S2 is genuinely fixed.
- **One AI Developer session per branch.** Two collided this round because a 0-byte transcript was
  misread as a dead spawn and retried, then a successor was spawned. Poll **file/git activity**,
  not transcript size — one agent read for 10 minutes before its first write.
- Two-platform gating (Windows/MSYS + Linux `ubuntu:24.04`) before any release claim. Never
  `--no-verify`. FR-07 protected: `policies/*.yml`, `hooks/{handlers,shared,git}/**`.

## Not done, and why

- **T6/T7/T8** (profile → decision → conditional optimization) — gated behind a working T4; the
  profiles would be measured on a tree with a broken reaper.
- **Full gate + Linux** — blocked by `DO-NOT-SHIP`.
- **No release published.** v4.7.0/v4.7.1 remain live and untouched.
