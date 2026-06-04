change_tier: lightweight
ticket: u15-eslint-ignore-staging-clone

Problem:   [BLOCKER] `fusebase deploy` runs lint first; Flow's staging clone
           `.fusebase-flow-source/` holds CLI-owned CommonJS hooks (require()) that trip
           @typescript-eslint/no-require-imports. ESLint flat config doesn't read .gitignore,
           and the CLI's eslint.config only ignores .claude/** — so the clone gets linted and
           deploy fails with zero app errors. (Verified: Flow has no eslint config; the CLI's
           project-template/eslint.config.mjs adds .claude/**; the hooks are CLI-owned per
           cli-vendor-manifest → can't ESM-rewrite.) Plus 2 minor install-UX items.
Change:    new hooks/local/eslint-ignore-flow-paths.sh (opt-in; idempotent; backup) adds
           ".fusebase-flow-source/**" after ".claude/**" in the project's flat-config ignores.
           upgrade.sh/bootstrap print a loud transient-clone note (rm -rf or run helper).
           AGENTS overlay maintenance + README document it. Minor: project-values placeholder ->
           "(run /onboard or edit)"; README documents cold-start docs layout (created on demand).
Verified:  helper tested on the real CLI eslint.config.mjs shape — adds entry, array stays valid
           (node --check OK), idempotent. recovery sim +U15; U1/U9 setups made robust to the new
           placeholder wording. 26/26 sim; run-tests 16/16; preflight 0/0; health HEALTHY.
Rollback:  git revert <SHA>
Commit:    905037f
Deploy:    plain operator go-ahead -> v3.8.6 (tag + GitHub release).
