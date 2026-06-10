change_tier: lightweight
ticket: publish-roadmap-backlog

Problem:   ROADMAP.md + 2 backlog tickets (architect-sub-agent, role-path-hook-
           enforcement) existed only on the stranded pre-v3.2 local-main line
           (commit d8f24f5, never pushed) — the published repo had no roadmap,
           and the tickets' framework references were 3 months stale
           (skills/ paths, 14/14 tests, 18 FR rules).
Change:    1) ROADMAP.md (new, root) rewritten to the v3.16.0 baseline: released
              arc v3.2→v3.16, Next-likely (architect sub-agent, role×path hook
              enforcement with the FR-25 plumbing precedent), radar items
              (rail-mapping rows, .claude/commands refresh path, baseline rename
              handling, dogfood baseline), corrected non-goals (plugin + slash
              commands exist as optional conveniences, not primary paths; regex
              gates only for objectively countable rules).
           2) docs/backlog/{architect-sub-agent,role-path-hook-enforcement}/
              README.md harvested + refreshed (flow-skills/ paths, 22/22 tests,
              docs/tmp/handoff relays, FR-25 glob-matcher reuse, *.local.yml
              gitignore note); docs/backlog/index.md created (3 parked tickets).
           3) .github/workflows/fusebase-flow-verify.yml — ROADMAP.md added to
              the public-surface allowlist (documented approval path).
           4) README public-docs list + CONTRIBUTING before-you-start gain
              ROADMAP pointers.
Verified:  preflight 0/0; run-tests 22/22; sweep dry-run clean; CI green on push
           (public-surface guard accepts ROADMAP.md).
Rollback:  git revert <SHA>  (single commit; markdown + one allowlist line)
Commit:    <backfilled after commit>
Deploy:    plain operator go-ahead ("proceed to finalize it in one development
           cycle") → push to origin main; local main fast-forwarded after
           (stranded line archived as a local branch).
