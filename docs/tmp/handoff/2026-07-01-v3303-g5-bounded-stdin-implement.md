# Implement handoff — v3.30.3 Group 5: bounded-capture stdin inheritance (T17)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.2. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03, FR-05, FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated); no runaways; stop at the gate; do NOT bump VERSION/push/tag.** One task = one commit.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Why (root cause — found by the G4 adversarial review, verified by the PO)
The full `run-tests.sh` **fixture-handler phase fails on MSYS**: `_ffhc_tempfile_capture` (hooks/local/lib/run-with-timeout.sh) runs the bounded child BACKGROUNDED (`run_with_timeout … >"$_tf" 2>… &`). POSIX makes an async command's stdin default to `/dev/null` when not otherwise redirected — and this default OVERRIDES the caller's `< fixture` redirect that was applied to the `ffhc_run_bounded_stdout` FUNCTION call (run-tests.sh:103). So stdin-fed handlers read EMPTY stdin and return the default `allow` instead of the expected `deny` → deny-fixtures FAIL. This is PRE-EXISTING (byte-identical at baseline; reproduces there) and is the true root cause of the "run-tests never completes / fails on MSYS" field symptom (WS3's reap fixed hangs, not this). Production hooks are invoked by Claude Code directly (not via this bounded path), so runtime security is unaffected — but the release gate "run-tests PASS on MSYS" cannot be met until this is fixed.

## Mandatory reads
1. `hooks/local/lib/run-with-timeout.sh` — `_ffhc_tempfile_capture` (:194-223, esp. the backgrounded launch :205-209 and the FFHC_LAST_WINPID/CHILD_PID lifecycle), `ffhc_run_bounded`/`ffhc_run_bounded_stdout` (:235-249+). Note the T8 tempfile-SKIP tripwire and the T12 winpid/childpid clear — PRESERVE both.
2. `hooks/tests/run-tests.sh` — the fixture loop (:68-145), esp. the bounded call at :103 (`ffhc_run_bounded_stdout "$FF_PHASE_TIMEOUT" "$python_bin" "$HANDLERS_DIR/$handler" < "$fixture"`).
3. `hooks/tests/test-health-check-timeout.sh` (the engine tests that exercise `_ffhc_tempfile_capture` — must stay GREEN, incl. the tempfile-SKIP/rc125 path and HT8-HT11 fail-closed).

## Scope — one task = one commit

- **T17 — OPT-IN stdin inheritance for the bounded capture (fix the MSYS fixture-phase stdin loss WITHOUT changing behavior for existing non-stdin callers).**
  - In `_ffhc_tempfile_capture`, make the backgrounded child's stdin EXPLICIT (never rely on the async default):
    - **Default (existing callers — health-check engine): `< /dev/null`** on the backgrounded run — make the current implicit /dev/null guarantee EXPLICIT so a bounded command can never block on an inherited TTY and behavior is identical to today.
    - **Opt-in (stdin-fed callers): inherit the caller's fd 0** (e.g. `0<&0` on the backgrounded run) so a `< file` redirect on the wrapper call reaches the child.
  - Thread the mode via a module variable (e.g. `FFHC_CAPTURE_STDIN` default 0) set by a thin wrapper — do NOT change the positional signature of `_ffhc_tempfile_capture` used elsewhere. Add a stdin-inheriting bounded variant, e.g. `ffhc_run_bounded_stdin_stdout SECS CMD…` (stdout-only capture, stderr dropped — mirrors `ffhc_run_bounded_stdout`, which the fixture loop currently uses) that sets `FFHC_CAPTURE_STDIN=1` around the capture call and resets it after. Keep the belt-#2 liveness guarantee (tempfile capture, winpid/childpid reap) IDENTICAL on both paths.
  - Point the run-tests fixture loop (:103) at the stdin-inheriting variant so fixture handlers get their input under the bound on MSYS. No other run-tests change needed (the `< "$fixture"` stays).
  - **Preserve**: the T8 tempfile-can't-be-created ⇒ SKIP (rc125) tripwire; the T12 winpid+childpid set/clear; the no-binary SKIP policy; stdout-only capture semantics for the fixture parse.
  - **Tests**:
    - Extend `test-msys-tree-cleanup.sh` (or the fixture/handler tests): a bounded run of a stdin-fed command through the new variant RECEIVES its stdin — e.g. `printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | <stdin-variant> python3 hooks/handlers/pre_tool_use.py` yields `decision=deny` (NOT the empty-stdin `allow`). Prove the RED→GREEN: the old `ffhc_run_bounded_stdout` path returns empty/allow, the new stdin path returns deny.
    - A non-stdin bounded run (default path) still behaves exactly as before (bounded, stdout captured, `< /dev/null`, no hang) — an explicit assertion that the default path did not regress.
    - After both, `FFHC_LAST_WINPID` and `FFHC_LAST_CHILD_PID` are cleared on return (T12 invariant holds on both paths).
  - **AC — the real deliverable**: with T17, the full `run-tests.sh` fixture phase (the 16 `pre_tool_use` fixtures) returns the correct decisions under the bounded wrapper on MSYS (deny-fixtures DENY). Run the fixture phase end-to-end (bounded) and confirm 0 FAIL attributable to stdin. (Other phases already pass in isolation.)

## FR-07 / hard rules
`hooks/local/lib/run-with-timeout.sh` and `hooks/tests/run-tests.sh` are NOT protected paths. Do NOT touch `policies/**`, FR rows, the 3 deploy-policy semantics, ratchet, or the health-check verdict engine. Do NOT weaken the bounded/liveness guarantee (FR-27) — the tempfile capture + reap must remain on BOTH stdin paths. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ default (non-stdin) capture path byte-behavior unchanged (< /dev/null, no hang)
☐ stdin variant delivers stdin to the bounded child (deny-fixture DENIES)
☐ T8 SKIP tripwire + T12 winpid/childpid clear preserved on both paths  ☐ liveness (tempfile+reap) intact
☐ health-check-timeout suite (HT1-HT11, tempfile-SKIP) still GREEN  ☐ no --no-verify  ☐ commit cites T17
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n` on the 2 changed shells · run-tests: **the fixture phase now PASSES under the bounded wrapper on MSYS** (the T17 deliverable) + the new stdin/non-stdin tests + health-check-timeout suite GREEN, bounded per-phase 0-FAIL · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** · FR-27 no-runaways · FR-07 clean. Emit the FR-22 marker; produce the gate report; HALT. A final Codex re-review runs on the corrected diff before deploy.

## Return
Gate report: T17 SHA, AC evidence (RED→GREEN stdin-reaches-child deny-fixture + default-path-unchanged + fixture-phase-now-passes-bounded-on-MSYS), no-regression (health-check-timeout HT1-11 + tempfile-SKIP + ws2-* + T12 winpid/childpid clear still GREEN), gate numbers, FR-07 statement. Do NOT push/tag.
