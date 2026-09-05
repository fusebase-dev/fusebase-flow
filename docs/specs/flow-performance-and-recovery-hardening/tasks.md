# Tasks — flow-performance-and-recovery-hardening

**T-counter going in:** T0
**Task range:** T1..T11
**Gate task:** T10
**Closeout task:** T11
**Linked spec:** `docs/specs/flow-performance-and-recovery-hardening/spec.md`
**Linked decisions:** `docs/specs/flow-performance-and-recovery-hardening/decisions.md`

## Task chain

| T# | Slice | Scope | Decision | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | S1 | exact Flow overlay replacement | A1, A2 | — | — | pending |
| T2 | S2 | settings ownership, trusted config, hook uniqueness | A1, A3 | T1 | — | pending |
| T3 | S3 | prior-intent restoration and recovery verdict | A2, A3 | T2 | — | pending |
| T4 | S4 | no-op mirrors and canonical recovery source | A1, A6 | T3 | — | pending |
| T5 | S5 | one-read Stop transcript processing | A6 | T2 | — | pending |
| T6 | S6 | lightweight diagnosis-first consumer flow | A4 | T3 | — | pending |
| T7 | S7 | compact startup carriers and role deltas | A5 | T6 | — | pending |
| T8 | S8 | validation responsibility and focused recovery checks | A6 | T4, T7 | — | pending |
| T9 | S9 | window-honest measurement and benchmark record | A7 | T8 | — | pending |
| T10 | S10 | integrated verification gate; no commit | A1..A7 | T1..T9 | — | pending |
| T11 | S10 | post-review closeout docs commit; no production deploy | A1..A7 | T10 + adversarial review | — | pending |

## T1 — Replace only the owned Flow overlay block

**Files:** `hooks/local/post-fusebase-update.sh`, `hooks/tests/cli-flow-recovery-direct.sh`, recovery fixture helpers only if required.
**Work:** validate exactly one non-nested BEGIN/END pair associated with the Flow heading; preserve prefix/suffix and FLOW:PRESERVE bytes; reject ambiguity before writes; atomic per-file replacement under A2, retaining original recovery material.
**Acceptance:** AC1.
**Tests:** suffix/custom-block/CRLF/Unicode/preserve/duplicate/nested/unbalanced/second-no-op; failed atomic replacement preserves destination and recovery material.
**Module-size:** all targets are under the 800-line ceiling at plan time; keep span parsing in a named helper if growth would cross it.
**Worker-undisturbed:** CLI-owned provider assets and `.claude/hooks/**` unchanged.
**Commit:** one T1 commit.

## T2 — Make settings recovery ownership-safe and unique

**Files:** `hooks/local/fusebase-flow-overlays/settings-json-merge.py`, `hooks/tests/test-wire-hooks-add-beside.sh`, `hooks/tests/cli-flow-recovery-direct.sh`, focused settings-merge fixture/test owner.
**Work:** remove MCP mutation; use installed complete Flow hook configuration; ignore incidental staging; verify exact recognized commands; search every Stop block before adding.
**Acceptance:** AC2, AC4.
**Tests:** empty/missing/custom MCP lists; permissions/custom settings; Stop positions/order/timeouts; stale/partial/malicious staging; complete handler/matcher set; idempotence.
**Module-size:** merger is 468 lines; extract trusted configuration validation to `hooks/local/fusebase-flow-overlays/flow-hook-config.py` if needed rather than growing toward the ceiling.
**Worker-undisturbed:** `.claude/hooks/**`, `.mcp.json`, `fusebase.json`, CLI skills/agents unchanged.
**Commit:** one T2 commit.

## T3 — Restore valid prior hook intent

**Files:** `hooks/local/post-fusebase-update.sh`, `hooks/local/lib/hook-wiring-intent.sh`, `hooks/tests/test-hook-wiring-intent.sh`, recovery E2E/classification fixtures.
**Work:** implement A2 surface matrix, schema-1 compatibility, whole-plan prevalidation, atomic per-file apply, durable interrupted/partial inventory and verified status/exit contract; parse settings event/command/matcher structure. Do not infer Git-hook authorization from settings intent.
**Acceptance:** AC3, AC11.
**Tests:** enabled/absent/revoked/malformed/foreign/empty-root intent; missing/partial settings; missing AGENTS/CLAUDE with/without recoverable originals; settings-only legacy intent and absent/custom Git hooks; unowned collisions; unavailable source/malformed later target produces zero writes; mid-apply failure/interruption persists partial inventory and backups; safe retry and exact CLI/user preservation; structured exit/status.
**Module-size:** post-update script is 545 lines; extract recovery-plan/verification responsibility into `hooks/local/lib/flow-recovery-plan.sh`; caller and helper each remain below 800.
**Worker-undisturbed:** CLI-owned bytes are named fixture sentinels and must remain identical.
**Commit:** one T3 commit.

