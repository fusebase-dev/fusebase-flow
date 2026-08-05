# Implement handoff — v3.30.5 correction: pre-commit FR-07 enumeration must FAIL CLOSED (T26)

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T26 EDITS a protected path — see note), FR-22, FR-27. **Synchronous; bound long runs (host saturated; pre-raise FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; stop at gate; do NOT bump VERSION/push/tag.** BLOCKER-class correction (Medium) from the T25 Codex re-review. One task = one commit, stacked on the v3.30.5 candidate.

## PROTECTED-PATH NOTE (FR-07)
T26 edits `hooks/git/pre-commit` (a `fusebase_flow_internals` protected path). Mint the SANCTIONED single-use digest-bound bootstrap approval FIRST (`bash hooks/local/write-bootstrap-approval.sh`), commit, then `--consume`. NEVER `--no-verify`.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the finding (T25 Codex re-review, Medium)
T25 closed the IMPORT fail-open. But `hooks/shared/path_policy.py` `staged_change_paths()` (~:112-158) runs `git diff --cached --name-status -M` in a try/except that returns `[]` on ANY subprocess exception, and `subprocess.run` does NOT raise on a nonzero git rc (so a failing git also yields `[]`). Then `hooks/git/pre-commit` §3 sees `paths=[]` → no hits → **exit 0**: a SECOND fail-open — if enumeration fails while staged changes exist, FR-07 is silently skipped. We are hardening FR-07 to be airtight, so this must fail CLOSED too.

## Design decision (lowest blast radius — do NOT change staged_change_paths' contract)
Fix at the ENFORCEMENT POINT in `hooks/git/pre-commit` §3 (Codex option B), NOT by changing `staged_change_paths()` (which is shared by `has_active_exception`, `write-bootstrap-approval.sh`, and the tool-time `pre_tool_use` path — changing its return/raise contract risks those callers). The pre-commit already knows staged changes exist (it computed `STAGED_ANY` via `git diff --cached --name-only`). Cross-check inside the §3 python:
- Re-list staged names with an explicit rc check: `p = subprocess.run(["git","diff","--cached","--name-only"], capture_output=True, text=True)`. If `p.returncode != 0` → print an FR-07 "could not list staged changes — failing closed" diagnostic + `sys.exit(1)`.
- `names = [n for n in p.stdout.splitlines() if n]`; `paths = staged_change_paths(root)`. If `names` is non-empty but `paths` is empty (enumeration disagreement/failure) → print an FR-07 "staged changes present but protected-path enumeration returned nothing — failing closed" diagnostic + `sys.exit(1)`.
- Otherwise proceed as today (evaluate each path; block on protected-without-exception).
This stays inside the T25 body-wrap try/except (which already fail-closes on unexpected errors). Keep it minimal + FR-22.

## Mandatory reads
1. `hooks/git/pre-commit` §3 (the T25 version — the import try/except now exits 1; the body-wrap; the `exit_proto` handling; the `STAGED_ANY` var).
2. `hooks/shared/path_policy.py` `staged_change_paths` (~:112-158) — understand WHY it returns [] on failure; do NOT change it (contract shared by 3 callers). Confirm the rc0-empty case (no staged changes) legitimately returns [] and must NOT be treated as a failure (only names-nonempty-but-paths-empty is the fail-closed trigger).
3. `hooks/tests/test-bootstrap-exception.sh` — the T23/T25 tests to extend.

## Scope — one task = one commit

- **T26 [MED/BLOCKER] — pre-commit FR-07 enumeration fails CLOSED on git-list failure or enumeration disagreement.** Implement the §3 cross-check above. Preserve everything else: the T25 import fail-closed + python3-absent WARN, §1/§2 secret checks (ACM), §4 module-size, §5 lint/typecheck, the `fusebase-flow-managed-hook: v1` marker, `set -uo pipefail`, exit-code contract, T23 delete/rename coverage.
  - **Tests** (extend `test-bootstrap-exception.sh`), RED→GREEN:
    - **enum-failure-fails-closed:** in a throwaway repo, force the enumeration to fail while staged changes exist — e.g. make `git diff --cached --name-status -M` fail (a `git` shim on PATH that returns nonzero for `--name-status` but the outer `--name-only` still lists a staged PROTECTED file), OR directly assert the cross-check: STAGED_ANY non-empty + staged_change_paths []-returning → pre-commit EXITS NONZERO (blocks). (Pick the most deterministic simulation; a `git` wrapper shim is reliable.)
    - **git-list-failure-fails-closed:** if `git diff --cached --name-only` itself returns nonzero → pre-commit blocks (exit 1), not 0.
    - **no-false-block:** a normal commit with NO staged changes still passes (rc0-empty is NOT a failure); a normal protected edit with approval still passes; a non-protected edit passes. (Guard against over-blocking.)
    - Keep ALL existing T23/T25 tests GREEN (25/25 → 27/27 or as extended).

## FR-07 / hard rules
Fail CLOSED for the enumeration. Do NOT change `staged_change_paths()`'s contract (leave path_policy.py untouched). Do NOT weaken the single-use exception or T23 coverage. Do NOT over-block the happy path (rc0-empty = legit no-op). Preserve §1/§2/§4/§5 + T25. Do NOT touch policies/**, other FR rows, deploy-policy, ratchet, verdict engine, bounded-run engine. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ enum-failure ⇒ exit 1 (fail closed)  ☐ git-list-failure ⇒ exit 1  ☐ rc0-empty (no staged) still PASSES (no over-block)
☐ T25 import-fail-closed + python3-warn + T23 coverage + §1/§2/§4/§5 all preserved  ☐ path_policy.py UNCHANGED
☐ no --no-verify  ☐ commit cites T26 (via sanctioned bootstrap approval)
```

## Gate (stop, report, HALT) — SCOPED
preflight 0/0 · `bash -n` pre-commit + test · `test-bootstrap-exception.sh` (incl. new enum tests) + fixture/handler phase GREEN bounded 0-FAIL · check-module-size --all exit 0 · **SINGLE `mirror-skills.sh --check` 0 drift** · FR-07 clean (sanctioned approval, consumed) · FR-27 no-runaways. Do NOT run the full run-tests. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: T26 SHA, AC evidence (enum-failure-fails-closed RED→GREEN; git-list-failure-fails-closed; no-false-block on rc0-empty/happy path; T25 + T23 + §1/§2 preserved; path_policy.py untouched), no-regression, scoped-gate numbers, FR-07 statement + bootstrap approval used. Do NOT push/tag.
