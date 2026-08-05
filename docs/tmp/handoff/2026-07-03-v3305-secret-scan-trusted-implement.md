# Implement handoff — v3.30.5 FINAL convergence: run §2 secret scanner from trusted HEAD too (T31)

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T31 EDITS a protected path — note), FR-12 (secrets), FR-22, FR-27. **Synchronous; bound long runs (host saturated; export FF_CLI_RECOVERY_TIMEOUT=600 FF_PHASE_TIMEOUT=900); no runaways; stop at gate; do NOT bump VERSION/push/tag. If you hit a server-side rate-limit/session-limit mid-task, STOP and report exactly where you are (committed vs WIP) — do not loop.** BLOCKER from the deploy-gate confirm. One coherent commit. This CLOSES the mutable-Python-load-point class across ALL hook security checks (§2 secret scan + §3 FR-07 are both trusted-HEAD after this).

## PROTECTED-PATH NOTE (FR-07)
T31 edits `hooks/git/pre-commit` (protected). REFRESH the wired hook first (`bash hooks/local/install-git-hooks.sh`), mint ONE sanctioned single-use bootstrap approval (60-min TTL), commit, `--consume`, confirm `.git/hooks/pre-commit` == source. (Test-only files under `hooks/tests/**` aren't protected.) NEVER `--no-verify`.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the finding (deploy-gate confirm, BLOCKER)
T30 closed the §3 (FR-07 protected-path) mutable-Python class: §3 now runs the enforcer from trusted HEAD under `-S` with a scrubbed env + git-based fallback. BUT §2 (the SECRET scanner, FR-12) at `hooks/git/pre-commit:~63` still runs the WORKING-TREE `hooks/shared/staged_secret_scan.py`: `PYTHONPATH="$ROOT/hooks" python3 -S "$ROOT/hooks/shared/staged_secret_scan.py"`. `-S` was added (T30) but the SCRIPT itself (and any patterns/config it reads) is the mutable working tree. An unstaged tamper of `staged_secret_scan.py` (or its patterns file) → make it report "no secrets" → a real secret in the staged changeset commits unguarded. Same class as the FR-07 self-tamper, applied to the secret scanner.

## Mandatory reads
`hooks/git/pre-commit` (§2 secret-scan invocation ~:63 + the T30 trusted-HEAD extraction infra used by §3 ~:200-245 — REUSE it), `hooks/shared/staged_secret_scan.py` (what it imports + any patterns/config it reads, e.g. a secret-patterns yaml + `_EXCLUDE_PATHSPECS`), `hooks/tests/test-secret-scan-staged.sh`, `hooks/tests/test-trusted-enforcer.sh`.

## Scope — ONE coherent commit (close §2's mutable-Python surface)

- **Run §2's secret scanner from trusted HEAD** — reuse T30's trusted-HEAD extraction. Extend the trusted temp package (already built for §3) to ALSO include HEAD's `hooks/shared/staged_secret_scan.py` + everything it imports/reads (its module deps + any patterns/config data file it loads — extract HEAD's version of each via `git show HEAD:<path>`). Invoke the secret scan as `python3 -S` with `PYTHONPATH` = the trusted temp dir (NOT `$ROOT/hooks`), so the TRUSTED HEAD scanner code + TRUSTED patterns run, scanning the STAGED changeset (git diff --cached — unchanged; it scans staged content, which is correct). The env is already scrubbed at the hook top (T30).
- **Git-based fallback (consistent with T30):** if HEAD genuinely lacks `staged_secret_scan.py` (true first-adoption, determined by `git ls-tree`/`cat-file` in the SHELL, not python), fall back to the working-tree scanner under `-S` with a note; a transient git error ⇒ fail closed (block, or run the trusted path — do NOT silently skip). When HEAD has the scanner ⇒ ALWAYS trusted (a working-tree tamper cannot run).
- **Preserve §2 behavior:** the secret scan must STILL block a real secret in the staged changeset (test-secret-scan-staged 10/10), still path-exclude the designed-token files (narrow excludes), still scan only added `+` lines. PyYAML (if the patterns are yaml) must import under `-S` (reuse the T30 getsitepackages path re-add). No over-block of legit commits.
- **Preserve everything else:** T23-T30 (§3 fully trusted-HEAD, all fail-closed load-points), §1 secret-file-name check, §4 module-size, §5 lint, the happy path (clean-tree + legit approval — YOUR OWN T31 commit must pass), bootstrap-edge, single-use exception, cross-policy get_policy scope, managed marker, set -uo pipefail, exit contract.

