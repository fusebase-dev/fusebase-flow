# Changelog

All notable changes to Fusebase Flow Local. Format follows [Keep a Changelog](https://keepachangelog.com/) (lite). This project follows the conventions in `PUBLISHING.md` for cutting releases.

Public release versions ship as annotated git tags on `main`. Per-version detail lives in `docs/release-notes/v<version>.md`.

## [2.1.1] — 2026-05-09

### Added — defense-in-depth refinements to the v2.1.0 sub-agent design

Two post-release hardening changes from independent v2.1.0 evaluation feedback. Both move guarantees from prompt-level (LLM judgment) to structural (tool / control flow).

- **`hooks/local/po-investigate.sh` (new)** — allowlisted, read-only investigation wrapper for the Product Owner sub-agent. Allowed subcommands: `status`, `diff`, `log`, `show`, `blame`, `ls`, `cat`, `head`, `tail`, `find`. Anything else exits non-zero. The PO sub-agent's tool surface still includes Bash, but its system prompt now mandates **wrapper-only** Bash usage and explicitly denies direct calls to `git`, `npm`, `node`, `python`, `cat`, `bash -c`, etc. Mutating commands (`git stash`, `git commit`, `npm install`, `node -e "fs.writeFileSync(...)"`, etc.) are not reachable through the wrapper because they aren't allowlisted subcommands.

- **`DP.6` deploy-time operator confirm** — new Deploy phase don't-list rule. Before the deploy command runs, the agent must obtain the operator typing the literal phrase `APPROVE-DEPLOY-NOW`. Anything else (`yes`, `y`, `ok`, partial matches) aborts the deploy. Mirrors the existing `APPEND-ONLY` pattern in `install.sh`. Adds ~5 seconds of structural friction to keep a human at the keyboard for production cutover moments. Codified in `skills/role-discipline/SKILL.md` (Deploy phase section), `agents/ai-developer/AGENT.md` (Deploy phase ownership table + don't-list + stop conditions), and `workflows/greenlight-deploy.md` (procedure step 4).

### Changed

- **`agents/product-owner/AGENT.md`** — Bash row in tool-surface table now mandates the `po-investigate.sh` wrapper. Direct Bash calls added to the Denied table.
- **`agents/ai-developer/AGENT.md`** — Deploy phase ownership table includes the new DP.6 step between DP.2 (worker-undisturbed re-check) and the deploy command run; don't-list expanded from `DP.1..DP.5` to `DP.1..DP.6`; stop-conditions table includes the abort-on-non-matching-phrase row.
- **`skills/role-discipline/SKILL.md`** — Deploy phase don't-list adds DP.6 with refusal phrasing for the "just deploy, I'm watching" violation request, plus recovery note.
- **`workflows/greenlight-deploy.md`** — procedure list inserts step 4 (operator confirm); subsequent steps renumbered 5–10. Self-attestation phrase updated `DP.1..DP.5` → `DP.1..DP.6`.
- **`VERSION`** `2.1.0` → `2.1.1`.
- **Mirrors regenerated** by `mirror-skills.sh` and `mirror-agents.sh`.

### Why these changed

Both refinements address ergonomic-vs-structural tradeoffs identified during external evaluation of v2.1.0. The PO wrapper closes a fuzzy "read-only Bash" boundary that the prompt-level instruction couldn't fully police (`git stash` mutates; `node -e "..."` is one keystroke from a write). The DP.6 confirm closes the "operator distracted at moment of production cutover" failure mode that purely automated deploys can hit. Both are minimal-surface additions that preserve v2.1.0's architectural shape (two sub-agents, role-discipline-driven, handoff-on-disk).

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 18 files, 0 drift (after regen)
- agent mirror: 4 files, 0 drift (after regen)
- hook tests: 14/14 PASS
- `po-investigate.sh`: syntax OK; smoke-tested allowlisted (`status`, `log`) and rejected (`nonsense` → exit 2) paths

### Notes for upgraders

