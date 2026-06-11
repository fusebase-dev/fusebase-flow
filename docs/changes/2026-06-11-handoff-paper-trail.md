change_tier: lightweight
ticket: handoff-paper-trail

Problem:   docs/tmp/handoff.md is superseded in place; "audit trail = git
           history" (FR-18) fails when the supersede is never committed —
           which is the normal case, since handoffs are written mid-session
           right before a session dies. Prior restart state silently lost.
Change:    handoff skill + /handoff command: archive the existing
           docs/tmp/handoff.md to docs/tmp/handoff/archive/
           <YYYY-MM-DD-HHMM>-handoff.md (timestamp from its Updated: header,
           else mtime/now) BEFORE writing fresh; Updated: timestamp header
           mandatory. Archives = dated history, never agent-loaded, operator
           may prune. Live filename unchanged (read path stable). Formal
           relays unchanged (revision = same artifact, FR-18 supersede
           correct there). Carriers: flow-skills/handoff/SKILL.md (+mirrors),
           templates/handoff.md, .claude/commands/handoff.md, AGENTS.md row,
           documentation-budget Tier-2 row. Plus: gh release create codified
           as mandatory in PUBLISHING.md.
Verified:  preflight 0/0; run-tests 24/24; mirrors 0 drift post-sweep.
Rollback:  git revert <SHA>
Commit:    <backfilled after commit>
Deploy:    operator request (timestamped handoffs + paper trail) -> v3.18.2
           tag + GitHub Release, push origin main --follow-tags.
