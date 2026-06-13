# Tasks — ceremony-efficiency-middle-lane

**T-counter going in:** T17 (next task is T18)
**Task range:** T18..T32 (across 3 phases; P3 is GATED — outline only)
**Phase gates:** P1 gate T22 / deploy T23 · P2 gate T25 / deploy T26 · P3 gate T31 / deploy T32
**Linked spec:** `docs/specs/ceremony-efficiency-middle-lane/spec.md` (decisions D1..D7 inline; ACs AC1..AC7; implementation order)
**Decisions:** in spec.md § Decisions (no separate decisions.md — FR-23, not duplicated)

> **Phasing is the spec's safe-sequencing (Implementation order): P1 governance + read-only audit → P2 audit writes → P3 Middle Lane.** Each phase ships independently (own gate + deploy). P3 does not start until its entry conditions hold (see T27 header).

## Task chain

| T# | Phase | Track | Scope | Cites | Depends on | SHA | Status |
|---|---|---|---|---|---|---|---|
| T18 | P1 | governance | A3: `prevents:` annotation scheme + annotate scoped ceremony elements | D5 | — | — | pending |
| T19 | P1 | skill | A2: author `flow-skills/find-wasted-effort/SKILL.md` (read-only, 6 rules) | D7 | — | — | pending |
| T20 | P1 | hook | A2: read-only analyzer `hooks/local/find-wasted-effort.py` | D7 | T19 | — | pending |
| T21 | P1 | wiring | A2: command + provider mirrors + skill-count + FR/version strings | D7 | T19,T20 | — | pending |
| T22 | P1 | — | verification gate (no commit; gate report only) | — | T18..T21 | — | pending |
| T23 | P1 | — | deploy P1 + probes + single docs commit | — | T22 | — | pending |
| T24 | P2 | skill+hook | A2 write phase: proposed-memory output + per-rule FP fixtures, gated flip read-only→write | D7 | T23 | — | pending |
| T25 | P2 | — | verification gate | — | T24 | — | pending |
| T26 | P2 | — | deploy P2 + probes + docs commit | — | T25 | — | pending |
| T27 | P3 🔒 | rules | A1: extend FR-21 two-tier → three-tier (lane-classification) | D1,D3 | (gated) | — | gated |
| T28 | P3 🔒 | policy+hook | A1: `middle_deploy` enforcement **code** (author/role check, DP.6 phrase, TTL, baseline-hash, hooks-off fallback) | D2 | T27 | — | gated |
| T29 | P3 🔒 | template+skill | A1: `templates/round-file.md` + Middle-lane skill/workflow wiring | D6,D3 | T27 | — | gated |
| T30 | P3 🔒 | tests | A1: hook tests + recovery-sim Middle-lane fixtures | D2 | T28,T29 | — | gated |
| T31 | P3 🔒 | — | verification gate + **security-permissions-review** | — | T27..T30 | — | gated |
| T32 | P3 🔒 | — | deploy P3 (Full lane, AC7) + probes + docs commit | — | T31 | — | gated |

## Per-task detail — Phase 1 (executable now)

### T18. A3 — `prevents:` ratchet-governance annotations
**Track:** governance · **Cites:** D5 · **Depends on:** — · **Acceptance:** AC3
**Scope:** Define the `prevents: <incident-class>` annotation convention + the `catastrophic-low-frequency` tag; annotate the **scoped set only** (D5): ceremony elements that `/find-wasted-effort` rule 6 reads + the deploy/gate controls. State coverage explicitly (silence ≠ safety).
**Files:** `policies/ratchet-governance.yml` (new — taxonomy + coverage map), annotations added in `templates/{handoff-implement,handoff-deploy,gate-report,verification-gate}.md`, `workflows/greenlight-deploy.md`, `workflows/eight-phase-flow.md` (scoped).
**Module-size (FR-25):** all targets doc/yaml, under ceiling.
**Tests:** preflight clean; a fixture asserting the annotation parser (T20) reads `prevents:` correctly.
**Worker-undisturbed:** FR-01..FR-26 rule rows in `FLOW_RULES.md` (no rule-row edits in this task).

### T19. A2 — `find-wasted-effort` skill (read-only)
**Track:** skill · **Cites:** D7 · **Depends on:** — · **Acceptance:** AC2
**Scope:** Author `flow-skills/find-wasted-effort/SKILL.md` — the process-per-outcome ceremony audit. 6 active rules (rule 4 CUT — already in `/token-waste-audit` cross-session aggregate; rule 7 scoped to cross-session ceremony layer). Each rule emits confirmed/dismissed/inconclusive with required contrary-evidence. **Reuse the shipped `token-economy` discipline** (candidate/FP header, read-only-first, `state/audit/<date>.md` gitignored output) — cite it, don't reinvent. Description carries technical aliases (process overhead / ceremony / token-waste-audit sibling) for matcher.
**Files:** `flow-skills/find-wasted-effort/SKILL.md`, `flow-skills/find-wasted-effort/references/` (rule signatures + FP examples).
**Module-size (FR-25):** markdown; under ceiling.
**Tests:** skill frontmatter valid; description-match smoke.