- **PO sub-agent users:** if you've started a session before this upgrade, restart it so the v2.1.1 prompt loads (the wrapper-only Bash rule is in the system prompt; cached prompts won't have it).
- **Deploy automation:** the DP.6 pause adds a single round-trip to every Deploy phase invocation. For automated CI/CD that needs no-pause deploys, that path is an Operator-attested action (the operator runs deploys directly), not a Deploy-phase sub-agent invocation. The DP.6 rule applies only to sub-agent / role-attested deploys.

---

## [2.1.0] — 2026-05-09

### Added — Sub-agents (major feature)

- **Two role-shaped sub-agents** that cover the full eight-phase ticket lifecycle:
  - **Product Owner** (`agents/product-owner/AGENT.md`) — drives Specify, Clarify, Plan, Decisions, Tasks, draft-verification-gate, post-implement code-review and security-permissions-review, deploy-handoff drafting, and the spec DRAFT→DONE flip. Absorbs Architect responsibilities inline when escalation triggers fire (>10 files, cross-cutting refactor, platform blocker, blocked migration). Never edits application code.
  - **AI Developer** (`agents/ai-developer/AGENT.md`) — executes Implementer or Deploy-phase handoffs. Self-attests by handoff filename: `*-implement.md` → Implementer (runs the T-chain, stops at the gate); `*-deploy.md` → Deploy phase (runs deploy command, captures hash, runs probes). Never drafts specs; STOPS and asks if no handoff is provided.
- **Provider parity** via canonical → mirror pattern (parallel to skills):
  - `agents/<name>/AGENT.md` (canonical)
  - `.claude/agents/<name>.md` (Claude Code — auto-discovered)
  - `.codex/agents/<name>.md` (Codex — operator-referenced in fresh session)
- **`hooks/local/mirror-agents.sh`** regenerates both provider mirrors from canonical; parallel to `mirror-skills.sh`.
- **`audit/agent-mirror-manifest.txt`** sha256 manifest for drift detection.
- **`hooks/local/preflight.sh`** new step 5b verifies agent mirror parity (warn-level on drift).
- **`install.sh`** new step 4 (4/4) offers to mirror agents alongside skills. Prompts renumbered 1/3..3/3 → 1/4..4/4.
- **`README.md`** — sub-agents row added to the enforcement table; tree shows `agents/`, `.claude/agents/`, `.codex/agents/`, `audit/agent-mirror-manifest.txt`; how-to-use section added under "Filing your first ticket".

### Changed

- **Self-attestation phrase** updated from `Fusebase Flow v0.1` to `Fusebase Flow v2.1` across all canonical files: `FLOW_RULES.md`, `CLAUDE.md`, `AGENTS.md` (where present), `GEMINI.md`, `.github/copilot-instructions.md`, `agents/*/AGENT.md`, `workflows/architect-escalation.md`, `workflows/greenlight-deploy.md`, `workflows/greenlight-implement.md`, `workflows/session-initiation.md`. Mirrors regenerated automatically.
- **Skill frontmatter** `fusebase_flow_version: 0.1` → `fusebase_flow_version: 2.1` across all 9 canonical skills + `templates/skill-template.md`. Mirrors regenerated.
- **`VERSION`** `0.1.2` → `2.1.0`.

### Coverage walkthrough (verified at release)

| Phase / cross-cut | Sub-agent | Verified |
|---|---|---|
| 1 Specify | Product Owner | ✓ |
| 2 Clarify | Product Owner | ✓ |
| 3 Plan | Product Owner | ✓ |
| 4 Decisions (recommend; operator locks) | Product Owner | ✓ |
| 5 Tasks | Product Owner | ✓ |
| 6a Draft verification gate | Product Owner | ✓ |
| 6b Run gate | AI Developer | ✓ |
| 6c Code review + security review | Product Owner | ✓ |
| 7 Implement | AI Developer (Implementer attestation) | ✓ |
| 8a Draft deploy handoff | Product Owner | ✓ |
| 8b Run deploy command | AI Developer (Deploy-phase attestation) | ✓ |
| 8c Spec DRAFT→DONE flip | Product Owner | ✓ |
| Architect escalation | Product Owner inline (AR.1..AR.6 additive) | ✓ |
| Live-user verification | AI Developer | ✓ |
| Knowledge curation | Product Owner | ✓ |
| Violation recovery | both (own role section) | ✓ |

