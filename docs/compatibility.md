# Compatibility matrix — Fusebase Flow

The public template targets the following provider / IDE surfaces. **No other compatibility surfaces are claimed.**

| Surface | Files | How operator activates | What works | What does not work yet |
|---|---|---|---|---|
| **Anthropic Claude Code** | `CLAUDE.md`, `.claude/settings.json.example`, `.claude/skills/<33>/SKILL.md` (14 Flow mirrors + 19 CLI provider skills), `.claude/agents/<4>.md` | Open repo in Claude Code; copy `settings.json.example` to `settings.json` if hooks desired | Self-attestation, state-announcement footer, Flow skills auto-loaded by description match, CLI provider skills available for Fusebase Apps domain work, optional Flow lifecycle hooks plus CLI Stop hooks | Hooks require explicit settings.json activation; active downstream settings must be merged, not overwritten |
| **OpenAI / ChatGPT Codex** | `AGENTS.md`, `.codex/config.toml.example`, `.codex/hooks.json.example`, `.agents/skills/<33>/SKILL.md` (14 Flow mirrors + 19 CLI provider skills), `.codex/agents/<4>.md` | Open repo in Codex; copy `config.toml.example` to `config.toml`; accept project trust prompt | Self-attestation, state-announcement footer, Flow skills and CLI provider skills available by skill matching/reference, 6 hook events wired via repo-root-stable paths | Project-trust prompt required before hooks load; hook event names not documented as stable contract in v0.1 |
| **Cursor** | `.cursor/rules/fusebase-flow-{always,specs,implementation,validation,security}.mdc`, `AGENTS.md` | Open repo in Cursor; rules load automatically | Always-on rule + 4 scoped rules (specs / implementation / validation / security); reads `AGENTS.md` | No native lifecycle hooks in v0.1; enforcement falls back to git hooks + operator vigilance |
| **GitHub Copilot / VS Code** | `.github/copilot-instructions.md`, `.github/instructions/{fusebase-flow,security,validation}.instructions.md`, `AGENTS.md` | Open repo in VS Code with Copilot enabled | Repository-wide instructions + 3 scoped instruction files; reads `AGENTS.md` | No native lifecycle hooks in v0.1; enforcement falls back to git hooks + operator vigilance |
| **Gemini / Antigravity-style IDE agents** | `GEMINI.md`, `AGENTS.md` | Open repo in the host IDE | Always-on baseline via `AGENTS.md` and `GEMINI.md` | No documented lifecycle-hook surface in v0.1; enforcement falls back to git hooks + operator vigilance |
| **Generic local repo workflow** | `AGENTS.md`, `*` (rules, skills, workflows, policies, templates), git fallback hooks, local scripts | Clone repo; install git hooks via `hooks/local/install-git-hooks.sh` | Full rule / workflow / template substrate; git pre-commit and commit-msg enforcement; local approval / preflight / mirror scripts | Provider-specific skill mirrors only useful when paired with Claude Code or Codex; otherwise read canonical `skills/` directly |

## Surfaces explicitly NOT claimed

The public template does not advertise compatibility with any AI coding assistant outside the table above. If a future surface is added, it appears here first.

## Verification

| Check | Result |
|---|---|
| Public-surface grep (case-insensitive, full tree) for non-target tool names | 0 true-positive matches |
| Canonical Flow skill mirror count | 28 = 14 canonical x 2 approved provider mirrors |
| CLI provider skill count | 38 = 19 CLI provider skills x 2 provider surfaces |
| Mirror dirs allowed | `.agents/skills/`, `.claude/skills/`; this edition also keeps CLI provider skills in those dirs |
| `mirror-skills.sh` target list | mirrors canonical Flow skills only and preserves extra CLI provider skills |
| `preflight.sh` mirror drift check | validates canonical Flow skill mirrors only |
| Hook tests | 14 / 14 PASS |
| Preflight | 0 errors / 0 warnings |
| GitHub Action | runs preflight + hook tests + mirror drift check on every push / PR |

## Last amended

```
2026-05-27 - v3.1 Fusebase CLI edition matrix; reflects 14 Flow skills plus 19 CLI provider skills.
```
