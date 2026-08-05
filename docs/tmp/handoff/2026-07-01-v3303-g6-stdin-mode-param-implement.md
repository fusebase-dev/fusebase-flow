# Implement handoff — v3.30.3 Group 6: make bounded-capture stdin-mode an explicit parameter (T18)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.2. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03, FR-05, FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated); no runaways; stop at the gate; do NOT bump VERSION/push/tag.** One task = one commit. This is the LAST correction before the v3.30.3 deploy (found by the final Codex re-review of the corrected diff).

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Why (final Codex re-review finding — HIGH on T17, verified by the PO)
T17 (commit `cb1d15f`) made `_ffhc_tempfile_capture` (hooks/local/lib/run-with-timeout.sh) branch on the AMBIENT module global `FFHC_CAPTURE_STDIN` (:212). The stdin wrapper `ffhc_run_bounded_stdin_stdout` sets it =1 then resets =0 (:291-292), so there is no intra-shell leak. BUT the DEFAULT wrappers `ffhc_run_bounded` (:258) and `ffhc_run_bounded_stdout` (:273) call `_ffhc_tempfile_capture` WITHOUT forcing the mode — so an externally EXPORTED / stale / adversarial `FFHC_CAPTURE_STDIN=1` in the environment flips the default path to `0<&0` (inherit) instead of the guaranteed `</dev/null`. Liveness is still bounded (timeout/tempfile), but a stdin-reading command on the default path could block until the deadline instead of getting immediate EOF — violating the stated "default path is behavior-identical / explicit `</dev/null`" guarantee. The set/reset dance is also fragile if the wrapper is interrupted between :291 and :292.

## Mandatory reads
1. `hooks/local/lib/run-with-timeout.sh` — `_ffhc_tempfile_capture` (:194-242, esp. the stdin branch :212-224), the 3 wrappers `ffhc_run_bounded` (:254-264), `ffhc_run_bounded_stdout` (:269-279), `ffhc_run_bounded_stdin_stdout` (:287-298).
2. `hooks/tests/test-msys-tree-cleanup.sh` — the T17 tests (`t17-stdin-reaches-child`, `t17-default-path-unchanged`, `t17-stdin-path-t12-clear`) to extend.

## Scope — one task = one commit

- **T18 — replace the ambient `FFHC_CAPTURE_STDIN` global with an explicit stdin-mode PARAMETER of `_ffhc_tempfile_capture`.**
  - Change the `_ffhc_tempfile_capture` signature to take stdin-mode as an explicit positional arg (e.g. `_ffhc_tempfile_capture STDERR_MODE STDIN_MODE SECS CMD...` where STDIN_MODE ∈ `null` | `inherit`). Select the redirect from the PARAM, not from any ambient global. Remove ALL reads of `FFHC_CAPTURE_STDIN` and the set/reset dance in the stdin wrapper.
  - Update the 3 call sites to pass the mode explicitly:
    - `ffhc_run_bounded` → `_ffhc_tempfile_capture merge null "$secs" "$@"`
    - `ffhc_run_bounded_stdout` → `_ffhc_tempfile_capture drop null "$secs" "$@"`
    - `ffhc_run_bounded_stdin_stdout` → `_ffhc_tempfile_capture drop inherit "$secs" "$@"`
  - Net effect: the DEFAULT path can NEVER take the inherit branch regardless of the environment; the stdin path is selected ONLY by the dedicated wrapper. No ambient global, no reset fragility.
  - **Preserve everything else IDENTICALLY**: the T8 tempfile-can't-create⇒SKIP(rc125) tripwire, the T12 winpid+childpid set/clear-on-return, the belt-#2 tempfile capture + reap (FR-27 liveness), stdout-only vs merge capture semantics, the no-binary SKIP policy. Only the stdin-mode selection mechanism changes.
  - **Tests** (extend `test-msys-tree-cleanup.sh`):
    - Keep the existing T17 RED→GREEN (stdin variant delivers stdin; default variant does not).
    - **NEW (the T18 fix):** with `FFHC_CAPTURE_STDIN=1` EXPORTED in the environment, a DEFAULT `ffhc_run_bounded_stdout` call STILL uses `</dev/null` (a stdin-reading command gets EOF, NOT the caller's fd 0) — proving the default path no longer honors the ambient global. (After T18 the var is dead; assert the default path is immune to it.)
    - Default-path-no-hang and T12 winpid/childpid-clear invariants still hold on all paths.
  - **AC**: the full run-tests fixture phase still passes bounded on MSYS (16/16 correct decisions — T17 deliverable preserved), and the default bounded path is now provably immune to an exported `FFHC_CAPTURE_STDIN`.

## FR-07 / hard rules
`hooks/local/lib/run-with-timeout.sh` + `hooks/tests/**` are NOT protected paths. Do NOT touch policies/**, FR rows, the 3 deploy-policy semantics, ratchet, or the health-check verdict engine. Do NOT weaken FR-27 liveness (tempfile capture + reap identical). Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ default path immune to exported FFHC_CAPTURE_STDIN (uses </dev/null unconditionally)
☐ stdin path (dedicated wrapper) still delivers fd 0  ☐ FFHC_CAPTURE_STDIN global fully removed
☐ T8 SKIP tripwire + T12 winpid/childpid clear + belt-#2 liveness preserved  ☐ no --no-verify  ☐ commit cites T18
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n` on the changed shell(s) · run-tests: fixture phase still passes bounded on MSYS + the new default-path-immune-to-exported-flag test + health-check-timeout GREEN (bounded, per-phase 0-FAIL) · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** · FR-27 no-runaways · FR-07 clean. Emit the FR-22 marker; produce the gate report; HALT.

## Return
Gate report: T18 SHA, AC evidence (default-path-immune-to-exported-FFHC_CAPTURE_STDIN + stdin-path-still-delivers + fixture-phase-still-passes-bounded), no-regression (T17 tests + T8 SKIP + T12 clear + health-check-timeout still GREEN), gate numbers, FR-07 statement. Do NOT push/tag.
