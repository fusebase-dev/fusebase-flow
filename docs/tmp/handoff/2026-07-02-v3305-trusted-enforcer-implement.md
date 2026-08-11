# Implement handoff — v3.30.5 final hardening: trusted-HEAD enforcer (T28 #1) + tool-time policy assert (#7)

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T28 EDITS protected paths — note below), FR-22, FR-27. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; stop at gate; do NOT bump VERSION/push/tag.** Final convergence batch from the third v3.30.5 Codex confirm (BLOCK). One coherent commit.

## PROTECTED-PATH NOTE (FR-07)
T28 edits protected paths: `hooks/git/pre-commit` + `hooks/handlers/pre_tool_use.py` (both `fusebase_flow_internals`). Mint ONE sanctioned single-use digest-bound bootstrap approval covering both, commit, then `--consume`. Refresh the wired hook first (`bash hooks/local/install-git-hooks.sh`) and re-verify `.git/hooks/pre-commit` == source at the end. NEVER `--no-verify`.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the two findings (third Codex confirm; verified)
T23-T27 closed every ACCIDENTAL/environmental FR-07 fail-open (delete/rename, import error, enumeration error, missing-policy, SystemExit(0), local-override). Two SELF-PROTECTING-CONTROL load-points remain:
- **#1 [High, reachable]** `hooks/git/pre-commit` §3 imports `evaluate`/`staged_change_paths`/`assert_protected_policy_loaded` from the MUTABLE working-tree `hooks/shared/path_policy.py` (+ `policy_loader.py` + `protected-paths.yml`). A staged/tampered enforcer that imports cleanly but returns "nothing protected" (`is_protected→False`, or `evaluate().protected=False`) self-passes → the tamper commits and disables FR-07 going forward. (T27's SystemExit(0) block does NOT cover a *successful-but-lying* enforcer.)
- **#7 [Medium]** `hooks/handlers/pre_tool_use.py` (~:87) calls `evaluate_path()` WITHOUT `assert_protected_policy_loaded()`; a missing/empty `protected-paths.yml` lets a protected-path Edit/Write pass at TOOL-TIME (the commit is still blocked by the pre-commit, but the tool-time load-point isn't fail-closed).

## Mandatory reads
`hooks/git/pre-commit` (§3 import + body), `hooks/shared/path_policy.py` (`assert_protected_policy_loaded`, `evaluate`, `staged_change_paths`, `has_active_exception`, `is_protected`), `hooks/shared/policy_loader.py` (get_policy + local-override + git-root resolution), `hooks/handlers/pre_tool_use.py` (`evaluate_path` call site ~:87), `hooks/tests/test-bootstrap-exception.sh`.

## Scope — ONE coherent commit

- **#1 [High] — run FR-07 enforcement from a TRUSTED (HEAD) copy of the enforcement code + policy.**
  - In `hooks/git/pre-commit` §3, BEFORE importing the enforcement modules, extract the COMMITTED (HEAD) versions into a temp dir and import FROM THERE (evaluating the STAGED changeset): `git show HEAD:hooks/shared/__init__.py`, `git show HEAD:hooks/shared/path_policy.py`, `git show HEAD:hooks/shared/policy_loader.py`, `git show HEAD:hooks/shared/policy_loader`'s deps if any, and `git show HEAD:policies/protected-paths.yml`. Build a temp package (`<tmp>/shared/...` + `<tmp>/policies/protected-paths.yml`), set `PYTHONPATH`/policy-root so the TRUSTED code + TRUSTED policy are used, then run `assert_protected_policy_loaded` + `staged_change_paths` + `evaluate` against the actual staged paths. The trusted enforcer reads the WORKING-TREE `state/approvals/` (so a legit sanctioned approval is still honored) and the STAGED changeset (so it evaluates the real commit).
  - **Why this closes it:** committing a tampered working-tree `path_policy.py` now runs the CLEAN HEAD enforcer, which still sees `hooks/shared/path_policy.py` as protected → requires an approval → blocks the tamper. The tampered code never runs during its own gate.
  - **Preserve the common path + legit flows (critical — test each):**
    - A commit that does NOT touch enforcement code behaves identically (still blocked/allowed correctly). No behavior change for normal protected/non-protected edits.
    - A LEGIT approved edit to `path_policy.py`/`policy_loader.py`/`protected-paths.yml` (with the sanctioned single-use bootstrap approval on disk) STILL PASSES — the trusted HEAD enforcer finds the approval in the working-tree `state/approvals/` and allows it. (This is how YOUR OWN T28 commit must pass — verify it does.)
    - **Bootstrap edge:** if HEAD does not yet contain these files (fresh consumer adopting the framework — the first commit that ADDS `hooks/shared/path_policy.py`), `git show HEAD:…` fails → FALL BACK to the working-tree enforcer (the file being added is not a tamper) with a one-line note. Detect this precisely (HEAD lacks the file) — do NOT fall back on a transient git error (that must fail closed per T26/T27).
    - Keep it bounded/fast: a handful of `git show` calls + a temp dir; clean up the temp dir; FR-27 no-runaways.
  - Document (tripwire comment + the deploy problem-catalog entry) the ACCEPTED residuals a discipline-guardrail cannot mechanically stop: `--no-verify` (rule-forbidden), deleting/replacing `.git/hooks/pre-commit`, or full repo write bypassing the hook entirely.
