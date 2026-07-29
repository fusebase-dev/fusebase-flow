# Hook test results

Run: 2026-07-29T01:14:06Z

Total: 666 — PASS: 665 — FAIL: 1

| Fixture | Test | Result | Detail |
|---|---|---|---|
| run_hook_tests.py | 01_pre_tool_use_blocked_rm_rf.json  (blocked rm -rf) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 02_pre_tool_use_blocked_git_add_dot.json  (blocked git add .) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 03_pre_tool_use_blocked_git_add_A.json  (blocked git add -A) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 04_pre_tool_use_blocked_git_reset_hard.json  (blocked git reset --hard) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 05_pre_tool_use_blocked_no_verify.json  (blocked --no-verify) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 06_pre_tool_use_blocked_env_write.json  (blocked .env write (protected path)) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 07_pre_tool_use_blocked_protected_path_edit.json  (blocked protected path edit (deployment config)) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 08_pre_tool_use_allowed_harmless.json  (allowed harmless command (git status)) -> decision=allow | PASS | single-process fixture |
| run_hook_tests.py | 09_stop_blocks_done_without_gate.json  (Stop hook blocks 'implementation complete' claim without gate evidence) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 10_user_prompt_submit_secret.json  (UserPromptSubmit detects pasted secret-like text (GitHub PAT)) -> decision=warn | PASS | single-process fixture |
| run_hook_tests.py | 11_pre_tool_use_secret_in_write.json  (PreToolUse blocks write that introduces a secret-shaped value) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 12_pre_tool_use_cookie_escalation.json  (PreToolUse blocks Write that contains a session cookie (pattern_overrides escalates cookie_session_value warn -> block in pre_tool_use)) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 13_stop_blocks_deploy_complete_without_cleanup_marker.json  (Stop hook blocks 'deploy complete' claim when live-user verification was used but cleanup marker phrase is missing) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 14_stop_allows_deploy_complete_with_cleanup_marker.json  (Stop hook allows 'deploy complete' claim when live-user verification was used AND cleanup marker phrase is present) -> decision=allow | PASS | single-process fixture |
| run_hook_tests.py | 15_stop_allows_lightweight_deploy_complete.json  (Stop hook ALLOWS a Lightweight-lane (FR-21) deploy-complete claim without the Full-lane probes table / post-deploy docs commit / smoke � as long as the safety floor (deploy hash + rollback) is present) -> decision=allow | PASS | single-process fixture |
| run_hook_tests.py | 16_stop_blocks_lightweight_deploy_complete_without_rollback.json  (Stop hook still BLOCKS a Lightweight-lane deploy-complete claim that drops a safety-floor signal (no rollback note) � FR-21 drops ceremony, not the safety floor) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 17_user_prompt_submit_native_prompt_key_secret.json  (UserPromptSubmit (NATIVE Claude Code shape: 'prompt' key, no 'user_prompt') detects pasted GitHub PAT -> warn fires live) -> decision=warn | PASS | single-process fixture |
| run_hook_tests.py | 18_stop_native_transcript_doneclaim.json  (Stop (NATIVE Claude Code shape: NO agent_message, transcript_path only) denies 'implementation complete' final assistant message without gate evidence -> deny fires live) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 19_stop_native_transcript_midclaim_no_overtrigger.json  (Stop (NATIVE shape) does NOT over-trigger: a done-claim EARLIER in the transcript with a CLEAN final assistant message -> allow (claim detection scans only the final message, never history)) -> decision=allow | PASS | single-process fixture |
| run_hook_tests.py | 20_stop_native_corrupt_transcript_claim_failclosed.json  (Stop (NATIVE shape) FAILS CLOSED on extraction failure: a corrupt/format-drifted transcript_path that carries a done/deploy claim but from which NO final assistant message can be extracted -> deny (the ungateable claim cannot be verified). RED on eb50078 (fell through to allow).) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 21_stop_native_corrupt_transcript_noclaim_allow.json  (Stop (NATIVE shape) does NOT false-deny on a claimless corrupt transcript: a corrupt/format-drifted transcript_path with NO final assistant message AND no done/deploy claim text -> allow (the extraction-failure fallback fires only when the raw text carries a claim).) -> decision=allow | PASS | single-process fixture |
| run_hook_tests.py | 22_pre_tool_use_compound_requires_all_actions.json  (compound command with NO artifact denies (K8 all-match, no-artifact path). NOT a first-match discriminator � this fixture is denied by the old code too; the discriminating case (first action SATISFIED, deny hinges on the second) runs through both handlers in hooks/tests/test-command-policy.sh, because run_hook_tests.py executes every fixture from the repo root and a fixture cannot carry its own state/approvals/.) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | 23_permission_request_compound_requires_all_actions.json  (compound command with NO artifact denies (K8 all-match, no-artifact path). NOT a first-match discriminator � this fixture is denied by the old code too; the discriminating case (first action SATISFIED, deny hinges on the second) runs through both handlers in hooks/tests/test-command-policy.sh, because run_hook_tests.py executes every fixture from the repo root and a fixture cannot carry its own state/approvals/.) -> decision=deny | PASS | single-process fixture |
| run_hook_tests.py | _parse-invariant  (empty _expected_rule_id preserved; substring FR-12 selected) | PASS | single-process fixture |
| test-module-size.sh | warn-without-baseline | PASS | exit-code scenario |
| test-module-size.sh | new-under-ceiling-passes | PASS | exit-code scenario |
| test-module-size.sh | new-over-ceiling-blocked | PASS | exit-code scenario |
| test-module-size.sh | ratchet-allows-shrink | PASS | exit-code scenario |
| test-module-size.sh | ratchet-blocks-growth | PASS | exit-code scenario |
| test-module-size.sh | exempt-glob-passes | PASS | exit-code scenario |
| test-module-size.sh | local-override-cannot-disarm | PASS | exit-code scenario |
| test-module-size.sh | single-file-rekey-ratchets | PASS | exit-code scenario |
| test-module-size.sh | preexisting-nonbaselined-shrink-allowed | PASS | exit-code scenario |
| test-module-size.sh | preexisting-nonbaselined-growth-blocked | PASS | exit-code scenario |
| test-module-size.sh | preexisting-nonbaselined-worktree-touch-allowed | PASS | exit-code scenario |
| test-module-size.sh | preexisting-nonbaselined-audit-still-reports | PASS | exit-code scenario |
| test-module-size.sh | rename-grown-monolith-still-blocks | PASS | exit-code scenario |
| test-module-size.sh | write-baseline-worktree-redirect-ignored | PASS | exit-code scenario |
| test-module-size.sh | worktree-redirect-victim-intact | PASS | exit-code scenario |
| test-module-size.sh | write-baseline-worktree-redirect-nonexistent-ignored | PASS | exit-code scenario |
| test-module-size.sh | worktree-redirect-no-stray-file | PASS | exit-code scenario |
| test-module-size.sh | write-baseline-committed-redirect-refused | PASS | exit-code scenario |
| test-module-size.sh | committed-redirect-victim-intact | PASS | exit-code scenario |
| test-module-size.sh | write-baseline-missing-policy-failclosed | PASS | exit-code scenario |
| test-module-size.sh | missing-policy-baseline-not-staged | PASS | exit-code scenario |
| test-health-check-timeout.sh | mv-baseline-healthy (D4): matching manifest => HEALTHY/0, integrity critical reports files-match | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-verify-timeout (T8a): verify timeout => hook layer integrity UNVERIFIED => PARTIAL_UNVERIFIED/exit 4, never 0 | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-absent (T8b): absent manifest => standalone verifier rc 4 => engine PARTIAL_UNVERIFIED/exit 4 (SF8: never rc 3) | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-corrupt (T8c): corrupt manifest self-hash => verifier rc 2 => BROKEN/exit 2 | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-tamper (T8d): covered-file tamper => verifier rc 1 => FLOW_LAYER_DRIFT/exit 1, names the drifted file | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-fast (T8e): --fast skips the integrity critical => exit 4 + 'not a full verdict', keeps preflight (--skip-hook-tests aliases it) | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-deeprun-adaptive-pass (D14 v4): MSYS --run-hook-tests => FAST diagnostic path, HEALTHY/0 (verdict unaffected) | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-deeprun-full-optin (D14 v4): --run-hook-tests-full forces the FULL run-tests.sh even on MSYS => HEALTHY/0 + full-suite line (FFHC_RUN_HOOK_TESTS_FULL=1 equivalent) | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-deeprun-fail (T8g/v4): forced-FAIL deep run => LOCAL_BROKEN => BROKEN/exit 2 (MSYS fast path OR POSIX full path) | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-deeprun-full-timeout (D5): full deep-run timeout => verdict UNAFFECTED (HEALTHY/0) + visible note | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-deeprun-unit-full-rc-contract (A2): strict PASS requires rc=0; rc=143 => LOCAL_BROKEN, rc=0 => LOCAL_OK | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | mv-deeprun-unit-fast-rc-contract (A2): nested helper rejects rc!=0 and 0/0; PASS + rc=0 => LOCAL_OK | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | ht6-no-timeout-bin (AC6): no timeout/gtimeout => bounded ops skipped => PARTIAL_UNVERIFIED/exit 4 (no hang) | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | ws4-knob-surfacing (WS4): MSYS/Git-Bash defaults (preflight 60s / tests 120s) + knob names+values surfaced in the PARTIAL recommendation | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | ws6-preflight-dual-accept (WS6): the REAL §5e ERE from preflight.sh accepts OLD+NEW markers, rejects a non-marker heading | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | ws6-migrate-idempotent (WS6): post-fusebase-update ff_migrate_marker rewrites OLD->NEW once, idempotent | PASS | timeout/verdict scenario |
| test-health-check-timeout.sh | ws6-install-append-idempotent (WS6): the REAL install.sh append_overlay runs once on a fresh file, no double-append, dual-marker guard skips a legacy tree | PASS | timeout/verdict scenario |
| test-git-hooks-smoke.sh | commit-msg blocks missing T-number | PASS | shell scenario |
| test-git-hooks-smoke.sh | commit-msg allows docs prefix | PASS | shell scenario |
| test-git-hooks-smoke.sh | commit-msg allows T-numbered subject | PASS | shell scenario |
| test-git-hooks-smoke.sh | pre-commit blocks staged .env | PASS | shell scenario |
| test-git-hooks-smoke.sh | pre-commit passes benign staged file | PASS | shell scenario |
| test-hook-manifest.sh | covered set includes .jsonl; excludes *.local.* and __pycache__/*.pyc | PASS | shell scenario |
| test-hook-manifest.sh | deleted listed file => rc 1 DRIFT naming missing path | PASS | shell scenario |
| test-hook-manifest.sh | stamp byte-idempotence | PASS | shell scenario |
| test-hook-manifest.sh | verify MATCH | PASS | shell scenario |
| test-hook-manifest.sh | tampered covered file => drift naming it | PASS | shell scenario |
| test-hook-manifest.sh | Scan A extra hooks/shared file => drift | PASS | shell scenario |
| test-hook-manifest.sh | Scan B nested sitecustomize.py => startup-file drift | PASS | shell scenario |
| test-hook-manifest.sh | corrupt self-hash => rc 2; absent manifest => rc 4 | PASS | shell scenario |
| test-newline-preserve.sh | trailing-newline-file-was-synced | PASS | shell scenario |
| test-newline-preserve.sh | no-newline-file-was-synced | PASS | shell scenario |
| test-newline-preserve.sh | trailing-newline-preserved | PASS | shell scenario |
| test-newline-preserve.sh | no-trailing-newline-preserved | PASS | shell scenario |
| test-baseline-merge.sh | upstream-count-wins | PASS | shell scenario |
| test-baseline-merge.sh | local-superseded-by-upstream | PASS | shell scenario |
| test-baseline-merge.sh | project-row-preserved-same-prefix | PASS | shell scenario |
| test-baseline-merge.sh | project-row-preserved-other-tree | PASS | shell scenario |
| test-baseline-merge.sh | absent-upstream-row-kept-by-membership | PASS | shell scenario |
| test-baseline-merge.sh | malformed-row-warned | PASS | shell scenario |
| test-baseline-merge.sh | standard-header | PASS | shell scenario |
| test-baseline-merge.sh | deterministic-sort | PASS | shell scenario |
| test-baseline-merge.sh | setup-fixture-exists | PASS | shell scenario |
| test-baseline-merge.sh | setup-fixture-line-count | PASS | shell scenario |
| test-baseline-merge.sh | setup-fixture-tracked | PASS | shell scenario |
| test-baseline-merge.sh | pre-upgrade-check-passes | PASS | shell scenario |
| test-baseline-merge.sh | clobber-removed-project-row | PASS | shell scenario |
| test-baseline-merge.sh | post-upgrade-project-row-survives | PASS | shell scenario |
| test-baseline-merge.sh | post-upgrade-check-passes | PASS | shell scenario |
| test-sync-allowlist.sh | allowlist-roots-parsed | PASS | shell scenario |
| test-sync-allowlist.sh | allowlist-files-parsed | PASS | shell scenario |
| test-sync-allowlist.sh | no-under-reach (18 framework files all reachable) | PASS | shell scenario |
| test-sync-allowlist.sh | guard-detects-omission (2-entry mutation: AGENTS.md + FLOW_RULES.md) | PASS | shell scenario |
| test-sync-allowlist.sh | docs-surface-is-top-level-only | PASS | shell scenario |
| test-sync-allowlist.sh | history-not-in-allowlist (carries live-looking tokens; excluded as dated history) | PASS | shell scenario |
| test-sync-allowlist.sh | history-never-synced | PASS | shell scenario |
| test-sync-allowlist.sh | consumer-doc-not-synced | PASS | shell scenario |
| test-policy-state-preserve.sh | pre-upgrade-workflow_mode-override-wins | PASS | shell scenario |
| test-policy-state-preserve.sh | pre-upgrade-worker_undisturbed-override-wins | PASS | shell scenario |
| test-policy-state-preserve.sh | local-overrides-survive-wholesale-copy | PASS | shell scenario |
| test-policy-state-preserve.sh | post-upgrade-workflow_mode-preserved | PASS | shell scenario |
| test-policy-state-preserve.sh | post-upgrade-worker_undisturbed-preserved | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | setup-inputs-present | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | extract-source-merge-lib | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | setup-fixture-exists | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | setup-fixture-line-count | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | setup-fixture-tracked | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | pre-hop-check-passes | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | precondition-no-local-lib | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | red-prefix-loses-row | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | green-engine-preserves-row | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | green-post-hop-check-passes | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | p1-precondition-no-lib | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | p1-bootstrap-stages-lib | PASS | shell scenario |
| test-bootstrap-baseline-hop.sh | p1-bootstrap-references-lib | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | setup-inputs-present | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac1-template-has-pushblock-header | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac1-template-has-tripwire-line | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac1-template-has-pointer-line | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac1-template-has-density-clause | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac1-template-present-by-construction-note | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac3-red-absent-not-detected | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac3-red-absent-still-allows | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac3-green-applied-detected | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac3-green-na-detected | PASS | shell scenario |
| test-fr22-delivery-guarantee.sh | ac3-required-still-denies | PASS | shell scenario |
| test-po-verifiable-boot.sh | setup-inputs-present | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac1-cmd-has-marker-prefix | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac1-overlay-has-marker-prefix | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac1-cmd-has-checklist | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac1-cmd-overlay-byte-identical | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac2-cmd-agent-block-match | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac2-extracted-block-has-marker | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac3-po-prompt-reminder | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac3-nonpo-no-reminder | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac3-never-blocks | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac4-red-no-marker-warns | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac4-red-no-marker-still-allows | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac4-green-with-marker-no-warn | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac4-green-nonpo-no-warn | PASS | shell scenario |
| test-po-verifiable-boot.sh | ac4-required-still-denies | PASS | shell scenario |
| test-po-investigate.sh | setup-inputs-present | PASS | shell scenario |
| test-po-investigate.sh | red-prefix-wrapper-breaches (--output wrote a file pre-fix) | PASS | shell scenario |
| test-po-investigate.sh | green-diff-output-refused (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-diff-output-eq-o (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-show-output-refused (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-log-output-refused (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-ext-diff-flag-refused (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-c-config-refused (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-paginate-refused (refused, no file, rc=2) | PASS | shell scenario |
| test-po-investigate.sh | green-env-scrub-no-external-exec | PASS | shell scenario |
| test-po-investigate.sh | legit-diff | PASS | shell scenario |
| test-po-investigate.sh | legit-diff-stat | PASS | shell scenario |
| test-po-investigate.sh | legit-diff-no-ext | PASS | shell scenario |
| test-po-investigate.sh | legit-log-oneline | PASS | shell scenario |
| test-po-investigate.sh | legit-show-file | PASS | shell scenario |
| test-po-investigate.sh | legit-status | PASS | shell scenario |
| test-po-investigate.sh | legit-output-indicator-not-overblocked | PASS | shell scenario |
| test-liveness-bounded-run.sh | setup-lib-present | PASS | shell scenario |
| test-liveness-bounded-run.sh | lib-syntax-clean | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3a-hang-rc-124-or-137 | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3a-terminal-timeout-line | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3a-bounded-within-deadline | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3b-incremental-progress | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3d-ignored-sigterm-sigkilled | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3c-no-binary-skip-rc-125 | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3c-no-binary-command-not-run | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac3c-skip-marker-line | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac6-health-check-timeout-no-regression | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac6-ffhc-api-functions-present | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac4-liveness-in-hard-invariants | PASS | shell scenario |
| test-liveness-bounded-run.sh | ac4-hard-region-bounded | PASS | shell scenario |
| test-liveness-bounded-run.sh | f3-nap-primitive-probed-usable (FFHC_NAP_OK=1 on this host) | PASS | shell scenario |
| test-liveness-bounded-run.sh | f3-fast-child-returns-well-under-budget (2s wall for a 600s-budget instant child, own rc=0 — reap loop did not block for the budget; nap ladder, not a 1s sleep floor) | PASS | shell scenario |
| test-liveness-bounded-run.sh | f3-no-early-reap-bounded (hang-child bounded at 2s => timeout rc=124 in 4s: FLOOR >=2s honored AND CEILING <=45s — never reaped early, never a late/never-kill regression) | PASS | shell scenario |
| test-liveness-bounded-run.sh | f3-fallback-sleep1-path-still-bounds (FFHC_NAP_OK=0 => literal sleep-1 loop still returns timeout rc=124 — zero regression on the fallback) | PASS | shell scenario |
| test-liveness-bounded-run.sh | f3-mkfifo-absent-forces-fallback (mkfifo unusable => FFHC_NAP_OK=0 => v3.30.5 sleep-1 behavior) | PASS | shell scenario |
| test-codex-prompt-parity.sh | setup-inputs-present | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac1-table-header-present | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac1-all-commands-listed | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac1-portable-column-has-skill-invocation | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac1-table-outside-flow-preserve | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac2-installer-generated-files | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac2-description-frontmatter-kept | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac2-agents-path-repointed | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac2-flow-marker-present | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac2-po-boot-block-preserved | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac2-drift-guard-canonical-edit-propagates | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-all-files-marked | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-idempotent-rerun | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-refuses-unmarked-collision | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-force-overwrites-unmarked | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-marked-file-not-blocked | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-no-frontmatter-hard-fails | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-no-frontmatter-writes-no-unmarked-file | PASS | shell scenario |
| test-codex-prompt-parity.sh | ac3-no-frontmatter-red-proof | PASS | shell scenario |
| test-codex-plugin-surface.sh | manifest-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | product-owner-canonical-skill-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | manifest-shape | PASS | shell scenario |
| test-codex-plugin-surface.sh | canonical-product-owner-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | canonical-product-docs-first-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | canonical-product-apps-decomposition-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | agents-product-owner-mirror-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | claude-product-owner-mirror-present | PASS | shell scenario |
| test-codex-plugin-surface.sh | product-owner-trigger-rich | PASS | shell scenario |
| test-codex-plugin-surface.sh | product-owner-mirrors-byte-identical | PASS | shell scenario |
| test-cli-0259-compat.sh | setup-files-present | PASS | shell scenario |
| test-cli-0259-compat.sh | ac1-red-pre-fix-phantom-confirmed | PASS | shell scenario |
| test-cli-0259-compat.sh | ac1-green-0259-set-not-drift | PASS | shell scenario |
| test-cli-0259-compat.sh | ac1-green-verdict-healthy | PASS | shell scenario |
| test-cli-0259-compat.sh | ac1-m4-dropped-is-advisory-not-drift | PASS | shell scenario |
| test-cli-0259-compat.sh | ac1-m4-no-exit1-from-missing-cli-hook | PASS | shell scenario |
| test-cli-0259-compat.sh | ac1-m4-verdict-stays-healthy | PASS | shell scenario |
| test-cli-0259-compat.sh | acm1-receipt-written-on-real-merge | PASS | shell scenario |
| test-cli-0259-compat.sh | acm1-receipt-lists-cli-hooks-only | PASS | shell scenario |
| test-cli-0259-compat.sh | acm1-receipt-durable-across-noop | PASS | shell scenario |
| test-cli-0259-compat.sh | acm2-receipt-dropped-hook-is-baseline-drift | PASS | shell scenario |
| test-cli-0259-compat.sh | acm2-unwired-typecheck-apps-stays-benign | PASS | shell scenario |
| test-cli-0259-compat.sh | acm2-verdict-healthy | PASS | shell scenario |
| test-cli-0259-compat.sh | acm2-exit-0 | PASS | shell scenario |
| test-cli-0259-compat.sh | acm2-rebaseline-clears-advisory | PASS | shell scenario |
| test-cli-0259-compat.sh | acm3-no-receipt-is-unverified | PASS | shell scenario |
| test-cli-0259-compat.sh | acm3-verdict-healthy | PASS | shell scenario |
| test-cli-0259-compat.sh | acm3-exit-0 | PASS | shell scenario |
| test-cli-0259-compat.sh | acm3-no-stop-py-no-nag | PASS | shell scenario |
| test-cli-0259-compat.sh | acl1-pristine-sha-eq-provenance-not-flagged | PASS | shell scenario |
| test-cli-0259-compat.sh | acl1-drifted-sha-ne-provenance-flagged | PASS | shell scenario |
| test-cli-0259-compat.sh | acl1-advisory-only-stays-healthy | PASS | shell scenario |
| test-cli-0259-compat.sh | acl1-provenance-absent-conservative-flag | PASS | shell scenario |
| test-cli-0259-compat.sh | ac2-merge-preserve-only | PASS | shell scenario |
| test-cli-0259-compat.sh | ac2-merge-idempotent | PASS | shell scenario |
| test-cli-0259-compat.sh | ac2-older-cli-typecheck-preserved | PASS | shell scenario |
| test-cli-0259-compat.sh | ac2-migrate-python3-to-wrapper | PASS | shell scenario |
| test-cli-0259-compat.sh | ac2-migrate-idempotent | PASS | shell scenario |
| test-cli-0259-compat.sh | ac2-migrate-no-clobber-customizations | PASS | shell scenario |
| test-cli-0259-compat.sh | ac3b-flag-gated-benign | PASS | shell scenario |
| test-cli-0259-compat.sh | ac3b-flag-gated-exit-not-drift | PASS | shell scenario |
| test-cli-0259-compat.sh | ac3-freshness-sha-matches-manifest | PASS | shell scenario |
| test-cli-0259-compat.sh | ac3-no-snapshot-stale | PASS | shell scenario |
| test-secret-scan-staged.sh | setup-helper-present | PASS | shell scenario |
| test-secret-scan-staged.sh | a1-edit-secret-patterns-not-blocked | PASS | shell scenario |
| test-secret-scan-staged.sh | a1-real-secret-plus-line-still-blocks | PASS | shell scenario |
| test-secret-scan-staged.sh | a1-removed-line-secret-not-blocked | PASS | shell scenario |
| test-secret-scan-staged.sh | a1-fixtures-excluded-deliberate-gap | PASS | shell scenario |
| test-secret-scan-staged.sh | backup-fixture-policy-twins-excluded | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-still-blocks-backup-of-real-file | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-still-blocks-name-spoof-no-ts | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-still-blocks-untimestamped-fixtures | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-still-blocks-tz-glob-spoof | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-still-blocks-exact-ts-non-root | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-still-blocks-exact-ts-wrong-prefix | PASS | shell scenario |
| test-secret-scan-staged.sh | a2-no-whitelist-added | PASS | shell scenario |
| test-secret-scan-staged.sh | a2-fixture10-still-detects | PASS | shell scenario |
| test-secret-scan-staged.sh | a2-fixture11-still-detects | PASS | shell scenario |
| test-secret-scan-staged.sh | a1-real-secret-in-nondesigned-test-still-blocks | PASS | shell scenario |
| test-secret-scan-staged.sh | release-gate-self-test-tree-commits-clean | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-script-tamper-blocks (trusted HEAD scanner runs, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-script-tamper-RED-t30-not-exit0-here (GREEN still asserted) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-patterns-tamper-blocks (trusted HEAD patterns run, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-patterns-tamper-RED-t30-not-exit0-here (GREEN still asserted) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-still-blocks-normal (trusted HEAD, untampered, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-no-over-block-legit-passes (trusted HEAD §2, non-secret) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-bootstrap-edge-falls-back (working-tree scanner note emitted) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-bootstrap-edge-still-blocks (fallback scanner blocks the real secret, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-transient-error-fails-closed (source) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-invokes-trusted-head-not-worktree (source: §2 imports from SEC_IMPORT_DIR, no bare $ROOT/hooks helper invocation) | PASS | shell scenario |
| test-secret-scan-staged.sh | secret-scan-pyyaml-imports-under-S (getsitepackages re-add works for the §2 seed) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-shadow-secret-pathlib-blocks (§2 file-script strips CWD; pathlib shadow inert, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-shadow-secret-pathlib-RED-was-fail-open (41a8c6d stdin -S - imported the repo-root pathlib shadow; secret self-passed at exit 0) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-shadow-secret-yaml-blocks (discriminating shim inert; real PyYAML wins; §2 BLOCKS, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-shadow-secret-yaml-RED-was-fail-open (41a8c6d: discriminating shim neutered §2, kept §3 green; the AWS key self-passed at exit 0) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-no-over-block-legit-passes (T32 file-script §2, non-secret, PyYAML imports) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-still-blocks-untampered-secret (§2 detection intact under file-script, exit 1) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-sec-main-is-file-script (source: §2 MAIN runs python3 -S $SEC_TMP/_main_secret.py, no stdin -S -) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-syspath-has-no-cwd (file-script + in-script scrub: '', '.', CWD absent before first non-builtin import) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-restore-site-packages-prepends (staged_secret_scan: insert after leading trusted dir, not append) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-pythonsafepath-exported (defense-in-depth: 3.11+ never puts CWD on sys.path) | PASS | shell scenario |
| test-secret-scan-staged.sh | cwd-strip-sec-sentinel-file-redirect (§2 sentinel via file redirect, no $(git ls-tree) command substitution — MSYS rc=124 hang closed) | PASS | shell scenario |
| test-bootstrap-exception.sh | 1-blocks-without-approval | PASS | shell scenario |
| test-bootstrap-exception.sh | 1-passes-with-bootstrap-approval-no-noverify | PASS | shell scenario |
| test-bootstrap-exception.sh | 2-reuse-second-unrelated-edit-denies | PASS | shell scenario |
| test-bootstrap-exception.sh | 2-consume-cleans-artifact | PASS | shell scenario |
| test-bootstrap-exception.sh | 4-glob-artifact-denies | PASS | shell scenario |
| test-bootstrap-exception.sh | 4b-no-staged-content-denies | PASS | shell scenario |
| test-bootstrap-exception.sh | 3-custom-hook-preserved | PASS | shell scenario |
| test-bootstrap-exception.sh | 3-custom-hook-backed-up | PASS | shell scenario |
| test-bootstrap-exception.sh | 3-force-installs-flow-hook | PASS | shell scenario |
| test-bootstrap-exception.sh | 3-flow-hook-refreshed-in-place | PASS | shell scenario |
| test-bootstrap-exception.sh | 6a-protected-delete-blocked | PASS | shell scenario |
| test-bootstrap-exception.sh | 6b-protected-delete-with-approval-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 6c-protected-rename-blocked | PASS | shell scenario |
| test-bootstrap-exception.sh | 6d-protected-rename-with-approval-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 6e-rename-leaving-protection-blocked | PASS | shell scenario |
| test-bootstrap-exception.sh | 6f-rename-entering-protection-blocked | PASS | shell scenario |
| test-bootstrap-exception.sh | 6g-nonprotected-delete-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 6g-nonprotected-rename-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 6h-delete-approval-single-use | PASS | shell scenario |
| test-bootstrap-exception.sh | 5-fusebase-mentioning-custom-hook-preserved | PASS | shell scenario |
| test-bootstrap-exception.sh | 5-fusebase-mentioning-custom-hook-backed-up | PASS | shell scenario |
| test-bootstrap-exception.sh | 5-genuine-flow-hook-refreshed-by-unique-marker | PASS | shell scenario |
| test-bootstrap-exception.sh | 7-import-error-fails-closed (pre-commit BLOCKS, exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 7-import-error-diagnostic-emitted | PASS | shell scenario |
| test-bootstrap-exception.sh | 8-git-mask-lists-staged-file | PASS | shell scenario |
| test-bootstrap-exception.sh | 8-python3-absent-non-blocking | PASS | shell scenario |
| test-bootstrap-exception.sh | 8-python3-absent-loud-warn (git-preserving mask; §3 names the un-enforceable FR-07 check — a loud WARN, not a silent skip) | PASS | shell scenario |
| test-bootstrap-exception.sh | 9a-enum-failure-fails-closed (pre-commit BLOCKS, exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 9a-enum-failure-diagnostic-emitted | PASS | shell scenario |
| test-bootstrap-exception.sh | 9a-RED-old-code-was-fail-open (T25 pre-commit exit 0 on the same scenario) | PASS | shell scenario |
| test-bootstrap-exception.sh | 9b-git-list-failure-fails-closed (pre-commit BLOCKS, exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 9b-git-list-failure-diagnostic-emitted | PASS | shell scenario |
| test-bootstrap-exception.sh | 10a-no-staged-changes-passes (rc0-empty not over-blocked) | PASS | shell scenario |
| test-bootstrap-exception.sh | 10b-nonprotected-edit-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 10c-protected-edit-with-approval-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 11-systemexit0-import-blocks (pre-commit BLOCKS, exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 11-systemexit0-import-diagnostic | PASS | shell scenario |
| test-bootstrap-exception.sh | 11-RED-t26-was-fail-open (dadea26 exit 0 on SystemExit(0) import) | PASS | shell scenario |
| test-bootstrap-exception.sh | 11b-systemexit0-in-evaluate-blocks (exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 11b-systemexit0-in-evaluate-diagnostic | PASS | shell scenario |
| test-bootstrap-exception.sh | 11c-clean-nohit-still-passes (SystemExit split doesn't over-block) | PASS | shell scenario |
| test-bootstrap-exception.sh | 12a-staged_change_paths-raises-on-rc (unit) | PASS | shell scenario |
| test-bootstrap-exception.sh | 12b-name-status-partial-rc-blocks (exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 12b-name-status-partial-diagnostic | PASS | shell scenario |
| test-bootstrap-exception.sh | 12b-RED-t26-not-exit0-here (GREEN still asserted) | PASS | shell scenario |
| test-bootstrap-exception.sh | 13a-missing-policy-blocks (exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 13a-missing-policy-diagnostic | PASS | shell scenario |
| test-bootstrap-exception.sh | 13a-RED-t26-was-fail-open (missing policy exit 0) | PASS | shell scenario |
| test-bootstrap-exception.sh | 13b-empty-policy-blocks (exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 13c-emptied-sentinel-category-blocks (exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 14a-local-override-cannot-erase-internals (unit: base paths re-unioned) | PASS | shell scenario |
| test-bootstrap-exception.sh | 14b-erasing-local-still-blocks-protected-edit (exit 1) | PASS | shell scenario |
| test-bootstrap-exception.sh | 14c-additive-local-override-still-honored | PASS | shell scenario |
| test-bootstrap-exception.sh | 15a-happy-path-protected-edit-still-blocks | PASS | shell scenario |
| test-bootstrap-exception.sh | 15b-happy-path-with-approval-passes | PASS | shell scenario |
| test-bootstrap-exception.sh | 15c-cross-policy-get_policy-unchanged (approval-policy local override wins) | PASS | shell scenario |
| test-bootstrap-exception.sh | 16-outer-git-list-rc-guard-present (source) | PASS | shell scenario |
| test-bootstrap-exception.sh | 17-ac11-shared-parsed-expiry-across-carriers | PASS | shell scenario |
| test-bootstrap-exception.sh | 18-active-approvals-status-aware-array-contract-intact | PASS | shell scenario |
| test-trusted-enforcer.sh | 17-tamper-lying-enforcer-blocks (trusted HEAD runs, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 17-tamper-diagnostic-emitted | PASS | shell scenario |
| test-trusted-enforcer.sh | 17-RED-t27-was-fail-open (working-tree enforcer exit 0: the lie self-passed) | PASS | shell scenario |
| test-trusted-enforcer.sh | 18-legit-approved-enforcer-edit-passes (trusted HEAD honors the working-tree approval) | PASS | shell scenario |
| test-trusted-enforcer.sh | 18-unapproved-enforcer-edit-blocks | PASS | shell scenario |
| test-trusted-enforcer.sh | 19a-common-nonprotected-edit-passes | PASS | shell scenario |
| test-trusted-enforcer.sh | 19b-common-protected-nonenforcer-edit-blocks | PASS | shell scenario |
| test-trusted-enforcer.sh | 19c-bootstrap-first-add-falls-back (working-tree enforcer note emitted) | PASS | shell scenario |
| test-trusted-enforcer.sh | 19c-bootstrap-first-add-with-approval-passes | PASS | shell scenario |
| test-trusted-enforcer.sh | 19d-transient-error-fails-closed-not-fallback (source) | PASS | shell scenario |
| test-trusted-enforcer.sh | 20a-tooltime-missing-policy-denies (fail closed) | PASS | shell scenario |
| test-trusted-enforcer.sh | 20b-tooltime-empty-policy-denies | PASS | shell scenario |
| test-trusted-enforcer.sh | 20c-tooltime-shipped-policy-nonprotected-allows | PASS | shell scenario |
| test-trusted-enforcer.sh | 20d-tooltime-shipped-policy-protected-denies | PASS | shell scenario |
| test-trusted-enforcer.sh | 20-RED-t27-was-fail-open (pre-T28 handler allowed the protected write on missing policy) | PASS | shell scenario |
| test-trusted-enforcer.sh | 21-unstaged-enforcer-tamper-blocks (trusted HEAD runs unconditionally, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 21-unstaged-tamper-diagnostic-emitted | PASS | shell scenario |
| test-trusted-enforcer.sh | 21-RED-t28-was-fail-open (conditional OFF: unstaged lie self-passed at exit 0) | PASS | shell scenario |
| test-trusted-enforcer.sh | 22a-sitecustomize-injection-blocks (-S disables startup file; §3 runs, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 22a-RED-t28-was-fail-open (startup os._exit(0) exited the check at 0) | PASS | shell scenario |
| test-trusted-enforcer.sh | 22b-usercustomize-injection-blocks (-S disables usercustomize; exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 22c-secret-scan-still-blocks-under-S (§2 ran under -S with sitecustomize present, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 23-prep-step-injection-blocks (env scrub + -S PREP + git decision, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 23-prep-injection-diagnostic-emitted | PASS | shell scenario |
| test-trusted-enforcer.sh | 23-RED-t29-was-fail-open (plain-python3 PREP honored the forged RESULT=fallback; the PoC self-passed at exit 0) | PASS | shell scenario |
| test-trusted-enforcer.sh | 24a-hostile-pythonpath-protected-no-approval-blocks (exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 24b-hostile-pythonpath-nonprotected-passes (no over-block) | PASS | shell scenario |
| test-trusted-enforcer.sh | 25-forged-fallback-impossible-when-HEAD-has-enforcer (git decides trusted; forged RESULT inert -> BLOCK, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 26-pyyaml-imports-under-S (getsitepackages re-add works) | PASS | shell scenario |
| test-trusted-enforcer.sh | 27-cwd-shadow-fr07-pathlib-blocks (§3 file-script strips CWD; pathlib shadow inert, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 27-cwd-shadow-fr07-pathlib-diagnostic | PASS | shell scenario |
| test-trusted-enforcer.sh | 27-RED-was-fail-open (41a8c6d stdin -S - imported the repo-root pathlib shadow; the protected edit self-passed at exit 0) | PASS | shell scenario |
| test-trusted-enforcer.sh | 28-cwd-shadow-fr07-yaml-blocks (§3 file-script strips CWD; repo-root yaml.py shadow inert, exit 1) | PASS | shell scenario |
| test-trusted-enforcer.sh | 28-RED-yaml-was-fail-open (41a8c6d imported the repo-root yaml.py shadow at the §3 seed; the protected edit self-passed at exit 0) | PASS | shell scenario |
| test-trusted-enforcer.sh | 29-cwd-strip-legit-approved-enforcer-edit-passes (T32 §3 file-script honors the working-tree approval) | PASS | shell scenario |
| test-trusted-enforcer.sh | 29-cwd-strip-nonprotected-edit-passes (no over-block) | PASS | shell scenario |
| test-trusted-enforcer.sh | 30-cwd-strip-fr07-main-is-file-script (source: §3 MAIN runs python3 -S $FR07_TMP/_main.py, no stdin -S -) | PASS | shell scenario |
| test-trusted-enforcer.sh | 30-cwd-strip-inscript-scrub-uses-builtin-oscore (nt/posix builtin -> unshadowable CWD source; sys.path filtered, not del path[0]) | PASS | shell scenario |
| test-trusted-enforcer.sh | 30-cwd-strip-fr07-sentinel-file-redirect (§3 sentinel via file redirect, no $(git ls-tree) command substitution — MSYS rc=124 hang closed) | PASS | shell scenario |
| test-hook-install-rc.sh | upgrade-rc-nonzero-no-silent-installed | PASS | shell scenario |
| test-hook-install-rc.sh | upgrade-rc0-custom-preserved | PASS | shell scenario |
| test-hook-install-rc.sh | upgrade-rc0-clean-installed | PASS | shell scenario |
| test-hook-install-rc.sh | upgrade-rc-nonzero-set-e-safe | PASS | shell scenario |
| test-hook-install-rc.sh | postup-rc-nonzero-no-silent-installed | PASS | shell scenario |
| test-hook-install-rc.sh | postup-rc0-custom-preserved | PASS | shell scenario |
| test-hook-install-rc.sh | postup-rc0-clean-installed | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t8-tempfail-routes-to-skipped (unwritable TMPDIR => rc 125 + SKIPPED + empty out => UNVERIFIED, never false BROKEN/hang) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t8-no-cwd-tempfile-leak (explicit ${TMPDIR}/ffhc-bounded.$$.XXXXXX template — no transient files in CWD) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2-true-124-on-kill (overrun => rc 124 is timeout-induced 124/137, never 0) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2-no-hang-large-budget (returned in 1s with the command's own rc=7, not the 300s budget) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t12-winpid+childpid-cleared-on-return (both globals empty after a normal bounded return => EXIT-trap reap is a no-op) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t17-stdin-reaches-child (RED old stdout path=allow [stdin dropped] => GREEN new stdin path=deny [fixture reached handler]) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t17-default-path-unchanged (non-stdin bounded run: stdout captured, own rc=7, < /dev/null EOF => no hang) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t17-stdin-path-t12-clear (stdin variant clears WINPID+CHILD_PID on return => EXIT-trap reap is a no-op) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t18-default-path-immune-to-exported-FFHC_CAPTURE_STDIN (exported flag=1 + piped fixture => DEFAULT wrapper still uses < /dev/null: cat sees EOF, captured out is marker-only, own rc=5) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | t18-stdin-wrapper-still-delivers-fd0 (explicit inherit param drives the stdin path; deny-fixture DENIES even with the dead FFHC_CAPTURE_STDIN exported) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-posix-body-byte-unchanged (run_with_timeout body sha256 == pinned WS2-core hash; the fence is additive-only) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-default-off-no-extra-fork (knob-first gate: default-OFF bounded run never calls ffhc_job_available (0 probe invocations) + own rc/capture intact; source leads with the FFHC_USE_JOB_OBJECT compare — no uname/powershell fork added to the hot default path) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-default-off-byte-identity (knob unset: own rc=3 + captured 'off-marker' + timeout rc=124 == today, no job branch taken) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-probe-gating (knob=1 => AVAILABLE here; knob unset => OFF (default); FFHC_JOB_PROBE_FORCE_FAIL=1 => OFF) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-job-rc-preserved+capture (job ON: own rc=7 + tempfile-captured stdout 'job-capture') | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-job-124-on-timeout (job ON: overrun => timeout-induced rc=124, never 0) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-job-137-on-hard-kill (job ON path: stubborn TERM-ignoring child => rc 137 (128+SIGKILL) + captured 'started'; rc from wait $_bpid — mechanism exercised; NOT claimed as Job-Object-vs-timeout-k proof (consumer-gated)) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-job-sibling-survives (unrelated bash sleep pid=343121 alive after the fence's TerminateJobObject — assigned-tree-only, no collateral) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-forced-probe-fail-clean-fallback (FFHC_JOB_PROBE_FORCE_FAIL=1 => WS2-core path: own rc=5 + 'fb-marker' in 1s, no hang, no re-run) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2hard-fast-opt-in-returns-promptly (secs=30 fast cmd returned in 1s (<=15s, no secs+grace stall) + rc0 + 'fast-opt-in'; fence called DIRECTLY (not $(…)) so FFHC_JOB_FENCE_HPID propagates + helper is reaped, no orphan — the command-substitution HANG/leak is fixed) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | native-descendant-returns-at-deadline (2s <= 6s) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | native-descendant-rc-preserved (rc=124 is timeout-induced 124/137) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | early-winpid-capture-plumbing-present (T7: winpid resolved at launch, taskkill on timeout) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | tempfile-capture-faster-than-pipe (pipe 8s > tempfile 2s) | PASS | shell scenario |
| test-msys-tree-cleanup.sh | ws2-concurrent-sibling-survives (unrelated bash sleep pid=343394 alive after a bounded op's timeout-taskkill — reap scoped to recorded child only) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w1-prune-single-pass (single-pass: 154 -> 93 backups (keep 3/stem), 61 pruned, terminated in 9s — no per-stem busy-loop) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w1b-prune-keeps-newest (file1 kept the 3 newest timestamps: file1.txt.pre-upgrade-20260103T000001Z file1.txt.pre-upgrade-20260104T000001Z file1.txt.pre-upgrade-20260105T000001Z ) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w2-optional-killed-continues (a killed OPTIONAL step WARNs + continues; harness reaches AFTER-OPTIONAL rc=0 — upgrade not failed) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w3-critical-killed-fails-with-hint (a killed CRITICAL step exits nonzero (rc=1) + prints the recovery hint + does NOT continue — never masks a partial upgrade) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w4-critical-failing-cmd-fails (a CRITICAL step whose cmd exits nonzero => exit 1 + recovery hint + halts — partial upgrade never reported success) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w5-optional-ok-returns0 (a fast successful OPTIONAL step returns 0 and continues — no spurious bound failure) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w9-optional-timeout-set-e-safe (UNDER set -e + ERR trap: a timed-out OPTIONAL step WARNs + continues + reaches the VERSION-write marker rc0 — the set -e wait-abort can no longer escape) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w10-optional-fail-set-e-safe (UNDER set -e: a fast-failing OPTIONAL step (rc4) WARNs + continues + reaches the marker rc0 — no wait-abort) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w11-critical-fail-set-e-exits-with-hint (UNDER set -e: a failing CRITICAL step exits nonzero (rc=1) via ffhc_run_step's FATAL+hint path — not a raw wait-abort that would skip the hint) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w12-degraded-optional-fail-set-e-safe (UNDER set -e, FFHC_STEP_LIB_OK=0 direct-run path: a failing OPTIONAL step WARNs + continues + reaches the marker rc0) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w13-prune-ignores-non-backup (non-backup .pre-upgrade-/.pre-refresh- files survive; genuine timestamped backups prune to newest-3/stem: real.txt.pre-upgrade-20260103T000001Z real.txt.pre-upgrade-20260104T000001Z real.txt.pre-upgrade-20260105T000001Z ) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w6-version-write-critical-guard (upgrade.sh verifies the VERSION write landed + exits with the recovery hint on failure — CRITICAL, never a silent stale VERSION) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w7-remirror+prune-bounded-wiring (re-mirror + sync-strings routed through ffhc_run_step OPTIONAL bound; prune is single-pass — all present in the shipped engine) | PASS | shell scenario |
| test-ws5-upgrade-bounded.sh | w8-no-runaway-after-prune (prune left no background job: before=0 after=0) | PASS | shell scenario |
| test-ff-only.sh | ff-list-tag-count (37 canonical tags) | PASS | shell scenario |
| test-ff-only.sh | scoped-one-starting-marker | PASS | shell scenario |
| test-ff-only.sh | scoped-skip-count | PASS | shell scenario |
| test-ff-only.sh | scoped-summary-marker | PASS | shell scenario |
| test-ff-only.sh | scoped-fails-strict-classifier (ffhc_count_pass_lines=0) | PASS | shell scenario |
| test-ff-only.sh | scoped-summary-rejected-by-pass-ok | PASS | shell scenario |
| test-ff-only.sh | scoped-results-file-written | PASS | shell scenario |
| test-ff-only.sh | full-results-file-untouched-by-scoped-run | PASS | shell scenario |
| test-ff-only.sh | bogus-tag-exit-2 | PASS | shell scenario |
| test-ff-only.sh | empty-selection-exit-2 | PASS | shell scenario |
| test-ff-only.sh | scoped-with-injected-failure-exits-nonzero (rc=1) | PASS | shell scenario |
| test-return-budget.sh | setup-inputs-present | PASS | shell scenario |
| test-return-budget.sh | ac12-skill-both-limits | PASS | shell scenario |
| test-return-budget.sh | ac12-implement-both-limits | PASS | shell scenario |
| test-return-budget.sh | ac12-deploy-both-limits | PASS | shell scenario |
| test-return-budget.sh | ac12-skill-overflow-route | PASS | shell scenario |
| test-return-budget.sh | ac12-skill-commit-conditional | PASS | shell scenario |
| test-return-budget.sh | ac12-implement-overflow-route | PASS | shell scenario |
| test-return-budget.sh | ac12-deploy-overflow-route | PASS | shell scenario |
| test-return-budget.sh | ac12-skill-brief-field | PASS | shell scenario |
| test-return-budget.sh | ac13-implement-gate-exempt | PASS | shell scenario |
| test-return-budget.sh | ac13-deploy-report-exempt | PASS | shell scenario |
| test-return-budget.sh | ac13-skill-exemption | PASS | shell scenario |
| test-return-budget.sh | ac12-handoff-successor-pointer | PASS | shell scenario |
| test-return-budget.sh | red-line-only-cap-rejected | PASS | shell scenario |
| test-supersede-primitive.sh | setup-inputs-present | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-flow-rules-both-dimensions | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-role-discipline-both-dimensions | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-handoff-skill-both-dimensions | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-token-economy-both-dimensions | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-template-both-dimensions | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-flow-rules-semantics-clause | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-role-discipline-write-primitive-section | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-role-discipline-digest-row | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-handoff-skill-fresh-disambiguated | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-handoff-command | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-handoff-overlay-twin | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-audit-command | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-audit-overlay-twin | PASS | shell scenario |
| test-supersede-primitive.sh | ac21-handoff-twin-byte-identical | PASS | shell scenario |
| test-supersede-primitive.sh | ac21-audit-twin-byte-identical | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-audit-parser-header | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-audit-parser-primitive-clause | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-te06-contradiction-gone | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-audit-contradiction-gone | PASS | shell scenario |
| test-supersede-primitive.sh | ac14-te-antipattern-qualified | PASS | shell scenario |
| test-rule-inventory.sh | setup-instrument-present | PASS | shell scenario |
| test-rule-inventory.sh | baseline-produced | PASS | shell scenario |
| test-rule-inventory.sh | covers-fr-01-27 | PASS | shell scenario |
| test-rule-inventory.sh | covers-all-role-dont-lists | PASS | shell scenario |
| test-rule-inventory.sh | covers-b1-b12 | PASS | shell scenario |
| test-rule-inventory.sh | schema-four-columns | PASS | shell scenario |
| test-rule-inventory.sh | schema-residency-values | PASS | shell scenario |
| test-rule-inventory.sh | schema-has-resident-rows | PASS | shell scenario |
| test-rule-inventory.sh | schema-has-lazy-rows | PASS | shell scenario |
| test-rule-inventory.sh | schema-relative-paths | PASS | shell scenario |
| test-rule-inventory.sh | covers-amended-categories | PASS | shell scenario |
| test-rule-inventory.sh | deterministic-rerun | PASS | shell scenario |
| test-rule-inventory.sh | drop-fr-row | PASS | shell scenario |
| test-rule-inventory.sh | drop-dont-row | PASS | shell scenario |
| test-rule-inventory.sh | drop-principle | PASS | shell scenario |
| test-rule-inventory.sh | reword-statement | PASS | shell scenario |
| test-rule-inventory.sh | reword-attestation | PASS | shell scenario |
| test-rule-inventory.sh | move-resident-to-lazy | PASS | shell scenario |
| test-rule-inventory.sh | move-dont-between-roles | PASS | shell scenario |
| test-rule-inventory.sh | reword-enforcement | PASS | shell scenario |
| test-rule-inventory.sh | principle-relayout | PASS | shell scenario |
| test-rule-inventory.sh | principle-as-bullet | PASS | shell scenario |
| test-rule-inventory.sh | range-heading-ignored | PASS | shell scenario |
| test-rule-inventory.sh | no-raw-version-literals | PASS | shell scenario |
| test-rule-inventory.sh | attestation-version-normalized | PASS | shell scenario |
| test-rule-inventory.sh | version-bump-perturbs-source | PASS | shell scenario |
| test-rule-inventory.sh | version-bump-green | PASS | shell scenario |
| test-rule-inventory.sh | fail-closed-zero-fr-rows | PASS | shell scenario |
| test-rule-inventory.sh | fail-closed-missing-sources | PASS | shell scenario |
| test-rule-inventory.sh | rejects-unknown-arg | PASS | shell scenario |
| test-boot-size.sh | ceiling-communication | PASS | shell scenario |
| test-boot-size.sh | ceiling-role-discipline | PASS | shell scenario |
| test-boot-size.sh | ceiling-flow-rules | PASS | shell scenario |
| test-boot-size.sh | ceiling-role-reference | PASS | shell scenario |
| test-boot-size.sh | total-boot-floor | PASS | shell scenario |
| test-boot-size.sh | frontmatter-first-communication | PASS | shell scenario |
| test-boot-size.sh | anti-reread-communication | PASS | shell scenario |
| test-boot-size.sh | frontmatter-first-role-discipline | PASS | shell scenario |
| test-boot-size.sh | anti-reread-role-discipline | PASS | shell scenario |
| test-boot-size.sh | required-references | PASS | shell scenario |
| test-boot-size.sh | body-eager-claim | PASS | shell scenario |
| test-boot-size.sh | red-fixture-baseline-green | PASS | shell scenario |
| test-boot-size.sh | red-ceiling-communication | PASS | shell scenario |
| test-boot-size.sh | red-ceiling-role-discipline | PASS | shell scenario |
| test-boot-size.sh | red-ceiling-flow-rules | PASS | shell scenario |
| test-boot-size.sh | red-ceiling-role-reference | PASS | shell scenario |
| test-boot-size.sh | red-total-boot-floor | PASS | shell scenario |
| test-boot-size.sh | red-frontmatter-first | PASS | shell scenario |
| test-boot-size.sh | red-anti-reread | PASS | shell scenario |
| test-boot-size.sh | red-missing-required-reference | PASS | shell scenario |
| test-boot-size.sh | red-body-eager-claim | PASS | shell scenario |
| test-boot-size.sh | ceilings-sum-to-total | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-relay-mandatory | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-relay-no-exceptions | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-relay-wait | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-popup-prohibition | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-popup-refusal-phrasing | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-gate-no-terminal | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-gate-self-approval | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-gate-uncovered-action | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-gate-role-authority | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-gate-backstops | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-gate-deflection-phrasing | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-momentum-prohibition | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-momentum-refusal-phrasing | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-supersede-prohibition | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-supersede-refusal-phrasing | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-operator-dont-list | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-operator-not-enforced | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-stop-missing-attestation | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-stop-two-roles | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-stop-operator-insists | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-escalation-no-bypass | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-no-on-demand-load | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-no-prohibition-demotion | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-visuals | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b3 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b4 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b5 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b6 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b7 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b8 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b11 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modeb-b12 | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modea-decoration | PASS | shell scenario |
| test-prohibition-residency.sh | ledger-modea-width | PASS | shell scenario |
| test-prohibition-residency.sh | lazy-scope | PASS | shell scenario |
| test-prohibition-residency.sh | lazy-normative-clean | PASS | shell scenario |
| test-prohibition-residency.sh | red-fixture-baseline-green | PASS | shell scenario |
| test-prohibition-residency.sh | red-planted-lazy-prohibition | PASS | shell scenario |
| test-prohibition-residency.sh | red-demoted-prohibition | PASS | shell scenario |
| test-token-waste-classify.sh | setup-inputs-present | PASS | shell scenario |
| test-token-waste-classify.sh | report-written | PASS | shell scenario |
| test-token-waste-classify.sh | ac18-live-counts-exclude-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac18-dismissed-counted-separately | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-growing-tail-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-probe-triple-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-size-differs-only-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-intervening-write-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-compaction-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-error-result-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-nonprobe-triple-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-nonprobe-quad-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-row-02 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-row-03 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-row-04 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-row-05 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-row-07 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-row-08 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-mutctl-02 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-mutctl-03 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-mutctl-04 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-mutctl-05 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-mutctl-07 | PASS | shell scenario |
| test-token-waste-classify.sh | ac27-mutctl-08 | PASS | shell scenario |
| test-token-waste-classify.sh | ac17-growing-tail-evidence | PASS | shell scenario |
| test-token-waste-classify.sh | ac17-probe-triple-evidence | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-size-differs-only-evidence | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-contradictory-write | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-contradictory-compaction | PASS | shell scenario |
| test-token-waste-classify.sh | ac15-contradictory-error | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-triple-label-kept-live | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-since-last-write-noted | PASS | shell scenario |
| test-token-waste-classify.sh | ac18-live-section | PASS | shell scenario |
| test-token-waste-classify.sh | ac18-dismissed-section | PASS | shell scenario |
| test-token-waste-classify.sh | ac18-live-table-has-no-dismissals | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-probe-command-branch | PASS | shell scenario |
| test-token-waste-classify.sh | ac16-probe-command-evidence | PASS | shell scenario |
| test-token-waste-classify.sh | ac19-state-candidates-found | PASS | shell scenario |
| test-token-waste-classify.sh | ac19-state-all-classified | PASS | shell scenario |
| test-token-waste-classify.sh | ac19-state-clean | PASS | shell scenario |
| test-token-waste-classify.sh | ac19-state-parse-failure | PASS | shell scenario |
| test-token-waste-classify.sh | ac19-state-no-transcripts | PASS | shell scenario |
| test-token-waste-classify.sh | ac25-falseneg-none-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac25-falseneg-all-stay-live | PASS | shell scenario |
| test-token-waste-classify.sh | ac25-echo-status-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac25-message-status-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac25-probe-plus-mutation-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | ac26-path-alias-not-dismissed | PASS | shell scenario |
| test-token-waste-classify.sh | privacy-no-result-bodies | PASS | shell scenario |
| test-budget-literals.sh | enforced-ceilings-read (5 distinct CEIL_* literals) | PASS | shell scenario |
| test-budget-literals.sh | no-divergent-budget-literal (enforced: 11500 14500 42200 7000 9200) | PASS | shell scenario |
| test-budget-literals.sh | enforced-total-stated-in-prose (4 carrier(s) say 42,200) | PASS | shell scenario |
| test-budget-literals.sh | red-stale-literal-detected | PASS | shell scenario |
| test-budget-literals.sh | green-current-literal-accepted | PASS | shell scenario |
| test-budget-literals.sh | annotated-history-exempt | PASS | shell scenario |
| test-history-extraction.sh | setup-inputs-present | PASS | shell scenario |
| test-history-extraction.sh | stub-heading-retained | PASS | shell scenario |
| test-history-extraction.sh | stub-carries-no-dated-entries | PASS | shell scenario |
| test-history-extraction.sh | extraction-commit-resolved (cfac6c0) | PASS | shell scenario |
| test-history-extraction.sh | payloads-extracted | PASS | shell scenario |
| test-history-extraction.sh | content-equivalent-modulo-final-newline | PASS | shell scenario |
| test-history-extraction.sh | only-difference-is-the-final-newline (raw delta 1B) | PASS | shell scenario |
| test-history-extraction.sh | red-truncated-payload-detected | PASS | shell scenario |
| test-history-extraction.sh | red-edited-payload-detected | PASS | shell scenario |
| test-approval-binding.sh | verdict-table-and-loader-total | PASS | shell scenario |
| test-approval-binding.sh | ac3-extreme-offset-denies-through-both-handlers | PASS | shell scenario |
| test-approval-binding.sh | command-policy-action-agreement-and-root-anchoring | PASS | shell scenario |
| test-approval-binding.sh | ac9-binding-enforced-when-present | PASS | shell scenario |
| test-approval-binding.sh | ac14-denial-message-specific-and-bounded | PASS | shell scenario |
| test-approval-binding.sh | ac11-compat-acceptance-audited-cross-carrier | PASS | shell scenario |
| test-approval-binding.sh | ac11-active-approvals-honors-strict | PASS | shell scenario |
| test-approval-binding.sh | ac11-active-approvals-compat-acceptance-audited | PASS | shell scenario |
| test-approval-writer.sh | ac10-unknown-action-rejected | PASS | shell scenario |
| test-approval-writer.sh | ac10-unsafe-slug-rejected | PASS | shell scenario |
| test-approval-writer.sh | ac22-command-mandatory-for-gated-action | PASS | shell scenario |
| test-approval-writer.sh | ac22-non-gated-action-still-optional | PASS | shell scenario |
| test-approval-writer.sh | ac10-adversarial-values-round-trip | PASS | shell scenario |
| test-approval-writer.sh | ac22-emitted-invocation-round-trips | PASS | shell scenario |
| test-approval-writer.sh | ac12-inventory-four-verdicts-and-reject-count | PASS | shell scenario |
| test-approval-writer.sh | ac27-inventory-never-accepts-a-gate-rejected-artifact | PASS | shell scenario |
| test-approval-writer.sh | ac12-strict-vs-compat-and-audited-legacy-acceptance | PASS | shell scenario |
| test-approval-writer.sh | ac19-no-authorship-enforcement-claim | PASS | shell scenario |
| test-approval-writer.sh | ac19-approval-authors-marked-declarative | PASS | shell scenario |
| test-command-policy.sh | failclosed-and-all-match | PASS | shell scenario |
| test-command-policy.sh | ac8-lightweight-parity-both-handlers | PASS | shell scenario |
| test-command-policy.sh | ac26-evasion-limit-documented-and-backlogged | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | manifest-byte-stable-drift-and-single-home | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | k9-ten-state-truth-table-and-auto-yes-containment | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac16-changed-by-both-aborts-auto-yes-and-preserves-the-patch | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac13c-partial-apply-preserves-one-refreshes-siblings | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac13b-base-refresh-keeps-the-classifier-correct-on-the-next-upgrade | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac23-classifier-unavailable-fails-closed-and-writes-nothing | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac23-unsafe-legacy-copy-is-the-only-legacy-route | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac23-pre-classifier-source-still-upgrades | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac13b-base-synthesis-from-the-version-tag-delivers-content | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | k9-row10-unresolvable-tag-preserves-and-reports-never-aborts | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac24-no-self-restamp-advice-in-any-carrier | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac24-self-restamped-base-loses-the-edit-tag-sourced-base-preserves-it | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac25-aborted-bootstrap-hop-writes-nothing | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | ac25-source-executed-engine-still-upgrades-end-to-end | PASS | shell scenario |
| test-upgrade-conflict-classification.sh | t29c-classification-eol-stable-under-autocrlf-true | PASS | shell scenario |
| test-cli-flow-recovery.sh | cli-flow-recovery (0.25.9-era wired-set model; unchanged through 0.25.16) | INCONCLUSIVE | bounded timeout rc 124 |
