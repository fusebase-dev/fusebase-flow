change_tier: lightweight
ticket: f1-f5-install-upgrade-review

Problem:   Downstream review vs v3.8.5 (Windows overlay). F1 [High]: install doc
           "Safe additive copies" omitted agents/ → mirror-agents aborts → FLOW_LAYER_DRIFT
           0/2 sub-agents. F2 [High]: U11 half-applied — main engine
           fusebase-flow-health-check.sh:252,255 still record_drift the deliberate hooks-off
           state → overlay-only opt-in verdicts SHARED_MERGE_DRIFT (conflict checker says
           HEALTHY). F3 [Med]: .gitattributes (+ LICENSE/PUBLISHING.md/.python-version) in the
           blind-copy list → eol renormalization / license overwrite on existing repos. F4 [Low]:
           shallow/tag .fusebase-flow-source → "upstream NEWER … behind by ?". F5 [Low]: node vs
           deprecated .sh Stop duplicate (intended, undocumented).
Change:    F1: add agents/ to docs/install-fusebase-cli-project.md list + bash + PowerShell.
           F2: fusebase-flow-health-check.sh settings block now U11-consistent — hooks-off
           (no stop.py, events not wired) = LOCAL_OK; drift only for events-wired-but-stop.py-
           missing (U14) or stop.py-present-but-incomplete. F3: move .gitattributes/LICENSE/
           PUBLISHING.md/.python-version to a "Copy only after review" section w/ reasons. F4:
           detect shallow/detached/unresolvable origin/main → "comparison unavailable" + VERSION.
           F5: documented (node canonical; .sh deprecated). Out of scope: CLI eslint .codex gap.
Verified:  recovery sim +U16 (run the MAIN engine on a hooks-off overlay → not SHARED_MERGE_DRIFT);
           27/27 sim; run-tests 16/16; preflight 0/0; health HEALTHY; health-check + tests syntax OK.
Rollback:  git revert <SHA>
Commit:    <filled after commit>
Deploy:    plain operator go-ahead -> v3.8.7 (tag + GitHub release).