- **#7 [Medium] — tool-time fail-closed on missing policy.** In `hooks/handlers/pre_tool_use.py`, call `assert_protected_policy_loaded(root)` (or the equivalent presence check) BEFORE `evaluate_path()`; on `BaseException` / a missing-or-empty protected-paths policy, DENY the tool action (fail closed) with a clear FR-07 message. Preserve normal behavior when the shipped policy is present (no over-block of normal edits).

## Tests (extend test-bootstrap-exception.sh) — RED→GREEN
- **#1:** (a) tamper-blocks — stage a `path_policy.py` whose `is_protected` returns False-for-all (imports cleanly, lies) + a protected edit → pre-commit BLOCKS (exit 1) because the TRUSTED HEAD enforcer runs; add a RED assertion that the working-tree-enforcer approach (pre-T28) would have exited 0. (b) legit-approved-enforcer-edit-passes — a sanctioned approval + a real path_policy edit → PASSES (trusted HEAD enforcer honors the approval). (c) common-non-enforcement-commit-unaffected — a normal non-protected edit passes; a normal protected-without-approval edit blocks (unchanged). (d) bootstrap-edge — HEAD lacking path_policy.py → falls back to working-tree, first-add passes; a transient git-show error (not "file absent") → fail closed.
- **#7:** with `protected-paths.yml` missing/empty, a PreToolUse Edit/Write on a protected path → DENY (fail closed); with the shipped policy present, a normal edit is unaffected. RED (current tool-time allows) → GREEN.
- ALL existing T23/T24/T25/T26/T27 tests remain GREEN.

## FR-07 / hard rules
The enforcer must run from TRUSTED (HEAD) code for staged enforcement-code changes; fail closed at the tool-time load-point too. Do NOT weaken the single-use exception, T23 coverage, or the happy path. Do NOT change get_policy for other policies. Preserve §1/§2 secret (ACM), §4 module-size, §5 lint, managed marker, set -uo pipefail, exit contract, and T25/T26/T27 fail-closed behavior. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one coherent commit  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ tampered/lying enforcer ⇒ BLOCK (trusted HEAD runs)  ☐ legit approved enforcer edit ⇒ PASS  ☐ common path unchanged  ☐ bootstrap-first-add ⇒ pass, transient-git-error ⇒ fail closed
☐ tool-time missing-policy ⇒ DENY (fail closed); shipped policy present ⇒ normal
☐ T23–T27 tests GREEN  ☐ .git/hooks/pre-commit == source  ☐ single-use intact  ☐ no --no-verify  ☐ commit cites T28 (sanctioned approval)
```

## Gate (stop, report, HALT) — SCOPED
preflight 0/0 · `bash -n`/`py_compile` changed files · `test-bootstrap-exception.sh` (incl. new #1/#7 tests) + fixture/handler phase (esp. `07`/`06` protected-deny fixtures — pre_tool_use path) + policy-state/baseline-merge GREEN bounded 0-FAIL · check-module-size --all exit 0 · **SINGLE `mirror-skills.sh --check` 0 drift** · FR-07 clean (sanctioned approval, consumed) · FR-27 no-runaways · `.git/hooks/pre-commit` == source. Do NOT run the full run-tests. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: T28 SHA, AC evidence (#1 tamper-blocks RED→GREEN + legit-approved-passes + common-path-unchanged + bootstrap-edge; #7 tool-time-deny RED→GREEN), no-regression (T23-T27 + fixtures + cross-policy GREEN), scoped-gate numbers, FR-07 statement + bootstrap approval used, `.git/hooks/pre-commit`==source confirmation, and the documented ACCEPTED residuals (--no-verify / hook-deletion / full-repo-write). Do NOT push/tag.
