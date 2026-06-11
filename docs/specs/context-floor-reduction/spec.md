# Spec — context-floor-reduction (v3.17.0)

**Status:** DONE (shipped 2026-06-10, framework v3.17.0, tag `v3.17.0`)
**Lands in:** framework v3.17.0
**Tier:** 3 (spec + tasks; decisions inline) per FR-23
**Lane:** Full (contract files + recovery-machinery coordination)
**Deploy hash:** `0157f59`. Independent implementer (gate clean) + independent reviewer (FIX-FIRST → B1 11-pointer sweep + B2 install-doc docs copy fixed; AC2 per-rule semantic attestation PASSED FR-16..24). Measured: PO −8.0k / AI-Dev −7.9k / Deploy −8.5k tokens/session. AC1 soft-miss noted (SKILL.md 23.4KB vs ~20KB target — shared-protocol floor).

## Problem

Measured always-on session floor: ~34.5k tokens (Claude Code) / ~27.9k (Codex). Concentrations: `role-discipline` whole-file load 12.5k (36% of floor; a PO session carries ~4.6k of other roles' sections); FLOW_RULES FR-16..24 rows are essays + implications triple-carry content the mandatory skills already deliver (FR-18 alone paid 3× = 5.4KB/session); template adapters pay base + overlay duplicates (~1.5k/session Claude); CLAUDE overlay re-lists 28 skills the harness already injects (~775/session); consumers inherit ~7.4MB of upstream dev history via `cp -R $SRC/docs`.

## Decisions (locked)

| ID | Decision | Rejected |
|---|---|---|
| C1 | role-discipline: 4 role sections move to `flow-skills/role-discipline/references/{product-owner,ai-developer,architect,deploy}.md`; SKILL.md keeps purpose/procedure/load-model + role→file index + ALL shared protocols (Operator Relay, Chat-Text, Forward Momentum, Supersede, FR-24 digest). Same lazy-load pattern as `communication/references/patterns.md`. | Splitting shared protocols too (always apply — no win); separate skills per role (matcher confusion). |
| C2 | FLOW_RULES FR-16..24 rows compressed to house style (~≤350 chars body each; pattern = the shipped FR-25 trim) and implications for FR-16..24 collapsed to 1–3-line pointers at the owning protocol/skill. Semantics preserved; rationale lives in dated specs. FR-21 implication keeps its safety-floor list (load-bearing, no other always-on home). | Deleting implications outright (some carry role-split operational content with no other always-on home). |
| C3 | Adapter dedup happens on the BASE side only — inline overlay blocks must stay verbatim == canonical templates (F4 lesson). CLAUDE.md base: attestation §, operator-questions §, state-announcement § replaced by one pointer line to the overlay below. AGENTS.md base: "Project-specific values" fill-in table removed (overlay FLOW:PRESERVE owns it); base Active-project-context table → 2-line pointer to the overlay's. | Editing inline overlays independently (re-creates drift); removing overlay blocks from template (health-check greps their headings). |
| C4 | Canonical `claude-md-overlay.md`: 28-bullet skill catalog → 3-line pointer (Claude Code injects every skill description; the bullets are the 3rd copy). AGENTS overlay comma-list STAYS (load-bearing on Codex — no harness injection). Then re-splice inline CLAUDE block from canonical. | Dropping the AGENTS list (Codex would lose the catalog). |
| C5 | README copy block + install-existing-project.md: stop `cp -R $SRC/docs` wholesale; copy the ~15 live framework docs (`docs/*.md` top level + `docs/translations/` optional) and explicitly EXCLUDE `docs/{specs,changes,release-notes,backlog,handoff,problem-catalog,assets,fusebase-health,skills,decisions,verification,tmp}` (upstream dev history ≈ 7.4MB). README "What's in the box"/docs-layout wording aligned. | Untracking dev history from the template branch (separate decision, not this ticket). |

## Acceptance criteria

1. **AC1** — role-discipline SKILL.md ≤ ~20KB; 4 reference files exist; mirrors carry them; `session_start.py` REQUIRED_SKILL_FILES path unchanged and passing; no protocol content lost (diff-verifiable: every PO.x/IM.x/AR.x/DP.x rule line present in exactly one file).
2. **AC2** — FLOW_RULES.md (to amendment log) shrinks ≥ 8KB; every FR-16..24 row still states WHAT + WHY + enforcement pointers; no FR semantics changed (reviewer-attested); FR_MAX grep (sweep) still finds FR-25.
3. **AC3** — CLAUDE.md base contains no duplicate of attestation/footer/operator-questions (single pointer line); AGENTS.md base has no second project-values table; inline overlay blocks byte-match their canonical templates after the C4 edit.
4. **AC4** — `claude-md-overlay.md` catalog replaced by pointer; AGENTS overlay list intact; mirrors + manifests regenerated.
5. **AC5** — README copy block + install doc exclude dev-history paths; preflight §8 still passes (CLAUDE.md `/handoff` mention must survive — it lives in the overlay).
6. **AC6** — preflight 0/0; run-tests 24/24; `--all` green; sweep dry-run clean; health-check heading greps still match (`## Fusebase Flow — workflow lifecycle overlay` in AGENTS.md, `## Fusebase Flow — additional rules (overlay)` in CLAUDE.md).
7. **AC7** — measured: Claude session floor reduction ≥ 8k tokens vs v3.16.4 baseline (report before/after numbers).

## Out of scope

Untracking upstream dev history from the template branch; per-role split of `communication`; footer/attestation removal (drift detectors — keep); `.claude/commands` refresh path (separate radar item).

## Risks

Health-check / recovery grep anchors (mitigated: heading text untouched; AC6 verifies). Mirror manifest only tracks SKILL.md — references/ must still be mirrored byte-identical (verify mirror-skills.sh copies whole skill dirs; extend if not). Semantic loss in FR row compression (mitigated: independent reviewer attests AC2).

## Related

`docs/release-notes/v3.16.4.md` (audit context) · precedent: FR-25 row trim (v3.16.3) · `flow-skills/communication/references/` (lazy-load pattern)
