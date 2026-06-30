# Spec — secret-scan-and-msys-liveness-fix

**Status:** LOCKED — 2nd design review folded (RESCOPE). Target **v3.30.2** (PATCH) — **candidate; public tag GATED on a consumer pre-release re-run** (D-VALIDATION). [BLOCKER] from the 2nd review: the prior implement handoff is stale and REPLACED by `docs/tmp/handoff/2026-06-30-secret-scan-msys-liveness-v2-implement.md`.
**Created:** 2026-06-30
**Baseline:** FuseBase Flow v3.30.1
**Source:** Two consumer bug reports + **two consumer verification reports from real MINGW64 / Git-Bash hosts** (the env where Bug B manifests). The field evidence OVERTURNED the first root-cause and is folded below.

## Root-cause correction (the load-bearing change)
The 1st design review (Codex) and the read-only investigation concluded Bug B = the synthetic FR-27 AC3d test forcing `timeout -k` to SIGKILL a TERM-ignoring child, and recommended an MSYS test-guard + DEFER the core fix. **Two MINGW64 consumers disproved that:**
- The **AC3d UNIT assertion PASSES** on MSYS (a single-level SIGTERM-ignoring child is reaped, rc 137, ~3s). So AC3d is NOT the hang.
- The hang needs a **deeper nested tree**: `run_with_timeout` = `timeout -k` reaps only the **direct child**; an **orphaned, pipe-holding grandchild survives on MINGW64**, so any bounded op **captured via `$(…)`** never receives EOF on the pipe the orphan still holds → the parent's command-substitution **blocks past the deadline** → CPU-bound hang + accumulating runaway `bash.exe` (only Windows-native `Stop-Process`/`taskkill` reap them). It is **intermittent** (race on whether the grandchild leaks).
- This single mechanism explains ALL observed hangs: `run-tests.sh`, `test-health-check-timeout.sh`, the conflict-reporter's bounded `$(…)`, and **`--fast`** (which runs the conflict-reporter) — all route through a bounded `$(…)` capture.
- It ALSO explains **Bug B2's non-determinism**: when the bounded health-check sub-run's tree isn't cleanly reaped, it surfaces an rc that `ffhc_timed_out` doesn't recognize (not 124/137) and unparseable output → `fusebase-flow-health-check.sh:406-410` → false **BROKEN**. One consumer saw `PARTIAL_UNVERIFIED` one run and **BROKEN** another. So **B1 and B2 share one root cause**: the bounded-run core does not reap the process **tree** on timeout.
**Therefore the core process-tree-kill that the 1st review deferred is now JUSTIFIED by real evidence and is the load-bearing fix.** (The MSYS AC3d test-guard is dropped — AC3d already passes.)

## Problem (proven, with code refs)

### A — pre-commit secret scan self-trips on `secret-patterns.yml` (DONE — kept)
`hooks/git/pre-commit:45` fed the whole `git diff --cached -U0` (incl. removed `-` lines) to `secret_scanner.scan()` → editing `policies/secret-patterns.yml` tripped its own fake example tokens; the `whitelist:` escape broke fixtures 10/11. **Fixed in T1 (`83b15f5`)**: scan only added (`+`) lines + path-exclude `policies/secret-patterns.yml` + `policies/secret-patterns.local.yml` + `hooks/tests/fixtures/`, via a Python helper; `scan()` unchanged. Independently corroborated by two consumers (one wrote the same path-exclusion locally, `e2be78c`): edit no longer blocks, a real secret in a normal file still blocks, fixtures 10/11 still PASS.

### B — bounded-run core does not reap the process tree on timeout (B1 hang + B2 false-BROKEN)
`hooks/local/lib/run-with-timeout.sh:65-69` runs `timeout -k <grace> <secs> "$@"`. GNU `timeout` signals the direct child; descendants in the same job that survive (a backgrounded/pipe grandchild) are NOT reaped. When the bounded op's stdout is captured via `$(…)` (the conflict-reporter, `ffhc_run_bounded`, `test-health-check-timeout.sh`), a surviving grandchild keeps the write end of that pipe open → the reading `$(…)` blocks indefinitely on MSYS (where the orphan is a native `bash.exe` that POSIX signals don't kill). Result: B1 = intermittent infinite hang + runaway accumulation; B2 = non-deterministic false `BROKEN` (`fusebase-flow-health-check.sh:406-410`) when the un-reaped run surfaces an unrecognized rc + unparseable output.

