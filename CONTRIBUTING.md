# Contributing to Fusebase Flow

Thanks for helping improve Fusebase Flow. This project is a repo-local workflow framework — most contributions are edits to skills, workflows, policies, hooks, docs, or the provider compatibility surfaces.

## Before you start

- Read [`AGENTS.md`](AGENTS.md) (portable baseline) and [`FLOW_RULES.md`](FLOW_RULES.md) (FR-01..FR-27). Contributions are expected to respect the always-on rules.
- Check [`ROADMAP.md`](ROADMAP.md) — especially the explicit non-goals — before proposing new surfaces or features.
- For framework changes, the project itself follows the eight-phase lifecycle in [`workflows/eight-phase-flow.md`](workflows/eight-phase-flow.md). Small doc fixes don't need a full spec; behavior changes do.

## Ground rules

- **Stdlib-first.** Python is standard-library only except PyYAML (`hooks/requirements.txt`). No new heavy dependencies, no servers, no daemons, no network webhooks.
- **Clean-room.** Canonical Flow files are clean-room original — do **not** paste text from other proprietary frameworks. CLI provider assets are provider-scoped; keep the separation documented in [`docs/clean-room.md`](docs/clean-room.md) and [`docs/source-map.md`](docs/source-map.md).
- **Cross-platform.** Shell is bash; line endings are enforced LF via `.gitattributes`. Hooks must run on Linux, macOS, and Windows (Git Bash / WSL).

## Editing skills or sub-agents

Skill and agent files are **mirrored** across provider folders (`.claude/`, `.agents/`, `.codex/`) and tracked by SHA-256 manifests in [`audit/`](audit/). Always edit the **canonical** source, then regenerate mirrors:

```bash
# Canonical skill lives at: flow-skills/<name>/SKILL.md
bash hooks/local/mirror-skills.sh

# Canonical sub-agent lives at: agents/<name>/AGENT.md
bash hooks/local/mirror-agents.sh
```

Preflight fails on mirror drift, so never hand-edit a mirror.

## Validate before you push

Both must pass cleanly:

```bash
bash hooks/local/preflight.sh    # structure + YAML + frontmatter + mirror drift + action-name consistency
bash hooks/tests/run-tests.sh    # deterministic hook test fixtures
```

Expected:

```
[preflight] preflight finished — errors: 0, warnings: 0
[run-tests] 24/24 PASS
```

CI runs both on every push / PR via `.github/workflows/fusebase-flow-verify.yml`.

## Commits & pull requests

- Use clear, conventional-style commit subjects: `feat(flow): …`, `fix(flow): …`, `docs: …`, `chore: …`.
- Keep one logical change per commit where practical.
- In the PR description, state **what changed and why**, the phase/ticket if applicable, and confirm preflight + tests pass locally.
- Update [`CHANGELOG.md`](CHANGELOG.md) for user-visible changes (the project follows the cutting-a-release conventions in [`PUBLISHING.md`](PUBLISHING.md)).

## Reporting bugs & requesting features

Open a GitHub issue using the templates in [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/). For anything security-sensitive, follow [`SECURITY.md`](SECURITY.md) instead of opening a public issue.

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).