### T20. A2 — read-only analyzer
**Track:** hook · **Cites:** D7 · **Depends on:** T19 · **Acceptance:** AC2
**Scope:** `hooks/local/find-wasted-effort.py` — deterministic, stdlib-only, **read-only**. Inputs: gate reports, deploy reports, handoffs, approval artifacts (`state/`), git log, round structure, `prevents:` annotations (T18). Emits per-rule confirmed/dismissed/inconclusive findings + FP header to `state/audit/find-wasted-effort-<date>.md` (gitignored). NO writes to memory/overlays/specs; NO prune recommendations (P2 only). Mirror `token-waste-audit.py`'s structure where applicable.
**Files:** `hooks/local/find-wasted-effort.py`.
**Module-size (FR-25):** target < 800-line ceiling; if it approaches, extract rule-evaluators into `hooks/local/find_wasted_effort/` along the per-rule seam (not mechanical split). `token-waste-audit.py` (~270 lines) is the size precedent.
**Tests:** unit fixtures per rule (synthetic gate/deploy/handoff inputs → expected confirmed/dismissed/inconclusive); a clean-repo run produces a well-formed report.

### T21. A2 — command + mirrors + counts
**Track:** wiring · **Cites:** D7 · **Depends on:** T19,T20 · **Acceptance:** AC2, AC5
**Scope:** `.claude/commands/find-wasted-effort.md` + overlay command under `hooks/local/fusebase-flow-overlays/commands/`; mirror the skill to `.claude/skills/` + `.agents/skills/`; bump canonical skill count (31st skill) across CLAUDE.md/AGENTS.md/GEMINI.md/overlays/README; sweep FR-range (unchanged FR-01..FR-26) + version strings; CHANGELOG + `docs/release-notes/v<next>.md`; plugin manifest.
**Files:** command files, provider mirrors, adapter docs, CHANGELOG, release notes, `.claude-plugin/plugin.json`.
**Module-size (FR-25):** docs/json; under ceiling.
**Tests:** mirror drift 0; plugin validate clean; skill-count consistent across adapters.

### T22. Verification gate (P1)
No code change. AI Developer produces the gate report from `templates/gate-report.md`; fields per `policies/gate-contracts.yml: gate_report`. See `verification-gate.md`. **Stop at gate (FR-05); wait for deploy handoff.**

### T23. Deploy P1 + probes + docs commit
**Procedure:** `workflows/greenlight-deploy.md` (framework release pattern: VERSION bump, commit, push, annotated tag, GitHub release). Capture deploy hash; run probes G-M..G-Q (`verification-gate.md`); run smoke S1 (run `/find-wasted-effort` against THIS repo — AC7 first-consumer). Single docs commit (FR-14): spec P1 status note + tasks SHAs + CHANGELOG/release-notes + README skill-count. **Approval artifact** per `policies/approval-policy.yml`.

## Per-task detail — Phase 2 (executable after P1)

### T24. A2 write phase
**Cites:** D7 · **Depends on:** T23 · **Acceptance:** AC2 (P3-write clause)
**Scope:** Add proposed-project-memory output + per-rule false-positive fixtures; flip the analyzer from read-only to write-capable **behind the fixtures gate** (no writes ship until each rule has FP fixtures). Optional FLOW:PRESERVE overlay-edit draft (operator-confirmed only). Files: `hooks/local/find-wasted-effort.py`, `flow-skills/find-wasted-effort/`, fixtures. **T25** gate, **T26** deploy (as P1 pattern).

## Per-task detail — Phase 3 (GATED — outline only)

> **Entry conditions (ALL must hold before T27 starts):** (1) `/find-wasted-effort` (P1/P2) has produced **cross-project evidence beyond n=2** that the second-session rebuild is genuinely outcome-neutral for a change class; (2) the `middle_deploy` enforcement design has passed **security-permissions-review**. Until both hold, P3 stays `gated`. Full per-task detail is authored at that point (avoid planning conditional work in detail now — FR-23).

- **T27** Extend FR-21 to three-tier (D1): FLOW_RULES FR-21 row + a lane-classification skill; eligibility = existing Lightweight gate one notch stricter (reference, don't re-derive). **Worker-undisturbed:** FR-01..FR-20, FR-22..FR-26 rows byte-unchanged.
- **T28** `middle_deploy` enforcement **code** (D2): build the author/role check that does NOT exist today (`command_policy.py` must read `approved_by` vs `approval_authors.middle_deploy`, denying the AI-Developer role); add `middle_deploy` to approval/required-artifacts/command policies; DP.6 typed phrase; minutes-scale round-bound TTL (config); baseline-fail-set hash binding; **hooks-off ⇒ fall back to Full DP.6**. Models on the v3.18.0 `dp1_waiver`. **Security-permissions-review mandatory.**
- **T29** `templates/round-file.md` (D6) + Middle-lane skill/workflow wiring + PO-owned classification, upward-only Middle→Full promotion (D3).
- **T30** Hook tests + recovery-sim Middle-lane fixtures (incl. builder-cannot-self-stamp, hooks-off-falls-back, unlisted-deviation-stops-to-Full).
- **T31** Verification gate + security-permissions-review.
- **T32** Deploy P3 via **Full lane** (AC7 — do not dogfood conditional deploy on its own ticket).

## Task chain audit
| Invariant | Affirmed |
|---|---|
| Worker-undisturbed | T18/T27 declare FR rule-row no-touch scopes |
| One task = one commit (FR-03) | each T = one slice |
| Stop at gate (FR-05) | T22/T25/T31 are no-commit gates |
| Module-size (FR-25) | T20/T28 name targets + extraction seam |
| No conditional over-planning (FR-23) | P3 outline-only until entry conditions hold |