## T4 — Eliminate unchanged mirror writes and duplicate health-skill source

**Files:** `hooks/local/mirror-skills.sh`, `hooks/local/mirror-agents.sh`, `hooks/local/post-fusebase-update.sh`, `hooks/tests/cli-flow-recovery-direct.sh`, mirror tests/manifest fixtures.
**Work:** use populated hash cache without per-file command substitution; skip identical skill/agent copies and manifests; make canonical health skill normal source and ownership-verified snapshot fallback-only. Apply A6 no-op scope to every recovery target, including settings backups/receipts/intent and Git hooks.
**Acceptance:** AC5, AC12.
**Tests:** full-corpus skill/agent zero-copy/mtime no-op; one-file repair; whole recovery target inventory unchanged on second run; missing canonical fallback; divergent snapshot cannot supersede canonical; manifest/mirror drift zero. Count diagnostics separately.
**Module-size:** targets under ceiling; keep fallback policy in the recovery-plan helper from T3.
**Worker-undisturbed:** CLI provider skills with colliding/similar names unchanged.
**Commit:** one T4 commit.

## T5 — Reuse one Stop transcript read

**Files:** `hooks/handlers/stop.py`, focused Stop test owner, `hooks/tests/fixtures/18_*.jsonl` through `21_*.jsonl` only if fixture changes are necessary.
**Work:** read raw transcript once; pass it into final-assistant extraction and signal scanning; keep agent_message handling separate.
**Acceptance:** AC6.
**Tests:** existing Stop fixtures plus read-count assertion and 1/10/30 MiB benchmark record.
**Module-size:** handler is 339 lines; no extraction required unless responsibility clarity improves.
**Worker-undisturbed:** `hooks/handlers/**` is protected; use the operator-authorized, digest-bound bootstrap approval at commit.
**Commit:** one T5 commit.

## T6 — Make ordinary work diagnosis-first and lightweight by default

**Files:** `FLOW_RULES.md`, `flow-skills/lightweight-lane/SKILL.md`, `flow-skills/documentation-budget/SKILL.md`, `flow-skills/requirements-specification/SKILL.md`, `workflows/eight-phase-flow.md`, `workflows/lightweight-lane.md`, `agents/ai-developer/AGENT.md`, `flow-skills/role-discipline/references/ai-developer.md`, affected shared/PO role protocols, `hooks/local/lane-router.sh`, `hooks/tests/test-lane-router.sh`, affected mirrors.
**Work:** replace doubt/unknown-cause escalation with bounded read-only diagnosis before classification; define objective Full triggers; ordinary low-risk tasks use one product decision and one-pass implementation; retain release authorization and safety floor.
**Acceptance:** AC8.
**Tests:** router path/input-error/structured-output unit cases plus distinct workflow fixture runner per A4; ordinary diagnosis→lightweight fix; each sensitive trigger→Full including auth/public-contract logic in ordinary source filenames; unresolved assessment never safe; artifact/decision/relay inventory; carrier consistency search. Name and register the focused workflow test in the existing test registry.
**Module-size:** shell/Python sources remain under ceiling; markdown carriers are documentation, not gated source.
**Worker-undisturbed:** only Flow canonical/mirrors change; CLI provider assets unchanged.
**Commit:** one T6 commit.

## T7 — Compact mandatory startup context

