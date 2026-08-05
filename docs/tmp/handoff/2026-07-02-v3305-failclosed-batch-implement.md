# Implement handoff — v3.30.5 convergence: FR-07 fail-closed BATCH (T27) — BaseException + name-status rc + missing/overridden policy

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T27 EDITS protected paths — see note), FR-22, FR-27. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; stop at gate; do NOT bump VERSION/push/tag.** Convergence batch from the comprehensive final Codex confirm (BLOCK). One task = one commit (this whole batch is one coherent "FR-07 fails closed at every load-point" commit).

## PROTECTED-PATH NOTE (FR-07)
T27 edits protected paths: `hooks/git/pre-commit`, `hooks/shared/path_policy.py`, `hooks/shared/policy_loader.py` (all `fusebase_flow_internals`). Mint the SANCTIONED single-use digest-bound bootstrap approval FIRST covering ALL edited protected paths (`bash hooks/local/write-bootstrap-approval.sh` collects them from the staged set), commit, then `--consume`. NEVER `--no-verify`.
IMPORTANT — the LIVE wired hook is stale: before you can commit, the CURRENT `.git/hooks/pre-commit` is an OLD copy (still fail-open). Run `bash hooks/local/install-git-hooks.sh` to refresh the wired hook from source BEFORE your first protected commit (so your own commit is gated by the fixed hook), OR ensure the bootstrap-approval path works with whatever hook is wired. Verify `.git/hooks/pre-commit` matches `hooks/git/pre-commit` after your changes.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the findings (comprehensive final confirm; verified)
T23/T25/T26 hardened import + enumeration, but the confirm found remaining fail-opens:
- **#3 [High]** `pre-commit` §3 import wrapper (~:67) + body wrapper (~:107) catch `Exception`, NOT `BaseException`. `SystemExit` (from `raise SystemExit(0)` / `sys.exit(0)`) subclasses `BaseException`, so a staged/tampered `path_policy.py` that exits 0 on import/call slips through → §3 exits 0 unguarded (a self-bypass: stage the tampered module in the same commit).
- **#4 [Medium]** `path_policy.staged_change_paths` (~:122) ignores `proc.returncode` on `git diff --cached --name-status -M`. A nonzero rc with PARTIAL stdout yields a nonempty-but-INCOMPLETE list → the check evaluates the partial list and MISSES a protected path that didn't make the truncated output → fail-open (T26 only covered the empty-list case).
- **#5 [Critical]** Missing/empty `protected-paths.yml` fails OPEN: `policy_loader.get_policy` returns `{}` for a missing file (~:44); `path_policy._load_categories`/`is_protected` turn absent categories into "nothing protected" (~:69) → FR-07 fully disabled. Also the gitignored `protected-paths.local.yml` (~policy_loader:77) can ERASE/relax protected categories.
- **#1 [Low, optional]** outer bash `git diff --cached --name-only` (~:53) failure → §3 skipped (non-reachable — broken repo won't commit — but cheap to harden).

## Mandatory reads
`hooks/git/pre-commit` (§3 wrappers + outer gate), `hooks/shared/path_policy.py` (`staged_change_paths` :122, `_load_categories` :60, `is_protected` :69, `evaluate`), `hooks/shared/policy_loader.py` (`get_policy` :44, local-override merge :77, `local_override_may_relax`), `policies/protected-paths.yml` (categories + any `local_override_may_relax`/`on_unapproved_edit`), `hooks/tests/test-bootstrap-exception.sh`.

## Scope — ONE commit (the coherent "FR-07 fails closed everywhere" batch)

- **#3 [High] — catch `BaseException`.** In `hooks/git/pre-commit` §3, change BOTH the import wrapper and the body wrapper from `except Exception` to `except BaseException as e:` → print an FR-07 diagnostic + `sys.exit(1)` (fail closed). Ensure a LEGIT `sys.exit(1)` for a real protected-hit is NOT swallowed into a pass (the outermost handler exits 1 either way — verify the exit code stays 1 for a real hit, and that a clean no-hit pass still falls through to exit 0). Do NOT catch a legit clean exit-0 fall-through as an error.
- **#4 [Medium] — name-status rc fail-closed.** In `path_policy.staged_change_paths`, capture `proc.returncode`; if the `git diff --cached --name-status -M` subprocess raises OR returns nonzero, RAISE (e.g. `RuntimeError("staged_change_paths: git name-status failed rc=<n>")`) instead of returning a partial/empty list. rc0 → parse normally (empty is legit). The pre-commit body wrapper (#3, now BaseException) catches the raise → exit 1. VERIFY the other callers tolerate the raise in a fail-closed way: `has_active_exception` (bootstrap branch, inside `evaluate`, inside the pre-commit wrapper → exit 1 ✓); `write-bootstrap-approval.sh` (mint fails on git error — acceptable; confirm it doesn't mint a bad artifact); the tool-time `pre_tool_use` path (at tool-time there are usually no staged changes → rc0-empty → no raise; confirm a git failure there degrades safely, e.g. treat as protected/deny or surface the error — do NOT silently allow).
- **#5 [Critical] — missing/empty/overridden protected-paths policy fails CLOSED, scoped to FR-07 (do NOT change global get_policy behavior for other policies).**
  - At the FR-07 enforcement point (pre-commit §3 and/or a new `path_policy` helper like `assert_protected_policy_loaded()`), VALIDATE the protected-paths policy before enforcing: it must exist, be a mapping, and have at least the `fusebase_flow_internals` category with a non-empty `paths` list. If missing/empty/malformed → print an FR-07 diagnostic + `sys.exit(1)` (fail closed) — "protected-paths policy missing/empty; cannot enforce FR-07; fix policies/protected-paths.yml".
  - **Local-override non-relaxing for FR-07:** ensure `protected-paths.local.yml` CANNOT remove/empty a protected category (esp. `fusebase_flow_internals`). Prefer: honor `local_override_may_relax: false` for protected-paths (add it to `policies/protected-paths.yml` if absent) and make the loader/consumer refuse a local override that DROPS a base category's paths for protected-paths (additive-only). Keep this SCOPED to the protected-paths policy — do NOT change how approval-policy/command-policy/ratchet load.
  - Do NOT break the happy path: with the shipped `policies/protected-paths.yml` present and valid, enforcement proceeds exactly as today.
