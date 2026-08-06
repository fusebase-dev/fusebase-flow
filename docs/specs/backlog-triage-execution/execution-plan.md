# Execution plan — 2026-08-06 backlog triage

**Status:** DRAFT, pending adversarial review · **Lane:** per-slice (S0/S1 Lightweight, S2/S3 Full)
**Inputs:** `docs/specs/v5-c0-contracts/reviews.md` (3 adversarial reviews) · Codex xhigh triage 2026-08-06 · direct measurement (§2)
**Supersedes:** the "ready to execute / C0 first" direction in `docs/tmp/handoff.md` — rejected by review.

## 1. Triage outcome — 15 tickets

| Ticket | Verdict | Reason |
|---|---|---|
| `gate-bounds-lack-headroom` | **DO (S3)** | Windows verification cannot pass on committed defaults. Release-evidence defect, not performance polish |
| `harness-kill-leaves-orphan-children` | **DO (S2)** | Observed; leaked children corrupt the timings S3 depends on |
| `codex-plugin-packaging` | **DO (S0)** | Status is FALSE — shipped in v4.4.0 (`.codex-plugin/plugin.json` in tree, documented in v4.4.0 notes). Close it |
| `local-gate-misses-manifest-freshness` | **DROP** | CI already catches it. Taxes every consumer's default gate to save a maintainer one push-retry |
| `self-granting-health-deferral` | **DROP** | Real parser defect, but under K3 the same principal can write a valid array directly. Malformed-record handling, not an authority boundary. Does not justify another Full-lane cycle |
| `adapter-overlay-refresh-parity` | **DROP** | Duplicated overlays are the wrong architecture; secondary adapters already point at canonical files |
| `architect-sub-agent` | **DROP** | Adds a role/relay/escalation to solve unmeasured PO context cost |
| `role-path-hook-enforcement` | **DROP** | Would document a structural guarantee it cannot provide (fail-open role extraction) |
| `fr22-predelegation-hook` | **DROP** | Closes no observed escape; enforces nothing |
| `fr27-prelaunch-nudge` | **DROP** | Another warning line is prose delivery, not liveness |
| `repair-trust-root-outside-workspace` | **DROP** | Addresses hostile co-tenants explicitly excluded by K3 |
| `command-gate-shell-evasion` | DEFER | Real FR-06 gap, but every narrow fix opens another. Needs a semantic corpus + false-positive tolerance |
| `approval-single-use-consumption` | DEFER | Needs a stable cross-hook call ID + atomic reservation; neither exists |
| `compat-approval-surfacing` | DEFER | Needs the carrier table; `--inventory` is an adequate interim |
| `install-into-existing-fusebase-cli-project` | DEFER | No observed demand; its collision list is stale. **But its doc defect is real → S1** |

Nine DROP, four DEFER, three DO. Carrying a ticket nobody will action is itself a cost (North Star: cost is a first-class defect class).

## 2. Measured evidence — supersedes every prior cost claim

`cli-flow-recovery`, 1568s total (2026-08-06, this host, no competing suite):

| Component | Measured | Share |
|---|---:|---:|
| **13× `post-fusebase-update.sh`** | **78s each ⇒ ~1012s** | **~65%** |
| 5× health-check drives | remainder | ~33% |
| 14× `check-cli-flow-conflicts.sh` | 1.35s ⇒ 19s | 1.2% |
| 4× `mirror-skills.sh --check` | 2.8s ⇒ 11s | 0.7% |
| 10× `cp -R "$PROJECT"` | 0.43s ⇒ 4.3s | **0.3%** |

**The "copies are the cost driver" claim is refuted.** It appeared in the backlog ticket, in an adversarial review, and in my own earlier commit message. Copies are 0.3%. `post-fusebase-update.sh` is `sys`-dominated (59.6s sys vs 4.9s user) — MSYS spawn + filesystem cost.

**Tested lever:** rebuilding the fixture with 3 skills instead of 49 took that script **78s → 31s (60% cut)**. Projected ~600s saved across 13 invocations. The residual 31s is fixed overhead, so a reduced skill tree is necessary but **not sufficient** to clear 900s alone.

Corrected counts (previous figures were wrong): **10** full `cp -R "$PROJECT"` clones, **26** recursive-copy calls, **31** assertion groups, 954 lines.

## 3. Slices

### S0 · Reset backlog and handoff truth — Lightweight, docs only

**Why now.** `docs/tmp/handoff.md:1` says "ready to execute" and `:16` says "C0 … Do this first". Three reviews rejected that sequence. Any fresh session reads this file first and would execute rejected work.

**Scope.** Supersede the handoff with this triage. Apply DROP/DEFER verdicts in `docs/backlog/index.md` + each ticket README. Correct `codex-plugin-packaging` from "done (pending release)" to shipped-in-v4.4.0.

**Discriminator (fails today).** `grep -n "ready to execute\|Do this first" docs/tmp/handoff.md` returns 2 hits; `grep "pending release" docs/backlog/index.md` returns 1. All must be gone, and each DROP ticket must state why it was closed.

**Do not.** Delete ticket bodies — mark status and keep the evidence. Do not bulk-rewrite history.

---

### S1 · Fix the Windows safe-install path — Lightweight, one line

**Why now.** [`docs/install-fusebase-cli-project.md:137`](../../install-fusebase-cli-project.md) has `Copy-Item -Recurse -Force .fusebase-flow-source\skills .` The Bash block at `:117` correctly uses `flow-skills`. Root `skills/` **does not exist** (canonical moved in v3.9.0). A Windows operator following the canonical procedure gets an error and installs **zero Flow skills**.

