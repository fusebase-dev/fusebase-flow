---
name: repo-onboarding-context-map
description: Use on first Fusebase Flow install, opening an unfamiliar repo, or after major restructuring; produces durable context map (commands, structure, protected paths, risky boundaries). Do NOT use for routine ticket investigation.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 0.1
risk_level: low
invocation: manual
expected_outputs:
  - docs/specs/repo-context.md
  - AGENTS.md (project-specific section, recommended updates)
related_workflows:
  - setup.md
  - session-initiation.md
hook_dependencies:
  - none
---

# Repo Onboarding & Context Map

## Purpose

Inspect an unfamiliar repo and produce a durable context map so future sessions know the project's structure, commands, protected paths, and risky system boundaries without re-investigating each session.

## When to invoke

- First-time installation of Fusebase Flow into an existing repo
- Operator says "I'm picking up this repo" / "what's in this codebase?" / "set up flow here"
- After a major structural change (large rename, monorepo split, framework swap)
- When `docs/specs/repo-context.md` is missing or older than 90 days

## Do not invoke when

- A current `repo-context.md` exists and the repo hasn't changed structurally
- Operator is asking a code-specific question — use code-review or normal investigation
- A spec is in flight — don't pivot to onboarding mid-ticket

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Repo root | git root | Stop; ask operator to confirm working directory |
| Package/project files | `package.json`, `pyproject.toml`, `Cargo.toml`, etc. | Note "no manifest detected"; describe based on file extensions only |
| Existing READMEs | `README.md`, `docs/`, etc. | Note absence; flag as Phase-4 onboarding gap |

## Procedure

1. List repo root files (top level only). Identify project type (Node/Python/Go/Rust/etc.) and frontend/backend split if visible.
2. Read root `README.md` if present. Read up to 3 most-referenced docs in `docs/`.
3. Detect build/test/lint commands from manifest files. Capture exact commands.
4. Identify protected-path candidates: long-lived worker code, generated files, migration files, deployment configs.
5. Identify risky system boundaries: external APIs, database migrations, auth surfaces, file system writes outside repo.
6. Run `git log --oneline -30` to read commit cadence + recent areas of activity.
7. Save findings to `docs/specs/repo-context.md` using `templates/spec.md` adapted for context-mapping (see template).
8. Propose updates to `AGENTS.md` "project-specific values" section. Show the diff in chat. Do NOT apply unless operator says "apply".
9. Propose initial `policies/protected-paths.yml` candidates. Save as draft if operator approves; do NOT auto-write.

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| Repo context map | `docs/specs/repo-context.md` | Mode B (full) |
| AGENTS.md project-specific updates (proposed) | chat diff | Mode A |
| Protected paths candidates | `policies/protected-paths.yml` (proposed; commit only on operator approval) | Mode B (full, YAML) |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Repo has no manifest, no README, no docs | Initial scan returns nothing identifying | Capture what's visible (file extensions, recent commits). Mark `repo-context.md` as `partial` and ask operator to fill the gaps. |
| Repo is a monorepo with conflicting conventions | Multiple `package.json` / `pyproject.toml` at different paths | Map each subdir separately. Flag in `repo-context.md` "monorepo: yes". |
| Repo uses git submodules | `.gitmodules` exists | Note submodules but do not recurse into them in v0.1. |

## Escalation path

- Repo too large to scan in one pass (>10k files) → ask operator which subdirs to prioritize
- Build commands fail when run → file backlog ticket for build-environment-fix; do not propose flow installation until build is healthy

## Anti-patterns

- Do not silently write `AGENTS.md` updates — propose, get operator approval, then write
- Do not commit `policies/protected-paths.yml` candidates without operator approval
- Do not save permanent memories about the repo without operator confirmation
- Do not invoke during an in-flight spec — context-mapping is a separate, longer-running task

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
