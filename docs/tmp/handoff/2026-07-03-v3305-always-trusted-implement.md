# Implement handoff — v3.30.5 TRUE convergence: always-trusted-HEAD enforcer + no Python startup injection (T29)

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T29 EDITS protected paths — note), FR-22, FR-27. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; stop at gate; do NOT bump VERSION/push/tag. If you hit a server-side rate-limit/session-limit mid-task, STOP and report exactly where you are (committed vs WIP) — do not loop.** BLOCKER from the converging Codex confirm. One coherent commit.

## PROTECTED-PATH NOTE (FR-07)
T29 edits protected paths: `hooks/git/pre-commit` + `policies/protected-paths.yml` (both `fusebase_flow_internals`). REFRESH the wired hook first (`bash hooks/local/install-git-hooks.sh`), mint ONE sanctioned single-use bootstrap approval covering both (use a 60-min TTL — the host is slow), commit, `--consume`, confirm `.git/hooks/pre-commit` == source. NEVER `--no-verify`.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the BLOCKER (converging confirm, verified with 2 PoCs)
T28 made the trusted-HEAD enforcer CONDITIONAL — it only activates when the STAGED changeset includes `path_policy.py`/`policy_loader.py`/`__init__.py`/`protected-paths.yml`. For every OTHER commit, `hooks/git/pre-commit` §3 (~:217) imports the enforcer from the mutable working tree via `PYTHONPATH="$ROOT/hooks"`. Reachable bypasses (both proven in temp repos):
1. **Unstaged enforcer tamper:** change working-tree `hooks/shared/path_policy.py` to return "nothing protected" WITHOUT staging it; stage only a protected file (e.g. FLOW_RULES.md); the pre-commit imports the lying working-tree enforcer → `exit 0`, unapproved protected edit commits.
2. **Python startup injection:** an untracked `hooks/sitecustomize.py` (or `usercustomize.py`) containing `import os; os._exit(0)` on `PYTHONPATH=$ROOT/hooks` is imported at interpreter startup (via `site`), BEFORE any check runs → the check process exits 0 → hook reports "all checks passed". Not `--no-verify`; the hook runs but trusts mutable working-tree Python.

## Mandatory reads
`hooks/git/pre-commit` (§2 secret-scan python invocation ~:42-45, §3 trusted-HEAD dispatch + the conditional at ~:95 + the working-tree import at ~:217), `hooks/shared/path_policy.py` (unchanged — enforcement logic is sound), `policies/protected-paths.yml` (`fusebase_flow_internals` category), `hooks/tests/test-trusted-enforcer.sh`.

## Scope — ONE coherent commit (close the mutable-Python-load-point class)

