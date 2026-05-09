# Compatibility matrix — Fusebase Flow Local v0.1

The public template targets the following provider / IDE surfaces. **No other compatibility surfaces are claimed.**

| Surface | Files | How operator activates | What works | What does not work yet |
|---|---|---|---|---|
| **Anthropic Claude Code** | `CLAUDE.md`, `.claude/settings.json.example`, `.claude/skills/<9>/SKILL.md` (mirror — 2 mandatory + 7 on-demand) | Open repo in Claude Code; copy `settings.json.example` → `settings.json` if hooks desired | Self-attestation, state-announcement footer, 7 on-demand skills auto-loaded by description match + 2 mandatory skills (`communication`, `role-discipline`) loaded at session start, optional 6 lifecycle hooks (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, PreCompact) returning `hookSpecificOutput.permissionDecision` | Hooks require explicit settings.json activation; PermissionRequest hook is reserved for future use |
| **OpenAI / ChatGPT Codex** | `AGENTS.md`, `.codex/config.toml.example`, `.codex/hooks.json.example`, `.agents/skills/<9>/SKILL.md` (mirror — 2 mandatory + 7 on-demand) | Open repo in Codex; copy `config.toml.example` → `config.toml`; accept project trust prompt | Self-attestation, state-announcement footer, 9 skills mirrored under `.agents/skills/` (2 mandatory + 7 on-demand), 6 hook events (`session_start`, `user_prompt_submit`, `pre_tool_use`, `permission_request`, `post_tool_use`, `stop`) wired via repo-root-stable paths | Project-trust prompt required before hooks load; hook event names not documented as stable contract in v0.1 |
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
| Skill mirror count | 18 = 9 canonical × 2 approved provider mirrors |
| Mirror dirs allowed | `.agents/skills/`, `.claude/skills/` only |
| `mirror-skills.sh` target list | matches the table above |
| `preflight.sh` mirror drift check | only validates the 2 approved mirrors |
| Hook tests | 14 / 14 PASS |
| Preflight | 0 errors / 0 warnings |
| GitHub Action | runs preflight + hook tests + mirror drift check on every push / PR |

## Last amended

```
2026-05-08 — Phase 4 final matrix; reflects post-cleanup public-surface scope.
```
