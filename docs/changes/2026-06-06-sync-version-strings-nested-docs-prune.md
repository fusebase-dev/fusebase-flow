change_tier: lightweight
ticket: sync-version-strings-nested-docs-prune

Problem:   sync-version-strings.sh prune list used exact top-level -path patterns
           (./docs/handoff, ./docs/specs, ./docs/release-notes, ./docs/fusebase-health).
           find's -path is exact (no implicit depth), so per-app layouts
           (docs/<app>/handoff, docs/<app>/specs …) were NOT pruned → the live-string
           rewrite reached into dated handoff/spec/release-note records and falsified
           their historical attestation versions. Header (lines 34-39) states the intent
           to NEVER touch dated history. Reproduced by PO.
Change:    1) hooks/local/sync-version-strings.sh prune list — add depth-tolerant
              ./docs/*/{release-notes,handoff,specs,fusebase-health} siblings to the
              existing top-level patterns (find * spans /, so ./docs/*/ catches any
              nesting depth >=1; flat case still covered). One-line FR-22 tripwire added
              above the find block. No other engine script touched.
           2) FLOW_RULES.md Status :3 v0.8 -> v0.9 + one amendment-log entry. FR-01..FR-22
              rule rows/implications unchanged.
           3) VERSION 3.11.0 -> 3.11.1; ran sync-version-strings (live attestation/FR-range/
              skill-count -> v3.11.1, FR-01..FR-22, 25 skills) + re-mirror.
Verified:  Live proof (acceptance gate, run pre-commit): fixture docs/_acctest/handoff/old.md
           + docs/_acctest/specs/old.md each carrying "Fusebase Flow v3.10.0 / FR-01 through
           FR-21". sync --dry-run → NEITHER fixture file in the would-change list (pruned by
           the fix; old exact patterns would have rewritten them). Framework live files still
           bump (GEMINI.md + FLOW_RULES.md + AGENTS.md + CLAUDE.md + templates/ + workflows/
           in the list; banner "version v3.11.1, FR-01..FR-22, 25 skills"). Fixture removed
           (not committed). preflight 0/0; health HEALTHY, 25 skills.
Rollback:  git revert <SHA>  (single commit; reversible — shell + markdown only, no schema/data)
Commit:    9a4d554
Deploy:    go-ahead "ship it" · deployed 9a4d554 via git push origin main · FR-07 check: clean
