# Changelog

All notable changes to Fusebase Flow Local. Format follows [Keep a Changelog](https://keepachangelog.com/) (lite). This project follows the conventions in `PUBLISHING.md` for cutting releases.

Public release versions ship as annotated git tags on `main`. Per-version detail lives in `docs/release-notes/v<version>.md`.

## [2.2.1] — 2026-05-10

### Added — duplicate-overlay-block detection in health check engine

The health-check engine now counts occurrences of the AGENTS.md and CLAUDE.md heading markers (instead of just checking presence) and flags `DUPLICATE` if more than one copy is found.

#### Why

When upgrading across major heading-marker renames (e.g. v2.1.x → v2.2.0 dropped the "V2" qualifier), an operator who runs `bash hooks/local/post-fusebase-update.sh` without first manually removing the old block ends up with **two overlay blocks** in AGENTS.md (the old "V2" one + a new appended block matching the v2.2.0 heading). Recovery's `grep -qF` for the new heading finds it and skips, but recovery's first run already appended a duplicate.

Pre-v2.2.1, the engine reported `AGENTS.md overlay block: present` — incorrectly green-lighting a state that needs cleanup. v2.2.1 catches this.

#### Changed

- **`hooks/local/fusebase-flow-health-check.sh`** — AGENTS.md and CLAUDE.md overlay-marker checks now use `grep -cF` (count) instead of `grep -qF` (presence). Three states:
  - `0` → `MISSING` (LOCAL_DRIFT — same as before)
  - `1` → `present` (LOCAL_OK — same as before)
  - `>1` → `DUPLICATE (N copies present — likely from a heading-marker rename without first removing the old block; remove the older block manually)` (LOCAL_DRIFT — new state)
- **`VERSION`** `2.2.0` → `2.2.1`.

#### Drift signature behavior

Duplicate state classifies as `DRIFTED` (not `FUSEBASE_UPDATE_AFTERMATH`). The canonical `FUSEBASE_UPDATE_AFTERMATH` signature requires `AGENTS_MISSING` AND `SETTINGS_REDUCED` — duplicates have neither, so they fall through to `DRIFTED` with the descriptive LOCAL_DRIFT message guiding the operator to remove the older block manually.

The skill does not offer auto-recovery for this verdict (recovery wouldn't help — recovery script itself is what could have created the duplicate during a heading rename). Operator removes the old block by hand, then re-runs the health check.

#### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files (10 × 2 mirrors), 0 drift
- agent mirror: 4 files, 0 drift
- hook tests: 14/14 PASS
- Smoke test: induced 2 copies of the AGENTS.md heading marker in a downstream project; engine correctly reported `DUPLICATE (2 copies present...)`, verdict `DRIFTED`, exit 1
- Single-copy and missing-marker behavior unchanged (regression-free)

#### Notes for upgraders (v2.2.0 → v2.2.1)

- **No content edits required.** Patch only changes the engine; existing AGENTS.md / CLAUDE.md / settings.json content remains valid.
- Pulling v2.2.1 (via re-clone or re-running `mirror-skills.sh`) is sufficient. Recovery script is unchanged.
- If your project currently has a duplicate marker block (carried over from v2.1.x → v2.2.0 without a manual edit), v2.2.1's health check will start reporting it — fix it once by deleting the older block, then re-run health check.

---

## [2.2.0] — 2026-05-10

### Added — Health check & recovery (major feature)

A built-in **health check skill** + **recovery script** that diagnose and repair Fusebase Flow overlay drift. The most common drift cause is `fusebase update` (Fusebase CLI) regenerating `AGENTS.md` / `.claude/settings.json` / `.claude/hooks/` from CLI templates and evicting the Fusebase Flow overlay. The new system handles this end-to-end.

#### What ships

- **`skills/fusebase-flow-health-check/SKILL.md`** (canonical skill, description-matched) plus mirrors at `.claude/skills/fusebase-flow-health-check/SKILL.md` and `.agents/skills/fusebase-flow-health-check/SKILL.md`.
- **`hooks/local/fusebase-flow-health-check.sh`** — read-only diagnostic engine. 12 inventory checks + active-approval-artifact awareness + upstream-comparison via `.fusebase-flow-source/` clone. Exit codes: 0 HEALTHY, 1 DRIFTED / FUSEBASE_UPDATE_AFTERMATH, 2 BROKEN, 3 EXCEPTION_IN_EFFECT.
- **`hooks/local/post-fusebase-update.sh`** — idempotent recovery script. 10 steps restore: skills + sub-agents mirrors, AGENTS.md + CLAUDE.md overlay blocks, `.claude/settings.json` lifecycle events, Windows shell:true patch on the typecheck hook (CVE-2024-27980 mitigation), the health-check skill mirror, and the `/fusebase-health` slash command.
- **`hooks/local/fusebase-flow-overlays/`** — overlay templates (the canonical content the recovery script appends/restores):
  - `agents-md-overlay.md` — `## Fusebase Flow — workflow lifecycle overlay` block for AGENTS.md
  - `claude-md-overlay.md` — `## Fusebase Flow — additional rules (overlay)` block for CLAUDE.md
  - `settings-json-merge.py` — Python merger (no `jq` dependency; auto-discovers events from upstream's `.claude/settings.json.example`)
  - `skills/fusebase-flow-health-check/SKILL.md` — skill template
  - `commands/fusebase-health.md` — slash command template
- **`.claude/commands/fusebase-health.md`** — `/fusebase-health` slash command (Claude Code).

#### Skill behavior — diagnose then offer

The skill is **read-only during diagnosis**. When drift is detected and recoverable, the skill **offers** recovery in chat with a yes/no confirmation:

```
Run recovery now? It will:
  • Restore AGENTS.md overlay block
  • Merge .claude/settings.json lifecycle events
  • Re-apply Windows shell:true patch
  • Re-mirror Fusebase Flow skills + sub-agents

Reply `yes` / `run it` / `fix it` / `proceed` to execute.
Reply anything else to halt and decide later.
```

On affirmative reply → recovery executes + re-check + report new verdict. On any non-affirmative reply (silence, `no`, a question) → halt. Operator authority preserved (PO.5 from `role-discipline` skill); friction reduced — no terminal context-switch needed for most cases. **EXCEPTION_IN_EFFECT** (drift attributable to active approval artifacts in `state/approvals/`) and **BROKEN** verdicts do NOT trigger the recovery offer (recovery wouldn't fix them).

#### Auto-discovery for upstream upgrades

The engine and the merger auto-discover canonical sets at runtime from `.fusebase-flow-source/`:

- **Skill names** from `skills/*/`
- **Agent names** from `agents/*/`
- **Lifecycle event names** from `.claude/settings.json.example`
- **Hook handler commands + matchers** from the same example file

Patch / minor upstream releases (new skill / agent / event) require **zero maintenance** to this system. Only major-version semantic changes (heading marker rename) require manual edits.

#### Heading marker convention

This release standardizes on `## Fusebase Flow — workflow lifecycle overlay` (AGENTS.md) and `## Fusebase Flow — additional rules (overlay)` (CLAUDE.md). The previous internal "V2" qualifier was dropped per the standard "Fusebase Flow" naming.

### Changed

- **`VERSION`** `2.1.1` → `2.2.0`.
- **`README.md`** — added "Health check & recovery (v2.2+)" section with quick reference, verdicts table, recovery flow, auto-discovery posture, and file inventory.
- **`docs/install-fusebase-cli-project.md`** — heading marker text updated to `## Fusebase Flow — workflow lifecycle overlay` (was `# Fusebase Flow Local — workflow discipline overlay`); recovery section added.
- **`docs/install-existing-project.md`** — health check + recovery section added.

### Validation at release

- preflight: 0 errors / 0 warnings
- skill mirror: 20 files (10 × 2 mirrors), 0 drift (after regen)
- agent mirror: 4 files, 0 drift (after regen)
- hook tests: 14/14 PASS
- Health check end-to-end test: HEALTHY → fusebase update → FUSEBASE_UPDATE_AFTERMATH → recovery offer → affirmative → recovery executed → HEALTHY (exit 0)
- Idempotency: 2nd recovery run reports "already in place" for all restorable items, byte-identical no-op on settings.json merge

### Notes for upgraders (v2.1.x → v2.2.0)

- **Heading marker change:** if you have an existing v2.1.x project with `## Fusebase Flow V2 — workflow lifecycle overlay` in your AGENTS.md, edit it to drop the "V2 ": `## Fusebase Flow — workflow lifecycle overlay`. Same for CLAUDE.md (`## Fusebase Flow V2 — additional rules (overlay)` → `## Fusebase Flow — additional rules (overlay)`). The recovery script and engine grep for the new heading; without this edit they'll think the marker is missing and append a duplicate block.
- **`stop.py` statusMessage:** the merger now writes `"Fusebase Flow stop hook…"` (was `"Fusebase Flow V2 stop hook…"`). Existing settings.json entries with the old text continue to work but will not match the merger's substring check on the next merge — re-run `bash hooks/local/post-fusebase-update.sh` to pick up the updated text.
- **No skill / agent rename:** existing skills and sub-agents keep their names. The new `fusebase-flow-health-check` skill is additive.
- **Fresh installs:** `bash install.sh` works as before; new health check files are picked up automatically by the existing mirror-skills step.

---

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