- **A — ALWAYS run FR-07 §3 from the trusted HEAD enforcer (remove the conditional).** Make the trusted-HEAD extraction UNCONDITIONAL: for EVERY commit with staged changes, extract HEAD's `hooks/shared/{__init__,path_policy,policy_loader}.py` (+ any policy_loader deps) + `policies/protected-paths.yml` into a temp dir and import/run FR-07 from THERE. Do NOT import the enforcer from the working-tree `$ROOT/hooks` for the protected-path check. For a clean tree (no tamper), HEAD==working-tree so behavior is identical; when the working-tree enforcer is tampered/unstaged, the CLEAN HEAD enforcer still runs. Keep: the trusted enforcer reads the working-tree `state/approvals/` (legit approvals honored) + evaluates the staged changeset; the BOOTSTRAP edge (HEAD lacks the enforcer via `git ls-tree` rc0+empty → fall back with a note) — and a TRANSIENT git error → FAIL CLOSED (never fall back).
- **B — no Python startup injection: `python3 -S` + isolated PYTHONPATH.** Invoke the §3 trusted-enforcer python with `python3 -S` (disables `site` ⇒ no `sitecustomize`/`usercustomize` import) AND set `PYTHONPATH` to ONLY the trusted temp dir (NOT `$ROOT/hooks`), so no working-tree/untracked startup file is on the import path. Also add `-S` to the §2 secret-scan python invocation (`staged_secret_scan.py`) — a `sitecustomize` `os._exit(0)` currently disables the secret scan too; `-S` closes that. (The secret scanner still resolves via its explicit path/PYTHONPATH; `-S` only disables site startup files, not your imports — verify the secret scan still runs + still blocks a real secret.)
- **C — defense-in-depth: protect the startup-file names.** Add `hooks/sitecustomize.py`, `hooks/usercustomize.py` (and, if cheap, a `**/sitecustomize.py` / `**/usercustomize.py` pattern scoped to the repo's hooks import roots) to the `fusebase_flow_internals` protected paths in `policies/protected-paths.yml`, so committing such a file also requires an approval. (Runtime is already closed by `-S`; this is belt-and-suspenders + makes an untracked one visible when staged.)
- **Preserve:** T23-T28 behavior (delete/rename, import/enumeration/policy/SystemExit/BaseException fail-closed, single-use exception, tool-time assert), §1 secret-file-name check, §4 module-size, §5 lint, managed marker, `set -uo pipefail`, exit contract, cross-policy `get_policy` scope, the happy path (clean-tree commits unchanged), and the legit sanctioned-approval flow (YOUR OWN T29 commit must pass via the trusted enforcer honoring the approval).

## Tests (extend test-trusted-enforcer.sh) — RED→GREEN
- **A:** unstaged-enforcer-tamper-blocks — clean enforcer in HEAD, working-tree path_policy.py tampered to "nothing protected" but NOT staged, stage a protected file → pre-commit BLOCKS (exit 1). RED: pre-T29 (a12b450) → exit 0.
- **B:** sitecustomize-injection-blocks — untracked `hooks/sitecustomize.py` with `import os; os._exit(0)`, stage a protected file → pre-commit BLOCKS (exit 1). RED: pre-T29 → exit 0. Also a usercustomize.py variant. AND: secret-scan-still-blocks-under-sitecustomize (a real secret + the sitecustomize file → still BLOCK on the secret, proving `-S` didn't disable §2).
- **common/legit:** clean-tree common commit unchanged; legit protected edit + sanctioned approval passes; non-protected passes; bootstrap-edge (HEAD-lacks-enforcer falls back; transient-git-error fails closed).
- ALL T23-T28 tests (test-bootstrap-exception.sh + test-trusted-enforcer.sh) remain GREEN.

## FR-07 / hard rules
The enforcer ALWAYS runs from trusted HEAD code with `-S` + isolated PYTHONPATH; no mutable working-tree Python (code OR startup files) can influence the check. Keep #5 scoped to FR-07 (get_policy for other policies unchanged). Do NOT weaken single-use/T23-coverage/happy-path. Preserve §1/§2 (with -S)/§4/§5. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one coherent commit  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ unstaged-enforcer-tamper ⇒ BLOCK  ☐ sitecustomize/usercustomize injection ⇒ BLOCK  ☐ secret scan still blocks under -S
☐ common clean-tree commit unchanged  ☐ legit approved edit passes  ☐ bootstrap-edge (fallback vs transient-fail-closed)
☐ trusted-HEAD is UNCONDITIONAL (no working-tree enforcer import for §3)  ☐ PYTHONPATH isolated to trusted temp  ☐ -S on §2+§3
☐ T23-T28 tests GREEN  ☐ .git/hooks==source  ☐ single-use intact  ☐ no --no-verify  ☐ commit cites T29 (sanctioned approval)
```

## Gate (stop, report, HALT) — SCOPED
preflight 0/0 · `bash -n`/`py_compile` changed files · test-trusted-enforcer.sh (incl. new A/B tests) + test-bootstrap-exception.sh + fixture/handler phase (06/07) + policy-state + baseline-merge GREEN bounded 0-FAIL · check-module-size --all exit 0 · **SINGLE `mirror-skills.sh --check` 0 drift** · FR-07 clean (sanctioned approval, consumed) · FR-27 no-runaways · `.git/hooks/pre-commit` == source. Do NOT run the full run-tests. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: T29 SHA, AC evidence (unstaged-tamper-blocks RED→GREEN; sitecustomize/usercustomize-injection-blocks RED→GREEN; secret-scan-still-blocks-under-S; common/legit/bootstrap preserved), no-regression (T23-T28 GREEN), scoped-gate numbers, FR-07 statement + approval used, .git/hooks==source, and confirm the ONLY remaining bypasses are the documented out-of-model residuals (--no-verify / hook-deletion / full-repo-write / system-compromise). Do NOT push/tag.
