change_tier: lightweight
ticket: overlay-refresh-trailing-blank

Problem:   refresh_overlay_block() drift-rebuild leaves one extra blank line before
           <!-- CUSTOM:SKILL:BEGIN --> vs a freshly-appended block (cosmetic; outside the
           marker-anchored compare region, so non-compounding). Re-review nit on v3.6.0 F2.
Change:    hooks/local/post-fusebase-update.sh — when rebuilding, trim trailing blank lines
           from the preserved pre-BEGIN region before re-appending the template, so the
           template's single leading blank yields exactly one blank line before BEGIN
           (byte-identical to a fresh append). Test: hooks/tests/test-cli-flow-recovery.sh
           gains a byte-exactness lock (AGENTS.md sha after a drift refresh == sha of the
           clean post-recovery block).
Verified:  recovery sim PASS — F2 no-op refresh and drift refresh both restore AGENTS.md
           byte-identical to the clean appended block (sha match); BEGIN/END balanced 1/1;
           run-tests 16/16; preflight 0/0.
Rollback:  git revert <SHA>
Commit:    <filled after commit>
Deploy:    rides with the pending v3.7.0 release (tag + GitHub release) on operator go-ahead.
