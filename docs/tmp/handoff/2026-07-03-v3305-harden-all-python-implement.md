# Implement handoff — v3.30.5 CLASS-CLOSING: harden EVERY python invocation + sanitize env + git-based fallback (T30)

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T30 EDITS a protected path — note), FR-22, FR-27. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; stop at gate; do NOT bump VERSION/push/tag. If you hit a server-side rate-limit/session-limit mid-task, STOP and report exactly where you are (committed vs WIP) — do not loop.** BLOCKER from the deploy-gate confirm. One coherent commit. This is the fix that CLOSES the mutable-Python-load-point class (finite surface — all python invocations).

## PROTECTED-PATH NOTE (FR-07)
T30 edits `hooks/git/pre-commit` (protected). REFRESH the wired hook first (`bash hooks/local/install-git-hooks.sh`), mint ONE sanctioned single-use bootstrap approval (60-min TTL), commit, `--consume`, confirm `.git/hooks/pre-commit` == source. (If the test-label fix touches only `hooks/tests/*` those aren't protected.) NEVER `--no-verify`.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the BLOCKER (deploy-gate confirm, live PoC)
T29 added `-S` + isolated PYTHONPATH to the §3 MAIN check and §2 secret scan, but the trusted-HEAD **PREP** step (the git-show extraction script at `hooks/git/pre-commit:~208`) runs **plain `python3`** and **inherits external PYTHONPATH**; its fallback is chosen by a **python-writable `RESULT` variable** (`:~214`). Live PoC: `PYTHONPATH=$ROOT/hooks` + untracked `hooks/sitecustomize.py` (writes `RESULT=fallback` / `os._exit(0)`) + unstaged lying `hooks/shared/path_policy.py` + staged `FLOW_RULES.md` → `bash hooks/git/pre-commit` returned `rc=0` "all checks passed". Root pattern: ANY python invocation running with mutable env/startup files is a sitecustomize-injection surface. Close ALL of them uniformly.

## Mandatory reads
`hooks/git/pre-commit` — enumerate EVERY `python3` invocation (§2 secret-scan, §3 PREP/extraction, §3 MAIN check, the fallback path, and any others; grep `python3`). `hooks/shared/staged_secret_scan.py` (the -S site-packages re-add pattern T29 used). `hooks/tests/test-trusted-enforcer.sh` + `hooks/tests/run-tests.sh` (the label mismatch, finding 7).

## Scope — ONE coherent commit (close the class)

- **A — sanitize the hook environment ONCE at the top of `hooks/git/pre-commit`** (right after `set -uo pipefail`/`cd "$ROOT"`): `unset PYTHONPATH PYTHONSTARTUP PYTHONHOME 2>/dev/null || true` (and any other python-influencing env you find — PYTHONNOUSERSITE can be SET to 1). So NO inherited env influences any subsequent python invocation. (Set them explicitly per-invocation instead of unsetting if that's cleaner — but the guarantee is: no external PYTHONPATH/startup path reaches any python call.)
- **B — `python3 -S` + explicit trusted-only PYTHONPATH on EVERY python invocation** (prep, main, secret-scan, fallback — UNIFORMLY):
  - The §3 PREP/extraction invocation MUST use `python3 -S` with `PYTHONPATH` set to ONLY what it needs (the trusted temp dir being built, or empty + explicit sys.path) — never `$ROOT/hooks`, never inherited. Re-add site-packages (for PyYAML) via `site.getsitepackages()`/`getusersitepackages()` PATHS only (the T29 pattern), never re-importing startup files.
  - The §2 secret-scan + §3 main invocations: confirm they already do this (T29) and remain correct after the env sanitization.
  - Any OTHER python call in the hook: same treatment.
- **C — git-based fallback determination (not python-writable).** Whether to use the trusted-HEAD enforcer vs. the bootstrap fallback MUST be decided by GIT (e.g. `git cat-file -e HEAD:hooks/shared/path_policy.py` / `git ls-tree`), NOT by a value a python script (or a forged startup file) can write. Rule: if HEAD genuinely contains the enforcer files ⇒ ALWAYS trusted (no fallback possible); fall back to the working-tree enforcer ONLY when git proves HEAD lacks them (true first-adoption bootstrap), and even then under `-S` with a controlled PYTHONPATH. A forged `RESULT=fallback` must be impossible to honor when HEAD has the enforcer.
- **D — fix the test-label wiring (finding 7).** `hooks/tests/test-trusted-enforcer.sh` emits `bootstrap-exception` PASS rows while `run-tests.sh` invokes it under the `trusted-enforcer` label, so success rows aren't counted (failures still fail). Make the emitted label match so PASS rows count. (Not protected — `hooks/tests/**`.)
- **Preserve:** T23-T29 behavior (all prior fail-closed load-points), the happy path (clean-tree common commit, legit sanctioned-approval edit — YOUR OWN T30 commit must pass), bootstrap-edge (true HEAD-missing ⇒ fallback; transient git error ⇒ fail closed), single-use exception, §1/§4/§5, cross-policy get_policy scope, managed marker, set -uo pipefail, exit contract, PyYAML still importable under -S.

## Tests (extend test-trusted-enforcer.sh) — RED→GREEN
- **prep-step-injection-blocks:** the confirm's live PoC — `PYTHONPATH=$ROOT/hooks` exported + untracked `hooks/sitecustomize.py` (forging fallback / os._exit(0)) + unstaged lying `path_policy.py` + staged protected file → pre-commit BLOCKS (exit 1). RED: pre-T30 (ec94204) → exit 0.
- **inherited-PYTHONPATH-neutralized:** with a hostile `PYTHONPATH` exported, a normal protected-without-approval edit still BLOCKS and a normal non-protected edit still passes (env sanitization works; no over-block).
- **forged-fallback-impossible-when-HEAD-has-enforcer:** a forged `RESULT=fallback` (via startup file) does NOT cause the working-tree enforcer to run when HEAD has the enforcer → BLOCK.
- All T23-T29 tests GREEN; PyYAML-dependent checks still work under -S.

## FR-07 / hard rules
EVERY python invocation in the hook runs `-S` with a controlled PYTHONPATH; the env is sanitized; the trusted-vs-fallback decision is git-based and unforgeable. No mutable working-tree Python (code OR startup files OR env) can influence any check. Keep it scoped to the FR-07 hook (do NOT change get_policy for other policies). Do NOT weaken single-use/T23-coverage/happy-path. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one coherent commit  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ env sanitized at hook top (unset PYTHONPATH/STARTUP/HOME)  ☐ EVERY python invocation uses -S + controlled PYTHONPATH (grep-verify: no plain `python3` without -S in the hook's security checks)
☐ fallback decision git-based/unforgeable  ☐ prep-step-injection ⇒ BLOCK  ☐ inherited-PYTHONPATH neutralized (no over-block)
☐ PyYAML still imports under -S  ☐ happy path + legit approval + bootstrap-edge preserved  ☐ test label fixed
☐ T23-T29 tests GREEN  ☐ .git/hooks==source  ☐ single-use intact  ☐ no --no-verify  ☐ commit cites T30 (sanctioned approval)
```

## Gate (stop, report, HALT) — SCOPED
preflight 0/0 · `bash -n`/`py_compile` changed files · test-trusted-enforcer.sh (incl. new prep-injection tests) + test-bootstrap-exception.sh + test-secret-scan-staged.sh + fixture/handler phase (06/07) + policy-state + baseline-merge GREEN bounded 0-FAIL · check-module-size --all exit 0 · **SINGLE `mirror-skills.sh --check` 0 drift** · FR-07 clean (sanctioned approval, consumed) · FR-27 no-runaways · `.git/hooks/pre-commit` == source · grep-verify no un-hardened `python3` invocation remains in the hook's checks. Do NOT run the full run-tests. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: T30 SHA, AC evidence (prep-step-injection-blocks RED→GREEN; inherited-PYTHONPATH-neutralized; forged-fallback-impossible; PyYAML-under-S; happy/legit/bootstrap preserved; test-label fixed), a grep showing every hook python invocation uses `-S`, no-regression (T23-T29 GREEN), scoped-gate numbers, FR-07 statement + approval used, .git/hooks==source, and confirmation the ONLY remaining bypasses are out-of-model (--no-verify / hook-deletion / full-repo-write / system-compromise). Do NOT push/tag.
