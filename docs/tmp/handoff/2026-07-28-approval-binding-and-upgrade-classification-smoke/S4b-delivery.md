```text
##### S4b: CLEAN 4.6.1 consumer (no local edits) -> bootstrap-upgrade to 4.7.0 #####
pre-run sha256 (control files):
51c13460c7925ce453d19e356a143f54f41eeabb5b9d335e059cc9082cb840e9 *hooks/local/upgrade.sh
eee8aaeeb5703a4f41b9c52d989f8733b7f8d333e945829126aa0f5088233964 *hooks/shared/command_policy.py

[bootstrap-upgrade] Cloning c:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition (fix/msys-v3307-hardening) -> .fusebase-flow-source/ ...
Cloning into '.fusebase-flow-source'...
warning: --depth is ignored in local clones; use file:// instead.
done.
[bootstrap-upgrade] Source VERSION: 4.7.0
[bootstrap-upgrade] synthesized the classifier base from upstream tag v4.6.1 -> audit/managed-content-manifest.json
                    (this is what upstream shipped you at 4.6.1, so the upgrade can now
                     tell YOUR edits from upstream's.)
[bootstrap-upgrade] Handing off to .fusebase-flow-source/hooks/local/upgrade.sh --auto-yes

[upgrade] Source: .fusebase-flow-source/  (HEAD 6224bbe, VERSION 4.7.0)
[upgrade] Local:  VERSION 4.6.1


[upgrade] Managed-content classification:
  current                   220 file(s)
  upstream-only              46 file(s)
  upstream-added             13 file(s)
  (no consumer divergence — every managed path was safe to refresh)

[upgrade] Backups of every touched directory: *.pre-upgrade-20260729T004338Z
[upgrade] Resume / re-run with:
    bash hooks/local/upgrade.sh
[upgrade] Plan:
  • refresh file: .claude-plugin/marketplace.json
  • refresh file: .claude-plugin/plugin.json
  • refresh file: .codex-plugin/plugin.json
  • refresh file: FLOW_RULES.md
  • refresh file: agents/ai-developer/AGENT.md
  • refresh file: agents/product-owner/AGENT.md
  • refresh file: audit/hook-layer-manifest.json
  • refresh file: flow-skills/lightweight-lane/SKILL.md
  • refresh file: flow-skills/release-deploy-reporting/SKILL.md
  • refresh file: flow-skills/role-discipline/references/deploy.md
  • refresh file: flow-skills/role-discipline/references/shared-protocols.md
  • refresh file: flow-skills/security-permissions-review/SKILL.md
  • refresh file: hooks/README.md
  • refresh file: hooks/git/pre-commit
  • refresh file: hooks/handlers/permission_request.py
  • refresh file: hooks/handlers/pre_tool_use.py
  • refresh file: hooks/local/approve-local.sh
  • refresh file: hooks/local/fusebase-flow-overlays/agents-md-overlay.md
  • refresh file: hooks/local/fusebase-flow-overlays/claude-md-overlay.md
  • refresh file: hooks/local/lib/active-approvals.sh
  • refresh file: hooks/local/lib/approval_inventory.py
  • refresh file: hooks/local/lib/hook_manifest.py
  • refresh file: hooks/local/lib/managed_content_manifest.py
  • refresh file: hooks/local/preflight.sh
  • refresh file: hooks/local/rule-inventory.sh
  • refresh file: hooks/local/stamp-managed-content-manifest.sh
  • refresh file: hooks/local/upgrade.sh
  • refresh file: hooks/local/verify-managed-content-manifest.sh
  • refresh file: hooks/shared/approval_artifact.py
  • refresh file: hooks/shared/command_policy.py
  • refresh file: hooks/shared/command_rules.py
  • refresh file: hooks/shared/denial_message.py
  • refresh file: hooks/shared/path_policy.py
  • refresh file: hooks/shared/policy_loader.py
  • refresh file: hooks/tests/fixtures/22_pre_tool_use_compound_requires_all_actions.json
  • refresh file: hooks/tests/fixtures/23_permission_request_compound_requires_all_actions.json
  • refresh file: hooks/tests/run-tests.sh
  • refresh file: hooks/tests/run_hook_tests.py
  • refresh file: hooks/tests/test-approval-binding.sh
  • refresh file: hooks/tests/test-approval-writer.sh
  • refresh file: hooks/tests/test-bootstrap-exception.sh
  • refresh file: hooks/tests/test-command-policy.sh
  • refresh file: hooks/tests/test-rule-inventory.sh
  • refresh file: hooks/tests/test-trusted-enforcer.sh
  • refresh file: hooks/tests/test-upgrade-conflict-classification.sh
  • refresh file: policies/approval-policy.yml
  • refresh file: policies/command-policy.yml
  • refresh file: templates/architect-response.md
  • refresh file: templates/change-note.md
  • refresh file: templates/deploy-report.md
  • refresh file: templates/gate-report.md
  • refresh file: templates/handoff-deploy.md
  • refresh file: templates/handoff-implement.md
  • refresh file: workflows/architect-escalation.md
  • refresh file: workflows/greenlight-deploy.md
  • refresh file: workflows/greenlight-implement.md
  • refresh file: workflows/lightweight-lane.md
  • refresh file: workflows/session-initiation.md
  • refresh file: workflows/violation-recovery.md
  • refresh file: audit/managed-content-manifest.json
  • re-mirror skills + agents (canonical -> .claude/.agents/.codex)
  • sync derived attestation strings (version + FR-range + skill count) from the repo
  • version-aware refresh of AGENTS.md/CLAUDE.md overlay blocks (operator FLOW:PRESERVE region carried forward)
  • restore Flow slash commands: recovery snapshot -> .claude/commands/ (new commands install here)
  • (framework docs NOT copied — pass --with-framework-docs to stage them under docs/_fusebase-flow/)
  • VERSION: 4.6.1 -> 4.7.0  (applied LAST, after content)

[upgrade] Step 1/5: refreshing canonical content (8 dir(s) + 4 file(s))…
[upgrade] applied 60 file(s), removed 0, preserved 220 (per-file, K15).
[merge-baseline] merged baseline -> /tmp/tmp.0KToVBEANJ (1 upstream row(s), 0 preserved project row(s))
[upgrade] Step 2/3: re-mirroring skills + agents (canonical -> providers)…
[upgrade] step: re-mirror skills (bounded 300s)…
[mirror-skills] mirroring 34 skill(s) across 2 mirror(s)…
[mirror-skills] mirrored 98 files (across 2 mirrors); 10 had pre-existing drift.
[mirror-skills] manifest: C:/tmp/ff470/s4b/audit/skill-mirror-manifest.txt
[upgrade] step: re-mirror agents (bounded 300s)…
[mirror-agents] mirrored 4 files (across 2 mirrors); 4 had pre-existing drift.
[mirror-agents] manifest: C:/tmp/ff470/s4b/audit/agent-mirror-manifest.txt
[upgrade] Step 2/3: re-mirror done.
[upgrade] Step 3/3: syncing derived attestation strings (sync-version-strings)…
[upgrade] step: sync-version-strings (bounded 180s)…
[sync-version-strings] scanning 124 allowlisted file(s); 34 contain a syncable token…
[sync-version-strings] synced derived strings (version v4.7.0, FR-01..FR-27, 34 skills) in:
  • .cursor/rules/fusebase-flow-always.mdc
  • AGENTS.md
  • CLAUDE.md
  • GEMINI.md
  • .github/copilot-instructions.md
[upgrade] recovery:   * re-mirrored Fusebase Flow skills (.claude/skills/ + .agents/skills/)
[upgrade] recovery:   * re-mirrored Fusebase Flow sub-agents (.claude/agents/ + .codex/agents/)
[upgrade] (re)installed Flow git fallback hooks (.git/hooks/pre-commit, commit-msg)
[upgrade] step: prune old .pre-* backups (single-pass, keep newest 3/stem)…

[upgrade] Content upgrade applied. VERSION now: 4.7.0
[upgrade] Backups written with suffix .pre-upgrade-20260729T004338Z (git-excluded via .git/info/exclude,
          so 'git add -A' / fusebase-update checkpoints won't stage them) — remove once validated.
[upgrade] NOTE: the pre-commit secret scan skips ONLY Flow's fixture/policy backup twins, so a BLOCK on a
          .pre-* path is NOT automatically 'just a fixture' — inspect it: rotate if it is a real credential;
          if it is only a Flow backup you don't want committed, unstage it (git restore --staged <path>).
          Mid-ticket, answer 'No' to the CLI checkpoint prompt so WIP growth in grandfathered over-ceiling
          files doesn't trip the FR-25 ratchet on a wholesale add.
[upgrade] NOTE: the hooks/ layer (incl. this engine + sync-version-strings.sh) was
          refreshed. The in-memory run finished on the OLD engine; any NEW engine
          logic takes effect on the NEXT run. Operator overrides (hooks/local/*.local.*)
          and CLI-owned .claude/hooks/** were left untouched.

[upgrade] Recommended next:
  bash hooks/local/preflight.sh                       # expect 0 errors / 0 warnings
  bash hooks/local/fusebase-flow-health-check.sh      # expect HEALTHY
  git diff                                            # review
  # On the operator's go-ahead the AGENT runs the steps below (the operator types no command):
  # stage the upgraded paths, then commit through the wired pre-commit (NO --no-verify):
  git add <upgraded paths>                            # explicit paths (not git add -A)
  bash hooks/local/write-bootstrap-approval.sh        # single-use, digest-bound internals approval
  git commit -m 'chore(flow): upgrade content to v4.7.0'
  bash hooks/local/write-bootstrap-approval.sh --consume   # single-use: clean up after the commit

[upgrade] NOTE: the Flow git fallback pre-commit was (re)installed above so the FIXED
          pre-commit is live. .claude/settings.json (Claude Code lifecycle hooks) was
          NOT modified — to (re)wire those, run: bash hooks/local/post-fusebase-update.sh --wire-hooks

[upgrade] NOTE: .fusebase-flow-source/ is a transient staging clone. ESLint flat
          config does NOT honor .gitignore, so if 'fusebase deploy' runs lint it
          will lint this clone's CommonJS hooks and fail. Either:
            rm -rf .fusebase-flow-source                         # transient; re-created next upgrade
          or add it to your eslint ignores (next to .claude/**):
            bash hooks/local/eslint-ignore-flow-paths.sh
EXIT=0

--- post-run sha256 (control files) ---
2a52bdb5adef4101924ef339d1435e09f400989d58dfb5a7c7795e78e681a666 *hooks/local/upgrade.sh
69e8b62aaaa0db57e9556d60ecc40256fe324f503592b2508ada7f6ba7492540 *hooks/shared/command_policy.py
--- VERSION ---
4.7.0
S4B_DONE=0
```