**Files:** `AGENTS.md`, `hooks/local/fusebase-flow-overlays/agents-md-overlay.md`, `CLAUDE.md`/overlay source if it duplicates protocol bodies, `FLOW_RULES.md`, `flow-skills/communication/SKILL.md`, `flow-skills/role-discipline/SKILL.md`, role reference deltas, `agents/ai-developer/AGENT.md`, `agents/product-owner/AGENT.md`, provider mirrors, instruction/overlay tests.
**Work:** establish one authoritative core, retain all prohibitions and mixed-fleet bootstrap behavior, move procedure detail to on-demand references, generate/pointer provider adapters, preserve FLOW:PRESERVE values.
**Acceptance:** AC7, AC12.
**Tests:** semantic invariant inventory across old/new carriers; required-path bootstrap on supported providers; overlay recovery; paired host-delivered-context measurements with identical scenario/model/settings. Per-host character estimates remain UNVERIFIED, with missing telemetry reason; report verified and unverified coverage separately.
**Module-size:** documentation/provider files are exempt; scripts touched for generation remain below ceiling.
**Worker-undisturbed:** CLI base instructions outside the exact Flow overlay and CLI provider assets unchanged.
**Commit:** one T7 commit.

## T8 — Assign validation once per exact state

**Files:** `hooks/git/pre-commit`, new `hooks/local/lib/validator-evidence.py`, trusted validator-runner entry point, focused validator-evidence tests, `hooks/local/post-fusebase-update.sh`, `templates/handoff-implement.md`, `workflows/greenlight-implement.md`, `flow-skills/validation-and-qa/SKILL.md`, focused recovery-hint/instruction tests; do not edit CLI Stop validators.
**Work:** implement A6 authenticated exact-state reuse at actual pre-commit lint/typecheck invocation; extract identity/receipt validation from the 799-line hook. Keep fail-closed rerun when host authenticity is unavailable. Replace consumer recovery full-suite advice with focused checks and align instructions with runtime behavior.
**Acceptance:** AC9.
**Tests:** invoke actual pre-commit boundary with counted validators: authentic matching success skips once permitted; missing/failed/forged/edited/replayed receipt reruns; source/staged/unstaged/untracked/config/dependency/environment/command/toolchain mismatch and concurrent mutation rerun. Assert secret/protected/release checks still execute on reuse; CLI validators unchanged; recovery advice excludes full maintainer suite.
**Module-size:** pre-commit is 799 lines: extract validator invocation/evidence responsibility before adding behavior; pre-commit and named helpers stay ≤800. No exemption/baseline increase.
**Worker-undisturbed:** `hooks/git/**` requires exact staged digest-bound approval; `.claude/hooks/run-lint-on-stop.sh`, `.claude/hooks/run-typecheck-on-stop.sh`, `.claude/hooks/quality-check-apps.js` byte-identical.
**Commit:** one T8 commit.

## T9 — Make ceremony evidence window-honest and benchmark consumers

**Files:** `hooks/local/find-wasted-effort.py`, `hooks/local/find_wasted_effort/evidence.py`, rule/report/fixture modules, `state/audit/` benchmark outputs (gitignored; evidence only).
**Work:** separate historical artifact evidence from commit-window-linked evidence; require linkage for window-specific conclusions; record representative ordinary change/recovery measurements with missing-metric labels.
**Acceptance:** AC10, AC11.
**Tests:** old artifact outside window; linked/unlinked artifacts; approval history; false-positive preservation; isolated current CLI refresh attempt bounded and recorded.
**Module-size:** `evidence.py` must stay under ceiling or extract temporal correlation into `hooks/local/find_wasted_effort/windowing.py`.
**Worker-undisturbed:** CLI/current workspace remains unchanged; actual CLI refresh runs only in a disposable validated directory.
**Commit:** one T9 commit; do not commit gitignored benchmark output.

## T10 — Integrated verification gate

No code change or commit. Fill `templates/gate-report.md` into `docs/specs/flow-performance-and-recovery-hardening/gate-report.md`. Run targeted tests per T1–T9, full registered hook suite once on final state, preflight, mirror checks, module-size gate, secret scan, protected-path verification, CLI-owned byte comparison, no-op recovery, and bounded disposable current-CLI refresh test when supported.

## T11 — Post-review closeout

After GPT-6 Astra Medium adversarial review reports zero blockers, update this spec from DRAFT to DONE with final implementation SHA, fill task SHAs/statuses, and make one docs-only closeout commit. No production deploy command exists for this repository; record deploy as N/A and rollback as per-commit `git revert`.

## Task chain audit

| Invariant | Coverage |
|---|---|
| Every AC mapped | T1–T9; integrated at T10 |
| Every decision cited | T1–T9 |
| Worker-undisturbed | every task names CLI/Flow boundaries |
| Mixed fleet | T6–T8 |
| Migration | none |
| UI/client functionality | N/A |
| Deploy | no target; T11 docs closeout only |
