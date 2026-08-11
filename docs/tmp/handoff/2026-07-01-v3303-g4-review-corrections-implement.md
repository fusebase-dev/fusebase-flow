# Implement handoff — v3.30.3 Group 4: adversarial-review corrections (pre-deploy)

## Role bootstrap
AI Developer under FuseBase Flow v3.30.2. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03, FR-05, FR-07 (T10 EDITS a protected path — see note), FR-12 (secrets), FR-22, FR-25, FR-27. **Synchronous; bound long runs (host saturated); no runaways; stop at the gate; do NOT bump VERSION/push/tag.** These are pre-deploy corrections to the v3.30.3 candidate found by the FuseBase security-aware + Codex adversarial review of G1+G2+G3. One task = one commit.

## PROTECTED-PATH NOTE (FR-07 — sanctioned, not a bypass)
T10 edits `hooks/shared/path_policy.py` (a `fusebase_flow_internals` protected path). If the installed pre-commit blocks the commit, author the **sanctioned** `state/approvals/protected_path_edit-<slug>.json` approval artifact FIRST, then commit. **NEVER `--no-verify`.** T11-T14 files are not protected.

## COMMENT POLICY (FR-22) — tripwire + pointer only. At done: `comment-policy review: applied (FR-22)`.

## Context — reviewed changeset
The v3.30.3 candidate is HEAD `f8ee3ab` (9 commits d6d2985..f8ee3ab on v3.30.2 `12a543f`). Two independent adversarial reviews (external Codex + a FuseBase 8-dimension workflow) found the issues below. Fix all confirmed items as additional commits BEFORE the v3.30.3 deploy. Health-check regression, WS6 migration, and FR-07/rule-integrity dimensions PASSED — do not touch them except as required by the fixes.

## Mandatory reads
1. `hooks/shared/path_policy.py` (`has_active_exception` :105-146, `compute_staged_tree_digest` :94-102, `_matches_any`/`_glob_starstar` :40-57), `hooks/local/write-bootstrap-approval.sh`, `policies/protected-paths.yml` (fusebase_flow_internals), `hooks/tests/test-bootstrap-exception.sh`.
2. `hooks/local/install-git-hooks.sh` (`is_flow_managed` :40-42, FLOW_MARKER :27), `hooks/git/pre-commit` + `hooks/git/commit-msg` (headers).
3. `hooks/local/lib/run-with-timeout.sh` (`_ffhc_tempfile_capture` :194-223 esp. the FFHC_LAST_WINPID lifecycle :211-223; `ffhc_msys_taskkill_winpid` :112-121), `hooks/tests/run-tests.sh` (`_ff_exit_reap` :37-41, `run_bounded_phase` :51-56).
4. `hooks/local/upgrade.sh` :460-469, `hooks/local/post-fusebase-update.sh` :434-443, `hooks/tests/test-health-check-timeout.sh` (`ht_ws6_preflight_dual_accept` :525-544).

## Scope — one task = one commit

- **T10 (BLOCKER, WS1b verifier hardening) — close the glob-path single-use bypass.**
  In `path_policy.py` `has_active_exception`, for category `fusebase_flow_internals` ONLY:
  - Require **EXACT membership**: replace the `path in approved_paths or any(_matches_any(...))` gate with exact `path in approved_paths` for the bootstrap category (drop the glob fallback — a glob like `hooks/shared/**` must NOT match a concrete queried path).
  - **Reject glob metacharacters**: if any `approved_path` contains `*`, `?`, `[`, or `**`, treat the artifact as invalid for bootstrap (`continue`). This prevents a crafted wildcard artifact from ever binding.
  - **Bind the digest to content+mode**: extend `compute_staged_tree_digest` to hash `<path>\0<mode>\0<object>` (add the staged mode, field 1 of `git ls-files --stage`), and for the bootstrap category REJECT any artifact whose approved_paths include a path with no staged content (the `-` placeholder) — an approvable internals path must actually be in the pending commit. `write-bootstrap-approval.sh` calls the SAME `compute_staged_tree_digest`, so the writer stays consistent (it already collects concrete staged paths via `git diff --cached --name-only`, never globs — verify it still mints a valid artifact after the change).
  - **Harden `_staged_blob_sha` parsing** (both reviews flagged this compounding bug): today `line = proc.stdout.strip()` then `return parts[1]` of the whole (possibly multi-line) output — when a pathspec matches MULTIPLE staged files it silently keeps only the alphabetically-first blob. Parse the output PER LINE and, since bootstrap now passes only concrete single paths, assert the `git ls-files --stage -- <path>` output is a single line for that exact path (or read the line whose trailing `\t<path>` matches). Never pass a glob as a git pathspec in the bootstrap digest path.
  - **Tests** (extend `test-bootstrap-exception.sh`): (a) a bootstrap artifact with a glob `paths` entry (`hooks/shared/**`) + a precomputed digest DENIES an edit to a concrete file under that tree; (b) an artifact listing a path with NO staged content DENIES; (c) the legit writer→commit flow still PASSES (regression); (d) the existing reuse-denial + concrete-path tests still PASS. Other protected categories UNCHANGED (backward-compatible).