- **#1 [Low, optional but cheap] — outer git-list rc.** Capture the outer `git diff --cached --name-only` rc; on nonzero, fail closed (exit 1) with a diagnostic. (You already added an inner rc-check in T26; mirror it at the outer gate.) If it complicates the bash flow, a clear WARN + the inner python rc-checks are acceptable — state your choice.

## Tests (extend test-bootstrap-exception.sh) — RED→GREEN for each
- **#3:** a staged/tampered `path_policy.py` shim that `raise SystemExit(0)` on import (and one that exits 0 inside `evaluate`) with a staged PROTECTED change → pre-commit BLOCKS (exit 1), not 0. (RED under the current `except Exception`.)
- **#4:** a `git` shim that returns rc≠0 with PARTIAL `--name-status` output (a protected path omitted) while `--name-only` lists it → pre-commit BLOCKS (exit 1). Plus a unit assertion that `staged_change_paths` raises on nonzero name-status rc.
- **#5:** (a) protected-paths.yml removed/emptied → pre-commit BLOCKS with the policy-missing diagnostic (not a silent pass); (b) a `protected-paths.local.yml` that tries to erase `fusebase_flow_internals` → the category is STILL enforced (override cannot relax); (c) happy path: shipped policy present → normal enforcement + all T23/T25/T26 tests GREEN.
- **#1 (if implemented):** outer git-list rc≠0 → block.
- ALL existing T23/T24/T25/T26 tests remain GREEN.

## FR-07 / hard rules
Fail CLOSED at EVERY load-point. Keep #5 SCOPED to the protected-paths/FR-07 path (do NOT change get_policy's behavior for approval-policy/command-policy/ratchet-governance). Do NOT weaken the single-use exception or T23 delete/rename coverage. Preserve §1/§2 secret (ACM), §4 module-size, §5 lint, managed marker, set -uo pipefail, exit-code contract. Do NOT touch the deploy-policy SEMANTICS, other FR rows, the health-check verdict engine, or the bounded-run engine. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one coherent commit  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ SystemExit(0) via tampered module ⇒ BLOCK (BaseException)  ☐ name-status rc≠0 ⇒ raise/BLOCK  ☐ missing/empty protected-paths ⇒ BLOCK
☐ local override cannot erase fusebase_flow_internals  ☐ happy path unchanged (shipped policy ⇒ normal enforcement)
☐ get_policy behavior for OTHER policies unchanged  ☐ T23/T24/T25/T26 tests GREEN  ☐ .git/hooks/pre-commit refreshed to match source
☐ single-use exception intact  ☐ no --no-verify  ☐ commit cites T27 (via sanctioned approval covering all edited protected paths)
```

## Gate (stop, report, HALT) — SCOPED
preflight 0/0 · `bash -n`/`py_compile` changed files · `test-bootstrap-exception.sh` (incl. ALL new #3/#4/#5 tests) + fixture/handler phase + the policy-state/baseline-merge tests that exercise get_policy (confirm no cross-policy regression) GREEN bounded 0-FAIL · check-module-size --all exit 0 · **SINGLE `mirror-skills.sh --check` 0 drift** · FR-07 clean (sanctioned approval, consumed) · FR-27 no-runaways · confirm `.git/hooks/pre-commit` == source. Do NOT run the full ~40-min run-tests. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: T27 SHA, per-finding AC evidence (#3 SystemExit-blocks RED→GREEN; #4 name-status-rc-raises/blocks; #5 missing-policy-blocks + local-override-cannot-relax + happy-path-unchanged; #1 if done), no-regression (T23/T24/T25/T26 + cross-policy get_policy consumers GREEN), scoped-gate numbers, FR-07 statement + bootstrap approval used, and confirmation the wired `.git/hooks/pre-commit` now matches source. Do NOT push/tag.
