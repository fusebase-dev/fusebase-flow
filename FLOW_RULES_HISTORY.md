# Fusebase Flow — amendment log (dated history)

> Dated history extracted from `FLOW_RULES.md`; the live rule set stays there and per-release detail is in `docs/release-notes/`. Not a session read.
> TRIPWIRE: never version-sync this file — its banner/FR/skill-count strings are historical, and rewriting them falsifies history (`hooks/tests/test-sync-allowlist.sh` proves it stays out of the sync allowlist).

```
2026-05-08 — v0.1 initial. 15 always-on rules codified from clean-room redesign of
             prior Product Owner Flow rails. Communication and implementation discipline
             moved from "skills" into rules per design thesis.

2026-05-10 — v0.2. FR-16 added (operator is a thin relay). Codifies the Operator
             Stewardship principle: human operator's job narrows to product
             decisions, gate approvals, and physical relay between sessions.
             Cognitive load — interpreting reports, recommending options,
             composing return prompts — moves to PO via the Operator Relay
             Protocol (flow-skills/role-discipline/SKILL.md). Driver: operator
             friction during paperclip+hermes-v1 deploy gate where operator
             couldn't decode "DP.6 magic phrase" guidance and PO gave
             framework-jargon responses instead of plain action steps.
             Shipped in framework v2.6.0.

2026-05-10 — v0.3. FR-17 added (forward momentum, never retreat). Driver:
             observed agent tendency to suggest closing the session, "letting
             it bake," resting, or postponing — framed as operator-friendly
             advice but actually presumptuous agent caution. Operator surfaced
             this explicitly: "AI always tries to avoid continue working...
             constantly engages in things like 'You are done', 'Go to rest',
             'Let's postpone'. This is not productive." FR-17 codifies the
             reverse default: every turn presents the next forward action;
             agents do not recommend stopping. If there's nothing to do, say
             "no pending action" neutrally and let the operator decide.
             Shipped in framework v2.8.0.

2026-05-10 — v0.4. FR-18 added (supersede, don't accumulate). Token-efficiency
             initiative. Driver: real-world artifact bloat observed in
             paperclip+hermes-v1 deploy handoff — first deploy attempt aborted,
             PO added "RESUMPTION NOTES" on top but didn't delete the now-stale
             "ORIGINAL HANDOFF BODY". Result: 25KB handoff with ~50% dead
             weight, paid in tokens on every reload. Framework had no rule
             against accumulating. FR-18 codifies REPLACE-not-PRESERVE for
             revisions; audit trail moves to git history. Exception for
             human-readable diff: `## Superseded sections (audit only —
             agents skip)` heading. Shipped in framework v2.9.0 alongside
             5 other token-efficiency themes (de-dup self-attestation,
             lazy-load patterns library, role-filtered role-discipline,
             extracted template checklists, tightened handoff preludes).

2026-05-27 — v0.5. FR-19 added (chat-text questions, no popup menus).
             Driver: operators reported that clickable popup menus are hard
             to copy, forward, scroll back to, or follow up on across the
             Product Owner / AI Developer relay loop. FR-19 broadens the
             v2.7.1 PO-only AskUserQuestion restriction to all roles:
             operator questions must be normal chat text with options.

2026-05-31 — v0.6. FR-20 added (zoom out, don't patch-myopically).
             Driver: gap analysis of the FuseBase positioning source
             identified patch-myopia — LLMs fixing the visible symptom
             with narrow patches instead of zooming out to root cause —
             as a primary driver of AI-development drift. FR-20 makes
             "zoom out before you patch" an always-on default (paired
             with FR-10 reproduce-before-fix) and is operationalized by
             flow-skills/zoom-out/SKILL.md. Shipped in framework v3.3.0
             alongside the generic-flow-skills batch (zoom-out,
             phase-audit, git-history-diagnostic, plus domain-expert and
             prototype-before-build skill extensions).

2026-06-01 — v0.7. FR-21 added (ceremony proportional to change size).
             Driver: production feedback from paperclip+hermes-v1 — a
             one-line, reversible edit ran the full lifecycle (spec →
             decisions → tasks → gate → two-agent build-then-deploy split +
             DP.1 artifact + DP.6 magic phrase) at ~10-16 min wall-clock,
             ~98% process/build/verify/approval and ~2% the actual change.
             The only prior concession (skip-clarify) skips clarify alone.
             FR-21 introduces a two-tier model: every ticket is classified
             Full or Lightweight at Specify; a Lightweight ticket uses a
             single change-note, one build->verify->deploy agent pass, and a
             plain operator go-ahead instead of the DP.1 artifact + DP.6
             phrase — while keeping the full safety floor (live proof,
             explicit deploy go-ahead, FR-07, rollback, one-commit) in both
             lanes. Fail-safe-up + mandatory mid-flight promotion guard
             against under-tiering. Operationalized by
             flow-skills/lightweight-lane/SKILL.md. Shipped in framework v3.7.0.

2026-06-04 — v0.8. FR-22 added (comment policy: tripwire + pointer only).
             Driver: cross-project audits (paperclip+hermes-v1 + AssetWatch
             Prod, 2026-06-04) found ~45% of comments in trust-critical files
             removable — WHAT-restating prose, rationale already homed in a
             decision/backlog, and changelog history — because Flow source is
             read by AI agents, not humans. Two framework-level root causes:
             the base "match surrounding comment density" instruction is a
             one-directional ratchet (Flow now ships an explicit override), and
             every Stop-hook gate is comment-blind so over-commenting is
             invisible to the loop. FR-22 mandates two comment kinds (one-line
             tripwire; ≤1-line retrieval pointer to the external WHY-home) and
             removes the rest. Two subtleties preserved: storage ≠ retrieval
             (the pointer is load-bearing, not a duplicate — deleting it
             orphans the external record), and architecture-dependence
             (carve-outs are project-settable via policies/comment-policy.yml:
             trust_critical_globs; each project runs the audit prompt in
             docs/comment-policy.md). Enforced at write-time (this rule) +
             review-time (code-review dimension), never via a regex/lint gate
             (tripwire-vs-restate is semantic). Not retroactive. Shipped in
             framework v3.10.0.

2026-06-06 — v0.9. FR-22 write-time delivery shipped in v3.11.0 (comment-policy
             carrier skill + sub-agent push + reachable audit prompt +
             role-discipline false-claim fix); sync-version-strings
             nested-per-app-docs prune fix in v3.11.1.

2026-06-07 — v0.10. FR-23 added (documentation budget). Documentation-overhead
             reduction initiative. Driver: PO and AI Developer sessions create
             unnecessary AI-consumed artifacts — decisions with no real
             decision, handoffs that reprint the full spec, product docs for
             small fixes, narrative-heavy business-logic docs — that cost
             context on every future load and spawn stale conflicting copies.
             FR-23 codifies tier-based doc creation (Tier 0-4), canonical
             artifact ownership, pointer-over-duplication, and an active-vs-
             formal handoff split (docs/tmp/handoff.md for active session
             continuity; docs/handoff/* for formal implement/deploy relays).
             Complements FR-21 on the documentation axis (Tier 1 == the
             Lightweight change-note). New skill
             flow-skills/documentation-budget/SKILL.md + new AI-readable
             template templates/business-logic-index.md (human-readable
             templates/business-logic.md preserved). No safety gate weakened;
             Full lane + FR-05/FR-07/FR-12 unchanged. Lands in framework
             v3.12.0.

2026-06-07 — v0.11. Handoff-path consolidation (no rule added/removed). All
             handoff artifacts moved under docs/tmp/handoff: active restart
             state = docs/tmp/handoff.md; formal implement/deploy/architect
             relays = docs/tmp/handoff/<date>-<slug>-<stage>.md. Rationale:
             handoffs are operational/transient AI-workflow artifacts, not
             durable product docs. Deferred from the v3.12.1 patch because
             formal relays are load-bearing for the deploy-safety gate; done
             atomically here. Rewired policies/required-artifacts.yml +
             gate-contracts.yml, hooks/handlers/stop.py smoke regex + fixtures
             13/14, all workflow/agent/template/skill references, and the FR-23
             row + implication (above). docs/handoff/ retained as a frozen
             historical archive (README redirects). Deploy-safety semantics
             preserved: run-tests 16/16, preflight 0/0. Spec:
             docs/specs/handoff-path-migration/spec.md. Shipped in framework
             v3.13.0.

2026-06-07 — v0.12. Handoff procedure finalized (no rule added/removed). New
             flow-skills/handoff/SKILL.md (operator-triggered; writes active
             restart state to docs/tmp/handoff.md), templates/handoff.md
             (16-section Mode B substrate), and /handoff slash command —
             completing the active-continuity half of FR-23 Tier 2 (formal
             relays already at docs/tmp/handoff/ since v3.13.0). Also ran the
             deferred sync-version-strings.sh sweep so all live attestation
             strings read v3.14.0 / FR-01..FR-23 / 27 skills (canonical skill
             count 26 -> 27). No rule text changed; FLOW_RULES attestation
             version bumped by the sweep. Shipped in framework v3.14.0.

2026-06-07 — v0.13. Release-hygiene polish (no rule added/removed). v3.14.1:
             clarified /handoff (Claude Code command) vs the portable handoff
             skill (AGENTS.md states the non-Claude invocation); fixed stale
             surface metadata (plugin.json 3.10.0, README badge, compatibility
             matrix counts, existing-repo copy block flow-skills/); added
             preflight §8 command-surface guard (handoff command/skill present +
             plugin.json version == VERSION). Attestation version swept to
             v3.14.1. Shipped in framework v3.14.1.

2026-06-07 — v0.14. Doc-consistency sweep (no rule added/removed). v3.14.2:
             corrected stale skill/mirror/hook counts and canonical-path refs
             that the version-string sweep does not reach (prose counts) —
             audit/README.md, docs/{compatibility,source-map,clean-room,
             fusebase-cli-edition}.md, PUBLISHING.md, README catalog: 27 Flow
             skills, 54 mirrors, 16/16 hook tests, canonical `flow-skills/`
             (not `skills/`). Translated READMEs are intentionally version-free
             summaries (point to canonical English README) — unchanged.
             Attestation swept to v3.14.2. Shipped in framework v3.14.2.

2026-06-08 — v0.15. FR-24 added (write-time discipline delivery). Driver:
             consumer (WorkHub Managed) upgraded to v3.14.2 and still got
             verbose human-oriented comments — FR-22's carrier skill is
             description-matched and never loaded in an operator-launched
             AI-Developer fix chain. Zoom-out (FR-20): FR-22 is one symptom of
             a class — the write-time rules (FR-09 Mode B, FR-18 supersede,
             FR-22 comments, FR-23 doc-budget) all share the same "is it in the
             writing agent's context at write time?" delivery gap, and FR-23
             (the documentation rule) is exposed identically. Per-skill
             mandatory_load was already rejected (comment-policy decisions,
             Option D) as self-contradictory context bloat. FR-24 codifies ONE
             systemic fix: an always-on, role-scoped **write-time discipline
             digest** (pointer index, not duplicated bodies) in
             role-discipline's writing-role sections, reinforced in
             handoff-implement (sub-agent reach) + session_start reminder. New
             write-time rules register one digest line. No new skill, no
             mandatory_load change, no gate. Audience principle codified: dev
             artifacts are AI-consumed (optimize for AI only); human-facing
             surface stays human-readable. Spec:
             docs/specs/write-time-discipline-delivery/spec.md. Shipped in
             framework v3.15.0.

2026-06-10 — v0.16. FR-25 added (module-size ratchet). Driver: consumer audit
             (paperclip+hermes-v1) found source files of 19,026 / 14,202 /
             10,434 / 5,363 lines accreted under full Flow discipline. Root
             cause is a structural blind spot, not a broken rule: tasks say
             WHAT but never WHERE; every gate is behavioral; one-task-one-
             commit + FR-21 make mid-task extraction look like scope creep —
             the monolith is the integral of N individually-reasonable diffs.
             FR-25 ships the first DETERMINISTIC write-time gate (line count
             is objective, unlike FR-22/FR-23 semantics): new
             policies/module-size.yml (ceiling 800, source/exempt globs,
             local override) + hooks/shared/module_size.py (wrapper
             hooks/local/check-module-size.sh) wired into the pre-commit
             fallback; ratchet-only — over-ceiling files freeze at the
             committed baseline (policies/module-size-baseline.txt), new
             files must be under ceiling, no baseline -> warn-only
             (adoption-safe on legacy repos). Plan-time: tasks name target
             files; over-ceiling target -> extract or exempt (implementation-
             planning + templates/tasks.md). Steering: FR-24 digest line,
             code-review dimension (incl. mechanical-split check — split
             quality stays semantic/review-time), lightweight-lane interplay
             (extraction-to-satisfy-ratchet is in-scope, not promotion), new
             carrier skill flow-skills/module-size-discipline. Not
             retroactive. 6 deterministic gate scenarios added to hook tests
             (16 fixtures + 6 = 22). Spec:
             docs/specs/module-size-discipline/spec.md. Shipped in framework
             v3.16.0.

2026-06-10 — v0.17. Roadmap publication (no rule added/removed). v3.16.1:
             ROADMAP.md (root, public-surface allowlisted) + 2 parked backlog
             tickets (architect-sub-agent, role-path-hook-enforcement)
             harvested from the stranded pre-v3.2 local line and refreshed to
             the v3.16.0 baseline; docs/backlog/index.md; README/CONTRIBUTING
             pointers. Local main fast-forwarded to origin/main (stale-local-
             main hazard resolved; stranded line archived locally).
             Attestation strings swept to v3.16.1.

2026-06-10 — v0.18. FR-25 hardening (no rule added/removed). v3.16.2: stress
             test (empirical probe on the motivating consumer repo — monoliths
             grew 14,202->15,616 / 10,434->10,840 lines in the days since the
             audit — + independent devil's-advocate review) confirmed the
             ratchet core and exposed delivery gaps. Fixes: template now SHIPS
             its own baseline (gate live from commit #1 greenfield; retrofit =
             one --write-baseline, added to both install docs); local override
             additive-only (exempt/source globs appended; enforcement/ceiling/
             baseline_file not locally overridable; notice printed) — closes
             the gitignored kill-switch channel; --write-baseline <path>
             single-file re-key (rename remedy without global amnesty);
             baseline path protected (fusebase_flow_internals); CI --all step
             in fusebase-flow-verify; test-file exempts (*.test.* / *.spec.* /
             __tests__); LL extractions name their seam in the change-note;
             mechanical-split review blocker made observable (utilsN-style
             names, no intent inference). Gate scenarios 6->8 (totals 24/24).
             Change-note: docs/changes/2026-06-10-fr-25-hardening.md. Shipped
             in framework v3.16.2.

2026-06-10 — v0.19. Token-trim (no rule semantics changed). v3.16.3: an
             independent token-economy audit of FR-25 (verdict NET POSITIVE,
             4-6x cost coverage, WITH WASTE) found the framework's biggest
             hidden cost: session-start instructions said "load FLOW_RULES.md"
             unbounded, so this amendment log (~40% of the file, dated
             history) was paid by every compliant session (~410k tokens/100
             sessions per consumer repo). Session reads now stop at
             "## Amendment log" (skip instruction in all adapters + workflows
             + handoff template + overlays; boundary marker under the heading;
             heading text unchanged — sweep-guard anchor). FR-25 row +
             implication deduplicated to house style (~47k/100 sessions);
             role-discipline write-preamble collapsed into the digest table it
             pointed at (~12k); role-discipline:50 load-model contradiction
             fixed; module-size-discipline decisions M4 superseded in place
             (FR-18 — was stale vs the v3.16.2 shipped baseline); gate stderr
             gains "extraction is in-scope for the current task". Change-note:
             docs/changes/2026-06-10-flow-token-trim.md. Shipped in framework
             v3.16.3.

2026-06-10 — v0.20. Efficiency repairs (no rule changed). v3.16.4, from a
             framework-wide independent efficiency audit: fixed the broken
             existing-repo install (copy blocks still copied retired skills/,
             never flow-skills/ -> consumers got zero Flow skills) and the
             broken hook quick-activation (settings.json.example used
             ${PROJECT_DIR}, never set by Claude Code -> all 6 Flow hooks
             silently dead; now $CLAUDE_PROJECT_DIR). Inline AGENTS/CLAUDE
             overlay blocks re-synced to the canonical templates (markers +
             amendment-log stop). Deprecated jq/bash Stop scripts removed
             (provenance re-stamped). Stale-facts sweep (9 canonical-skills/
             path refs, README dev-history claim, role-discipline token
             claim). rail-mapping rows FR-20..25 added (6 releases behind).
             Change-note: docs/changes/2026-06-10-flow-efficiency-repairs.md.
             Shipped in framework v3.16.4.

2026-06-10 — v0.21. Context-floor reduction (no rule semantics changed —
             independent-reviewer attested per rule FR-16..FR-24). v3.17.0:
             always-on session floor cut ~30% (~8k tokens/session/role).
             (1) role-discipline role sections split to references/<role>.md
             (SKILL.md 50.3KB -> 23.4KB keeps shared protocols + role index;
             same lazy-load pattern as communication/references). (2) This
             file's FR-16..24 rows + implications compressed to house style
             (live region -8.2KB); dropped text verified surviving in each
             rule's enforcement-pointer target. (3) Adapter dedup: CLAUDE/
             AGENTS base sections that duplicated their overlay blocks ->
             single pointer (overlays stay byte-identical to canonical
             templates); canonical claude overlay's 28-bullet catalog ->
             pointer (Claude Code injects skill descriptions; AGENTS comma
             list kept for Codex). (4) Existing-repo install copies only live
             docs/*.md, never upstream dev history (~7.4MB). Spec:
             docs/specs/context-floor-reduction/spec.md. Shipped in framework
             v3.17.0.

2026-06-10 — v0.22. Post-ship audit sweep (no rule changed). v3.17.1: an
             independent post-ship audit of the v3.16.0->v3.17.0 chain found
             zero blockers; this patch closes its nits + one real gap —
             references/*.md mirrors (which carry the per-role don't-lists
             since v3.17.0) are now drift-gated by mirror-skills.sh (manifest
             56->68 entries) and preflight §5; 6 residual stale pointers
             repointed to references/<role>.md; PUBLISHING expected outputs +
             inline allowlist synced; installer description skills/ ->
             flow-skills/. Change-note:
             docs/changes/2026-06-10-audit-nit-sweep.md. Shipped in framework
             v3.17.1.

2026-06-10 — v0.23. Integration-debloat (no rule text changed). v3.18.0, from
             a capability-integration audit: 3 live cross-surface
             contradictions fixed (FR-14 docs-commit owner = Deploy session,
             agents corrected; decisions requirement tier-aware per FR-23 —
             "LOCKED if present"; security review conditional on its own
             trigger list). Procedure de-dup: gate contract canonical =
             gate-contracts.yml + gate-report template (7 carriers ->
             pointers); smoke canonical = smoke-testing skill; ~130 lines of
             legacy handoff snippets deleted from greenlight workflows
             (-9.3KB / -20% across per-ticket-read files). Review boundary:
             code-review trusts the recorded validation-and-qa gate verdict
             for deterministic fields. Reversible-deploy waiver: on
             dp1_waiver:eligible handoffs the Deploy agent stamps DP.1 itself
             upon the operator's DP.6 phrase (artifact + hook semantics
             unchanged; migration/security/protected-path excluded).
             Machinery: task_complete.py retired; session-initiation reads
             context-summary; preflight overlay-copy drift check;
             upgrade-engine.sh shimmed; 2 orphan templates deleted (24->22),
             audience.md wired into project-onboarding; knowledge routing
             cross-pointers; workflows/git-workflow.md renamed
             git-discipline.md (CLI skill name collision). Spec:
             docs/specs/integration-debloat/spec.md. Shipped in framework
             v3.18.0.

2026-06-11 — v0.24. Post-ship nit-sweep (no rule changed). v3.18.1: an
             independent post-ship audit of v3.18.0 found 0 blockers, 9 nits —
             all fixed: waiver-path consistency (DP.6 prompt no longer claims
             'artifact verified' pre-stamp on eligible deploys; mandatory-read
             7 + release-deploy-reporting step 1 carry the waiver branch);
             gate-field restatements in ai-developer agent + IM.9 pointer-ized
             (the agent copy had already drifted — missing
             implementation_summary); README conditional security-review
             residue; task_complete removed from the event-schema enum;
             producer line added: omitting decisions.md requires the literal
             'no real decisions' in spec.md (consumed by optional_when);
             handoff drafting steps repointed at the canonical templates;
             gate-report placeholder attestation made sweep-maintained.
             Change-note: docs/changes/2026-06-11-v3181-nit-sweep.md. Shipped
             in framework v3.18.1.

2026-06-11 — v0.25. Handoff paper trail (no rule changed). v3.18.2: operator
             observed docs/tmp/handoff.md is overwritten in place, and the
             FR-18 "audit trail = git history" assumption fails exactly when
             handoffs are written — mid-session, often uncommitted. The
             handoff skill/command now ARCHIVE the predecessor to
             docs/tmp/handoff/archive/<YYYY-MM-DD-HHMM>-handoff.md before
             writing fresh (timestamped Updated: header mandatory). Archives
             are dated history — never loaded by agents (zero context cost);
             operator may prune anytime. Formal relays unchanged (revisions
             correctly supersede in place per FR-18). Also: gh release create
             codified as a mandatory step in PUBLISHING.md (9 releases had
             shipped tags-only). Change-note:
             docs/changes/2026-06-11-handoff-paper-trail.md. Shipped in
             framework v3.18.2.

2026-06-11 — v0.26. app-quality-patterns added (no rule changed). v3.19.0,
             operator-driven: recurring behavioral defects across consumer
             projects (view state not in URL — refresh loses filters/reports;
             deletes leaving orphaned records; chevron misalignment) with no
             Flow carrier. New 29th canonical skill = thin router +
             references/{state-and-navigation,data-integrity,ui-polish}.md —
             14 ID'd patterns (QP-01..04, 10..14, 20..24), each Trigger ·
             Requirement · Verify (copy-ready smoke recipe) · Anti-pattern.
             Enforcement = AC-injection: requirements-specification scans the
             index and matching patterns become spec ACs by ID, riding the
             existing tasks->gate->smoke->review machinery (no new gates —
             behavioral requirements aren't regex-able, FR-25 lesson inverse).
             Reinforced: implementation-planning design brief cites QP IDs;
             code-review QP-AC dimension; smoke-testing copies Verify lines as
             S<n>. Growth: one table row per new cross-project lesson;
             project-specific patterns stay in project docs/skills/.
             Independent pre-ship review: 12/12 seeds sound, 1 count blocker
             fixed, 2 reviewer-suggested patterns added (QP-14 destructive
             confirm/undo, QP-24 unsaved-changes guard). Spec:
             docs/specs/app-quality-patterns/spec.md. Shipped in framework
             v3.19.0.

2026-06-11 — v0.27. Delegation turn-completion + verification cost discipline
             (no rule changed). v3.19.1, downstream proposal (paperclip+
             hermes-v1 autonomous run, operator-relayed): (1) three delegated
             sessions ended their turn "watching in background — I'll resume
             when it completes" — a delegated session cannot self-resume;
             task-delegation now carries a binding turn-completion rule
             (deliverable complete in-turn; bounded in-turn polling or
             record-then-read; one-sentence push into delegating prompts;
             also in greenlight-deploy + handoff-implement push line).
             (2) Verification skills defined WHAT counts as evidence but not
             HOW to obtain it economically — agent-side watching measured at
             ~10x the cost of reading durable records after the run.
             smoke-testing gains § Verification cost discipline
             (record-then-read default; missing evidence surface = an
             observability-gap finding; sole exception = first live drive of
             fresh code hunting unknown failure modes, bounded);
             validation-and-qa cross-references it. Change-note:
             docs/changes/2026-06-11-delegation-verification-discipline.md.
             Shipped in framework v3.19.1.

2026-06-11 — v0.28. FR-26 added (token-efficient execution). Driver: after
             FR-21/22/23/25 + v3.19.1 the execution axis still leaked —
             read-side waste (re-reading unchanged files, whole-file reads for
             one fact, reading generated/vendored files, re-deriving known
             IDs), retry storms (same failing approach re-attempted instead of
             diagnosed), whole-file regeneration for small edits — and, root
             cause, no measurement: nobody could see where a session's tokens
             went. Operator constraint is the rule's FIRST clause: quality
             outranks tokens — rules cut REDUNDANT consumption only; never
             skip a needed first-read, thin verification, or truncate
             reasoning. Deliberately no gate/hook (FR-22 semantic class; a
             budget gate trains truncation = intelligence damage). Delivery:
             one FR-24 digest line (all tool-using execution, every role) +
             30th carrier skill flow-skills/token-economy (guardrail-first
             rules table with per-row quality guards; pointers to canonical
             homes, no restatement) + deterministic stdlib parser
             hooks/local/token-waste-audit.py behind the /token-waste-audit
             slash command (Claude Code; requestId-deduped usage totals, leak
             signatures reported as candidates-not-verdicts, privacy-
             preserving report to state/audit/); non-Claude surfaces degrade
             to the repo-side fallback summary. Spec:
             docs/specs/token-economy/spec.md. Shipped in framework v3.20.0.

2026-06-17 — v0.29. FR-27 added (liveness — never launch bare). Driver:
             operator report — a project's AI developer launched a background
             re-verify probe that HUNG (no internal timeout; a fetch/cleanup
             stalled against a cold-start proxy). A hung process emits no
             completion event, so the agent was never re-invoked and idled
             until the operator nudged it ("is it all done?"). The framework
             already named this failure but only for delegated sub-agents
             (task-delegation turn-completion / BLOCKED-AT, scope-gated to
             sub-agents) — the agent's OWN probe/script/deploy/fetch-loop/
             browser-automation was uncovered, and the protocol had been
             hand-retyped into 3 deploy handoffs + the subagent-deploy memory
             with no canonical home. Honest enforcement model (load-bearing):
             NO hook can reliably verify this hang class — there is no
             elapsed-time/idle event in the hook schema, post_tool_use cannot
             fire for a call that never returns, and a Stop-time
             "watchdog: applied" signal would be attestation theatre (the
             inert-lever anti-pattern). Therefore NO blocking gate and NO
             verification hook (FR-26 precedent: the failure is semantic — a
             real hang vs a legitimate long-but-live run; a gate would train
             premature kills). Enforcement = (1) structural safe-by-default
             tooling (new hooks/local/lib/bounded-run.sh REUSES
             run-with-timeout's core without breaking the ffhc_* API the
             health-check sources; adds a wall-clock deadline emitting a
             terminal timeout line + incremental progress logging so a
             monitored background launch reaches completion-or-death instead
             of a silent idle) + (2) present-by-construction delivery (FR-27
             digest row in role-discipline + session_start reminder + the
             liveness/BLOCKED-AT clause promoted into the handoff Role-bootstrap
             Hard-invariants so the MAIN session carries it). Qualified tooling
             claim (D7 — do not overstate): the wrapper bounds the MONITORED
             process; it does NOT kill an `&`-detached grandchild or an
             uninterruptible OS wait, and does NOT prove the host re-invokes —
             the skill teaches "don't `&`-detach under the wrapper; put a
             deadline INSIDE long scripts too; always flush partial results."
             New 32nd canonical skill flow-skills/liveness-discipline
             (cross-links task-delegation BLOCKED-AT + smoke-testing
             record-then-read). DEFERRED (follow-up tickets): D3 warn-only
             pre_tool_use nudge (host maps a non-allow/non-deny decision to
             an interactive `ask`/block — needs an allow-with-warning path +
             tests), D4 Python watchdog helper (shell first), D5
             templates/bounded-script.sh skeleton (compact example lives in
             the skill). Spec: docs/specs/liveness-discipline/spec.md. Shipped
             in framework v3.28.0.
```
