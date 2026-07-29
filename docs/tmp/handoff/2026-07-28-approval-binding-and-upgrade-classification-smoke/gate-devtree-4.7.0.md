```text
[run-tests] starting fixture handler tests (single-process)
[run-tests] fixture handler tests (single-process) took 0s
PASS: 01_pre_tool_use_blocked_rm_rf.json  (blocked rm -rf) -> decision=deny
PASS: 02_pre_tool_use_blocked_git_add_dot.json  (blocked git add .) -> decision=deny
PASS: 03_pre_tool_use_blocked_git_add_A.json  (blocked git add -A) -> decision=deny
PASS: 04_pre_tool_use_blocked_git_reset_hard.json  (blocked git reset --hard) -> decision=deny
PASS: 05_pre_tool_use_blocked_no_verify.json  (blocked --no-verify) -> decision=deny
PASS: 06_pre_tool_use_blocked_env_write.json  (blocked .env write (protected path)) -> decision=deny
PASS: 07_pre_tool_use_blocked_protected_path_edit.json  (blocked protected path edit (deployment config)) -> decision=deny
PASS: 08_pre_tool_use_allowed_harmless.json  (allowed harmless command (git status)) -> decision=allow
PASS: 09_stop_blocks_done_without_gate.json  (Stop hook blocks 'implementation complete' claim without gate evidence) -> decision=deny
PASS: 10_user_prompt_submit_secret.json  (UserPromptSubmit detects pasted secret-like text (GitHub PAT)) -> decision=warn
PASS: 11_pre_tool_use_secret_in_write.json  (PreToolUse blocks write that introduces a secret-shaped value) -> decision=deny
PASS: 12_pre_tool_use_cookie_escalation.json  (PreToolUse blocks Write that contains a session cookie (pattern_overrides escalates cookie_session_value warn -> block in pre_tool_use)) -> decision=deny
PASS: 13_stop_blocks_deploy_complete_without_cleanup_marker.json  (Stop hook blocks 'deploy complete' claim when live-user verification was used but cleanup marker phrase is missing) -> decision=deny
PASS: 14_stop_allows_deploy_complete_with_cleanup_marker.json  (Stop hook allows 'deploy complete' claim when live-user verification was used AND cleanup marker phrase is present) -> decision=allow
PASS: 15_stop_allows_lightweight_deploy_complete.json  (Stop hook ALLOWS a Lightweight-lane (FR-21) deploy-complete claim without the Full-lane probes table / post-deploy docs commit / smoke � as long as the safety floor (deploy hash + rollback) is present) -> decision=allow
PASS: 16_stop_blocks_lightweight_deploy_complete_without_rollback.json  (Stop hook still BLOCKS a Lightweight-lane deploy-complete claim that drops a safety-floor signal (no rollback note) � FR-21 drops ceremony, not the safety floor) -> decision=deny
PASS: 17_user_prompt_submit_native_prompt_key_secret.json  (UserPromptSubmit (NATIVE Claude Code shape: 'prompt' key, no 'user_prompt') detects pasted GitHub PAT -> warn fires live) -> decision=warn
PASS: 18_stop_native_transcript_doneclaim.json  (Stop (NATIVE Claude Code shape: NO agent_message, transcript_path only) denies 'implementation complete' final assistant message without gate evidence -> deny fires live) -> decision=deny
PASS: 19_stop_native_transcript_midclaim_no_overtrigger.json  (Stop (NATIVE shape) does NOT over-trigger: a done-claim EARLIER in the transcript with a CLEAN final assistant message -> allow (claim detection scans only the final message, never history)) -> decision=allow
PASS: 20_stop_native_corrupt_transcript_claim_failclosed.json  (Stop (NATIVE shape) FAILS CLOSED on extraction failure: a corrupt/format-drifted transcript_path that carries a done/deploy claim but from which NO final assistant message can be extracted -> deny (the ungateable claim cannot be verified). RED on eb50078 (fell through to allow).) -> decision=deny
PASS: 21_stop_native_corrupt_transcript_noclaim_allow.json  (Stop (NATIVE shape) does NOT false-deny on a claimless corrupt transcript: a corrupt/format-drifted transcript_path with NO final assistant message AND no done/deploy claim text -> allow (the extraction-failure fallback fires only when the raw text carries a claim).) -> decision=allow
PASS: 22_pre_tool_use_compound_requires_all_actions.json  (compound command with NO artifact denies (K8 all-match, no-artifact path). NOT a first-match discriminator � this fixture is denied by the old code too; the discriminating case (first action SATISFIED, deny hinges on the second) runs through both handlers in hooks/tests/test-command-policy.sh, because run_hook_tests.py executes every fixture from the repo root and a fixture cannot carry its own state/approvals/.) -> decision=deny
PASS: 23_permission_request_compound_requires_all_actions.json  (compound command with NO artifact denies (K8 all-match, no-artifact path). NOT a first-match discriminator � this fixture is denied by the old code too; the discriminating case (first action SATISFIED, deny hinges on the second) runs through both handlers in hooks/tests/test-command-policy.sh, because run_hook_tests.py executes every fixture from the repo root and a fixture cannot carry its own state/approvals/.) -> decision=deny
PASS: _parse-invariant  (empty _expected_rule_id preserved; substring FR-12 selected)
[run-tests] starting module-size ratchet
[run-tests] module-size ratchet took 22s
PASS: module-size warn-without-baseline
PASS: module-size new-under-ceiling-passes
PASS: module-size new-over-ceiling-blocked
PASS: module-size ratchet-allows-shrink
PASS: module-size ratchet-blocks-growth
PASS: module-size exempt-glob-passes
PASS: module-size local-override-cannot-disarm
PASS: module-size single-file-rekey-ratchets
PASS: module-size preexisting-nonbaselined-shrink-allowed
PASS: module-size preexisting-nonbaselined-growth-blocked
PASS: module-size preexisting-nonbaselined-worktree-touch-allowed
PASS: module-size preexisting-nonbaselined-audit-still-reports
PASS: module-size rename-grown-monolith-still-blocks
PASS: module-size write-baseline-worktree-redirect-ignored
PASS: module-size worktree-redirect-victim-intact
PASS: module-size write-baseline-worktree-redirect-nonexistent-ignored
PASS: module-size worktree-redirect-no-stray-file
PASS: module-size write-baseline-committed-redirect-refused
PASS: module-size committed-redirect-victim-intact
PASS: module-size write-baseline-missing-policy-failclosed
PASS: module-size missing-policy-baseline-not-staged
[run-tests] starting health-check-timeout scenarios
[run-tests] health-check-timeout scenarios took 90s
PASS: health-check-timeout mv-baseline-healthy (D4): matching manifest => HEALTHY/0, integrity critical reports files-match
PASS: health-check-timeout mv-verify-timeout (T8a): verify timeout => hook layer integrity UNVERIFIED => PARTIAL_UNVERIFIED/exit 4, never 0
PASS: health-check-timeout mv-absent (T8b): absent manifest => standalone verifier rc 4 => engine PARTIAL_UNVERIFIED/exit 4 (SF8: never rc 3)
PASS: health-check-timeout mv-corrupt (T8c): corrupt manifest self-hash => verifier rc 2 => BROKEN/exit 2
PASS: health-check-timeout mv-tamper (T8d): covered-file tamper => verifier rc 1 => FLOW_LAYER_DRIFT/exit 1, names the drifted file
PASS: health-check-timeout mv-fast (T8e): --fast skips the integrity critical => exit 4 + 'not a full verdict', keeps preflight (--skip-hook-tests aliases it)
PASS: health-check-timeout mv-deeprun-adaptive-pass (D14 v4): MSYS --run-hook-tests => FAST diagnostic path, HEALTHY/0 (verdict unaffected)
PASS: health-check-timeout mv-deeprun-full-optin (D14 v4): --run-hook-tests-full forces the FULL run-tests.sh even on MSYS => HEALTHY/0 + full-suite line (FFHC_RUN_HOOK_TESTS_FULL=1 equivalent)
PASS: health-check-timeout mv-deeprun-fail (T8g/v4): forced-FAIL deep run => LOCAL_BROKEN => BROKEN/exit 2 (MSYS fast path OR POSIX full path)
PASS: health-check-timeout mv-deeprun-full-timeout (D5): full deep-run timeout => verdict UNAFFECTED (HEALTHY/0) + visible note
PASS: health-check-timeout mv-deeprun-unit-full-rc-contract (A2): strict PASS requires rc=0; rc=143 => LOCAL_BROKEN, rc=0 => LOCAL_OK
PASS: health-check-timeout mv-deeprun-unit-fast-rc-contract (A2): nested helper rejects rc!=0 and 0/0; PASS + rc=0 => LOCAL_OK
PASS: health-check-timeout ht6-no-timeout-bin (AC6): no timeout/gtimeout => bounded ops skipped => PARTIAL_UNVERIFIED/exit 4 (no hang)
PASS: health-check-timeout ws4-knob-surfacing (WS4): MSYS/Git-Bash defaults (preflight 60s / tests 120s) + knob names+values surfaced in the PARTIAL recommendation
PASS: health-check-timeout ws6-preflight-dual-accept (WS6): the REAL §5e ERE from preflight.sh accepts OLD+NEW markers, rejects a non-marker heading
PASS: health-check-timeout ws6-migrate-idempotent (WS6): post-fusebase-update ff_migrate_marker rewrites OLD->NEW once, idempotent
PASS: health-check-timeout ws6-install-append-idempotent (WS6): the REAL install.sh append_overlay runs once on a fresh file, no double-append, dual-marker guard skips a legacy tree
[run-tests] starting git-smoke
[run-tests] git-smoke took 12s
PASS: git-smoke commit-msg blocks missing T-number
PASS: git-smoke commit-msg allows docs prefix
PASS: git-smoke commit-msg allows T-numbered subject
PASS: git-smoke pre-commit blocks staged .env
PASS: git-smoke pre-commit passes benign staged file
[run-tests] starting hook-manifest
[run-tests] hook-manifest took 8s
PASS: hook-manifest covered set includes .jsonl; excludes *.local.* and __pycache__/*.pyc
PASS: hook-manifest deleted listed file => rc 1 DRIFT naming missing path
PASS: hook-manifest stamp byte-idempotence
PASS: hook-manifest verify MATCH
PASS: hook-manifest tampered covered file => drift naming it
PASS: hook-manifest Scan A extra hooks/shared file => drift
PASS: hook-manifest Scan B nested sitecustomize.py => startup-file drift
PASS: hook-manifest corrupt self-hash => rc 2; absent manifest => rc 4
[run-tests] starting newline-preserve
[run-tests] newline-preserve took 10s
PASS: newline-preserve trailing-newline-file-was-synced
PASS: newline-preserve no-newline-file-was-synced
PASS: newline-preserve trailing-newline-preserved
PASS: newline-preserve no-trailing-newline-preserved
[run-tests] starting baseline-merge
[run-tests] baseline-merge took 8s
PASS: baseline-merge upstream-count-wins
PASS: baseline-merge local-superseded-by-upstream
PASS: baseline-merge project-row-preserved-same-prefix
PASS: baseline-merge project-row-preserved-other-tree
PASS: baseline-merge absent-upstream-row-kept-by-membership
PASS: baseline-merge malformed-row-warned
PASS: baseline-merge standard-header
PASS: baseline-merge deterministic-sort
PASS: baseline-merge setup-fixture-exists
PASS: baseline-merge setup-fixture-line-count
PASS: baseline-merge setup-fixture-tracked
PASS: baseline-merge pre-upgrade-check-passes
PASS: baseline-merge clobber-removed-project-row
PASS: baseline-merge post-upgrade-project-row-survives
PASS: baseline-merge post-upgrade-check-passes
[run-tests] starting sync-allowlist
[run-tests] sync-allowlist took 6s
PASS: sync-allowlist allowlist-roots-parsed
PASS: sync-allowlist allowlist-files-parsed
PASS: sync-allowlist no-under-reach (18 framework files all reachable)
PASS: sync-allowlist guard-detects-omission (2-entry mutation: AGENTS.md + FLOW_RULES.md)
PASS: sync-allowlist docs-surface-is-top-level-only
PASS: sync-allowlist history-not-in-allowlist (carries live-looking tokens; excluded as dated history)
PASS: sync-allowlist history-never-synced
PASS: sync-allowlist consumer-doc-not-synced
[run-tests] starting policy-state
[run-tests] policy-state took 4s
PASS: policy-state pre-upgrade-workflow_mode-override-wins
PASS: policy-state pre-upgrade-worker_undisturbed-override-wins
PASS: policy-state local-overrides-survive-wholesale-copy
PASS: policy-state post-upgrade-workflow_mode-preserved
PASS: policy-state post-upgrade-worker_undisturbed-preserved
[run-tests] starting bootstrap-baseline-hop
[run-tests] bootstrap-baseline-hop took 7s
PASS: bootstrap-baseline-hop setup-inputs-present
PASS: bootstrap-baseline-hop extract-source-merge-lib
PASS: bootstrap-baseline-hop setup-fixture-exists
PASS: bootstrap-baseline-hop setup-fixture-line-count
PASS: bootstrap-baseline-hop setup-fixture-tracked
PASS: bootstrap-baseline-hop pre-hop-check-passes
PASS: bootstrap-baseline-hop precondition-no-local-lib
PASS: bootstrap-baseline-hop red-prefix-loses-row
PASS: bootstrap-baseline-hop green-engine-preserves-row
PASS: bootstrap-baseline-hop green-post-hop-check-passes
PASS: bootstrap-baseline-hop p1-precondition-no-lib
PASS: bootstrap-baseline-hop p1-bootstrap-stages-lib
PASS: bootstrap-baseline-hop p1-bootstrap-references-lib
[run-tests] starting fr22-delivery
[run-tests] fr22-delivery took 4s
PASS: fr22-delivery setup-inputs-present
PASS: fr22-delivery ac1-template-has-pushblock-header
PASS: fr22-delivery ac1-template-has-tripwire-line
PASS: fr22-delivery ac1-template-has-pointer-line
PASS: fr22-delivery ac1-template-has-density-clause
PASS: fr22-delivery ac1-template-present-by-construction-note
PASS: fr22-delivery ac3-red-absent-not-detected
PASS: fr22-delivery ac3-red-absent-still-allows
PASS: fr22-delivery ac3-green-applied-detected
PASS: fr22-delivery ac3-green-na-detected
PASS: fr22-delivery ac3-required-still-denies
[run-tests] starting po-verifiable-boot
[run-tests] po-verifiable-boot took 6s
PASS: po-verifiable-boot setup-inputs-present
PASS: po-verifiable-boot ac1-cmd-has-marker-prefix
PASS: po-verifiable-boot ac1-overlay-has-marker-prefix
PASS: po-verifiable-boot ac1-cmd-has-checklist
PASS: po-verifiable-boot ac1-cmd-overlay-byte-identical
PASS: po-verifiable-boot ac2-cmd-agent-block-match
PASS: po-verifiable-boot ac2-extracted-block-has-marker
PASS: po-verifiable-boot ac3-po-prompt-reminder
PASS: po-verifiable-boot ac3-nonpo-no-reminder
PASS: po-verifiable-boot ac3-never-blocks
PASS: po-verifiable-boot ac4-red-no-marker-warns
PASS: po-verifiable-boot ac4-red-no-marker-still-allows
PASS: po-verifiable-boot ac4-green-with-marker-no-warn
PASS: po-verifiable-boot ac4-green-nonpo-no-warn
PASS: po-verifiable-boot ac4-required-still-denies
[run-tests] starting po-investigate
[run-tests] po-investigate took 7s
PASS: po-investigate setup-inputs-present
PASS: po-investigate red-prefix-wrapper-breaches (--output wrote a file pre-fix)
PASS: po-investigate green-diff-output-refused (refused, no file, rc=2)
PASS: po-investigate green-diff-output-eq-o (refused, no file, rc=2)
PASS: po-investigate green-show-output-refused (refused, no file, rc=2)
PASS: po-investigate green-log-output-refused (refused, no file, rc=2)
PASS: po-investigate green-ext-diff-flag-refused (refused, no file, rc=2)
PASS: po-investigate green-c-config-refused (refused, no file, rc=2)
PASS: po-investigate green-paginate-refused (refused, no file, rc=2)
PASS: po-investigate green-env-scrub-no-external-exec
PASS: po-investigate legit-diff
PASS: po-investigate legit-diff-stat
PASS: po-investigate legit-diff-no-ext
PASS: po-investigate legit-log-oneline
PASS: po-investigate legit-show-file
PASS: po-investigate legit-status
PASS: po-investigate legit-output-indicator-not-overblocked
[run-tests] starting liveness
[run-tests] liveness took 129s
PASS: liveness setup-lib-present
PASS: liveness lib-syntax-clean
PASS: liveness ac3a-hang-rc-124-or-137
PASS: liveness ac3a-terminal-timeout-line
PASS: liveness ac3a-bounded-within-deadline
PASS: liveness ac3b-incremental-progress
PASS: liveness ac3d-ignored-sigterm-sigkilled
PASS: liveness ac3c-no-binary-skip-rc-125
PASS: liveness ac3c-no-binary-command-not-run
PASS: liveness ac3c-skip-marker-line
PASS: liveness ac6-health-check-timeout-no-regression
PASS: liveness ac6-ffhc-api-functions-present
PASS: liveness ac4-liveness-in-hard-invariants
PASS: liveness ac4-hard-region-bounded
PASS: liveness f3-nap-primitive-probed-usable (FFHC_NAP_OK=1 on this host)
PASS: liveness f3-fast-child-returns-well-under-budget (1s wall for a 600s-budget instant child, own rc=0 — reap loop did not block for the budget; nap ladder, not a 1s sleep floor)
PASS: liveness f3-no-early-reap-bounded (hang-child bounded at 2s => timeout rc=124 in 4s: FLOOR >=2s honored AND CEILING <=45s — never reaped early, never a late/never-kill regression)
PASS: liveness f3-fallback-sleep1-path-still-bounds (FFHC_NAP_OK=0 => literal sleep-1 loop still returns timeout rc=124 — zero regression on the fallback)
PASS: liveness f3-mkfifo-absent-forces-fallback (mkfifo unusable => FFHC_NAP_OK=0 => v3.30.5 sleep-1 behavior)
[run-tests] starting codex-parity
[run-tests] codex-parity took 42s
PASS: codex-parity setup-inputs-present
PASS: codex-parity ac1-table-header-present
PASS: codex-parity ac1-all-commands-listed
PASS: codex-parity ac1-portable-column-has-skill-invocation
PASS: codex-parity ac1-table-outside-flow-preserve
PASS: codex-parity ac2-installer-generated-files
PASS: codex-parity ac2-description-frontmatter-kept
PASS: codex-parity ac2-agents-path-repointed
PASS: codex-parity ac2-flow-marker-present
PASS: codex-parity ac2-po-boot-block-preserved
PASS: codex-parity ac2-drift-guard-canonical-edit-propagates
PASS: codex-parity ac3-all-files-marked
PASS: codex-parity ac3-idempotent-rerun
PASS: codex-parity ac3-refuses-unmarked-collision
PASS: codex-parity ac3-force-overwrites-unmarked
PASS: codex-parity ac3-marked-file-not-blocked
PASS: codex-parity ac3-no-frontmatter-hard-fails
PASS: codex-parity ac3-no-frontmatter-writes-no-unmarked-file
PASS: codex-parity ac3-no-frontmatter-red-proof
[run-tests] starting codex-plugin
[run-tests] codex-plugin took 2s
PASS: codex-plugin manifest-present
PASS: codex-plugin product-owner-canonical-skill-present
PASS: codex-plugin manifest-shape
PASS: codex-plugin canonical-product-owner-present
PASS: codex-plugin canonical-product-docs-first-present
PASS: codex-plugin canonical-product-apps-decomposition-present
PASS: codex-plugin agents-product-owner-mirror-present
PASS: codex-plugin claude-product-owner-mirror-present
PASS: codex-plugin product-owner-trigger-rich
PASS: codex-plugin product-owner-mirrors-byte-identical
[run-tests] starting cli-0259
[run-tests] cli-0259 took 33s
PASS: cli-0259 setup-files-present
PASS: cli-0259 ac1-red-pre-fix-phantom-confirmed
PASS: cli-0259 ac1-green-0259-set-not-drift
PASS: cli-0259 ac1-green-verdict-healthy
PASS: cli-0259 ac1-m4-dropped-is-advisory-not-drift
PASS: cli-0259 ac1-m4-no-exit1-from-missing-cli-hook
PASS: cli-0259 ac1-m4-verdict-stays-healthy
PASS: cli-0259 acm1-receipt-written-on-real-merge
PASS: cli-0259 acm1-receipt-lists-cli-hooks-only
PASS: cli-0259 acm1-receipt-durable-across-noop
PASS: cli-0259 acm2-receipt-dropped-hook-is-baseline-drift
PASS: cli-0259 acm2-unwired-typecheck-apps-stays-benign
PASS: cli-0259 acm2-verdict-healthy
PASS: cli-0259 acm2-exit-0
PASS: cli-0259 acm2-rebaseline-clears-advisory
PASS: cli-0259 acm3-no-receipt-is-unverified
PASS: cli-0259 acm3-verdict-healthy
PASS: cli-0259 acm3-exit-0
PASS: cli-0259 acm3-no-stop-py-no-nag
PASS: cli-0259 acl1-pristine-sha-eq-provenance-not-flagged
PASS: cli-0259 acl1-drifted-sha-ne-provenance-flagged
PASS: cli-0259 acl1-advisory-only-stays-healthy
PASS: cli-0259 acl1-provenance-absent-conservative-flag
PASS: cli-0259 ac2-merge-preserve-only
PASS: cli-0259 ac2-merge-idempotent
PASS: cli-0259 ac2-older-cli-typecheck-preserved
PASS: cli-0259 ac2-migrate-python3-to-wrapper
PASS: cli-0259 ac2-migrate-idempotent
PASS: cli-0259 ac2-migrate-no-clobber-customizations
PASS: cli-0259 ac3b-flag-gated-benign
PASS: cli-0259 ac3b-flag-gated-exit-not-drift
PASS: cli-0259 ac3-freshness-sha-matches-manifest
PASS: cli-0259 ac3-no-snapshot-stale
[run-tests] starting secret-scan-staged
[run-tests] secret-scan-staged took 136s
PASS: secret-scan-staged setup-helper-present
PASS: secret-scan-staged a1-edit-secret-patterns-not-blocked
PASS: secret-scan-staged a1-real-secret-plus-line-still-blocks
PASS: secret-scan-staged a1-removed-line-secret-not-blocked
PASS: secret-scan-staged a1-fixtures-excluded-deliberate-gap
PASS: secret-scan-staged backup-fixture-policy-twins-excluded
PASS: secret-scan-staged secret-still-blocks-backup-of-real-file
PASS: secret-scan-staged secret-still-blocks-name-spoof-no-ts
PASS: secret-scan-staged secret-still-blocks-untimestamped-fixtures
PASS: secret-scan-staged secret-still-blocks-tz-glob-spoof
PASS: secret-scan-staged secret-still-blocks-exact-ts-non-root
PASS: secret-scan-staged secret-still-blocks-exact-ts-wrong-prefix
PASS: secret-scan-staged a2-no-whitelist-added
PASS: secret-scan-staged a2-fixture10-still-detects
PASS: secret-scan-staged a2-fixture11-still-detects
PASS: secret-scan-staged a1-real-secret-in-nondesigned-test-still-blocks
PASS: secret-scan-staged release-gate-self-test-tree-commits-clean
PASS: secret-scan-staged secret-scan-script-tamper-blocks (trusted HEAD scanner runs, exit 1)
PASS: secret-scan-staged secret-scan-script-tamper-RED-t30-not-exit0-here (GREEN still asserted)
PASS: secret-scan-staged secret-scan-patterns-tamper-blocks (trusted HEAD patterns run, exit 1)
PASS: secret-scan-staged secret-scan-patterns-tamper-RED-t30-not-exit0-here (GREEN still asserted)
PASS: secret-scan-staged secret-scan-still-blocks-normal (trusted HEAD, untampered, exit 1)
PASS: secret-scan-staged secret-scan-no-over-block-legit-passes (trusted HEAD §2, non-secret)
PASS: secret-scan-staged secret-scan-bootstrap-edge-falls-back (working-tree scanner note emitted)
PASS: secret-scan-staged secret-scan-bootstrap-edge-still-blocks (fallback scanner blocks the real secret, exit 1)
PASS: secret-scan-staged secret-scan-transient-error-fails-closed (source)
PASS: secret-scan-staged secret-scan-invokes-trusted-head-not-worktree (source: §2 imports from SEC_IMPORT_DIR, no bare $ROOT/hooks helper invocation)
PASS: secret-scan-staged secret-scan-pyyaml-imports-under-S (getsitepackages re-add works for the §2 seed)
PASS: secret-scan-staged cwd-shadow-secret-pathlib-blocks (§2 file-script strips CWD; pathlib shadow inert, exit 1)
PASS: secret-scan-staged cwd-shadow-secret-pathlib-RED-was-fail-open (41a8c6d stdin -S - imported the repo-root pathlib shadow; secret self-passed at exit 0)
PASS: secret-scan-staged cwd-shadow-secret-yaml-blocks (discriminating shim inert; real PyYAML wins; §2 BLOCKS, exit 1)
PASS: secret-scan-staged cwd-shadow-secret-yaml-RED-was-fail-open (41a8c6d: discriminating shim neutered §2, kept §3 green; the AWS key self-passed at exit 0)
PASS: secret-scan-staged cwd-strip-no-over-block-legit-passes (T32 file-script §2, non-secret, PyYAML imports)
PASS: secret-scan-staged cwd-strip-still-blocks-untampered-secret (§2 detection intact under file-script, exit 1)
PASS: secret-scan-staged cwd-strip-sec-main-is-file-script (source: §2 MAIN runs python3 -S $SEC_TMP/_main_secret.py, no stdin -S -)
PASS: secret-scan-staged cwd-strip-syspath-has-no-cwd (file-script + in-script scrub: '', '.', CWD absent before first non-builtin import)
PASS: secret-scan-staged cwd-strip-restore-site-packages-prepends (staged_secret_scan: insert after leading trusted dir, not append)
PASS: secret-scan-staged cwd-strip-pythonsafepath-exported (defense-in-depth: 3.11+ never puts CWD on sys.path)
PASS: secret-scan-staged cwd-strip-sec-sentinel-file-redirect (§2 sentinel via file redirect, no $(git ls-tree) command substitution — MSYS rc=124 hang closed)
[run-tests] starting bootstrap-exception
[run-tests] bootstrap-exception took 281s
PASS: bootstrap-exception 1-blocks-without-approval
PASS: bootstrap-exception 1-passes-with-bootstrap-approval-no-noverify
PASS: bootstrap-exception 2-reuse-second-unrelated-edit-denies
PASS: bootstrap-exception 2-consume-cleans-artifact
PASS: bootstrap-exception 4-glob-artifact-denies
PASS: bootstrap-exception 4b-no-staged-content-denies
PASS: bootstrap-exception 3-custom-hook-preserved
PASS: bootstrap-exception 3-custom-hook-backed-up
PASS: bootstrap-exception 3-force-installs-flow-hook
PASS: bootstrap-exception 3-flow-hook-refreshed-in-place
PASS: bootstrap-exception 6a-protected-delete-blocked
PASS: bootstrap-exception 6b-protected-delete-with-approval-passes
PASS: bootstrap-exception 6c-protected-rename-blocked
PASS: bootstrap-exception 6d-protected-rename-with-approval-passes
PASS: bootstrap-exception 6e-rename-leaving-protection-blocked
PASS: bootstrap-exception 6f-rename-entering-protection-blocked
PASS: bootstrap-exception 6g-nonprotected-delete-passes
PASS: bootstrap-exception 6g-nonprotected-rename-passes
PASS: bootstrap-exception 6h-delete-approval-single-use
PASS: bootstrap-exception 5-fusebase-mentioning-custom-hook-preserved
PASS: bootstrap-exception 5-fusebase-mentioning-custom-hook-backed-up
PASS: bootstrap-exception 5-genuine-flow-hook-refreshed-by-unique-marker
PASS: bootstrap-exception 7-import-error-fails-closed (pre-commit BLOCKS, exit 1)
PASS: bootstrap-exception 7-import-error-diagnostic-emitted
PASS: bootstrap-exception 8-git-mask-lists-staged-file
PASS: bootstrap-exception 8-python3-absent-non-blocking
PASS: bootstrap-exception 8-python3-absent-loud-warn (git-preserving mask; §3 names the un-enforceable FR-07 check — a loud WARN, not a silent skip)
PASS: bootstrap-exception 9a-enum-failure-fails-closed (pre-commit BLOCKS, exit 1)
PASS: bootstrap-exception 9a-enum-failure-diagnostic-emitted
PASS: bootstrap-exception 9a-RED-old-code-was-fail-open (T25 pre-commit exit 0 on the same scenario)
PASS: bootstrap-exception 9b-git-list-failure-fails-closed (pre-commit BLOCKS, exit 1)
PASS: bootstrap-exception 9b-git-list-failure-diagnostic-emitted
PASS: bootstrap-exception 10a-no-staged-changes-passes (rc0-empty not over-blocked)
PASS: bootstrap-exception 10b-nonprotected-edit-passes
PASS: bootstrap-exception 10c-protected-edit-with-approval-passes
PASS: bootstrap-exception 11-systemexit0-import-blocks (pre-commit BLOCKS, exit 1)
PASS: bootstrap-exception 11-systemexit0-import-diagnostic
PASS: bootstrap-exception 11-RED-t26-was-fail-open (dadea26 exit 0 on SystemExit(0) import)
PASS: bootstrap-exception 11b-systemexit0-in-evaluate-blocks (exit 1)
PASS: bootstrap-exception 11b-systemexit0-in-evaluate-diagnostic
PASS: bootstrap-exception 11c-clean-nohit-still-passes (SystemExit split doesn't over-block)
PASS: bootstrap-exception 12a-staged_change_paths-raises-on-rc (unit)
PASS: bootstrap-exception 12b-name-status-partial-rc-blocks (exit 1)
PASS: bootstrap-exception 12b-name-status-partial-diagnostic
PASS: bootstrap-exception 12b-RED-t26-not-exit0-here (GREEN still asserted)
PASS: bootstrap-exception 13a-missing-policy-blocks (exit 1)
PASS: bootstrap-exception 13a-missing-policy-diagnostic
PASS: bootstrap-exception 13a-RED-t26-was-fail-open (missing policy exit 0)
PASS: bootstrap-exception 13b-empty-policy-blocks (exit 1)
PASS: bootstrap-exception 13c-emptied-sentinel-category-blocks (exit 1)
PASS: bootstrap-exception 14a-local-override-cannot-erase-internals (unit: base paths re-unioned)
PASS: bootstrap-exception 14b-erasing-local-still-blocks-protected-edit (exit 1)
PASS: bootstrap-exception 14c-additive-local-override-still-honored
PASS: bootstrap-exception 15a-happy-path-protected-edit-still-blocks
PASS: bootstrap-exception 15b-happy-path-with-approval-passes
PASS: bootstrap-exception 15c-cross-policy-get_policy-unchanged (approval-policy local override wins)
PASS: bootstrap-exception 16-outer-git-list-rc-guard-present (source)
PASS: bootstrap-exception 17-ac11-shared-parsed-expiry-across-carriers
PASS: bootstrap-exception 18-active-approvals-status-aware-array-contract-intact
[run-tests] starting trusted-enforcer
[run-tests] trusted-enforcer took 178s
PASS: trusted-enforcer 17-tamper-lying-enforcer-blocks (trusted HEAD runs, exit 1)
PASS: trusted-enforcer 17-tamper-diagnostic-emitted
PASS: trusted-enforcer 17-RED-t27-was-fail-open (working-tree enforcer exit 0: the lie self-passed)
PASS: trusted-enforcer 18-legit-approved-enforcer-edit-passes (trusted HEAD honors the working-tree approval)
PASS: trusted-enforcer 18-unapproved-enforcer-edit-blocks
PASS: trusted-enforcer 19a-common-nonprotected-edit-passes
PASS: trusted-enforcer 19b-common-protected-nonenforcer-edit-blocks
PASS: trusted-enforcer 19c-bootstrap-first-add-falls-back (working-tree enforcer note emitted)
PASS: trusted-enforcer 19c-bootstrap-first-add-with-approval-passes
PASS: trusted-enforcer 19d-transient-error-fails-closed-not-fallback (source)
PASS: trusted-enforcer 20a-tooltime-missing-policy-denies (fail closed)
PASS: trusted-enforcer 20b-tooltime-empty-policy-denies
PASS: trusted-enforcer 20c-tooltime-shipped-policy-nonprotected-allows
PASS: trusted-enforcer 20d-tooltime-shipped-policy-protected-denies
PASS: trusted-enforcer 20-RED-t27-was-fail-open (pre-T28 handler allowed the protected write on missing policy)
PASS: trusted-enforcer 21-unstaged-enforcer-tamper-blocks (trusted HEAD runs unconditionally, exit 1)
PASS: trusted-enforcer 21-unstaged-tamper-diagnostic-emitted
PASS: trusted-enforcer 21-RED-t28-was-fail-open (conditional OFF: unstaged lie self-passed at exit 0)
PASS: trusted-enforcer 22a-sitecustomize-injection-blocks (-S disables startup file; §3 runs, exit 1)
PASS: trusted-enforcer 22a-RED-t28-was-fail-open (startup os._exit(0) exited the check at 0)
PASS: trusted-enforcer 22b-usercustomize-injection-blocks (-S disables usercustomize; exit 1)
PASS: trusted-enforcer 22c-secret-scan-still-blocks-under-S (§2 ran under -S with sitecustomize present, exit 1)
PASS: trusted-enforcer 23-prep-step-injection-blocks (env scrub + -S PREP + git decision, exit 1)
PASS: trusted-enforcer 23-prep-injection-diagnostic-emitted
PASS: trusted-enforcer 23-RED-t29-was-fail-open (plain-python3 PREP honored the forged RESULT=fallback; the PoC self-passed at exit 0)
PASS: trusted-enforcer 24a-hostile-pythonpath-protected-no-approval-blocks (exit 1)
PASS: trusted-enforcer 24b-hostile-pythonpath-nonprotected-passes (no over-block)
PASS: trusted-enforcer 25-forged-fallback-impossible-when-HEAD-has-enforcer (git decides trusted; forged RESULT inert -> BLOCK, exit 1)
PASS: trusted-enforcer 26-pyyaml-imports-under-S (getsitepackages re-add works)
PASS: trusted-enforcer 27-cwd-shadow-fr07-pathlib-blocks (§3 file-script strips CWD; pathlib shadow inert, exit 1)
PASS: trusted-enforcer 27-cwd-shadow-fr07-pathlib-diagnostic
PASS: trusted-enforcer 27-RED-was-fail-open (41a8c6d stdin -S - imported the repo-root pathlib shadow; the protected edit self-passed at exit 0)
PASS: trusted-enforcer 28-cwd-shadow-fr07-yaml-blocks (§3 file-script strips CWD; repo-root yaml.py shadow inert, exit 1)
PASS: trusted-enforcer 28-RED-yaml-was-fail-open (41a8c6d imported the repo-root yaml.py shadow at the §3 seed; the protected edit self-passed at exit 0)
PASS: trusted-enforcer 29-cwd-strip-legit-approved-enforcer-edit-passes (T32 §3 file-script honors the working-tree approval)
PASS: trusted-enforcer 29-cwd-strip-nonprotected-edit-passes (no over-block)
PASS: trusted-enforcer 30-cwd-strip-fr07-main-is-file-script (source: §3 MAIN runs python3 -S $FR07_TMP/_main.py, no stdin -S -)
PASS: trusted-enforcer 30-cwd-strip-inscript-scrub-uses-builtin-oscore (nt/posix builtin -> unshadowable CWD source; sys.path filtered, not del path[0])
PASS: trusted-enforcer 30-cwd-strip-fr07-sentinel-file-redirect (§3 sentinel via file redirect, no $(git ls-tree) command substitution — MSYS rc=124 hang closed)
[run-tests] starting hook-install-rc
[run-tests] hook-install-rc took 10s
PASS: hook-install-rc upgrade-rc-nonzero-no-silent-installed
PASS: hook-install-rc upgrade-rc0-custom-preserved
PASS: hook-install-rc upgrade-rc0-clean-installed
PASS: hook-install-rc upgrade-rc-nonzero-set-e-safe
PASS: hook-install-rc postup-rc-nonzero-no-silent-installed
PASS: hook-install-rc postup-rc0-custom-preserved
PASS: hook-install-rc postup-rc0-clean-installed
[run-tests] starting msys-tree-cleanup
[run-tests] msys-tree-cleanup took 49s
PASS: msys-tree-cleanup t8-tempfail-routes-to-skipped (unwritable TMPDIR => rc 125 + SKIPPED + empty out => UNVERIFIED, never false BROKEN/hang)
PASS: msys-tree-cleanup t8-no-cwd-tempfile-leak (explicit ${TMPDIR}/ffhc-bounded.$$.XXXXXX template — no transient files in CWD)
PASS: msys-tree-cleanup ws2-true-124-on-kill (overrun => rc 124 is timeout-induced 124/137, never 0)
PASS: msys-tree-cleanup ws2-no-hang-large-budget (returned in 0s with the command's own rc=7, not the 300s budget)
PASS: msys-tree-cleanup t12-winpid+childpid-cleared-on-return (both globals empty after a normal bounded return => EXIT-trap reap is a no-op)
PASS: msys-tree-cleanup t17-stdin-reaches-child (RED old stdout path=allow [stdin dropped] => GREEN new stdin path=deny [fixture reached handler])
PASS: msys-tree-cleanup t17-default-path-unchanged (non-stdin bounded run: stdout captured, own rc=7, < /dev/null EOF => no hang)
PASS: msys-tree-cleanup t17-stdin-path-t12-clear (stdin variant clears WINPID+CHILD_PID on return => EXIT-trap reap is a no-op)
PASS: msys-tree-cleanup t18-default-path-immune-to-exported-FFHC_CAPTURE_STDIN (exported flag=1 + piped fixture => DEFAULT wrapper still uses < /dev/null: cat sees EOF, captured out is marker-only, own rc=5)
PASS: msys-tree-cleanup t18-stdin-wrapper-still-delivers-fd0 (explicit inherit param drives the stdin path; deny-fixture DENIES even with the dead FFHC_CAPTURE_STDIN exported)
PASS: msys-tree-cleanup ws2hard-posix-body-byte-unchanged (run_with_timeout body sha256 == pinned WS2-core hash; the fence is additive-only)
PASS: msys-tree-cleanup ws2hard-default-off-no-extra-fork (knob-first gate: default-OFF bounded run never calls ffhc_job_available (0 probe invocations) + own rc/capture intact; source leads with the FFHC_USE_JOB_OBJECT compare — no uname/powershell fork added to the hot default path)
PASS: msys-tree-cleanup ws2hard-default-off-byte-identity (knob unset: own rc=3 + captured 'off-marker' + timeout rc=124 == today, no job branch taken)
PASS: msys-tree-cleanup ws2hard-probe-gating (knob=1 => AVAILABLE here; knob unset => OFF (default); FFHC_JOB_PROBE_FORCE_FAIL=1 => OFF)
PASS: msys-tree-cleanup ws2hard-job-rc-preserved+capture (job ON: own rc=7 + tempfile-captured stdout 'job-capture')
PASS: msys-tree-cleanup ws2hard-job-124-on-timeout (job ON: overrun => timeout-induced rc=124, never 0)
PASS: msys-tree-cleanup ws2hard-job-137-on-hard-kill (job ON path: stubborn TERM-ignoring child => rc 137 (128+SIGKILL) + captured 'started'; rc from wait $_bpid — mechanism exercised; NOT claimed as Job-Object-vs-timeout-k proof (consumer-gated))
PASS: msys-tree-cleanup ws2hard-job-sibling-survives (unrelated bash sleep pid=300690 alive after the fence's TerminateJobObject — assigned-tree-only, no collateral)
PASS: msys-tree-cleanup ws2hard-forced-probe-fail-clean-fallback (FFHC_JOB_PROBE_FORCE_FAIL=1 => WS2-core path: own rc=5 + 'fb-marker' in 1s, no hang, no re-run)
PASS: msys-tree-cleanup ws2hard-fast-opt-in-returns-promptly (secs=30 fast cmd returned in 1s (<=15s, no secs+grace stall) + rc0 + 'fast-opt-in'; fence called DIRECTLY (not $(…)) so FFHC_JOB_FENCE_HPID propagates + helper is reaped, no orphan — the command-substitution HANG/leak is fixed)
PASS: msys-tree-cleanup native-descendant-returns-at-deadline (2s <= 6s)
PASS: msys-tree-cleanup native-descendant-rc-preserved (rc=124 is timeout-induced 124/137)
PASS: msys-tree-cleanup early-winpid-capture-plumbing-present (T7: winpid resolved at launch, taskkill on timeout)
PASS: msys-tree-cleanup tempfile-capture-faster-than-pipe (pipe 8s > tempfile 2s)
PASS: msys-tree-cleanup ws2-concurrent-sibling-survives (unrelated bash sleep pid=300791 alive after a bounded op's timeout-taskkill — reap scoped to recorded child only)
[run-tests] starting ws5-upgrade
[run-tests] ws5-upgrade took 28s
PASS: ws5-upgrade w1-prune-single-pass (single-pass: 154 -> 93 backups (keep 3/stem), 61 pruned, terminated in 6s — no per-stem busy-loop)
PASS: ws5-upgrade w1b-prune-keeps-newest (file1 kept the 3 newest timestamps: file1.txt.pre-upgrade-20260103T000001Z file1.txt.pre-upgrade-20260104T000001Z file1.txt.pre-upgrade-20260105T000001Z )
PASS: ws5-upgrade w2-optional-killed-continues (a killed OPTIONAL step WARNs + continues; harness reaches AFTER-OPTIONAL rc=0 — upgrade not failed)
PASS: ws5-upgrade w3-critical-killed-fails-with-hint (a killed CRITICAL step exits nonzero (rc=1) + prints the recovery hint + does NOT continue — never masks a partial upgrade)
PASS: ws5-upgrade w4-critical-failing-cmd-fails (a CRITICAL step whose cmd exits nonzero => exit 1 + recovery hint + halts — partial upgrade never reported success)
PASS: ws5-upgrade w5-optional-ok-returns0 (a fast successful OPTIONAL step returns 0 and continues — no spurious bound failure)
PASS: ws5-upgrade w9-optional-timeout-set-e-safe (UNDER set -e + ERR trap: a timed-out OPTIONAL step WARNs + continues + reaches the VERSION-write marker rc0 — the set -e wait-abort can no longer escape)
PASS: ws5-upgrade w10-optional-fail-set-e-safe (UNDER set -e: a fast-failing OPTIONAL step (rc4) WARNs + continues + reaches the marker rc0 — no wait-abort)
PASS: ws5-upgrade w11-critical-fail-set-e-exits-with-hint (UNDER set -e: a failing CRITICAL step exits nonzero (rc=1) via ffhc_run_step's FATAL+hint path — not a raw wait-abort that would skip the hint)
PASS: ws5-upgrade w12-degraded-optional-fail-set-e-safe (UNDER set -e, FFHC_STEP_LIB_OK=0 direct-run path: a failing OPTIONAL step WARNs + continues + reaches the marker rc0)
PASS: ws5-upgrade w13-prune-ignores-non-backup (non-backup .pre-upgrade-/.pre-refresh- files survive; genuine timestamped backups prune to newest-3/stem: real.txt.pre-upgrade-20260103T000001Z real.txt.pre-upgrade-20260104T000001Z real.txt.pre-upgrade-20260105T000001Z )
PASS: ws5-upgrade w6-version-write-critical-guard (upgrade.sh verifies the VERSION write landed + exits with the recovery hint on failure — CRITICAL, never a silent stale VERSION)
PASS: ws5-upgrade w7-remirror+prune-bounded-wiring (re-mirror + sync-strings routed through ffhc_run_step OPTIONAL bound; prune is single-pass — all present in the shipped engine)
PASS: ws5-upgrade w8-no-runaway-after-prune (prune left no background job: before=0 after=0)
[run-tests] starting ff-only
[run-tests] ff-only took 24s
PASS: ff-only ff-list-tag-count (37 canonical tags)
PASS: ff-only scoped-one-starting-marker
PASS: ff-only scoped-skip-count
PASS: ff-only scoped-summary-marker
PASS: ff-only scoped-fails-strict-classifier (ffhc_count_pass_lines=0)
PASS: ff-only scoped-summary-rejected-by-pass-ok
PASS: ff-only scoped-results-file-written
PASS: ff-only full-results-file-untouched-by-scoped-run
PASS: ff-only bogus-tag-exit-2
PASS: ff-only empty-selection-exit-2
PASS: ff-only scoped-with-injected-failure-exits-nonzero (rc=1)
[run-tests] starting return-budget
[run-tests] return-budget took 3s
PASS: return-budget setup-inputs-present
PASS: return-budget ac12-skill-both-limits
PASS: return-budget ac12-implement-both-limits
PASS: return-budget ac12-deploy-both-limits
PASS: return-budget ac12-skill-overflow-route
PASS: return-budget ac12-skill-commit-conditional
PASS: return-budget ac12-implement-overflow-route
PASS: return-budget ac12-deploy-overflow-route
PASS: return-budget ac12-skill-brief-field
PASS: return-budget ac13-implement-gate-exempt
PASS: return-budget ac13-deploy-report-exempt
PASS: return-budget ac13-skill-exemption
PASS: return-budget ac12-handoff-successor-pointer
PASS: return-budget red-line-only-cap-rejected
[run-tests] starting supersede-primitive
[run-tests] supersede-primitive took 3s
PASS: supersede-primitive setup-inputs-present
PASS: supersede-primitive ac14-flow-rules-both-dimensions
PASS: supersede-primitive ac14-role-discipline-both-dimensions
PASS: supersede-primitive ac14-handoff-skill-both-dimensions
PASS: supersede-primitive ac14-token-economy-both-dimensions
PASS: supersede-primitive ac14-template-both-dimensions
PASS: supersede-primitive ac14-flow-rules-semantics-clause
PASS: supersede-primitive ac14-role-discipline-write-primitive-section
PASS: supersede-primitive ac14-role-discipline-digest-row
PASS: supersede-primitive ac14-handoff-skill-fresh-disambiguated
PASS: supersede-primitive ac14-handoff-command
PASS: supersede-primitive ac14-handoff-overlay-twin
PASS: supersede-primitive ac14-audit-command
PASS: supersede-primitive ac14-audit-overlay-twin
PASS: supersede-primitive ac21-handoff-twin-byte-identical
PASS: supersede-primitive ac21-audit-twin-byte-identical
PASS: supersede-primitive ac14-audit-parser-header
PASS: supersede-primitive ac14-audit-parser-primitive-clause
PASS: supersede-primitive ac14-te06-contradiction-gone
PASS: supersede-primitive ac14-audit-contradiction-gone
PASS: supersede-primitive ac14-te-antipattern-qualified
[run-tests] starting rule-inventory
[run-tests] rule-inventory took 167s
PASS: rule-inventory setup-instrument-present
PASS: rule-inventory baseline-produced
PASS: rule-inventory covers-fr-01-27
PASS: rule-inventory covers-all-role-dont-lists
PASS: rule-inventory covers-b1-b12
PASS: rule-inventory schema-four-columns
PASS: rule-inventory schema-residency-values
PASS: rule-inventory schema-has-resident-rows
PASS: rule-inventory schema-has-lazy-rows
PASS: rule-inventory schema-relative-paths
PASS: rule-inventory covers-amended-categories
PASS: rule-inventory deterministic-rerun
PASS: rule-inventory drop-fr-row
PASS: rule-inventory drop-dont-row
PASS: rule-inventory drop-principle
PASS: rule-inventory reword-statement
PASS: rule-inventory reword-attestation
PASS: rule-inventory move-resident-to-lazy
PASS: rule-inventory move-dont-between-roles
PASS: rule-inventory reword-enforcement
PASS: rule-inventory principle-relayout
PASS: rule-inventory principle-as-bullet
PASS: rule-inventory range-heading-ignored
PASS: rule-inventory no-raw-version-literals
PASS: rule-inventory attestation-version-normalized
PASS: rule-inventory version-bump-perturbs-source
PASS: rule-inventory version-bump-green
PASS: rule-inventory fail-closed-zero-fr-rows
PASS: rule-inventory fail-closed-missing-sources
PASS: rule-inventory rejects-unknown-arg
[run-tests] starting boot-size
[run-tests] boot-size took 95s
PASS: boot-size ceiling-communication
PASS: boot-size ceiling-role-discipline
PASS: boot-size ceiling-flow-rules
PASS: boot-size ceiling-role-reference
PASS: boot-size total-boot-floor
PASS: boot-size frontmatter-first-communication
PASS: boot-size anti-reread-communication
PASS: boot-size frontmatter-first-role-discipline
PASS: boot-size anti-reread-role-discipline
PASS: boot-size required-references
PASS: boot-size body-eager-claim
PASS: boot-size red-fixture-baseline-green
PASS: boot-size red-ceiling-communication
PASS: boot-size red-ceiling-role-discipline
PASS: boot-size red-ceiling-flow-rules
PASS: boot-size red-ceiling-role-reference
PASS: boot-size red-total-boot-floor
PASS: boot-size red-frontmatter-first
PASS: boot-size red-anti-reread
PASS: boot-size red-missing-required-reference
PASS: boot-size red-body-eager-claim
PASS: boot-size ceilings-sum-to-total
[run-tests] starting prohibition-residency
[run-tests] prohibition-residency took 60s
PASS: prohibition-residency ledger-relay-mandatory
PASS: prohibition-residency ledger-relay-no-exceptions
PASS: prohibition-residency ledger-relay-wait
PASS: prohibition-residency ledger-popup-prohibition
PASS: prohibition-residency ledger-popup-refusal-phrasing
PASS: prohibition-residency ledger-gate-no-terminal
PASS: prohibition-residency ledger-gate-self-approval
PASS: prohibition-residency ledger-gate-uncovered-action
PASS: prohibition-residency ledger-gate-role-authority
PASS: prohibition-residency ledger-gate-backstops
PASS: prohibition-residency ledger-gate-deflection-phrasing
PASS: prohibition-residency ledger-momentum-prohibition
PASS: prohibition-residency ledger-momentum-refusal-phrasing
PASS: prohibition-residency ledger-supersede-prohibition
PASS: prohibition-residency ledger-supersede-refusal-phrasing
PASS: prohibition-residency ledger-operator-dont-list
PASS: prohibition-residency ledger-operator-not-enforced
PASS: prohibition-residency ledger-stop-missing-attestation
PASS: prohibition-residency ledger-stop-two-roles
PASS: prohibition-residency ledger-stop-operator-insists
PASS: prohibition-residency ledger-escalation-no-bypass
PASS: prohibition-residency ledger-no-on-demand-load
PASS: prohibition-residency ledger-no-prohibition-demotion
PASS: prohibition-residency ledger-modeb-visuals
PASS: prohibition-residency ledger-modeb-b3
PASS: prohibition-residency ledger-modeb-b4
PASS: prohibition-residency ledger-modeb-b5
PASS: prohibition-residency ledger-modeb-b6
PASS: prohibition-residency ledger-modeb-b7
PASS: prohibition-residency ledger-modeb-b8
PASS: prohibition-residency ledger-modeb-b11
PASS: prohibition-residency ledger-modeb-b12
PASS: prohibition-residency ledger-modea-decoration
PASS: prohibition-residency ledger-modea-width
PASS: prohibition-residency lazy-scope
PASS: prohibition-residency lazy-normative-clean
PASS: prohibition-residency red-fixture-baseline-green
PASS: prohibition-residency red-planted-lazy-prohibition
PASS: prohibition-residency red-demoted-prohibition
[run-tests] starting token-waste-classify
[run-tests] token-waste-classify took 26s
PASS: token-waste-classify setup-inputs-present
PASS: token-waste-classify report-written
PASS: token-waste-classify ac18-live-counts-exclude-dismissed
PASS: token-waste-classify ac18-dismissed-counted-separately
PASS: token-waste-classify ac15-growing-tail-dismissed
PASS: token-waste-classify ac16-probe-triple-dismissed
PASS: token-waste-classify ac15-size-differs-only-not-dismissed
PASS: token-waste-classify ac15-intervening-write-not-dismissed
PASS: token-waste-classify ac15-compaction-not-dismissed
PASS: token-waste-classify ac15-error-result-not-dismissed
PASS: token-waste-classify ac16-nonprobe-triple-not-dismissed
PASS: token-waste-classify ac16-nonprobe-quad-not-dismissed
PASS: token-waste-classify ac27-row-02
PASS: token-waste-classify ac27-row-03
PASS: token-waste-classify ac27-row-04
PASS: token-waste-classify ac27-row-05
PASS: token-waste-classify ac27-row-07
PASS: token-waste-classify ac27-row-08
PASS: token-waste-classify ac27-mutctl-02
PASS: token-waste-classify ac27-mutctl-03
PASS: token-waste-classify ac27-mutctl-04
PASS: token-waste-classify ac27-mutctl-05
PASS: token-waste-classify ac27-mutctl-07
PASS: token-waste-classify ac27-mutctl-08
PASS: token-waste-classify ac17-growing-tail-evidence
PASS: token-waste-classify ac17-probe-triple-evidence
PASS: token-waste-classify ac15-size-differs-only-evidence
PASS: token-waste-classify ac15-contradictory-write
PASS: token-waste-classify ac15-contradictory-compaction
PASS: token-waste-classify ac15-contradictory-error
PASS: token-waste-classify ac16-triple-label-kept-live
PASS: token-waste-classify ac16-since-last-write-noted
PASS: token-waste-classify ac18-live-section
PASS: token-waste-classify ac18-dismissed-section
PASS: token-waste-classify ac18-live-table-has-no-dismissals
PASS: token-waste-classify ac16-probe-command-branch
PASS: token-waste-classify ac16-probe-command-evidence
PASS: token-waste-classify ac19-state-candidates-found
PASS: token-waste-classify ac19-state-all-classified
PASS: token-waste-classify ac19-state-clean
PASS: token-waste-classify ac19-state-parse-failure
PASS: token-waste-classify ac19-state-no-transcripts
PASS: token-waste-classify ac25-falseneg-none-dismissed
PASS: token-waste-classify ac25-falseneg-all-stay-live
PASS: token-waste-classify ac25-echo-status-not-dismissed
PASS: token-waste-classify ac25-message-status-not-dismissed
PASS: token-waste-classify ac25-probe-plus-mutation-not-dismissed
PASS: token-waste-classify ac26-path-alias-not-dismissed
PASS: token-waste-classify privacy-no-result-bodies
[run-tests] starting budget-literals
[run-tests] budget-literals took 54s
PASS: budget-literals enforced-ceilings-read (5 distinct CEIL_* literals)
PASS: budget-literals no-divergent-budget-literal (enforced: 11500 14500 42200 7000 9200)
PASS: budget-literals enforced-total-stated-in-prose (4 carrier(s) say 42,200)
PASS: budget-literals red-stale-literal-detected
PASS: budget-literals green-current-literal-accepted
PASS: budget-literals annotated-history-exempt
[run-tests] starting history-extraction
[run-tests] history-extraction took 5s
PASS: history-extraction setup-inputs-present
PASS: history-extraction stub-heading-retained
PASS: history-extraction stub-carries-no-dated-entries
PASS: history-extraction extraction-commit-resolved (cfac6c0)
PASS: history-extraction payloads-extracted
PASS: history-extraction content-equivalent-modulo-final-newline
PASS: history-extraction only-difference-is-the-final-newline (raw delta 1B)
PASS: history-extraction red-truncated-payload-detected
PASS: history-extraction red-edited-payload-detected
[run-tests] starting approval-binding
[run-tests] approval-binding took 7s
PASS: approval-binding verdict-table-and-loader-total
PASS: approval-binding ac3-extreme-offset-denies-through-both-handlers
PASS: approval-binding command-policy-action-agreement-and-root-anchoring
PASS: approval-binding ac9-binding-enforced-when-present
PASS: approval-binding ac14-denial-message-specific-and-bounded
PASS: approval-binding ac11-compat-acceptance-audited-cross-carrier
PASS: approval-binding ac11-active-approvals-honors-strict
PASS: approval-binding ac11-active-approvals-compat-acceptance-audited
[run-tests] starting approval-writer
[run-tests] approval-writer took 17s
PASS: approval-writer ac10-unknown-action-rejected
PASS: approval-writer ac10-unsafe-slug-rejected
PASS: approval-writer ac22-command-mandatory-for-gated-action
PASS: approval-writer ac22-non-gated-action-still-optional
PASS: approval-writer ac10-adversarial-values-round-trip
PASS: approval-writer ac22-emitted-invocation-round-trips
PASS: approval-writer ac12-inventory-four-verdicts-and-reject-count
PASS: approval-writer ac27-inventory-never-accepts-a-gate-rejected-artifact
PASS: approval-writer ac12-strict-vs-compat-and-audited-legacy-acceptance
PASS: approval-writer ac19-no-authorship-enforcement-claim
PASS: approval-writer ac19-approval-authors-marked-declarative
[run-tests] starting command-policy
[run-tests] command-policy took 3s
PASS: command-policy failclosed-and-all-match
PASS: command-policy ac8-lightweight-parity-both-handlers
PASS: command-policy ac26-evasion-limit-documented-and-backlogged
[run-tests] starting upgrade-classify
[run-tests] upgrade-classify took 81s
PASS: upgrade-classify manifest-byte-stable-drift-and-single-home
PASS: upgrade-classify k9-ten-state-truth-table-and-auto-yes-containment
PASS: upgrade-classify ac16-changed-by-both-aborts-auto-yes-and-preserves-the-patch
PASS: upgrade-classify ac13c-partial-apply-preserves-one-refreshes-siblings
PASS: upgrade-classify ac13b-base-refresh-keeps-the-classifier-correct-on-the-next-upgrade
PASS: upgrade-classify ac23-classifier-unavailable-fails-closed-and-writes-nothing
PASS: upgrade-classify ac23-unsafe-legacy-copy-is-the-only-legacy-route
PASS: upgrade-classify ac23-pre-classifier-source-still-upgrades
PASS: upgrade-classify ac13b-base-synthesis-from-the-version-tag-delivers-content
PASS: upgrade-classify k9-row10-unresolvable-tag-preserves-and-reports-never-aborts
PASS: upgrade-classify ac24-no-self-restamp-advice-in-any-carrier
PASS: upgrade-classify ac24-self-restamped-base-loses-the-edit-tag-sourced-base-preserves-it
PASS: upgrade-classify ac25-aborted-bootstrap-hop-writes-nothing
PASS: upgrade-classify ac25-source-executed-engine-still-upgrades-end-to-end
PASS: upgrade-classify t29c-classification-eol-stable-under-autocrlf-true
[run-tests] starting cli-flow-recovery (0.25.9-era wired-set model; unchanged through 0.25.16)
[run-tests] cli-flow-recovery (0.25.9-era wired-set model; unchanged through 0.25.16) took 480s
INCONCLUSIVE: cli-flow-recovery (0.25.9-era wired-set model; unchanged through 0.25.16) (bounded timeout rc 124 at 480s — re-run on a quiet host or FF_SKIP_CLI_RECOVERY=1)

[run-tests] 665/666 PASS
[run-tests] report written: C:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition/state/audit/hook-test-results.md
GATE_RC=1
```
