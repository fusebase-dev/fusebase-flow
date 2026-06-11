change_tier: lightweight
ticket: flow-token-trim

Problem:   Independent token-economy audit of FR-25 (verdict: NET POSITIVE —
           4-6x cost coverage — WITH WASTE): ~33% of FR-25's live context cost
           was self-inflicted, and the audit's biggest find was framework-wide —
           AGENTS.md says "load FLOW_RULES.md" with no boundary, so the
           amendment log (4.1k tokens, ~40% of the file, pure dated history)
           was paid by EVERY compliant session in every consumer repo
           (~410k tokens / 100 sessions). Also: FR-25 row + implication
           restated the same semantics twice in that always-read file
           (744 tok/session); role-discipline preamble duplicated the digest
           table 30 lines below it; role-discipline:50 contradicted the actual
           load model; decisions.md M4 was stale (FR-18 violation —
           contradicted by the v3.16.2 shipped baseline).
Change:    1) Session reads now stop at `## Amendment log`: skip instruction
              added to AGENTS.md / CLAUDE.md / GEMINI.md / copilot-instructions
              / cursor always.mdc / session-initiation / handoff-implement +
              boundary marker under the heading itself (heading text unchanged —
              it anchors the sweep guard) + both overlay templates;
              role-discipline:50 load-model row corrected.
           2) FLOW_RULES FR-25 row compressed to house style (1,626->~700
              chars) + implication deduped (1,348->~700) — all operative
              semantics preserved, restated rationale cut (spec owns it).
           3) role-discipline :161 preamble -> one-line pointer to the digest
              table (715->~230 chars).
           4) decisions.md M4 superseded IN PLACE (FR-18) to the v3.16.2
              shipped-baseline truth; stderr remedy gains "extraction is
              in-scope for the current task" (saves operator round-trips).
Verified:  preflight 0/0; run-tests 24/24; sweep dry-run clean (amendment-log
           guard anchor unchanged); audited savings ~470k tokens / 100
           compliant sessions per consumer repo (amendment-log skip ~410k +
           row/implication merge ~47k + preamble dedupe ~12k).
Rollback:  git revert <SHA>
Commit:    <backfilled after commit>
Deploy:    operator go-ahead ("proceed") -> v3.16.3 tag, push origin main
           --follow-tags.
