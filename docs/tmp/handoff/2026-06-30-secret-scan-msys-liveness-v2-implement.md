# Implement handoff (v2 — REPLACES the stale v1) — secret-scan-and-msys-liveness-fix

> The v1 handoff (`...-secret-scan-msys-liveness-implement.md`) is STALE — it said "MSYS test-guard + DEFER core; run-with-timeout.sh unchanged." Field evidence overturned that. Use THIS v2. Current HEAD is `83b15f5` (T1 secret-scan fix, kept).

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.30.1. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03, FR-05 (stop at gate), FR-07, FR-12, FR-22, FR-25, **FR-27 (liveness)**. **Synchronous; stop at gate; do NOT bump VERSION/push/tag/deploy.** This ships as a CANDIDATE — the public tag is later gated on a consumer pre-release re-run (D-VALIDATION), so do NOT tag.

## COMMENT POLICY (FR-22)
ONLY tripwire + retrieval-pointer comments. At done emit `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-27.
2. `docs/specs/secret-scan-and-msys-liveness-fix/spec.md` — LOCKED (read "Root-cause correction", "B-core", "Decisions", "D-VALIDATION"). Authoritative.
3. `hooks/local/lib/run-with-timeout.sh` (esp. `run_with_timeout` `:65-69`, `ffhc_run_bounded` `:81-92`/the `$(…)` capture at `:85`), `bounded-run.sh`. `hooks/local/fusebase-flow-health-check.sh` (`:98` `--fast`, `:391-410` hook-test classify, `:460` conflict-reporter `$(…)`). `hooks/tests/test-health-check-timeout.sh`, `hooks/tests/run-tests.sh`.
4. This host is MINGW64/Git-Bash — `uname -s` is `MINGW*`. The native-descendant repro (below) REPRODUCES here, so the B-core test is genuine RED-then-GREEN here.

## Root cause (confirmed by 2 consumers + Codex local repro)
`run_with_timeout`=`timeout -k`. On MSYS a NATIVE/escaped descendant (not a plain bash `sleep`) survives POSIX timeout cleanup and keeps the captured-stdout pipe open, so a bounded op read via `$(…)` blocks past the deadline → hang + runaway native processes (B1), and the un-reaped run surfaces an unrecognized rc → non-deterministic false `BROKEN` (B2). POSIX bash descendants are reaped fine — **do not touch the POSIX path.**

## Scope — one commit per task.

- **T1b (A — finish the kept secret-scan fix).** T1 (`83b15f5`) already fixed `pre-commit` (`+`-only + path-exclude via a Python helper). Now: commit the secret-scan regression test (`hooks/tests/test-secret-scan-staged.sh`, currently untracked — verify it asserts: a staged `secret-patterns.yml` edit adding AND removing fake tokens is NOT blocked; a real secret on a `+` line in a NORMAL file IS blocked; fixtures 10/11 still PASS), strip the misleading "add a whitelist entry" guidance from the `pre-commit` BLOCK message + header, and document the deliberate excluded-file gap + the PreToolUse known-limitation (agent writing full secret-patterns.yml content) in a tripwire comment + `docs/compatibility.md`.
- **T2 (B-core) — MSYS tree cleanup + tempfile capture. POSIX UNCHANGED.**
  - In `run-with-timeout.sh`: **leave the POSIX `timeout -k` path byte-equivalent.** ADD an MSYS-only branch (`case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*)`): after the bounded command hits the deadline/grace, resolve its Windows pid via `/proc/<child_pid>/winpid` and run `taskkill //F //T //PID <winpid>` with stdout+stderr suppressed, to reap native/escaped descendants. Target the bounded command/wrapper tree **while attributable** (you must launch the bounded cmd so you hold its pid — e.g. background it, capture `$!`, enforce the deadline, then group/tree-kill — OR keep `timeout` and additionally `taskkill //T` the timeout child's tree before `timeout` exits). Preserve rc semantics: **124 on deadline, 137 on force-after-grace.** Graceful fallback: if `/proc/<pid>/winpid` or `taskkill` is unavailable, behave exactly as today (never error, never hang the bounded contract). Do NOT change the `ffhc_*` API signatures.
  - **Tempfile capture (belt #2, all platforms):** change `ffhc_run_bounded` (`:85`) and the conflict-reporter capture (`fusebase-flow-health-check.sh:460`) to redirect the bounded process's stdout/stderr to a temp file, `wait` for the bounded process, then read the file into the variable — instead of `VAR=$(run_with_timeout …)`. This stops the parent starving on a pipe a descendant holds even if the tree-kill races. Keep the captured value + rc identical to today on the success path.
  - **Test (RED-then-GREEN, MSYS-gated):** add a `hooks/tests/` case that, on `MINGW*|MSYS*|CYGWIN*`, runs a bounded op whose **native** descendant holds stdout open with a SHORT FINITE sleep (e.g. `bash -c 'cmd //c start //b cmd //c "ping -n 8 127.0.0.1 >NUL" & sleep 12'` captured via the bounded helper, deadline ~1-2s) and asserts the capture RETURNS within (deadline+grace+epsilon, e.g. ≤4s) with rc 124 — proving the descendant was reaped (pre-fix it would block ~8-12s → RED). Off MSYS: visible SKIP (not false-green). Keep it bounded so a failure is late-but-finite, never an infinite suite hang.
- **T3 (B2 defense).** `fusebase-flow-health-check.sh:406-410`: reclassify to advisory `HOOK_TESTS_INCONCLUSIVE` → existing `PARTIAL_UNVERIFIED` (exit 4) ONLY when no `FAIL:` + no strict `N/N PASS` + (`HOOK_TEST_RC==124 || HOOK_TEST_RC>=128`); a genuine crash (`rc 1..123/125..127` or `rc==0` malformed) STAYS `LOCAL_BROKEN` (exit 2). Reuse PARTIAL_UNVERIFIED (no new verdict). RED-then-GREEN incl. a "genuine crash stays BROKEN" case.
- **T4 (B3/B4).** `--skip-hook-tests` as an alias to existing `--fast` (help: skips hook tests, partial, exits 4). `upgrade.sh`: one-line progress echo bracketing the silenced Step 2 re-mirror + before `sync-version-strings`.
- **T5 (tests + code-adjacent docs).** Wire all tests into run-tests.sh. Health-check skill doc: `--skip-hook-tests`/`--fast` Windows escape. No-regression: the **26 timeout tests** + full 182+ suite PASS on this host; `ffhc_*` API + verdict ENUM + exit codes intact; **`run_with_timeout` POSIX behavior byte-equivalent** (diff shows only the added MSYS branch + tempfile capture). Release notes + spec/handoff→DONE are the DEPLOY commit.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet-governance.yml. Preserve the `ffhc_*` API + rc (124/137) + verdict ENUM + exit codes. POSIX `timeout -k` path UNCHANGED. pre-commit still blocks real secrets + protected paths. Do NOT bump VERSION/push/tag/deploy.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ POSIX timeout path byte-equivalent  ☐ ffhc_* API + rc(124/137) + verdict enum/exit intact  ☐ pre-commit still blocks real secrets
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n` the changed shells + `python -m py_compile` the helper · run-tests PASS incl. new + the 26 timeout tests · the B-core native-descendant test RED-then-GREEN on this MINGW host · check-module-size --all exit 0 · mirror 0 drift · confirm `run_with_timeout`'s POSIX path is byte-equivalent (only the MSYS branch + tempfile capture added) · FR-07 clean. Emit the FR-22 marker. Produce the gate report; HALT. A FuseBase adversarial review then a Codex final-validation review run after the gate; the public tag is then gated on a consumer pre-release re-run.

## Return
Gate report: per-task SHAs, AC evidence (A test + whitelist-guidance stripped; **B-core native-descendant RED-then-GREEN on this host** + POSIX byte-equivalent + tempfile capture; B2 INCONCLUSIVE-on-signal-rc AND BROKEN-on-genuine-crash; B3/B4), no-regression (26-timeout + 182+, ffhc_* API/rc/verdict intact), gate numbers, FR-07 confirmation. Do NOT push/tag/deploy.
