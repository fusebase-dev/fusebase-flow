change_tier: lightweight
ticket: audit-nit-sweep

Problem:   Independent post-ship audit of the v3.16.0->v3.17.0 chain: verdict
           ALL CORRECT / zero blockers, but 6 residual stale pointers (role
           don't-lists claimed to live in role-discipline/SKILL.md after the
           v3.17.0 split moved them to references/<role>.md), 2 stale
           PUBLISHING facts (expected mirror count; inline allowlist missing
           ROADMAP.md/.claude-plugin/flow-skills), one installer-description
           skills/ ref, and ONE real gap: references/*.md mirrors carried all
           55 role rules with NO drift gate (preflight + manifest hashed only
           SKILL.md files — silent-drift risk).
Change:    1) mirror-skills.sh: per-file hash + manifest rows + drift count
              for references/* (manifest 56 -> 68 entries). 2) preflight.sh §5
              loop extended to flow-skills/*/references/* across both mirrors.
           3) Pointers repointed to references/<role>.md: skill-authoring x2
              (one also had retired skills/ path), agents/product-owner:32 +
              agents/ai-developer:41 context-load rows, claude-md-overlay
              mandatory bullet (canonical edited + CLAUDE.md inline
              re-spliced, byte-verified), violation-recovery:187,
              operator-discipline:98, backlog/architect-sub-agent:49.
           4) PUBLISHING.md expected mirror output 56->68 + allowlist synced
              to fusebase-flow-verify.yml; install-existing-project.md:328
              skills/ -> flow-skills/.
Verified:  preflight 0/0 (references drift checks active); run-tests 24/24;
           check-module-size --all exit 0; sweep dry-run clean; mirror run
           reports 68 files; CLAUDE inline overlay == canonical (byte).
Rollback:  git revert <SHA>
Commit:    3f55feb
Deploy:    operator go-ahead ("bump up version and then publish it") ->
           v3.17.1 tag, push origin main --follow-tags.
