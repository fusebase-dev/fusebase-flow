change_tier: lightweight
ticket: u10-flag-gated-cli-skills

Problem:   The health-check treated all CLI provider skills as unconditionally expected,
           so flag-gated skills the CLI deletes when their flag is off (portal-specific-apps,
           managed-integrations, + git-workflow / app-business-docs / mcp-gate-debug) read as
           permanent CLI_LAYER_DRIFT "MISSING" — a chronic false positive for nearly every
           downstream, with dead-end advice (`fusebase update` can't restore a flag-off skill).
           Same class as F4 (absent-by-design ≠ drift).
Change:    agent-surface-ownership.json gains a flag_gated_skills map (skill -> enabling flag[s],
           mirrored from the CLI's FLAG_GATED_SKILLS). check-cli-flow-conflicts.sh: an absent
           flag-gated skill is benign INFO (flag off / undeterminable) naming the correct
           remediation (`fusebase config set-flag <flag>`), not MISSING. Only an absent skill
           whose flag is provably ON (read-only best-effort from fusebase.json) is genuine drift.
           Non-flag-gated absent skills still drift (precision retained). README health note added.
Verified:  recovery sim — U10: removing a flag-gated skill (managed-integrations) from a complete
           install stays non-CLI_LAYER_DRIFT with a benign set-flag INFO; the existing
           "MISSING CLI skill (fusebase-cli) -> CLI_LAYER_DRIFT" case still passes (precision).
           run-tests 16/16; preflight 0/0; health HEALTHY; embedded-python + manifest JSON valid.
Rollback:  git revert <SHA>
Commit:    <filled after commit>
Deploy:    plain operator go-ahead -> v3.8.2 (tag + GitHub release).