## In scope
- **A — DONE (T1, kept).** Re-attach its test (`hooks/tests/test-secret-scan-staged.sh`, currently untracked) + strip the misleading "just whitelist it" guidance from pre-commit messages + document the deliberate excluded-file gap.
- **B-core (load-bearing) — MSYS tree cleanup + tempfile capture (two coordinated belts).**
  - **POSIX (Linux/macOS): UNCHANGED.** Keep GNU `timeout -k` as-is — it is already process-group-oriented and preserves rc semantics; a manual `setsid`/deadline rewrite is higher regression risk for the 26 timeout tests. Do NOT touch it unless a test proves it insufficient.
  - **MSYS/MINGW/CYGWIN only — Windows-native tree cleanup.** Detect `case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)`. When the bounded command times out (or after the kill-grace), resolve the bounded command/wrapper's Windows pid via `/proc/<pid>/winpid` and `taskkill //F //T //PID <winpid>` (output suppressed) so a native/escaped descendant is reaped and the captured pipe closes. Target the command wrapper tree **while it is still attributable** (not the `timeout` supervisor after it has exited). Preserve `124` (deadline) / `137` (force-after-grace).
  - **Tempfile capture (belt #2, all platforms).** At the bounded `$(…)` capture sites — `ffhc_run_bounded` (`run-with-timeout.sh:85`) and the conflict reporter (`fusebase-flow-health-check.sh:460`) — redirect the bounded process's stdout/stderr to a TEMP FILE, `wait` for the bounded process, then read the file. This prevents the parent's `$(…)` from starving on a pipe a descendant still holds even if the tree-kill races/misses. Complements (does NOT replace) the tree-kill.
  - **MUST preserve the `ffhc_*` API + rc semantics** (`ffhc_detect_timeout`/`ffhc_timed_out`/`ffhc_run_bounded` signatures + 124/137 — the health-check engine sources them).
  - Together: B1 fixed (no orphan starves the capture; native runaways reaped on MSYS) AND B2 deterministic (a cleanly-reaped timeout surfaces 124 → `ffhc_timed_out` → `PARTIAL_UNVERIFIED`, not BROKEN).
- **B2-defense (kept from the narrowed predicate).** At `fusebase-flow-health-check.sh:406-410`, still reclassify to advisory `HOOK_TESTS_INCONCLUSIVE` → `PARTIAL_UNVERIFIED` (exit 4) when no `FAIL:` + no strict `N/N PASS` AND (`rc==124 || rc>=128`) — a belt for any residual non-124 rc; a genuine crash (`rc 1..123/125..127`, or `rc==0` malformed) STAYS BROKEN. (Codex BLOCKER fix retained.)
- **B3 — Windows escape.** `--skip-hook-tests` alias to the existing `--fast`. (`--fast` becomes RELIABLE once B-core lands — today it intermittently hangs because the conflict-reporter's bounded `$(…)` leaks a grandchild.)
- **B4 — upgrade observability.** Progress echo bracketing `upgrade.sh`'s silenced Step 2 re-mirror.
- **Tests/docs.** Drop the AC3d MSYS-guard. Add a **nested-tree / `$(…)`-capture** bounded-run test that reproduces the leak pattern (a bounded op whose grandchild holds stdout) and asserts it TERMINATES (RED-then-GREEN if constructible in this env; otherwise a documented MSYS-only behavior test) + that runaways are reaped. Keep the AC3d hard assertion on all platforms. Health-check B2 RED-then-GREEN (signal-rc→INCONCLUSIVE; genuine crash→BROKEN). No-regression: 182+ suite + the 26 timeout tests + `ffhc_*` API/verdict/exit intact.

## Out of scope
- Re-architecting bounded-run beyond the tree-reap.
- Changing `secret_scanner.scan()` semantics.
- The PreToolUse self-trip when an agent *writes* full `secret-patterns.yml` content (documented known-limitation; strip the misleading whitelist guidance).

## Decisions (LOCKED — 2nd design review folded)
- **D-B1 = MSYS tree cleanup + tempfile capture (POSIX path UNCHANGED).** Do NOT rewrite POSIX `timeout -k` (regression risk for the 26 timeout tests). MSYS-only Windows-native `taskkill //F //T` via `/proc/<pid>/winpid` (target the bounded wrapper tree while attributable; preserve 124/137). ADD tempfile capture at `ffhc_run_bounded` + the conflict reporter so the parent `$(…)` can't starve even if cleanup races. Preserve the `ffhc_*` API.
- **D-B2 = core fix (deterministic 124) + narrowed reclassification as defense** (no `FAIL:` + no strict pass + `rc==124||rc>=128` → `HOOK_TESTS_INCONCLUSIVE`/`PARTIAL_UNVERIFIED`; genuine crash stays BROKEN).
- **D-VALIDATION = local RED-then-GREEN + consumer-gated public tag.** A LOCAL repro EXISTS (Codex reproduced it on MINGW64: a *native* descendant via `cmd //c start //b ...` survives POSIX timeout and holds the pipe; plain bash `sleep` descendants do NOT). Add a **deterministic native-descendant test with a short finite sleep** (RED is late-but-bounded, never an infinite suite hang) → RED-then-GREEN. Plus: the 26 timeout tests + full suite green here. **The public `v3.30.2` tag is GATED on at least one real consumer pre-release re-run** of the verification prompt confirming B is fixed — design + local suite is enough for a *candidate*, not for the public tag (field evidence overturned the 1st review). Ship as a reviewed candidate; operator runs the prompt in an affected project; on PASS, cut the tag.
- **D-B3/B4/B5:** `--skip-hook-tests` alias to `--fast` (now reliable once B-core lands); upgrade progress echo; PATCH `v3.30.2`.

## Acceptance criteria
- **AC-A** (kept) secret-patterns.yml edit not blocked; real secret in a normal file still blocks; fixtures 10/11 PASS; test attached.
- **AC-B1** A bounded op whose **native** descendant holds the captured pipe open TERMINATES at the deadline (no infinite `$(…)` block) and the bounded-process tree is reaped (no runaway). RED-then-GREEN via the native-descendant repro (short finite sleep). AC3d hard assertion still passes on all platforms. (Claim scoped to the bounded *diagnostic* process tree — not detached/session-escaped helpers outside the monitored contract.)
- **AC-B-core-safety** `ffhc_*` API + rc semantics UNCHANGED; the 26 timeout tests + full 182+ suite PASS on this host; no Linux/macOS regression.
- **AC-B2** signal-rc + no-FAIL + no-parse → `HOOK_TESTS_INCONCLUSIVE`/`PARTIAL_UNVERIFIED` (exit 4); genuine crash → BROKEN. RED-then-GREEN.
- **AC-B3** `--fast`/`--skip-hook-tests` skip hook tests → non-BROKEN, no spin.
- **AC-gate** preflight 0/0; check-module-size --all exit 0; mirror 0 drift; FR-07 clean.

## Tasks (finalize post-2nd-design-review)
- **T1 (A)** DONE (`83b15f5`) — re-attach the test + strip whitelist guidance + doc the gap.
- **T2 (B-core)** process-tree reap in `run-with-timeout.sh` per D-B1; nested-tree test.
- **T3 (B2)** narrowed reclassification (defense) + RED-then-GREEN test.
- **T4 (B3/B4)** `--skip-hook-tests` alias + upgrade progress echo.
- **T5 (docs/tests)** release notes; wire tests; no-regression; PreToolUse known-limitation doc.

## Risks
- **FR-07 `ffhc_*` core** — the prime risk; the change must be API/rc-preserving + a strict kill-superset + green on the 26 timeout tests. The 2nd Codex design review + the FuseBase impl review + the Codex final-validation review all gate it.
- **Can't repro the hang here** — mitigated by the strict-superset argument + consumer re-verification (D-VALIDATION). Do NOT claim "fixed" on local evidence alone; the deploy notes must say "validated by design + the 26 tests + consumer re-test."
- **MSYS `taskkill` portability** — guard strictly to MINGW*/MSYS*/CYGWIN*; fall back gracefully if `/proc/<pid>/winpid` or `taskkill` is absent (never hang, never error the bounded contract).
