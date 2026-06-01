change_tier: lightweight
ticket: u11-u12-hooksoff-and-skills-guard

Problem:   U11 — a settings.json with CLI hooks but no Flow stop.py (deliberate opt-in-off
           per F3) was reported SHARED_MERGE_DRIFT (by-design state flagged as drift, like F4/U10).
           U12 — the FuseBase CLI now warns "the ./skills folder is obsolete and should be
           deleted"; root skills/ is Flow's canonical source, so a downstream following that
           advice silently breaks Flow's mirror/upgrade/health model.
Change:    check-cli-flow-conflicts.sh — (U11) hooks-not-wired => benign INFO, not drift;
           a Flow merge that clobbered CLI Stop hooks is still DRIFT. (U12 guard) empty/absent
           root skills/ while Flow mirrors exist => loud FLOW_LAYER_DRIFT with do-not-delete +
           restore guidance. Docs: AGENTS overlay "Maintenance posture" + README — don't delete
           skills/, ignore the CLI warning while Flow is installed.
           DEFERRED (open decision, not in this change): the larger realignment of Flow's
           canonical store with the CLI's .claude/skills/-only direction — needs CLI-team coord.
Verified:  recovery sim — U11 (hooks-off benign, not SHARED_MERGE_DRIFT), U12 (deleted skills/
           => FLOW_LAYER_DRIFT w/ restore steps); precision retained (missing non-flag-gated
           skill still CLI_LAYER_DRIFT; U10 flag-gated still benign). run-tests 16/16; preflight
           0/0; health HEALTHY; embedded-python + manifest JSON valid.
Rollback:  git revert <SHA>
Commit:    ea38342
Deploy:    plain operator go-ahead -> v3.8.3 (tag + GitHub release).
