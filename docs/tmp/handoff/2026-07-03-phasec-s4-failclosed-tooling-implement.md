# Implement handoff — Phase C Slice 4: fail-closed + robustness in tooling

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.6. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-10 (reproduce-before-fix), FR-22. **Synchronous; bound long runs; no runaways; STOP at gate; do NOT bump VERSION/push/tag/deploy.** ONE coherent commit stacked on the current HEAD (the Phase C S2 commit). NO protected paths (hooks/local/*.sh are non-`fusebase_flow_internals`) — no bootstrap approval needed. NEVER `--no-verify`.

## Findings (Phase C audit — M6/L12/L13; detail in tasks/wecmxwyrx.output + the slice-plan doc §Slice 4). Each is a fail-open / false-signal / crash — FR-10 reproduce-before-fix each.

## Scope — ONE commit
1. **M6 — preflight.sh false-clean (`|| true` swallows rc):** the skill-frontmatter check and the orphaned-approval-action check pipe a heredoc `python3 ... || true`, then test `$?` — but `|| true` has already reset rc to 0, so these checks can NEVER increment `errors`/affect the exit code. REPRODUCE: introduce a malformed skill frontmatter (or an orphaned approval action) and confirm preflight currently exits 0 (false-clean). FIX: drop the `|| true` and test the heredoc python's rc directly (e.g. `if ! python3 - <<'PY' ... PY; then errors=$((errors+1)); fi`) at BOTH sites, or capture rc before any `||`. Prove: same malformed input now makes preflight exit nonzero / increments errors.
2. **L12 — health engine mislabels INCONCLUSIVE as BROKEN:** in the hook-tests branch, a completed `run-tests.sh` that contains visible `INCONCLUSIVE:` rows (e.g. the cli-flow-recovery bound-hit, or the FF_SKIP_CLI_RECOVERY escape) is misread as BROKEN "crashed ... no parsable result" (false diagnosis — the very escape the engine recommends trips this). REPRODUCE: feed the engine a run-tests output with a present strict summary line + `^INCONCLUSIVE:` rows and confirm it currently says BROKEN. FIX: before the rc!=0 crash guard, detect `^INCONCLUSIVE:` rows (or a present strict `[run-tests] N/N PASS`/summary line) in the captured output and route to LOCAL_UNVERIFIED ("hook tests inconclusive on this host"), NOT BROKEN. Preserve the genuine-crash path (rc!=0 AND no summary AND no INCONCLUSIVE ⇒ still BROKEN). Do NOT weaken the fail-closed BROKEN-on-real-crash behavior.
3. **L13 — verify-gate.sh crashes from a subdirectory:** it computes `ROOT` but reads the policy CWD-relative, so running it from any subdir throws a Python traceback. REPRODUCE: `cd hooks && bash ../hooks/local/verify-gate.sh` (or wherever it lives) → traceback. FIX: add `cd "$ROOT" || exit 1` after computing ROOT (matching preflight.sh), or pass the absolute `$POLICY` into the python as argv. Prove: runs clean from a subdir.

## Do NOT
Do NOT weaken any fail-closed behavior — these fixes make checks MORE fail-closed (M6 restores the error path; L12 keeps real-crash=BROKEN while fixing the false-BROKEN; L13 is a crash fix). Do NOT touch protected paths / pre-commit chain / handlers. Do NOT bump VERSION/push/tag. Do NOT `--no-verify`.

## Gate (scoped) — stop, report, HALT
FR-10 reproduce evidence for all 3 (RED on the prior HEAD → GREEN). Run the health-check-timeout suite (FF_ONLY=health-check-timeout) + preflight (green, and prove the M6 error-path now fires on malformed input then revert the test input) + verify-gate from a subdir (clean). `bash -n` the changed scripts; `py_compile` any changed python; SINGLE mirror --check 0-drift; check-module-size --all exit 0. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: commit SHA; the 3 fixes with FR-10 RED→GREEN evidence (M6 preflight now fails on malformed frontmatter/orphaned-approval; L12 INCONCLUSIVE→LOCAL_UNVERIFIED not BROKEN while real-crash still BROKEN; L13 runs clean from subdir); confirmation no fail-closed behavior weakened; scoped-gate numbers; mirror/module-size clean; VERSION unchanged. Do NOT push/tag/deploy.
