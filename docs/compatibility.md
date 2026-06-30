# Compatibility matrix — Fusebase Flow

The public template targets the following provider / IDE surfaces. **No other compatibility surfaces are claimed.**

| Surface | Files | How operator activates | What works | What does not work yet |
|---|---|---|---|---|
| **Anthropic Claude Code** | `CLAUDE.md`, `.claude/settings.json.example`, `.claude/skills/<52>/SKILL.md` (32 Flow mirrors + 20 CLI provider skills), `.claude/commands/<6>.md` (incl. `/handoff`, `/find-wasted-effort`), `.claude/agents/<4>.md` | Open repo in Claude Code; copy `settings.json.example` to `settings.json` if hooks desired | Self-attestation, state-announcement footer, Flow skills auto-loaded by description match, slash commands (`/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort`), CLI provider skills available for Fusebase Apps domain work, optional Flow lifecycle hooks plus CLI Stop hooks | Hooks require explicit settings.json activation; active downstream settings must be merged, not overwritten |
| **OpenAI / ChatGPT Codex** | `AGENTS.md`, `.codex/config.toml.example`, `.codex/hooks.json.example`, `.agents/skills/<52>/SKILL.md` (32 Flow mirrors + 20 CLI provider skills), `.codex/agents/<4>.md` | Open repo in Codex; copy `config.toml.example` to `config.toml`; accept project trust prompt | Self-attestation, state-announcement footer, Flow skills and CLI provider skills available by skill matching/reference, command parity via the `AGENTS.md` command-equivalents convention (every agent) plus optional `bash hooks/local/install-codex-prompts.sh` for native `/prompts:<cmd>` (per-machine, namespaced, Codex-deprecated), 6 hook events wired via repo-root-stable paths | Project-trust prompt required before hooks load; hook event names not documented as stable contract in v0.1 |
| **Cursor** | `.cursor/rules/fusebase-flow-{always,specs,implementation,validation,security}.mdc`, `AGENTS.md` | Open repo in Cursor; rules load automatically | Always-on rule + 4 scoped rules (specs / implementation / validation / security); reads `AGENTS.md` | No native lifecycle hooks in v0.1; enforcement falls back to git hooks + operator vigilance |
| **GitHub Copilot / VS Code** | `.github/copilot-instructions.md`, `.github/instructions/{fusebase-flow,security,validation}.instructions.md`, `AGENTS.md` | Open repo in VS Code with Copilot enabled | Repository-wide instructions + 3 scoped instruction files; reads `AGENTS.md` | No native lifecycle hooks in v0.1; enforcement falls back to git hooks + operator vigilance |
| **Gemini / Antigravity-style IDE agents** | `GEMINI.md`, `AGENTS.md` | Open repo in the host IDE | Always-on baseline via `AGENTS.md` and `GEMINI.md` | No documented lifecycle-hook surface in v0.1; enforcement falls back to git hooks + operator vigilance |
| **Generic local repo workflow** | `AGENTS.md`, `*` (rules, skills, workflows, policies, templates), git fallback hooks, local scripts | Clone repo; install git hooks via `hooks/local/install-git-hooks.sh` | Full rule / workflow / template substrate; git pre-commit and commit-msg enforcement; local approval / preflight / mirror scripts | Provider-specific skill mirrors only useful when paired with Claude Code or Codex; otherwise read canonical `flow-skills/` directly |

## Surfaces explicitly NOT claimed

The public template does not advertise compatibility with any AI coding assistant outside the table above. If a future surface is added, it appears here first.

## Verification

| Check | Result |
|---|---|
| Public-surface grep (case-insensitive, full tree) for non-target tool names | 0 true-positive matches |
| Canonical Flow skill mirror count | 64 = 32 canonical (`flow-skills/`) x 2 approved provider mirrors |
| CLI provider skill count | 40 = 20 CLI provider skills x 2 provider surfaces (FuseBase CLI 0.25.9) |
| Mirror dirs allowed | `.agents/skills/`, `.claude/skills/`; this edition also keeps CLI provider skills in those dirs |
| `mirror-skills.sh` target list | mirrors canonical Flow skills only (source `flow-skills/`) and preserves extra CLI provider skills |
| `preflight.sh` mirror drift check | validates canonical Flow skill mirrors only |
| Hook tests | 24 / 24 PASS (16 handler fixtures + 8 module-size gate scenarios) |
| Preflight | 0 errors / 0 warnings |
| GitHub Action | runs preflight + hook tests + mirror drift check on every push / PR |

## Secret-scan scope (pre-commit + PreToolUse)

The pre-commit secret scan (`hooks/shared/staged_secret_scan.py`, decision D-A1) scans
ONLY added (`+`) lines of the staged diff. Two deliberate scope limits — by design, not bugs:

| Limit | Behavior | Why / legitimate path |
|---|---|---|
| Designed-token files path-excluded | A real secret added inside `policies/secret-patterns.yml`, `policies/secret-patterns.local.yml`, or `hooks/tests/fixtures/` is NOT caught by the commit scan | Those files hold fake example tokens that otherwise self-trip the scanner. Don't store real secrets there. PreToolUse / UserPromptSubmit still scan freely. |
| PreToolUse self-trip on full `secret-patterns.yml` writes | An agent that writes the FULL `secret-patterns.yml` content via Edit/Write can trip the PreToolUse scanner on the file's own fake example tokens | Known limitation. Legitimate path: stage the edit and commit (pre-commit path-excludes that file); the commit scan is the authoritative gate for it. |

To get a real-secret BLOCK past pre-commit: rotate the credential + `git reset HEAD -- <file>` to unstage. NEVER add a `whitelist:` entry — a non-empty whitelist disables a pattern globally and breaks fixtures 10/11.

## Last amended

```
2026-05-27 - v3.1 Fusebase CLI edition matrix; reflects 14 Flow skills plus 19 CLI provider skills.
2026-06-07 - v3.14.1 refresh; 27 canonical Flow skills (flow-skills/), 54 Flow mirrors, 16/16 hook tests, /handoff slash command added.
2026-06-10 - v3.16.0 refresh; 28 canonical Flow skills (module-size-discipline added), 56 Flow mirrors, 22/22 hook tests (16 fixtures + 6 FR-25 gate scenarios), module-size pre-commit step added to git fallback.
2026-06-10 - v3.16.2 hardening; 24/24 hook tests (8 gate scenarios), template ships its own FR-25 baseline (gate live by default), CI --all step, additive-only local override, --write-baseline <path> re-key.
2026-06-29 - FuseBase CLI 0.25.9 re-vendor; 20 CLI provider skills (adds app-api-contract-testing), 40 CLI mirrors (20 x 2). The 0.25.9 Stop set wires run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js (run-typecheck-apps.js shipped but unwired); the merge is preserve-only.
```
