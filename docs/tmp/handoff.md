# Active handoff

Mode: restart  (`restart` — operator-triggered)
**Updated:** 2026-08-07T08:05Z
**Branch:** `fix/msys-v3307-hardening`
**HEAD at write time:** `186ba38`
**Authoritative plan:** `docs/specs/backlog-triage-execution/execution-plan.md` (T1–T10, gates G0–G4)
**Blocking review:** `docs/specs/backlog-triage-execution/implementation-review.md` — **`DO-NOT-SHIP`, 8 BLOCKERs**
**Prior reviews:** `docs/specs/v5-c0-contracts/reviews.md`

## Next action

**Re-review, then the full unscoped gate + Linux on one SHA with committed defaults.** All 8
BLOCKERs are closed at `186ba38`. The prior review was against `b0b33b3`, before these four commits.

**SUPERSEDES the "B1 remains open" entry written at `7215d55`.** That was read from an intermediate
scoped run and its diagnosis was wrong — including the row's own failure text, which is why it
misled. The `FAIL` was not `_ff_exit_reap` disarming the guard before cleanup. Ordering was fixed in
`91f8748` (reap FIRST, sentinel disarmed LAST, both paths sharing `hooks/tests/lib/orphan-reap.sh`).
The trap was being **SIGKILLed part-way through** by the outer `-k` grace, which under nested load is
shorter than the guard's I/O takes — a grace-budget measurement, not an ordering defect.

The row was itself claiming more than the mechanism gives: the harness-side EXIT path is BEST-EFFORT
inside the `-k` window; the out-of-band sentinel is the guarantee, which is exactly why the ordering
must not disarm it first. `186ba38` corrects the row (a `reap-returned` marker separates "ran to
completion and reaped nothing" = FAIL from "cut short" = INCONCLUSIVE) rather than widening the
budget to hide it. Verified at `186ba38`:

```
19/19 PASS, 0 FAIL, 0 SKIP, 2 INCONCLUSIVE   (standalone signal-reap)
42/42 PASS, GATE_RC=0                        (FF_ONLY=signal-reap,cli-flow-profile,
                                              command-policy,install-doc — SCOPED, not release evidence)
```

The 2 INCONCLUSIVE are declared, not hidden: the EXIT-path grace budget under load, and the
pre-existing **INT exit-status design question** — the harness never acts on an untrapped SIGINT, so
there is no 130, and `trap … INT` cannot supply one while `_ffhc_nap`'s blocking FIFO read defers
delivery past the `-k` SIGKILL. Closing it means changing the nap primitive. **That is a design
decision and is the one thing this round deliberately did not implement.** The orphan reap itself is
unaffected — the INT scenarios reap child and grandchild within the grace window.

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

## The 8 BLOCKERs — all CLOSED (correction round, 2026-08-07)

| # | Blocker | Closed by | Discriminator, red-before -> green-after |
|---|---|---|---|
| B1 | `_ff_exit_reap` stopped the guard **before** the insufficient `taskkill //T` | `91f8748` + `186ba38` | `exit-path-reaps-group-without-sentinel` (isolated: record published, sentinel absent) |
| B2 | identity was only PID/WinPID/PGID — all recyclable | `91f8748` | group bound by the LEADER's `/proc` start token |
| B3 | group guards **failed open** on an empty PGID lookup | `91f8748` | `failed-pgid-lookup-kills-nothing` — unrelated group 2 alive -> **0** (old) vs **2** (new) |
| B4 | cleanup required the leader alive; the leaked topology has it dead | `91f8748` | `dead-leader-descendants-reaped` — **2 -> 2** (old, reaped nothing) vs **2 -> 0** (new) |
| B5 | native sweep `taskkill`ed every member without revalidation | `91f8748` | `group-identity-mismatch-kills-nothing` — **2 -> 0** (old) vs **2 -> 2** (new) |
| B6 | child launched before its record existed; non-atomic state write | `91f8748` | `launch-window-signal-still-reaps` (window widened deterministically) |
| B7 | plugin dirs documented "never copied" while upgrade owned them | `60cb051` | `plugin-dirs-not-in-managed-set` (asserts `list-managed`, not prose) |
| B8 | `preflight.sh` compared ANY plugin manifest's version to Flow's | `60cb051` | `preflight-parity-scoped-to-flow-manifests` (negative + positive control) |

Coverage honesty (the "8/8 overstates" finding) is fixed: rows are labelled DISCRIMINATOR vs
CONTROL, skips and inconclusives are counted apart from passes, and the summary line says so.

**Design decision still open (NOT a blocker, deliberately not improvised):** SIGINT exit status —
see § Next action.

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
