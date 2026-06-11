# Spec — integration-debloat (v3.18.0)

**Status:** DONE (shipped 2026-06-10, framework v3.18.0, tag `v3.18.0`)
**Tier:** 3 · **Lane:** Full (action 3 touches deploy-approval procedure → focused security pass required)
**Deploy hash:** `1a9ff6f`. Independent implementer (gate clean, −9.3KB/−20% per-ticket reads, net −609 lines); PO spot-verified G2/G8 safety edits + all gates (preflight 0/0, 24/24, --all green); security note § below applied. Deviations accepted: gate-report-checklist kept (referenced by producer), 5 extra restating carriers pointer-ized, architect-escalation refs to deleted templates replaced.

## Problem

Capability-integration audit: procedure layer violates the framework's own pointer rules — gate contract in 7 carriers, smoke in 6, ~130 lines legacy snippets in always-read workflows, review double-work, 3 live cross-surface contradictions, dead machinery. Cost ~6–10k tokens + 2–4 operator touches per Full ticket; 3 wrong-behavior paths.

## Decisions (locked; deltas from audit marked Δ)

| ID | Decision |
|---|---|
| G1 | **FR-14 ownership = the enforced path**: Deploy session makes the single docs commit (per `greenlight-deploy.md` + `gate-contracts.yml: docs_commit_sha` + stop-hook signal). Fix both canonical agent files to match; re-mirror. |
| G2 | Tier-aware artifacts: `greenlight-implement.md` pre-handoff checklist + `policies/required-artifacts.yml` decisions requirement become "LOCKED **if present**; absence valid per FR-23 when no real decision exists (record 'no real decisions' in spec)". Hook/fixture behavior must stay green (24/24). |
| G3 | Security review conditional in 3 carriers (`greenlight-deploy.md:10`, `agents/product-owner/AGENT.md` ×2, `AGENTS.md` step 5): invoke when the diff matches the skill's trigger list, else record `security: N/A — no sensitive surface` in the review summary. |
| G4 | Review boundary: `code-review` trusts a recorded validation-and-qa gate verdict for deterministic/cross-artifact fields (AC↔task map, decisions-cited, lint/typecheck, TODO scan, protected paths); reviews only semantic dimensions. One pointer line in `workflows/verification-gate.md`. |
| G5 | Gate-contract canonical = `policies/gate-contracts.yml` (machine) + `templates/gate-report.md` (producer, stays self-contained). `workflows/verification-gate.md` field table, `greenlight-implement.md` step-6 bullets, `templates/verification-gate.md` §Required fields → pointers. |
| G6 | Smoke canonical = `flow-skills/smoke-testing/SKILL.md`. `workflows/smoke-verification.md` shrinks to evidence-dir/ratio/reporting mechanics + pointer; `validation-and-qa` sub-mode B → "invoke smoke-testing; verify ratio vs threshold". **Tripwire: `hooks/tests` fixtures 13/14 assert smoke-regex/handoff-path behavior — keep `docs/tmp/handoff` strings + stop.py semantics untouched.** |
| G7 | Delete legacy handoff snippet blocks in both greenlight workflows (~130 lines) → one pointer line each to the canonical templates. `workflows/lightweight-lane.md` thinned to session mechanics + pointer at the LL skill (skill stays single source of truth). |
| G8 | **Reversible-deploy waiver (Full lane)**: when the ticket is reversible AND touches no protected path / security surface / migration, the Deploy agent **auto-stamps the DP.1 artifact upon receiving the operator's DP.6 phrase** (runs `approve-local.sh production_deploy <slug> 'APPROVE-DEPLOY-NOW'` itself). Artifact still exists on disk (FR-12 + hook semantics unchanged); human-at-keyboard gate (DP.6) unchanged; operator touches drop 3→2. High-risk classes (migration/security/protected-path) keep operator-run DP.1 + DP.6. Carriers: `greenlight-deploy.md`, `templates/handoff-deploy.md` (waiver field), `flow-skills/release-deploy-reporting`, `agents/ai-developer/AGENT.md`, one note in `policies/approval-policy.yml`. NO FR text change (artifact still required + produced). |
| G9 | Machinery: retire `hooks/handlers/task_complete.py` (wired nowhere; remove any fixtures + update totals everywhere if counts change); **Δ `pre_compact.py` unchanged — instead `workflows/session-initiation.md` step 5 reads `state/context-summary.md` if present** (no handler rewrite, no clobber risk on `docs/tmp/handoff.md`); preflight gains overlay-copy drift check (overlays' health-check SKILL + command files vs canonical, warn-level); `upgrade-engine.sh` → 6-line deprecation shim calling `upgrade.sh` (README row updated). |
| G10 | Templates: delete `research.md` + `data-model.md` (zero refs); **Δ `audience.md` wired into `project-onboarding` skill** (it's the substrate for `docs/audience.md` that `client-vs-internal` guards on) instead of deleted. Update template counts (24→22) where stated. |
| G11 | Knowledge routing: `documentation-budget` tier table + row "lesson/incident → route via `workflows/knowledge-curation.md` (FR-15)"; `knowledge-curation.md` + line "creation cost gated by FR-23". `git-workflow` name collision: Flow workflow renamed `workflows/git-discipline.md` + refs updated + disambiguation line in the CLI skill's... **Δ no edit to CLI-owned skill** — disambiguation note goes in the renamed workflow header only. `docs/fusebase-cli-edition.md:11` skills/→flow-skills/. |

## ACs

1. AC1 — 3 contradictions gone: agents match workflow on FR-14; checklist+policy tier-aware; security review conditional in all 3 carriers. Grep-verifiable.
2. AC2 — gate contract: field list present in exactly 2 carriers (yml + gate-report template); others pointer-only. Smoke: full S<n> contract only in smoke-testing skill; workflow ≤ ~60 lines.
3. AC3 — legacy snippets deleted; both greenlight workflows reference templates only.
4. AC4 — code-review carries the trust-the-gate clause; no deterministic-field re-verification instruction remains.
5. AC5 — waiver: handoff-deploy has the eligibility field; Deploy path documents auto-stamp; approval-policy notes the waiver; high-risk classes explicitly excluded.
6. AC6 — task_complete retired; tests remain green at the (possibly reduced) advertised total; preflight overlay drift check active; upgrade-engine shim; templates 22 + counts updated; git-discipline rename with all refs updated (grep 0 stale).
7. AC7 — preflight 0/0; run-tests all green; `--all` green; sweep clean; mirrors byte-identical; stop-hook fixtures (13/14/15/16) untouched semantics.

## Out of scope

Sub-agent don't-list dedup (F8 — deferred, medium risk); CLI bundle unbundle flag (F17 — roadmap); LL third lane (waiver suffices); FLOW_RULES text changes.

## Security note (G8)

Reviewed against `security-permissions-review` dimensions: the approval artifact remains mandatory and on-disk (hook contract unchanged); the human gate remains the literal DP.6 phrase typed by the operator; what changes is only which party runs the stamping command after the phrase. Excluded classes (migration/security/protected-path) retain the stricter flow. Worst case = agent stamps without phrase → identical to today's risk (agent could already run approve-local.sh; defense was and remains behavioral + audit trail).