**Scope.** `skills` → `flow-skills` in the PowerShell block. Sweep the file for any other `\skills` / `/skills` referring to the source tree, distinguishing them from the legitimate `.claude/skills/` and `.agents/skills/` destinations.

**Discriminator.** `.fusebase-flow-source\skills` is absent from the repo; `flow-skills/communication/SKILL.md` exists. After the fix, every source path in both blocks must resolve against the real tree, and the two blocks must be symmetric.

**Do not.** Rewrite the installer or touch the DEFERred automation ticket.

---

### S2 · Reap a gate terminated by TERM or INT — Full lane

**Why now.** Prerequisite for S3: leaked children manufacture the "competing suite" condition that corrupts phase timings.

**Diagnosis already done (do not re-derive).**
- [`run-tests.sh:121`](../../../hooks/tests/run-tests.sh) installs `trap _ff_exit_reap EXIT` only — no TERM/INT.
- Empirically: a bash EXIT trap **does** run on SIGTERM, but only *after the current foreground command returns*. With a multi-minute phase in flight, the outer `timeout` reaches its `-k` grace and hard-kills first, so the trap never runs.
- Empirically: the phase's children are **not** in a killed process group and survive the parent — confirmed with a minimal repro (1 orphan) and in the field (3 orphans, 38 min, one *spawned after* parent death).
- A `KILL_ON_JOB_CLOSE` Windows Job Object fence **already exists** at [`run-with-timeout.sh:307`](../../../hooks/local/lib/run-with-timeout.sh) (`_ffhc_job_helper_path`). The defect is that it did not cover this path — **determine why before adding anything new.**

**Scope.** Explicit TERM/INT handling around the existing strictly-scoped child identity (`FFHC_LAST_WINPID` / `FFHC_LAST_CHILD_PID`), reusing the existing fence rather than inventing a second mechanism. Preserve conventional termination status.

**Discriminator (must fail today, pass after).**
1. Launch a miniature bounded phase under a short outer `timeout`; let it fire mid-phase. Today ≥1 matching child survives; after, zero within the grace window.
2. Ctrl-C (SIGINT) equivalent: same result.
3. **Sibling survival** — an unrelated `bash`/`sleep` started independently must still be alive afterwards.
4. **Normal exit performs no kill** — a clean run's behaviour is byte-identical to today.

**Do not.** Use a broad `taskkill`; retain PID-reuse verification. Do not widen the kill to a process tree that could include the operator's shell — the repo already has a catalogued collateral-kill incident (`bounded-run-msys-collateral-kill`).

---

### S3 · Restore a clean default gate — Full lane

**Why now.** The full gate passes only with an unrecorded `FF_CLI_RECOVERY_TIMEOUT=2700`. `FF_SKIP_CLI_RECOVERY=1` is not an alternative: [`run-tests.sh:360-364`](../../../hooks/tests/run-tests.sh) increments `fail` and records INCONCLUSIVE. So release evidence today requires a hidden override.

**Scope, in order.**
1. **Instrument first.** Emit per-scenario and per-substep timings from `test-cli-flow-recovery.sh`. Publish the profile. No optimization before this lands — §2 shows what happens when cost is asserted rather than measured.
2. **Cut the dominant cost.** §2 identifies 13× `post-fusebase-update.sh` at ~65%. Reduce the fixture's skill tree to the minimum the assertions actually need (measured 60% cut on that script), and/or reduce invocation count where scenarios can share a recovered fixture.
3. **Reuse fixtures.** 10 full `cp -R "$PROJECT"` clones can become 1 shared fixture with exact mutate/assert/restore boundaries. This is ~0.3% of runtime — do it for clarity, **not** as the performance fix.
4. **Re-measure under load.** Keep 900s only if the healthy path now has deliberate headroom. Otherwise add a short no-progress (stall) deadline plus a larger absolute ceiling — **not** a bigger scalar.
5. **Record provenance in the gate artifact.** `state/audit/hook-test-results.md` currently records only a date and `768/768`. Add HEAD SHA, platform, scoped/unscoped, duration, and any non-default `FF_*` values. A scoped run was twice misread as release evidence in this session; the artifact must carry its own limits.

**Discriminator.** On one identical SHA: Windows full unscoped gate passes with **no** `FF_SKIP_CLI_RECOVERY` and **no** timeout override; recovery test stays **31/31**; the artifact records SHA/platform/scope/duration/env.

**Do not.** Reduce or hide the 31 assertion groups. Do not commit 2700s or 5400s. Do not profile after a killed run without first ruling out orphans (S2 is the prerequisite for exactly this reason).

## 4. Explicitly out of scope

- C0, M1A, the 11-trigger classifier, roadmap S5–S9 — rejected by review; `decisions.md` and `m1a-baseline.md` stay parked with their defects named.
- Any new FR, rule, or skill.
- Any claim that something is signed, operator-authenticated, or identity-bound (nothing in this repo signs anything).
- **UX/UI design: assessed, N/A.** This repository has no user-facing surface — no UI, no client/internal split, no routes, no components. Deliverables are markdown, bash and Python. The UI/UX step was considered and does not attach.
- **Migrations / production deploy: assessed, N/A.** No database, no schema, no users, no runtime service. "Deploy" here means publishing a release, which requires two-platform gating that has not run.
- **Problem-catalog platform entries: assessed, N/A.** No sign-in, registration, session tokens, or role/permission surfaces exist in this repo.

## 5. Sequencing

`S0 → S1` (independent, docs) then `S2 → S3` (S2 is a hard prerequisite for S3's measurements).

## 6. Verification for the whole round

Full **unscoped** gate on Windows/MSYS with **committed defaults** (the S3 acceptance), plus a Linux/`ubuntu:24.04` run on the same SHA. Two-platform gating is mandatory before any release claim; a green MSYS run alone has been wrong twice.
