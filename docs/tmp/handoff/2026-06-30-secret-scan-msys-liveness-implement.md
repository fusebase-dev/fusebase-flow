# Implement handoff — secret-scan-and-msys-liveness-fix

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.30.1. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07, FR-12 (secrets), FR-13, FR-22 (comments), FR-25, **FR-27 (liveness — bound/poll any long run)**. **Synchronous; stop at gate; do NOT bump VERSION/push/deploy.**

## COMMENT POLICY (FR-22) — any code you write
```
ONLY tripwire + retrieval-pointer comments. Remove WHAT-restating/recorded-elsewhere/changelog. Don't match density upward. Keep pointers.
```
At done emit `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-27 (stop at Amendment log).
2. `docs/specs/secret-scan-and-msys-liveness-fix/spec.md` — LOCKED (D-A1 python helper; D-B1 MSYS test-guard + DEFER core watchdog; D-B2 NARROWED predicate; D-B3/B4; D-B5 v3.30.2). Authoritative.
3. The files you change: `hooks/git/pre-commit`, `hooks/shared/secret_scanner.py` (read — do NOT change its `scan()` semantics), `hooks/tests/test-liveness-bounded-run.sh`, `hooks/local/fusebase-flow-health-check.sh` (the hook-test classifier ~L400-449 + `--fast` ~L98), `hooks/local/upgrade.sh` (the silenced Step 2 re-mirror ~L346), `hooks/tests/fixtures/{10,11}_*`, run-tests wiring.

## Scope — one commit per task. No new exit-1 path beyond what already exists; preserve FFHC verdict ENUM + exit codes.

- **T1 (A) — pre-commit secret scan: `+`-only + path-exclude, via a Python helper.**
  - Add a small Python helper (e.g. a function in a new `hooks/shared/staged_secret_scan.py`, or extend `pre-commit`'s inline python) that: takes the staged diff, keeps ONLY added (`+`) content lines (drop `-`, `@@`, `+++`, `---`), **excludes** `policies/secret-patterns.yml` + `policies/secret-patterns.local.yml` + `hooks/tests/fixtures/` (build the diff with `git diff --cached -U0 -- . ':(exclude)policies/secret-patterns.yml' ':(exclude)policies/secret-patterns.local.yml' ':(exclude)hooks/tests/fixtures/'`), then calls `secret_scanner.scan(...)` on the joined added text. **Do NOT change `scan()` semantics** (fixtures 10/11 call it directly → must stay green).
  - Strip the misleading "add a whitelist entry" guidance from the pre-commit BLOCK message + the header bypass note (`pre-commit:~11,~51`) — recommend unstaging/rotating, NOT whitelisting fixture tokens (that's the trap).
  - Document the deliberate excluded-file gap (a real secret added to one of those designed-token files won't be caught by pre-commit) in a tripwire comment + the health-check/compat docs as appropriate.
- **T2 (B1) — MSYS test-guard (DEFER the core watchdog).** In `test-liveness-bounded-run.sh`, gate the assertion(s) that force a hard `timeout -k` SIGKILL of a TERM-ignoring native child (AC3d at `:69`, and any sibling that does the same) behind `case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*)` → print a VISIBLE skip line ("SKIPPED on MSYS — OS may not reap a native child via POSIX SIGKILL"; count it as a skip, NOT a false PASS, following the file's existing skip precedent) and continue. Keep the full hard-SIGKILL (rc 137) assertion on Linux/macOS. Do NOT touch `run-with-timeout.sh` / the `ffhc_*` core (the Windows-native `taskkill` watchdog is DEFERRED — file a backlog note).
- **T3 (B2) — health-check narrowed reclassification (BLOCKER fix).** At `fusebase-flow-health-check.sh:~406-410`: reclassify the hook-test sub-run to a NEW advisory `HOOK_TESTS_INCONCLUSIVE` mapped to the EXISTING `PARTIAL_UNVERIFIED` verdict (exit 4) ONLY when **no `FAIL:` line AND no strict single `N/N PASS` AND (`HOOK_TEST_RC == 124` OR `HOOK_TEST_RC >= 128`)**. Every other rc≠0-no-result case (`1..123`, `125..127`, or `rc==0` malformed/no-pass) STAYS `LOCAL_BROKEN` (exit 2). Surface the 11 substantive checks in the INCONCLUSIVE case. Preserve the verdict ENUM + exit codes (reuse PARTIAL_UNVERIFIED; no new verdict).
- **T4 (B3/B4).** `--skip-hook-tests` as an alias to the existing `--fast` (help text: "skips hook tests; partial verdict, exits 4"). In `upgrade.sh`, add a one-line progress echo before/after the silenced Step 2 re-mirror (`mirror-skills.sh`/`mirror-agents.sh`, `:346-347`) and before `sync-version-strings` so a slow step is observably progressing (do NOT un-silence the full output; just bracket it).
- **T5 (tests + code-adjacent docs).** Tests: AC-A1 (a staged edit to `secret-patterns.yml` that adds AND removes example tokens → pre-commit does NOT BLOCK on the secret step; a real secret on a `+` line in a NORMAL file STILL blocks; a removed `-` secret in a normal file does not), AC-A2 (no whitelist added; fixtures 10/11 still PASS), AC-B1 (AC3d visibly skipped on MSYS; hard assertion intact on Linux/macOS — assert the skip is counted/visible, not false-green), AC-B2 (signal-like rc + no FAIL: → INCONCLUSIVE/exit 4; a genuine crash rc 1..123 + no FAIL: → BROKEN/exit 2 — **RED-then-GREEN on both**). Wire into run-tests.sh. Code-adjacent docs: the `--skip-hook-tests`/`--fast` Windows escape + the PreToolUse known-limitation note in the health-check skill / compatibility doc. Release notes + spec/backlog→DONE are the DEPLOY commit. No-regression: 182+ suite + 26 timeout tests + FFHC `ffhc_*` API/verdict/exit intact.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / the 3 deploy-policy rule semantics / ratchet-governance.yml. **Do NOT modify `run-with-timeout.sh` / the `ffhc_*` API** (B1 is a test-guard only; the core watchdog is deferred). The pre-commit must STILL block real secrets (+ lines, non-excluded files) + protected-path edits. Preserve the FFHC verdict ENUM + exit codes (B2 reuses PARTIAL_UNVERIFIED). Do NOT bump VERSION/push/deploy.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ FR-22 comments  ☐ FR-25 <ceiling  ☐ pre-commit still blocks real secrets + protected paths  ☐ run-with-timeout.sh/ffhc_* UNCHANGED
☐ FFHC verdict enum + exit codes intact  ☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n pre-commit test-liveness-bounded-run.sh fusebase-flow-health-check.sh upgrade.sh` + `python -m py_compile` the new helper · run-tests PASS incl. new + updated + the 26 timeout tests · check-module-size --all exit 0 · mirror 0 drift · FR-07 clean · confirm `run-with-timeout.sh` is byte-unchanged. Emit the FR-22 marker. Produce the gate report; HALT. A FuseBase adversarial review then a Codex final-validation review run after the gate.

## Return
Gate report: per-task SHAs (T1–T5), AC evidence (A: secret-patterns.yml edit not blocked + real secret still blocked + fixtures 10/11 green, RED-then-GREEN; B1: AC3d visibly skipped on MSYS + hard assertion intact elsewhere; B2: signal-rc→INCONCLUSIVE exit 4 AND genuine-crash→BROKEN exit 2, RED-then-GREEN; B3/B4), no-regression (182+/26-timeout, run-with-timeout.sh unchanged, verdict enum/exit intact), gate numbers, FR-07 confirmation. Do NOT push/deploy.
