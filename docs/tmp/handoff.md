# Active handoff

Mode: restart  (`restart` — operator-triggered)
**Updated:** 2026-08-07T08:05Z
**Branch:** `fix/msys-v3307-hardening`
**HEAD at write time:** `186ba38`
**Authoritative plan:** `docs/specs/backlog-triage-execution/execution-plan.md` (T1–T10, gates G0–G4)
**Blocking review:** `docs/specs/backlog-triage-execution/implementation-review.md` — **`DO-NOT-SHIP`, 8 BLOCKERs**
**Prior reviews:** `docs/specs/v5-c0-contracts/reviews.md`

## Next action

**STOP optimizing the local gate. It is not on the critical path to publishing.**

Architecture review 2026-08-07 returned **`DELETE-AND-MOVE`**
(`docs/specs/backlog-triage-execution/architecture-review.md`). The finding that reframes the
week: the local full gate is **not mechanically required for publication — CI is**.
`.github/workflows/fusebase-flow-release.yml` publishes only after its reusable `verify` job
passes on the tagged SHA. The prose disagrees with the machinery (`PUBLISHING.md` demands a local
full run; `maintainer-execution.md` demands two platforms; the enforced CI job is Ubuntu-only) —
that is an inconsistent contract, not a reason to keep spending hours locally.

**Ordered sequence, smallest first, each with its discriminator (full text in the review):**

1. Lock CI as the sole release-evidence authority — local output must not be able to match the release-pass contract.
2. Remove `cli-flow-profile` from required execution.
3. Make the fast phase set the local default — three loaded-host MSYS runs under 10 min, no overrides.
4. Decompose `cli-flow-recovery` — all 31 predicates preserved, `$PROJECT` clones 10 → 1.
5. Move `signal-reap` + heartbeat testing to Windows CI; keep the field discriminator and collateral controls.
6. Add required Linux **and** Windows/MSYS exact-SHA jobs — either red makes `publish` unreachable.
7. Delete the monolith, the profile helper/test, and the timeout-override guidance.

**On today's work.** The sentinel fixed a real defect and some child-lifecycle mechanism stays
necessary — but it is symptom-support for the current architecture and must not run on every fast
local check; scope it to the Windows/MSYS deep runner. The instrumentation seam was a temporary
diagnostic, not permanent release coverage: remove `cli-flow-profile` from required gates now, and
delete it once recovery is decomposed. Net today: **~1,786 added lines for ~22 minutes added to the
required gate. That direction should not continue.**

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
