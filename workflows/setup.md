# Workflow: setup

> **Style:** Mode-B-lite. Procedure for installing Fusebase Flow into a new or existing repo.

## When to run

- First-time installation in a fresh repo
- Adding Fusebase Flow to an existing project that uses an agentic IDE

## Inputs required

| Input | Source |
|---|---|
| Repo root | git root (run from there) |
| Project type | detect or ask: Node / Python / Go / Rust / etc. |
| Tool surfaces wanted | operator chooses from: Claude Code, Codex, Cursor, GitHub Copilot/VS Code, Gemini-style IDE agents, generic local |

## Procedure

1. Verify the repo is a git repo. If not: `git init -b main`.
2. Copy ``, `AGENTS.md`, `.gitignore` (merge if existing) from the template.
3. Ask operator which provider/IDE compatibility files to install. Copy:
   - Anthropic Claude Code → `.claude/skills/` (mirror) + `.claude/settings.json.example`
   - OpenAI / ChatGPT Codex → `.agents/skills/` (mirror) + `.codex/hooks.json.example` + `.codex/config.toml.example`
   - Cursor → `.cursor/rules/`
   - GitHub Copilot / VS Code → `.github/copilot-instructions.md` + `.github/instructions/*.instructions.md`
   - Gemini / Antigravity-style IDE agents → `GEMINI.md`
   - Generic local repo workflow → `*` + git fallback hooks (no provider-specific layer)
4. Run `bash hooks/local/mirror-skills.sh` to sync skill mirrors with canonical source.
5. Optionally install git fallback hooks: `bash hooks/local/install-git-hooks.sh`.
6. Optionally enable Claude Code or Codex agent hooks: copy `*.example` to active filenames and customize.
7. Run `repo-onboarding-context-map` skill to produce `docs/specs/repo-context.md` and propose `AGENTS.md` project-specific updates.
8. Operator reviews proposed `AGENTS.md` updates. Apply on confirm.
9. Run validation: `bash hooks/local/preflight.sh` (verifies file structure, YAML parse, skill frontmatter).
10. Write installation report to `state/audit/install-report.md`.

## Outputs

| Artifact | Path |
|---|---|
| Installed framework | `` + tool adapter folders |
| Repo context map | `docs/specs/repo-context.md` |
| Updated AGENTS.md | repo root |
| Install report | `state/audit/install-report.md` |

## Failure modes

| Failure | Response |
|---|---|
| Repo already has `` | Ask operator: overwrite, merge, or abort |
| Operator declines all provider / IDE compatibility files | Install canonical source only; rely on `AGENTS.md` for portable behavior |
| Preflight fails | Surface specific failure (missing file, YAML parse error, etc.) and stop |

## Related

- `workflows/session-initiation.md` — what to do at the start of each subsequent session
- `skills/repo-onboarding-context-map/SKILL.md` — produces `docs/specs/repo-context.md`
- `hooks/local/preflight.sh` — runs the validation in step 9
