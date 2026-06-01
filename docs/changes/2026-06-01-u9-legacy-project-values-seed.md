change_tier: lightweight
ticket: u9-legacy-project-values-seed

Problem:   The U1 FLOW:PRESERVE carry-forward only matches when the live block already
           has the markers. The FIRST preserve-aware upgrade (a pre-markers block →
           3.8.0) therefore still reset operator project-values once (downstream lost
           Project name + Stack on the 3.7.0→3.8.0 hop). The transition was lossy.
Change:    hooks/local/post-fusebase-update.sh — refresh_overlay_block() now also seeds
           the new preserve region from a LEGACY (marker-less) `### Project-specific
           values` table: detect it by its heading + "…rules win." footer, wrap it in
           the template's FLOW:PRESERVE markers, and carry it forward. Makes the first
           preserve-aware upgrade lossless. (AGENTS-only; CLAUDE has no preserve region.)
Verified:  recovery sim — a block with CUSTOM:SKILL markers but NO FLOW:PRESERVE and a
           customized legacy project-values table, after --refresh-overlays, keeps the
           operator value AND gains the FLOW:PRESERVE markers; existing U1/F2/U7 still
           pass; run-tests 16/16; preflight 0/0.
Rollback:  git revert <SHA>
Commit:    4c1c522
Deploy:    plain operator go-ahead → v3.8.1 (tag + GitHub release).