### Validation at release

- preflight: 0 errors / 0 warnings (now includes step 5b agent-mirror check)
- skill mirror: 18 files, 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS

### Notes for upgraders

- Previous self-attestation phrases referencing `Fusebase Flow v0.1` are now `Fusebase Flow v2.1`. Sessions that run from cached prompts may need to be restarted to load the new phrasing.
- Sub-agents are **opt-in** — the framework remains fully usable via the existing skill-and-workflow flow without invoking sub-agents at all. Sub-agents are an additional entry point, not a replacement.
- Codex does not auto-discover `.codex/agents/` — operators reference the file in their first message of a fresh session (e.g., `Read .codex/agents/product-owner.md and operate as Product Owner`).

---

## [0.1.2] — 2026-05-09

### Added

- Sub-agents foundation (commit `937f658`) — superseded by the `2.1.0` release on the same day; effectively folded into v2.1.0.

## [0.1.1] — 2026-05-09

### Added

- `skills/role-discipline` (mandatory 8th canonical skill — actually 9th) with per-role don't-lists and exact refusal phrasing for Product Owner, Implementer, Architect (escalation), Deploy phase, and Operator.
- `workflows/live-user-verification.md` — 8-step procedure with verbatim consent flow, cookie sanity test, masked smoke output, end-of-work cleanup phrase that the stop hook checks for.
- `workflows/violation-recovery.md` — per-FR rule recovery procedures plus per-hook-event recovery.
- `docs/architecture-overview.md`, `docs/operator-discipline.md`, `docs/tradeoffs.md`, `docs/constitution.md`.
- `hooks/handlers/stop.py` — `cleanup_marker_present` and `live_user_verification_used` signals.
- `hooks/shared/secret_scanner.py` — `pattern_overrides` precedence (per-pattern escalation in tool context).
- `policies/secret-patterns.yml` — `cookie_session_value` pattern now blocks (not warns) in `pre_tool_use` and `git_pre_commit` contexts.
- 3 new deterministic hook test fixtures (12, 13, 14) covering cookie escalation and cleanup-marker gating.

### Changed

- Self-attestation phrase appended `I will apply the role-discipline skill section for {role}.`
- Implementer / Deploy / Architect role-specific self-attestation phrases now reference numbered sections (`IM.1..IM.10`, `DP.1..DP.5`, `AR.1..AR.6`).
- `skills/requirements-specification`: skip-clarify gate, Phase 1/2 split, abort-ticket failure case, scope-disagreement escalation.
- `skills/validation-and-qa`: 3-question empirical-coverage test for ACs; Sub-mode D test-data hygiene cleanup.
- `templates/smoke-test-playwright.md`: when-to-skip table, one-time setup block, CDP-vs-Playwright trade-offs.
- Various count updates triggered by adding the role-discipline skill (skills 8 → 9; mirrors 16 → 18; workflows 10 → 12; fixtures 11 → 14).

## [0.1.0] — Initial release

- Fusebase Flow Local v0.1 — repo-local workflow framework for AI coding agents and IDEs.
- 8 canonical skills, 10 workflows, 6 policies, 13 templates.
- Hook handlers for `session_start`, `user_prompt_submit`, `pre_tool_use`, `post_tool_use`, `stop`, `pre_compact`.
- Provider mirrors for Anthropic Claude Code (`.claude/skills/`, `.claude/settings.json.example`) and OpenAI / ChatGPT Codex (`.agents/skills/`, `.codex/{config.toml,hooks.json}.example`).
- Cursor rules (`.cursor/rules/*.mdc`).
- GitHub Copilot / VS Code instructions (`.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`).
- 11 deterministic hook test fixtures.
- CI workflow `.github/workflows/fusebase-flow-verify.yml`.
- Clean-room license attestation (`docs/clean-room.md`).
- MIT license.
