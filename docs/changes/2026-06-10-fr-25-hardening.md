change_tier: lightweight
ticket: fr-25-hardening

Problem:   Stress test of FR-25 (empirical probe on the motivating consumer repo +
           independent devil's-advocate review) confirmed the ratchet core but
           found delivery gaps: (1) no shipped baseline -> gate dormant/silent for
           the median greenfield template consumer (copy-once distribution makes
           that ~permanent); (2) gitignored module-size.local.yml could flip
           enforcement block->warn invisibly (REPLACE semantics = silent kill
           switch); (3) full --write-baseline is a global amnesty, making the
           rename remedy grandfather every accumulated violation; (4) baseline
           .txt not a protected path; (5) no CI surface (--no-verify/dodges
           survive locally forever); (6) test files gated -> early false blocks ->
           exemption bleed; (7) LL lane has no split-quality check; (8) the
           mechanical-split review blocker hinged on unobservable intent.
Change:    1) policies/module-size-baseline.txt SHIPPED (dogfood: 1 row,
              hooks/tests/test-cli-flow-recovery.sh 954) -> gate live from
              commit #1 greenfield; install docs (install-existing-project,
              install-fusebase-cli-project) gain the one-command retrofit re-key
              step. 2) module_size.py: local override now ADDITIVE-ONLY
              (exempt_globs/source_globs appended; enforcement/ceiling/
              baseline_file ignored with warning) + notice printed whenever a
              local override is active. 3) --write-baseline <path> single-file
              re-key (rename remedy; no global amnesty); wrapper forwards args.
              4) policies/protected-paths.yml: baseline path added to
              fusebase_flow_internals. 5) fusebase-flow-verify.yml: new
              "Module-size ratchet --all" CI step. 6) default exempt_globs +=
              **/*.test.* / **/*.spec.* / **/__tests__/**. 7) lightweight-lane:
              extraction in an LL pass must name the seam in the change-note.
              8) code-review 5c + skill: observable blocker criterion (extraction
              landing in utilsN/helpersN/misc/extra-style names; no intent
              inference). Tests: +S7 local-override-cannot-disarm, +S8
              single-file-rekey-ratchets -> 8 gate scenarios, totals 24/24.
Verified:  test-module-size.sh 8/8; run-tests 24/24; preflight 0/0;
           check-module-size --all green vs shipped baseline; S7 proves a local
           enforcement:warn is ignored (violation still exits 1); S8 proves
           re-key tightens one row without touching others.
Rollback:  git revert <SHA>  (single commit; engine + policy + docs + tests)
Commit:    <backfilled after commit>
Deploy:    operator go-ahead ("proceed") -> v3.16.2 tag, push origin main
           --follow-tags. Lane note: classified Lightweight — scope was locked
           by the independent stress-test review (no open design decisions);
           gate-strengthening only, reversible, mechanically verified.
