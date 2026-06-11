change_tier: lightweight
ticket: flow-efficiency-repairs

Problem:   Framework-wide independent efficiency audit (after the FR-25 token
           audit) found 2 broken consumer paths + drifted/stale surfaces:
           (F5) docs/install-existing-project.md copy blocks still copied
           retired `skills/` and never `flow-skills/` -> documented existing-
           repo install landed with ZERO Flow skills; (F7) settings.json.example
           used ${PROJECT_DIR}, which Claude Code never sets -> documented
           quick-activation left all 6 Flow lifecycle hooks silently dead;
           (F4) inline AGENTS/CLAUDE overlay blocks drifted from the canonical
           overlay templates (missed the v3.16.3 amendment-log stop; CLAUDE
           inline lacked CUSTOM:SKILL markers recovery anchors on); (F8) two
           deprecated jq/bash Stop scripts still shipped 14 releases after
           deprecation; 11 stale facts (9 files still naming canonical
           `skills/`, false README no-dev-history claim, role-discipline:73
           token claim wrong >2x); rail-mapping rows 6 releases behind.
Change:    1) install-existing-project.md: skills -> flow-skills in bash + PS
              copy blocks (unbreaks the install). 2) settings.json.example:
              python3 \"$CLAUDE_PROJECT_DIR\"/... on all 6 Flow handlers +
              corrected comments (merger still normalizes legacy
              ${PROJECT_DIR} in old installs). 3) AGENTS.md/CLAUDE.md inline
              overlay blocks replaced with the canonical templates (markers,
              amendment-log stop, FLOW:PRESERVE, current catalog). 4) Deleted
              .claude/hooks/run-{lint,typecheck}-on-stop.sh; provenance
              re-stamped (124 assets); refs updated (README, audit/README,
              settings example; merger keeps stripping them downstream).
           5) Stale-facts sweep: flow-skills/ in framework.md, constitution,
              tradeoffs, problem-catalog README, docs/skills README,
              skill-template, eight-phase-flow, knowledge-curation; README
              docs-layout claim corrected; role-discipline:73 measured
              numbers. 6) rail-mapping: FR-20..25 rows + counts 19->25 base +
              dead open-questions.md ref removed; ROADMAP radar updated.
Verified:  preflight 0/0; run-tests 24/24; check-module-size --all green;
           settings.json.example parses as valid JSON with all 6 handlers on
           $CLAUDE_PROJECT_DIR; AGENTS/CLAUDE inline blocks contain
           CUSTOM:SKILL + FLOW:PRESERVE markers + amendment-log stop.
Rollback:  git revert <SHA>
Commit:    <backfilled after commit>
Deploy:    operator go-ahead ("proceed") -> v3.16.4 tag, push origin main
           --follow-tags.
