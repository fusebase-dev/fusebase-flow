# eight-rule-kernel-and-cards

**Status:** open — 6.0.0 rebuild, **wave 3**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 5 (R §2). **Surface:** `FLOW_RULES.md` (27 rule rows today, `:8-34`; role table and attestation `:36-58`), `FLOW_RULES_HISTORY.md`, the `AGENTS.md` and `CLAUDE.md` Flow overlay blocks, the two role cards, the writing card text, the bootstrap read list, and the tripwires that count rules and boot bytes (`hooks/local/rule-inventory.sh`, `hooks/local/sync-version-strings.sh`, `hooks/tests/test-boot-size.sh:33-37`, `test-rule-inventory.sh`, `test-startup-context.sh`). **FR-07:** yes (`FLOW_RULES.md`, `FLOW_RULES_HISTORY.md`, `policies/protected-paths.yml:87-88`).

## Delivers

- **`FLOW_RULES.md` with 8 rules** (H WP 5): backlog item before code (with the trivial tier); one task one commit; reversible by default; protected paths; approval-gated side effects (dev deploy approval pre-minted before an unattended run); lint and typecheck per code commit; file-size ratchet; liveness (never launch bare; the heartbeat has a reader).
- **Rule 6 takes the full FR-13 text**, the owner's decision 2 text as first given, from `workflows/git-discipline.md:91`. `FLOW_RULES.md:20` carries only the short row, and the workflow file is deleted by `one-lifecycle-page` (R §5b row 12).
- **Two role cards** (planner, builder), each with "Stop and ask when a locked decision, a named input or the task's scope is unclear; never guess." (decision 10b) and the "ceremony proportional to risk" line. The 53-file count has no separate card file, so the cards live in the canonical agent files (reading of R §5b row 3; this WP's plan confirms).
- **The writing card**, under eight lines (H WP 5): short chat answers; replace, do not append; comments only for non-obvious constraints; read your slice (keep the guard "read the whole artifact before you edit against its invariants", R §6 T158); plus three token-economy lines. It ships as one of the six skills (`six-skills-and-optional-pack`).
- **Removed always-on text:** self-attestation and the state footer (decision 10a, `FLOW_RULES.md:47`), the role table, FR-11 as a rule (`:18`, now a card line), the FR-24 digest.
- **The overlay blocks** for `AGENTS.md` and `CLAUDE.md` (decision 7 assigns their authoring here); `flow-migrate` installs them inside the CLI's `CUSTOM:SKILL` wrapper.
- **Boot measured, not estimated:** the bootstrap read list Flow publishes, under 6 KB for the builder (D) and under 8 KB for the planner (owner accepted). Today `test-boot-size.sh` caps the four mandatory files at 42,200 bytes (`:37`), with `FLOW_RULES.md` alone at 11,500 (`:35`).
- **Tripwires re-based to the new counts, never bypassed.** This pays backlog `startup-context-baseline-stale` and `rule-inventory-two-part-version`.

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 10a (no attestation, no footer) | Removed; carriers re-keyed (`rule-inventory.sh`, `sync-version-strings.sh` version anchor) |
| Decision 10b (stop and ask as a card line) | Both cards |
| 5.11 decision 2 / R §5b row 12 (full FR-13 text) | Rule 6 |
| 5.11 decisions 1 and I (pre-minted dev deploy) | Rule 5 wording |
| Decision 7 (overlay blocks kept; authoring here) | The two overlay texts |
| H §7 (`FLOW_RULES.md` diff) | Acceptance 3 |

## Estimate

R §2: 9 to 12 agent-h (mid 10.5), including about 2.5 for decision 10a's carriers and 0.5 for 10b. Review: 2 rounds (public rule text, consumer behaviour).

## Depends

`trivial-tier-and-task-ids` (rule 1 wording), `heartbeat-reader` (rule 8), `one-lifecycle-page` (rule 5 and the page in the boot list), `reader-agent-and-dispatch-check` (the cards live in the renamed agents); decision 10. Blocks: `six-skills-and-optional-pack` final (writing card), `flow-install-declared-providers` (inventory).

## Acceptance

1. 8 rules; no always-on text beyond the 8 rules and the two card lines (H non-negotiable 1).
2. The builder's bootstrap read list totals under 6 KB and the planner's under 8 KB, measured by the published list (fixture replaces today's ceilings).
3. A diff of `FLOW_RULES.md` against 5.11 shows only removals, the wording changes of rules 1, 5, 6 and 8, and the reader profile (H §7).
4. `rule-inventory.sh` and the heading-count tripwires are updated to the new counts, not bypassed (H WP 5); `startup-context-baseline-stale` and `rule-inventory-two-part-version` close.
5. No stale version or count strings: they are generated (H §7).

## Wave split

Wave 3. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
