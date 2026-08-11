# Fix handoff (v3 — review findings) — secret-scan-and-msys-liveness-fix

> Codex final-validation = DO-NOT-SHIP. Fix the BLOCKER + MEDIUM + LOW below on top of HEAD `1c762cc`, then re-gate. Candidate only — do NOT bump VERSION/push/tag.

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.30.1. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07, FR-22, FR-25, FR-27. **Synchronous; stop at gate; do NOT bump VERSION/push/tag.** Host is MINGW64 (MSYS tests run here). Host is CPU-loaded — bound long runs, read results from files, no runaways.

## COMMENT POLICY (FR-22)
Tripwire + retrieval-pointer comments only. At done emit `comment-policy review: applied (FR-22)`.

## Context
The candidate (HEAD `1c762cc`) passed the implement gate + FuseBase review (POSIX byte-equiv ✓, MSYS hang fixed/proven ✓, secret-scan ✓), but Codex final-validation found:
- **[BLOCKER]** B2 predicate omits the "no strict PASS" guard → a crash-after-PASS (signal rc, no FAIL:) is masked as INCONCLUSIVE instead of BROKEN.
- **[MEDIUM]** MSYS tree-kill reads `/proc/<pid>/winpid` AFTER the deadline, racing the wrapper exit → `taskkill` can no-op → native runaway survives (hang still fixed by tempfile capture, but reap not guaranteed).
- **[LOW]** tempfile fallback: if temp creation/redirect fails, the bounded cmd may not run + returns empty/nonzero (reads as a crash); `mktemp` without a template can drop files in CWD.

## Mandatory reads
1. `docs/specs/secret-scan-and-msys-liveness-fix/spec.md` (D-B2 requires no-FAIL: + **no strict N/N PASS** + rc==124||rc>=128).
2. `hooks/local/fusebase-flow-health-check.sh` around `:400-449` (the hook-test classifier + `HOOK_TEST_PASS_LINE`/`HOOK_TEST_OUTPUT`/`HOOK_TEST_RC` vars).
3. `hooks/local/lib/run-with-timeout.sh` (`ffhc_msys_tree_kill`, `ffhc_msys_wait_reap`, `_ffhc_tempfile_capture`, `ffhc_run_bounded`).
4. `hooks/tests/test-health-check-timeout.sh`, `hooks/tests/test-msys-tree-cleanup.sh`.

## Scope — one commit per task.

- **T6 (BLOCKER) — B2 must require no strict PASS.** At `fusebase-flow-health-check.sh:~407`, add `[ -z "$HOOK_TEST_PASS_LINE" ]` to the INCONCLUSIVE branch so the FULL predicate is: **no `FAIL:` AND no strict `N/N PASS` AND (`rc==124 || rc>=128`) → `HOOK_TESTS_INCONCLUSIVE`/PARTIAL_UNVERIFIED/exit 4**; otherwise (incl. **strict PASS + signal rc + no FAIL:**) → `LOCAL_BROKEN`/exit 2. Add a regression test in `test-health-check-timeout.sh`: `HOOK_TEST_OUTPUT` containing a strict `N/N PASS` line + `rc=143` + no `FAIL:` → **BROKEN/exit 2** (RED on current code, GREEN after). Keep the existing `b2-signal-inconclusive` (no-PASS + rc 143 → exit 4) + `b2-genuine-crash-broken` (rc 3 → exit 2) green.
- **T7 (MEDIUM) — capture the MSYS winpid BEFORE the deadline.** Restructure the MSYS bounded path so the bounded command's (or its wrapper's) Windows pid is resolved via `/proc/<pid>/winpid` **immediately after launch, while it is alive** (not after `timeout` returns). On timeout, `taskkill //F //T //PID <captured_winpid>` (output suppressed) to reap the tree. Keep the graceful no-op fallback (no winpid/taskkill → no-op). Be HONEST in a tripwire comment that this is **best-effort** — a descendant that has been reparented/detached after the ancestor exited may still survive (Windows doesn't reparent to init); the tempfile capture is the guaranteed anti-hang, tree-kill is best-effort anti-runaway. Update `test-msys-tree-cleanup.sh` if it asserted guaranteed reap → assert "no hang + rc 124 + best-effort reap (no assertion-failure if a reparented orphan lingers)". Preserve the `ffhc_*` API + rc 124/137 + POSIX path byte-equivalence.
- **T8 (LOW) — robust tempfile.** Use an explicit `"${TMPDIR:-/tmp}/ffhc-bounded.$$.XXXXXX"` template for `mktemp`; if temp creation OR the redirect fails, route the bounded result to a clear **UNVERIFIED/skipped** signal (NOT an empty/crash that reads as BROKEN) — never hang. No transient files in CWD.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet-governance.yml. POSIX `run_with_timeout` path stays byte-equivalent (T7 only touches the MSYS branch + the early-capture plumbing). Preserve `ffhc_*` API + rc(124/137) + verdict ENUM + exit codes (0/2/3/4). Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ POSIX path byte-equivalent  ☐ ffhc_* API + rc(124/137) + verdict enum/exit intact
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n` changed shells + `py_compile` (if touched) · the new B2 `PASS+rc143→BROKEN` test RED-then-GREEN · `test-health-check-timeout.sh` all green (incl. all 3 B2 cases) · `test-msys-tree-cleanup.sh` green (no-hang + rc 124) · run-tests PASS (bound it; host loaded) · check-module-size --all exit 0 · mirror 0 drift · POSIX byte-equivalence reconfirmed · FR-07 clean. Emit the FR-22 marker. Produce the gate report; HALT. A Codex re-validation of the BLOCKER + MEDIUM fixes runs after the gate.

## Return
Gate report: per-task SHAs (T6–T8), AC evidence (T6 PASS+signal-rc→BROKEN RED-then-GREEN + the 3 B2 cases green; T7 winpid captured pre-deadline + best-effort reap documented + POSIX byte-equiv; T8 robust tempfile + fail-to-UNVERIFIED), gate numbers, FR-07 confirmation. Do NOT push/tag.