- **T11 (HIGH, WS1c) — unique managed-hook marker (stop clobbering custom hooks that merely mention Fusebase Flow).**
  - Give `hooks/git/pre-commit` + `hooks/git/commit-msg` a UNIQUE managed marker line in the header (e.g. `# fusebase-flow-managed-hook: v1` — a token no hand-written custom hook would carry). In `install-git-hooks.sh` change `FLOW_MARKER` / `is_flow_managed` to match the UNIQUE marker (not the generic string `Fusebase Flow`), so a consumer's custom `.git/hooks/pre-commit` that references Fusebase Flow in a comment is treated as CUSTOM (backed up, preserved, not silently overwritten).
  - **Tests** (extend `test-bootstrap-exception.sh` or the hook-install test): a custom hook whose header contains the words "Fusebase Flow" but NOT the unique managed marker is PRESERVED + backed up (no clobber without `--force`); a genuine Flow hook (unique marker) is refreshed in place.
- **T12 (MED, correctness) — give the EXIT-trap the SAME re-verify guard as the deadline path (both reviews; Workflow proposes the stronger fix).**
  - Root cause: the run-tests EXIT-trap `_ff_exit_reap` calls the SINGLE-arg `ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID"` (no child pid) → the PID-reuse re-verify guard (`ffhc_msys_taskkill_winpid` :116-118) is bypassed; AND `_ffhc_tempfile_capture` never clears `FFHC_LAST_WINPID` (the :216 comment "Cleared once we return" is false), so between fixture iterations the global holds a DEAD/possibly-reused winpid.
  - Fix (do BOTH): (1) In `_ffhc_tempfile_capture`, set `FFHC_LAST_CHILD_PID="$_bpid"` right next to `FFHC_LAST_WINPID="$_winpid"` (:217), and CLEAR BOTH (`FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""`) immediately AFTER the wait/reap returns (after `FFHC_LAST_RC=$?`), so the library honors its own :216 comment and the globals are non-empty ONLY while the child is provably alive. Fix the false :216 comment. (2) In `run-tests.sh` `_ff_exit_reap`, pass the child pid through: `ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID" "$FFHC_LAST_CHILD_PID"` so the trap gets the same re-verify/PID-reuse skip as the deadline path; initialize `FFHC_LAST_CHILD_PID=""` alongside the existing `FFHC_LAST_WINPID=""` and clear it in `run_bounded_phase` too (belt-and-suspenders).
  - **Test** (extend `test-msys-tree-cleanup.sh`): after a bounded phase returns normally, BOTH `FFHC_LAST_WINPID` and `FFHC_LAST_CHILD_PID` are empty (an EXIT-trap reap is a no-op); and a stale/reused winpid is not swept. Preserve the existing ws2-* tests.
- **T13 (MED, accuracy) — correct the bootstrap-approval automation claim.**
  - In `write-bootstrap-approval.sh` header comments (:6-18), correct the overstated "The bootstrap writer … CONSUMES it after" to accurately describe the OPERATOR-driven flow (upgrade.sh / post-fusebase-update.sh PRINT the `mint → git commit → --consume` steps; the operator runs them). Note that because the artifact is digest-bound to the staged changeset, a lingering post-commit artifact no longer matches any new changeset (single-use holds even if `--consume` is skipped; TTL is 15 min). Pointer-style, FR-22.
