# Implement handoff — v3.30.5: FR-07 protected-path delete/rename coverage (T23) + hook-install rc handling (T24)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.4. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-05, FR-07 (T23 EDITS a protected path — see note), FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated); no runaways; stop at the gate; do NOT bump VERSION/push/tag.** These are corrections found by the FINAL whole-roadmap Codex review (verdict SERIOUS) of the shipped v3.30.3+v3.30.4. One task = one commit.

## PROTECTED-PATH NOTE (FR-07 — sanctioned, not a bypass)
T23 edits `hooks/git/pre-commit` (a `fusebase_flow_internals` protected path, `hooks/git/**`). If the wired pre-commit blocks the commit, author the SANCTIONED single-use digest-bound bootstrap approval FIRST (`bash hooks/local/write-bootstrap-approval.sh`), commit, then `--consume`. **NEVER `--no-verify`.**

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — the finding (verified by the PO against the code)
The final whole-roadmap review proved a SHIPPED FR-07 bypass: `hooks/git/pre-commit` section 3 (protected-path check) only considers `--diff-filter=ACM` staged paths (`:30` gate + `:59` inner python), so **staged DELETIONS (`git rm`) and RENAMES of protected files never reach `path_policy.evaluate`** — a `git rm hooks/shared/foo.py` or a rename of FLOW_RULES.md/policies/*.yml/hooks/{handlers,shared,git}/** commits with exit 0, no approval. (Proven: `D hooks/shared/to_delete.py` and `R100 …` both pass the real hook.) Also [MED] the git-hook reinstall call sites pipe into `grep`, losing the installer's rc.

## Mandatory reads
1. `hooks/git/pre-commit` (§3 protected-path check, :47-74; note §1/§2 secret checks correctly stay ACM — do NOT change those), `hooks/shared/path_policy.py` (`evaluate`, `is_protected`), `policies/protected-paths.yml`.
2. `hooks/tests/test-*` for the pre-commit/protected-path coverage (find the existing protected-path test; e.g. the bootstrap-exception test) to extend.
3. `hooks/local/upgrade.sh` (~:483 the install-git-hooks.sh call piped to grep) + `hooks/local/post-fusebase-update.sh` (~:333 same pattern) + `hooks/local/install-git-hooks.sh` (its output contract: prints `custom … detected` / `installed …`).

## Scope — one task = one commit

- **T23 [HIGH] — pre-commit protected-path check covers DELETES + RENAMES (close the FR-07 bypass).**
  - In `hooks/git/pre-commit` §3 ONLY (leave §1/§2 secret checks on ACM — deleting a file can't leak a secret): replace the ACM-limited path set with the FULL set of staged changes and evaluate every affected protected path. Use `git diff --cached --name-status -M` (or `-M --diff-filter=ACMRD`) and per status:
    - `A`/`C`/`M`: evaluate the path (as today).
    - `D` (delete): evaluate the DELETED path (removing a protected file needs an approval).
    - `R` (rename): evaluate BOTH the OLD path (source — leaving protection) AND the NEW path (destination).
  - The outer bash gate (`:48`) must run the protected-path check whenever there are ANY staged changes (not just ACM) — e.g. gate on `git diff --cached --name-only` (unfiltered) being non-empty, or always run the python when python3 is present and there is a staged tree. Keep the digest-bound single-use exception semantics (a protected delete/rename can be approved via the same artifact mechanism — `path_policy.evaluate` + `has_active_exception`).
  - Preserve: the secret checks (§1/§2), module-size (§4), lint/typecheck (§5), the `fusebase-flow-managed-hook: v1` marker header, `set -uo pipefail`, exit-code contract. `install-git-hooks.sh` copies `hooks/git/pre-commit` verbatim — no interface break.
  - **Tests** (extend the protected-path pre-commit test): a staged DELETE of a protected path (`git rm hooks/shared/<x>`) is BLOCKED without an approval; a staged RENAME of a protected path (old and/or new under protection) is BLOCKED; a delete/rename WITH the sanctioned approval PASSES; a delete/rename of a NON-protected path PASSES; the existing ACM protected-edit block + the legit bootstrap flow still PASS. RED (current hook exits 0 on protected delete/rename) → GREEN.
- **T24 [MED] — hook-install call-site rc handling (no silent "installed" on installer failure).**
  - In `hooks/local/upgrade.sh` (~:483) and `hooks/local/post-fusebase-update.sh` (~:333): the `install-git-hooks.sh … | grep 'custom … detected'` pattern loses the installer rc (a nonzero install that doesn't print the custom-preserve line falls into the "installed" branch). Capture the installer OUTPUT and RC SEPARATELY: on rc≠0 → WARN/FAIL explicitly with a hint (do NOT report "installed"); only report installed on rc 0; detect the custom-preserve signal from the captured output. Keep it set -e-safe (this is the same class as the WS5 fix — neutralize/capture rc, don't let a nonzero abort silently).
  - **Tests:** installer rc≠0 ⇒ the call site warns/does-not-claim-installed; installer rc0 + custom-preserve signal ⇒ preserved-message; installer rc0 clean ⇒ installed-message. (Extend an upgrade/post-update test or add a focused one.)

## FR-07 / hard rules
`hooks/git/pre-commit` is protected (T23 uses the sanctioned bootstrap approval). `upgrade.sh`/`post-fusebase-update.sh`/tests are NOT protected. Do NOT touch policies/**, other FR rows, deploy-policy semantics, ratchet, health-check verdict engine, or the bounded-run engine. The single-use exception must stay single-use (do not weaken it — T23 EXTENDS coverage to delete/rename, it must not open a new bypass). Do NOT `--no-verify`. Do NOT bump VERSION/push/tag.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ protected DELETE blocked  ☐ protected RENAME (old+new) blocked  ☐ delete/rename WITH approval passes  ☐ non-protected delete/rename passes
☐ secret §1/§2 unchanged (still ACM)  ☐ ACM protected-edit + legit bootstrap still pass  ☐ hook-install rc≠0 no longer silent-"installed"
☐ single-use exception not weakened  ☐ no --no-verify  ☐ commit cites the task (T23 via sanctioned approval)
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n`/`py_compile` changed files · run-tests PASS incl. the NEW tests (protected-delete-blocked · protected-rename-blocked · delete/rename-with-approval-passes · non-protected-delete/rename-passes · hook-install-rc-handled) bounded per-phase 0-FAIL · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** · FR-07 clean (T23 via sanctioned single-use approval, consumed) · FR-27 no-runaways. Emit the FR-22 marker; produce the gate report; HALT. A Codex re-review runs on the fix before deploy.

## Return
Gate report: per-task SHAs (T23, T24), AC evidence (RED→GREEN protected-delete/rename now blocked; delete/rename-with-approval passes; non-protected passes; ACM + secret + legit-bootstrap unchanged; hook-install rc handled), no-regression, gate numbers, FR-07 statement + the bootstrap approval artifact used for T23. Do NOT push/tag.
