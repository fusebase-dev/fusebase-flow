# Implement handoff — v3.30.3 Group 1: WS2-core (bounded-run winpid scoping) + WS3 (harness reap)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.2. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07, FR-22, FR-25, FR-27. **Synchronous; bound every long run (host CPU-saturated ~30+ bash.exe from other sessions), read results from files, leave NO runaways; stop at the gate; do NOT bump VERSION/push/tag.**

## COMMENT POLICY (FR-22)
Tripwire + retrieval-pointer comments only. At done emit `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-27.
2. `docs/specs/windows-msys-hardening/roadmap.md` — the "Codex doc-review — FOLDED" block is AUTHORITATIVE; WS2 + WS3 sections. Note **F-a**: WS2-core strict recorded-winpid scoping is the prerequisite for WS3; Job Object is NOT in this group (v3.30.4).
3. `hooks/local/lib/run-with-timeout.sh` (`ffhc_run_bounded`, `ffhc_msys_winpid`, `ffhc_msys_taskkill_winpid`, `ffhc_msys_wait_reap`, `_ffhc_tempfile_capture`, `run_with_timeout`, `ffhc_timed_out`), `hooks/local/lib/bounded-run.sh`.
4. `hooks/tests/run-tests.sh` (the `$(...)` captures ~`:100/:129/:158`, fixture loop `:32/:55/:59`, `run_exitcode_phase`/`test-cli-flow-recovery` `:194/:204`), `hooks/local/mirror-skills.sh` (no argv handling `:21`; `: > MANIFEST` `:35`; `>> append` `:153`; Phase-3 per-file forks `:140-154`), `hooks/tests/test-msys-tree-cleanup.sh`, `hooks/tests/test-liveness-bounded-run.sh`.

## Scope — one task = one commit.

- **T1 (WS2-core) — strict recorded-winpid scoping + true-rc-on-kill + no-hang.** In `run-with-timeout.sh`:
  - The MSYS taskkill must reap **ONLY the bounded command's own recorded child winpid subtree** — capture the child winpid at launch (already done); before `taskkill //F //T //PID <winpid>`, **assert the winpid still maps to the expected child** (guard Windows PID-reuse: verify via `/proc/<child_pid>/winpid` still equals the recorded winpid AND the child is still our descendant); **NEVER kill an ancestor** and NEVER a lazy/broad fallback. If the winpid can't be re-verified, do NOT taskkill (log + skip) rather than risk collateral. (This fixes the over-broad 255-collateral that reaps the caller/harness/other sessions.)
  - Ensure `run_with_timeout`/`ffhc_run_bounded` return a **true 124 (deadline) / 137 (kill-after-grace) on an MSYS kill — never 0** (this is the real fix for the health-check false-BROKEN `rc0-on-kill` path). Ensure **no hang with a large budget** (the watchdog + child rendezvous must complete; bound it).
  - **Preserve:** the `ffhc_*` API surface, POSIX `run_with_timeout` **byte-identical**, rc semantics (124/137), and the existing MSYS tempfile-capture behavior.
  - **Test:** add a **concurrent-sibling-survival** assertion (spawn an unrelated `bash -c 'sleep 20'` sibling in its own tree, run a bounded op that times out, assert the sibling PID SURVIVES the taskkill — a bounded kill reaps only its recorded child); plus true-124-on-kill + no-hang-on-large-budget. RED-then-GREEN where reproducible on this host; else a documented behavior test.
- **T2 (WS3) — harness reuses the reap + bounds heavy phases + real `--check` + Phase-3 batch.**
  - `run-tests.sh`: replace the raw `$(...)` captures in `run_shell_phase` (`:154-172`), module-size (`:100`), health-check (`:129`), and the fixture loop with **`ffhc_run_bounded`** (tempfile capture + the T1 reap; read `FFHC_LAST_OUT`/`FFHC_LAST_RC`). Add an **MSYS `trap … EXIT` reaper that taskkills ONLY the harness's own recorded child winpids** (accumulate them; never a broad taskkill — depends on T1 strict scoping). **Bound** `test-cli-flow-recovery` via `ffhc_run_bounded "${FF_CLI_RECOVERY_TIMEOUT:-240}"` with an **`FF_SKIP_CLI_RECOVERY=1`** opt-out; report its rc124 as **INCONCLUSIVE** (not silent-green). **Flush per-phase progress** before each phase: `printf '[run-tests] starting %s\n' "$phase" >&2`.
  - `mirror-skills.sh`: add a **real `--check`** read-only mode (parse argv; in `--check`, do NOT `mkdir`/`cp`/rewrite the manifest — compare current files vs the committed manifest and `exit $((drift>0))`); keep default (write) behavior unchanged. **Batch Phase-3**'s per-file `$(dirname)`/`$(cache_hash)` into the same fork-free pass Phase-2 uses (reduce the MSYS 255-fork-storm).
  - **Test:** `timeout 900 bash run-tests.sh` reaches `Total: N/N`/exit 0 on this host (if the host is too loaded, prove each phase green via bounded per-phase runs + record 0 FAIL); the EXIT-trap reaps only recorded children (reuse the T1 sibling-survival assertion); `mirror-skills.sh --check` is read-only (no mkdir/cp; exit nonzero on injected drift); `FF_SKIP_CLI_RECOVERY=1` skips the heavy phase.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet-governance.yml. Preserve `ffhc_*` API + rc(124/137) + POSIX `run_with_timeout` byte-identical. `--check` is additive (default behavior unchanged). NEVER a broad taskkill (recorded-child-winpid only). Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ POSIX run_with_timeout byte-identical  ☐ ffhc_* API + rc(124/137) intact  ☐ taskkill scoped to recorded child winpid only (no ancestor/broad)
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n` the changed shells · run-tests PASS incl. new tests + the 26 timeout tests (bounded; prove each phase 0-FAIL) · check-module-size --all exit 0 · **mirror 0 drift — verify the manifest is raw==unique==86, 0 dups BEFORE trusting it (do NOT run concurrent mirrors; the real check is a single `mirror-skills.sh --check`)** · POSIX byte-equivalence reconfirmed · FR-07 clean. Emit the FR-22 marker. Produce the gate report; HALT. A FuseBase + Codex adversarial review runs after the gate.

## Return
Gate report: per-task SHAs (T1/T2), AC evidence (T1 concurrent-sibling-survives + true-124-on-kill + POSIX byte-identical; T2 run-tests completes-or-per-phase-green + EXIT-trap recorded-only + real read-only `--check` + bounded recovery + flushed progress + Phase-3 batch), no-regression (26 timeout tests, ffhc_* API), gate numbers, FR-07 confirmation. Do NOT push/tag.
