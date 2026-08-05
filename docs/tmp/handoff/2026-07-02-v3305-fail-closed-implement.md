# Implement handoff — v3.30.5 correction: FR-07 pre-commit must FAIL CLOSED (T25)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T25 EDITS a protected path — see note), FR-22, FR-27. **Synchronous; bound long runs (host saturated; pre-raise FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900 for any harness run); no runaways; stop at the gate; do NOT bump VERSION/push/tag.** This is a BLOCKER correction found by the Codex re-review of the v3.30.5 candidate. One task = one commit.

## PROTECTED-PATH NOTE (FR-07 — sanctioned, not a bypass)
T25 edits `hooks/git/pre-commit` (a `fusebase_flow_internals` protected path). Mint the SANCTIONED single-use digest-bound bootstrap approval FIRST (`bash hooks/local/write-bootstrap-approval.sh`), commit, then `--consume`. NEVER `--no-verify`.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the BLOCKER (verified by the PO against the code)
The v3.30.5 candidate (`5caec4d` T23 + `4edf0ce` T24) correctly extends FR-07 protected-path enforcement to deletes/renames AND the single-use exception relaxation is sound (verified). BUT the Codex re-review found the protected-path check **FAILS OPEN**: `hooks/git/pre-commit` §3 (lines ~60-63):
```
try:
    from shared.path_policy import evaluate, staged_change_paths
except Exception:
    sys.exit(0)     # <-- FAIL-OPEN: import error => FR-07 check SKIPPED, commit proceeds
```
If the import raises (a syntax error / missing dep introduced in the SAME commit, a broken path_policy, a tampered module), the entire protected-path check is silently bypassed (exit 0). A security control must FAIL CLOSED (block + tell the operator), never fail open. Also the outer gate `command -v python3` (line ~54) silently skips the check when python3 is absent.

## Mandatory reads
1. `hooks/git/pre-commit` §3 (:47-78) — the import try/except (:60-63), the outer `command -v python3` gate (:54), the `exit_proto` handling (:77). Note §1/§2 secret checks + §4 module-size + §5 lint + the `fusebase-flow-managed-hook: v1` marker + `set -uo pipefail` + exit-code contract must be preserved.
2. `hooks/shared/path_policy.py` (`evaluate`, `staged_change_paths`, `has_active_exception`) — confirm nothing here needs changing (the exception logic is already sound; the fix is in the pre-commit's failure handling).
3. `hooks/tests/test-bootstrap-exception.sh` — the T23 tests to extend.

## Scope — one task = one commit

- **T25 [BLOCKER] — the FR-07 protected-path check must FAIL CLOSED.**
  - In `hooks/git/pre-commit` §3, change the import failure handler from `except Exception: sys.exit(0)` to **fail closed**: print a clear stderr message and `sys.exit(1)` (BLOCK). Message e.g.: `[fusebase-flow:pre-commit] BLOCK — FR-07 protected-path check could not load path_policy (import error: <e>). Refusing to commit fail-open. Fix the module/env; NEVER use --no-verify.` Include the exception text so the operator can diagnose. (Any UNexpected python error inside the check body should ALSO fail closed — wrap the enumerate/evaluate in a try/except that exits 1 on error, not 0.)
  - **python3-absent gate (:54):** if there ARE staged changes but `python3` is unavailable, do NOT silently skip FR-07 — emit a LOUD WARNING to stderr that FR-07 could not be enforced (python3 required). Judgment: a hard block on missing python3 would brick commits in a python3-less environment, and the secret-scan §2 already requires python3; so a visible WARN (not silent skip, not hard block) is the right middle for the python3-absent case. If you judge fail-closed (block) is safer and consistent with the security posture, block WITH a clear "install python3 or fix the env" message — but do NOT leave it a SILENT skip. State which you chose and why in the gate report.
  - **Preserve:** §1/§2 secret checks (ACM), §4 module-size, §5 lint/typecheck, the managed-hook marker, `set -uo pipefail`, the overall exit-code contract, and the delete/rename coverage from T23 (staged_change_paths). Do NOT touch path_policy.py's exception logic (it's sound).
  - **Tests** (extend `test-bootstrap-exception.sh`): 
    - **import-fail-closed:** simulate an import failure (e.g. point PYTHONPATH so `shared.path_policy` raises, or a temp shim that raises on import) with a staged PROTECTED change → the pre-commit EXITS NONZERO (blocks), NOT 0. RED (current exits 0) → GREEN.
    - **python3-absent:** with `python3` masked out of PATH and a staged protected change → the hook emits the loud WARN (or blocks, per your choice) — NOT a silent exit 0 with no message.
    - Keep ALL existing T23 tests GREEN (protected delete/rename blocked, with-approval passes, non-protected passes, single-use not weakened, ACM + secret + legit-bootstrap unchanged).

## FR-07 / hard rules
Fail CLOSED for the security control. Do NOT weaken the single-use exception (unchanged). Preserve the delete/rename coverage + all §1/§2/§4/§5 behavior. Do NOT touch policies/**, other FR rows, deploy-policy semantics, ratchet, health-check verdict engine, bounded-run engine. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ import error ⇒ pre-commit EXITS 1 (fail closed, with diagnostic)  ☐ python3-absent ⇒ loud WARN/block (not silent skip)
☐ T23 delete/rename coverage + single-use + §1/§2/§4/§5 all preserved (existing tests GREEN)
☐ no --no-verify  ☐ commit cites T25 (via sanctioned bootstrap approval)
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n`/`py_compile` changed files · run-tests: the affected suites — `test-bootstrap-exception.sh` (incl. the new fail-closed + python3-absent tests) + the fixture/handler phase — GREEN, bounded per-phase 0-FAIL (pre-raise FF_* budgets; the 3 known host-slow suites — liveness-bounded-run/codex-parity/cli-0259 — are orthogonal, note if they don't complete under load) · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** · FR-07 clean (T25 via sanctioned approval, consumed) · FR-27 no-runaways. Emit the FR-22 marker; produce the gate report; HALT. A Codex re-review runs on the fix before deploy.

## Return
Gate report: T25 SHA, AC evidence (import-fail-closed RED→GREEN; python3-absent no-silent-skip; T23 coverage + single-use + §1/§2 preserved), no-regression, gate numbers, FR-07 statement + the bootstrap approval artifact used, and which python3-absent behavior you chose (warn vs block) + why. Do NOT push/tag.
