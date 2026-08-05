# Implement handoff — Phase C Slice 6 (+ S3): doc / rule-text / path consistency sweep

## Role bootstrap
AI Developer (Opus 4.8) under FuseBase Flow v3.30.6. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-07 (may edit protected FLOW_RULES.md — note), FR-22. **Synchronous; bound long runs; no runaways; STOP at gate; do NOT bump VERSION/push/tag/deploy.** ONE coherent commit stacked on the current HEAD (Phase C S5). Mechanical/doc-consistency corrections from the Phase C audit — NO code-logic changes, NO enforcement weakened; text/docs only (+ a re-mirror). NEVER `--no-verify`.

## PROTECTED-PATH NOTE (FR-07)
Several fixes edit `FLOW_RULES.md` (protected `fusebase_flow_internals`). If you touch it: REFRESH the wired hook (`install-git-hooks.sh`), mint ONE sanctioned single-use bootstrap approval binding the whole staged changeset, commit, `--consume`, confirm `.git/hooks/pre-commit` == source. `flow-skills/**`, `docs/**`, `templates/**`, `agents/**`, `.claude/`/`.agents/` mirrors are NOT protected. NEVER `--no-verify`.

## This slice folds S3 (skills/→flow-skills/ path sweep) + S6 (doc/rule-text consistency). Full per-finding detail in tasks/wecmxwyrx.output + the slice-plan doc. Work the checklist below systematically; a few S1/S2 may have partially covered some — VERIFY + complete, don't duplicate.

