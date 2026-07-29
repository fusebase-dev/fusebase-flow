```text
##### S4a ADVERSARIAL: same fixture through the consumer's OWN 4.6.1 upgrade.sh engine #####
pre sha256:
88682ed62e0c67250c0965f41521524f7a77a84a6cfd8dd830de71f8723bbf36 *hooks/shared/command_policy.py
--- bash hooks/local/upgrade.sh --auto-yes (4.6.1 engine) ---
[upgrade] Source: .fusebase-flow-source/  (HEAD 6224bbe, VERSION 4.7.0)
[upgrade] Local:  VERSION 4.6.1

[upgrade] Plan:
  • refresh dir:  flow-skills/
  • refresh dir:  agents/
  • refresh dir:  workflows/
  • refresh dir:  policies/
  • refresh dir:  templates/
  • refresh dir:  hooks/
  • refresh dir:  .claude-plugin/
  • refresh dir:  .codex-plugin/
  • refresh file: FLOW_RULES.md
  • refresh file: audit/hook-layer-manifest.json
  • re-mirror skills + agents (canonical -> .claude/.agents/.codex)
  • sync derived attestation strings (version + FR-range + skill count) from the repo
  • version-aware refresh of AGENTS.md/CLAUDE.md overlay blocks (operator FLOW:PRESERVE region carried forward)
  • restore Flow slash commands: recovery snapshot -> .claude/commands/ (new commands install here)
  • (framework docs NOT copied — pass --with-framework-docs to stage them under docs/_fusebase-flow/)
  • VERSION: 4.6.1 -> 4.7.0  (applied LAST, after content)

[upgrade] Step 1/5: refreshing canonical content (8 dir(s) + 3 file(s))…
[merge-baseline] merged baseline -> /tmp/tmp.xiYTspjmUX (1 upstream row(s), 0 preserved project row(s))
[upgrade] Step 2/3: re-mirroring skills + agents (canonical -> providers)…
[upgrade] step: re-mirror skills (bounded 300s)…
[mirror-skills] mirroring 34 skill(s) across 2 mirror(s)…
[mirror-skills] mirrored 98 files (across 2 mirrors); 10 had pre-existing drift.
[mirror-skills] manifest: C:/tmp/ff470/s4a-old/audit/skill-mirror-manifest.txt
[upgrade] step: re-mirror agents (bounded 300s)…
[mirror-agents] mirrored 4 files (across 2 mirrors); 4 had pre-existing drift.
[mirror-agents] manifest: C:/tmp/ff470/s4a-old/audit/agent-mirror-manifest.txt
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
[upgrade] Backups written with suffix .pre-upgrade-20260729T003947Z (git-excluded via .git/info/exclude,
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
--- post sha256 ---
69e8b62aaaa0db57e9556d60ecc40256fe324f503592b2508ada7f6ba7492540 *hooks/shared/command_policy.py
--- sentinel count (0 = lost, proves the overwrite path) ---
0
0
ADV_DONE=0
```