- **T14 (MED/LOW, test integrity) — make the WS6 tests drive the REAL shipped code paths (both reviews; Workflow found a second case).**
  - `ht_ws6_preflight_dual_accept` (:529-543): stop grepping a hand-copied ERE (the `cp preflight.sh "$D"` at :532 is currently dead). Either (preferred) EXTRACT the real §5e marker predicate/ERE from `preflight.sh` (grep the actual pattern string out of the copied `$D/preflight.sh`, as `ht_ws6_migrate_idempotent` extracts `ff_migrate_marker`), or run `bash "$D/preflight.sh"` against a minimal OLD/NEW/none fixture tree and assert the marker error is absent for OLD+NEW and present for a non-marker heading. Remove the misleading "Run the REAL preflight" comment if you do not actually run it.
  - `ht_ws6_install_append_idempotent` (:572-589): stop re-inlining install.sh's append guard. SOURCE/extract the real `append_overlay` from `install.sh` (as WS6d extracts `ff_migrate_marker`) and drive IT, so the idempotency test guards the shipped code path.
  - Both tests must FAIL if the real preflight §5e ERE / install.sh `append_overlay` guard regresses.
- **T16 (LOW, hygiene) — drop the dead `changed` variable in ff_migrate_marker.**
  - In `hooks/local/post-fusebase-update.sh` `ff_migrate_marker` (~:172-178): `changed="$(awk … >"$tmp")"` always captures empty (awk stdout is redirected to `$tmp`); the var is never read (rewrite-count comes from `$tmp.n`). Drop the `changed=` assignment + its `local` entry; run awk as a plain statement `awk … 2>"$tmp.n" >"$tmp"`. Behavior-preserving (WS6d idempotency test must still PASS). One-line hygiene commit.

## T15 — DEFERRED (do NOT implement this group)
The Codex review flagged (MED) that `staged_secret_scan.py` path-excludes whole designed-token/policy files. **Merged-review decision: DEFER — not required for v3.30.3.** The Workflow review's dedicated `sec-secret-scanner` dimension did NOT confirm this as a real defect; the narrow path-excludes are an accepted decision in the roadmap's folded Codex doc-review, and the T6 runtime-token approach already removed the need to exclude test files. The negative-secret-blocks test proves a real secret in any NON-excluded path still blocks. Keep `_EXCLUDE_PATHSPECS` narrow and UNCHANGED. (If a future hardening pass wants defense-in-depth, a value-allowlist of known designed fake tokens is the path — but it is out of scope here.)

## FR-07 / hard rules
Secret scanner must still block real secrets (narrow excludes). The single-use exception must NOT become a standing bypass (T10 is the core fix). Do NOT `--no-verify`. Do NOT bump VERSION/push/tag. No change to other FR rows / the 3 deploy-policy semantics / ratchet-governance.yml. The health-check verdict engine (rc0-no-run⇒BROKEN guard, verdict ENUM, exit codes) stays intact.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ one task scope  ☐ no TODO/FIXME/WIP  ☐ FR-22 comments  ☐ FR-25 <ceiling
☐ secret scanner still blocks real secrets  ☐ bootstrap exception single-use (glob + reuse both DENY)  ☐ custom .git/hooks preserved  ☐ no --no-verify
☐ VERSION unchanged; other FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Task summary (one commit each): T10 (BLOCKER glob bypass) · T11 (HIGH unique hook marker) · T12 (MED trap re-verify) · T13 (MED cleanup-comment accuracy) · T14 (MED/LOW WS6c+WS6e test fidelity) · T16 (LOW dead-var hygiene). T15 is DEFERRED — do NOT implement.

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n`/`py_compile` changed files · run-tests PASS incl. the NEW tests (glob-artifact-denies · no-staged-content-denies · legit-flow-passes · custom-hook-preserved-by-unique-marker · winpid+childpid-cleared-on-return · real-preflight-predicate · real-append_overlay) bounded per-phase 0-FAIL · check-module-size --all exit 0 · **mirror 0 drift via a SINGLE `mirror-skills.sh --check`** · FR-07 clean. Emit the FR-22 marker; produce the gate report; HALT. A final Codex re-review runs on the corrected diff before deploy.

## Return
Gate report: per-task SHAs (T10-T14, T16), AC evidence (esp. the BLOCKER: glob-artifact DENIES a new file under the glob + legit writer→commit flow still PASSES), no-regression (reuse-denial + concrete-path + ws2-* + health-check-timeout + WS6a/b/d guards still GREEN), gate numbers, FR-07 statement, and the protected-path approval artifact used for T10. Do NOT push/tag.