## A. skills/ → flow-skills/ path sweep (S3: L1, L5, L16, M13) — mechanical
The v3.9.0 skills/→flow-skills/ rename (commit e4d1baf) left dead `skills/<slug>/SKILL.md` refs. Root `skills/` does NOT exist. One-pass replace `skills/` → `flow-skills/` in the stale carriers (grep to find ALL): `flow-skills/role-discipline/references/{product-owner,ai-developer,deploy}.md` (don't-list "Maps to" pointers + DP.10 mandatory-read), `flow-skills/skill-authoring/SKILL.md` (canonical home line ~43, destination table ~64, catalog ~51, mirror-consistency — M13: a skill authored per its current instructions would be orphaned from the mirror pipeline), + any other `skills/<slug>` carriers (design-discovery etc.). Then re-mirror (mirror-skills.sh) so the `.claude/`/`.agents/` copies + manifest match. Do NOT change flow-skills/ content otherwise.

## B. FLOW_RULES.md corrections (L8, L9, L22, M3) — PROTECTED (one approval)
- L8/L22: Status line says `v0.28 (FR-26 added…)` but the file defines FR-01..FR-27. Bump to v0.29 noting FR-27 (or replace the parenthetical with a pointer to the amendment log so it can't re-stale).
- L9: FR-02 and FR-10 cite non-existent "workflow implementation-planning" / "workflow validation-and-qa" — both are SKILLS. Relabel to `skill implementation-planning` / `skill validation-and-qa` (or point FR-02 at the real workflow file if one exists).
- M3: FR-01 claims `pre_tool_use` hook enforcement of spec-before-code, but NO hook checks spec-before-code at tool time. REWORD FLOW_RULES.md:10 (+ rail-mapping.md:7) to the TRUE enforcement surface (spec-review / gate / role-discipline — NOT a pre_tool_use hook). Do NOT add a new code check in this doc slice; just stop over-claiming a hook that doesn't exist.
- L22: replace dangling `FR-DP-4` (nonexistent; content matches DP.5) with `DP.5` in eight-phase-flow.md + agents/product-owner/AGENT.md (canonical) then re-mirror; replace `HR-PO-15` in templates/problem-catalog-entry.md with `PO per FR-15`.

## C. rail-mapping.md + role/hook doc corrections (M5, L6) — (rail-mapping is NOT protected)
- M5: rail-mapping credits the stop hook with gates stop.py does not implement; before_deploy_command's `worker_undisturbed_recheck` signal has no hook consumer. Correct the FR-04/FR-05 hook columns to what stop.py ACTUALLY gates (before_done_claim, before_deploy_complete_claim; FR-04 hook = n/a or the true surface). (S1 already added FR-12→user_prompt_submit; verify consistency.)
- L6: FR-04 claims stop-hook enforcement of handoff persistence; stop.py has no handoff check. Reword FLOW_RULES.md:13 + rail-mapping.md:10 to "rule + workflow discipline" (not a stop-hook check), OR note the gap — do NOT claim an unimplemented check.

## D. Lifecycle-skill / role doc corrections (M1, M14, L2, L3, L4, L10, L11) — (mostly flow-skills/, non-protected)
- M1: spec Status "LOCKED" contradicts the DRAFT-until-DONE convention every downstream skill checks (a skip-clarify ticket dead-ends). RESOLUTION: align to DRAFT — drop LOCKED from templates/spec.md:3; reword requirements-specification:33/:57 so a skip-clarify ticket keeps `Status: DRAFT` (lock = scope frozen, recorded in decisions, NOT a status value).
- M14: Architect-deliverables contradiction — workflow + AR.2 + FLOW_RULES say the Architect produces decisions.md/tasks.md/verification-gate.md; the mandated response template says the PO drafts them. RESOLUTION: align to the FLOW_RULES/AR.2/workflow model (Architect produces the 4 artifacts) — rewrite templates/architect-response.md sections 7/8 to match (do NOT change FLOW_RULES/AR.2).
- L2: CLAUDE.md claims "parts of validation-and-qa carry invocation: manual-for-side-effects" but the skill is invocation: automatic with no such marker. RESOLUTION: correct CLAUDE.md:20 to name only release-deploy-reporting (the actually-manual one).
- L3: release-deploy-reporting:32 mandates an unconditional docs/changes/index.md ledger line that lightweight-lane/change-note forbid assuming. Make it conditional ("if the project keeps a consolidated ledger (opt-in)…").
- L4: communication SKILL.md:97 says docs/tmp/handoff/* is "reserved for formal implement/deploy relays" — contradicted by the sanctioned smoke-evidence dirs + handoff archive routed there. Amend :97 (+ the :49-65 classification) to name all sanctioned residents.
- L10: secret-patterns.yml:133 precedence comment wrong vs secret_scanner.py. Fix comment to `pattern_overrides[<id>] > pattern-level action > per_tool action > default_action` (matching code). (secret-patterns.yml is a policy file — check if protected; policies/*.yml IS protected `fusebase_flow_internals` — if so, cover under the bootstrap approval.)
- L11: CLAUDE.md:82 claims PO Bash is "gated by" po-investigate.sh, but nothing gates it (opt-in by instruction). Reword to "PO Bash is instructed to route through the po-investigate.sh read-only wrapper (structural allowlist inside the wrapper; direct Bash is a discipline breach)".

## E. Doc catalog / count / version-string corrections (M10, L14, L19, L21) — (docs + templates, non-protected)
- M10: AGENTS.md:151 canonical skill catalog claims "(32 canonical skills total)" but enumerates 31 — omits `liveness-discipline`. Add it to AGENTS.md:151 AND hooks/local/fusebase-flow-overlays/agents-md-overlay.md:14 (mirror-consistency), then re-run sync/mirror.
- L14/L19: docs/hook-coverage.md fixture-count / "<5 seconds total" stale — 16 fixtures + a multi-minute 21-phase harness. (S1 already bumped the fixture matrix 11→19 — VERIFY it's complete + consistent; complete rows 12-16 + runtime/workflow-name if S1 didn't.)
- L21: two report templates carry stale "Fusebase Flow v3.1" self-attestation strings that sync-version-strings.sh anchors miss. Reword to the synced anchor form ("under FuseBase Flow vX.Y.Z") so future syncs catch them — OR add the phrasing as a sync anchor. (Note operator rule: spell "FuseBase", two capitals.)

## M11 — clean-room codename (HANDLE WITH CARE — verify, do NOT blindly scrub)
The audit flags 'headroom' in 13 tracked files vs a release-notes "codename grep = 0" claim. FIRST determine whether 'headroom' is (a) the actual third-party codename, or (b) a common English word used legitimately ("timeout headroom", "budget headroom"). If (b), the finding is a FALSE POSITIVE — do NOT scrub legitimate usage; instead, if any shipped release-note literally asserts "grep headroom = 0" and that's false, reword that CLAIM to reference the ACTUAL codename verification (not the word 'headroom'). If (a) — 'headroom' genuinely IS the codename being referenced — flag it in your report and reword the shipped artifacts to stop spelling it, but DO NOT invent scrubbing that breaks legitimate text. When unsure, leave the text and REPORT for operator adjudication rather than guess.

## Do NOT
NO code-logic changes, NO enforcement/gate weakened (text/docs only). Do NOT touch the pre-commit chain / hooks/handlers / hooks/shared / hooks/git (S1 + prior slices own the code). Do NOT bump VERSION/push/tag. Do NOT `--no-verify`.

## Gate (scoped) — stop, report, HALT
`git grep -n "skills/" flow-skills/ agents/` shows no stale `skills/<slug>` refs remain (only `flow-skills/`); FLOW_RULES.md defines FR-01..FR-27 with a current Status line; SINGLE mirror-skills.sh --check 0-drift + mirror-agents.sh --check 0-drift (after re-mirror); manifest 86/86/0-dups; preflight green; markdown refs resolve; check-module-size --all exit 0; FR-07 clean (approval consumed if FLOW_RULES/policies touched); `.git/hooks/pre-commit` == source. Emit FR-22 marker; gate report; HALT.

## Return
Gate report: commit SHA; a per-group checklist of what was fixed (A path-sweep, B FLOW_RULES, C rail-mapping, D lifecycle/role docs, E catalogs/counts/version-strings) with file:line; M11 disposition (fixed / false-positive / deferred-for-operator with reasoning); confirmation NO code/enforcement changed; mirror/manifest/preflight clean; FR-07 approval used (if any) + .git/hooks==source; VERSION unchanged. Do NOT push/tag/deploy.