## Tests (extend test-trusted-enforcer.sh and/or test-secret-scan-staged.sh) — RED→GREEN
- **secret-scan-tamper-blocks:** with a clean scanner in HEAD, tamper the WORKING-TREE `staged_secret_scan.py` (unstaged) to report "no secrets", stage a file containing a REAL secret → the pre-commit BLOCKS the secret (exit 1) because the TRUSTED HEAD scanner runs. RED: pre-T31 (555b897) → the tampered working-tree scanner runs → secret commits (rc=0). Also a variant tampering the patterns file (if applicable).
- **secret-scan-still-blocks-normal:** a real secret with an untampered scanner → BLOCK (regression: test-secret-scan-staged 10/10 GREEN under the trusted-HEAD path).
- **secret-scan-bootstrap-edge:** HEAD lacks the scanner (first-adoption) → falls back to working-tree scanner (with note), still blocks a real secret; transient git error ⇒ fail closed.
- **no over-block:** a legit non-secret commit passes; designed-token excludes still honored.
- ALL T23-T30 tests GREEN; PyYAML (if used) imports under -S.

## FR-07/FR-12 / hard rules
BOTH §2 (secret scan) and §3 (FR-07) now run trusted-HEAD code from a scrubbed env under `-S`; no mutable working-tree Python (code, patterns, startup, or env) can influence ANY security check. Keep it scoped to the hook (do NOT change get_policy for other policies). Do NOT weaken the secret scanner's real-secret blocking or narrow excludes; do NOT weaken single-use/T23-coverage/happy-path. Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one coherent commit  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ §2 secret scanner + patterns run from trusted HEAD under -S (grep: no §2 invocation runs $ROOT/hooks working-tree scanner when HEAD has it)
☐ secret-scan-tamper-blocks RED→GREEN  ☐ secret-scan still blocks a real secret (10/10)  ☐ bootstrap-edge + transient-fail-closed  ☐ no over-block
☐ §3 (T23-T30) + §1/§4/§5 preserved  ☐ happy path + legit approval + PyYAML-under-S  ☐ T23-T30 tests GREEN
☐ .git/hooks==source  ☐ single-use intact  ☐ no --no-verify  ☐ commit cites T31 (sanctioned approval)
```

## Gate (stop, report, HALT) — SCOPED
preflight 0/0 · `bash -n`/`py_compile` changed files · test-secret-scan-staged.sh (incl. new tamper test) + test-trusted-enforcer.sh + test-bootstrap-exception.sh + fixture/handler phase (06/07) + policy-state + baseline-merge GREEN bounded 0-FAIL · check-module-size --all exit 0 · **SINGLE `mirror-skills.sh --check` 0 drift** · FR-07 clean (sanctioned approval, consumed) · FR-27 no-runaways · `.git/hooks/pre-commit` == source · grep-verify §2 runs the trusted-HEAD scanner (not the working-tree one when HEAD has it). Do NOT run the full run-tests. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: T31 SHA, AC evidence (secret-scan-tamper-blocks RED→GREEN; still-blocks-real-secret 10/10; bootstrap-edge + transient-fail-closed; no over-block; PyYAML-under-S), no-regression (T23-T30 GREEN), scoped-gate numbers, FR-07/FR-12 statement + approval used, .git/hooks==source, and confirmation that ALL hook security checks (§2 + §3) now run trusted-HEAD code and the ONLY remaining bypasses are out-of-model (--no-verify / hook-deletion / full-repo-write / system-compromise). Do NOT push/tag.
