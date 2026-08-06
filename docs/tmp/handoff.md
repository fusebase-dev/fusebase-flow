# Active handoff

Mode: restart  (`restart` — operator-triggered)
**Updated:** 2026-08-06T22:00Z
**Branch:** `fix/msys-v3307-hardening`
**HEAD at write time:** `cd094eddee7d3f7468e9433ae0e06be170429095`
**Authoritative plan:** `docs/specs/backlog-triage-execution/execution-plan.md` (T1–T10, dependency gates G0–G4)
**Superseded:** `docs/tmp/handoff/archive/2026-08-06-v5-roadmap-superseded.md` · sha256 `8cc37a22d4c355907b71c0debb53caa2a531c262b0cf155218e053428fb21fb0`

## Next action

**Execute T1 → then the gate G0 check, then T2.** Task contracts, dependencies, commit boundaries and rollback are in the plan; do not re-derive them here.

## What changed, and why the previous direction is void

The superseded handoff presented the v5 roadmap as executable and directed that the C0 contract packet be locked before anything else. **That direction was rejected** — the literal wording is preserved only in the archived copy, so a search for it cannot land in an active file. Three independent adversarial reviews (Codex 5.6-sol, xhigh — condensed in `docs/specs/v5-c0-contracts/reviews.md`):

| Target | Verdict |
|---|---|
| Three implemented backlog fixes | `STOP-AND-ZOOM-OUT` → all reverted (`5f8004f`) |
| C0 decision packet | `WRONG-SEQUENCE`, 5 BLOCKERs → not locked |
| M1A measurement plan | `SHIP-SMALL-FIRST`, 7 BLOCKERs → not started |
| First execution plan | `STOP-AND-RESCOPE`, 6 BLOCKERs → reissued at `cd094ed` |

`docs/specs/v5-c0-contracts/decisions.md` and `m1a-baseline.md` remain parked with their own defects named in their headers. **Do not lock or execute either.**

## Standing constraints

- **Evidence labels are binding.** The plan marks each fact `VERIFIED` / `HYPOTHESIS` / `UNVERIFIED`. A `HYPOTHESIS` may not drive a fix. The last plan selected an optimization from a wrong arithmetic attribution; that is why the labels exist.
- **Full-gate evidence only.** A scoped `FF_ONLY=` run is not release proof — it was misread as such twice on 2026-08-05. Only `state/audit/hook-test-results.md` may be cited.
- **The gate currently needs a hand override.** `cli-flow-recovery` measured 1568s and 1813s against a committed 900s bound. The 768/768 pass at `88f7286` required `FF_CLI_RECOVERY_TIMEOUT=2700` in the environment. Do not commit that value; do not treat `FF_SKIP_CLI_RECOVERY=1` as a pass (it records INCONCLUSIVE and increments `fail`).
- **Timings taken after a killed run are void** until `harness-kill-leaves-orphan-children` is fixed — a terminated gate left children alive for 38 minutes.
- Two-platform gating (Windows/MSYS + Linux `ubuntu:24.04`) before any release claim. Never `--no-verify`. FR-07 protected: `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**`.
- Write long-running agent output to `c:/tmp/`, not the session scratchpad.

## Shipped and untouched

v4.7.0 (`bad4d92`) and v4.7.1 (`3ae1feb`) are live. Nothing in the current plan touches them. `88f7286` shipped `hooks/local/lane-router.sh` — a path-only hard-surface router that makes the existing lightweight-lane eligibility rule executable; it routes its own edits Full.
