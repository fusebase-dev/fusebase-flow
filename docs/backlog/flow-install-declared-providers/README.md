# flow-install-declared-providers

**Status:** open — 6.0.0 rebuild, **wave 4** (WP 1b). **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 1b (R §2). **Surface:** the `flow install` entry point under `maintainer/` (new); provider mirror generation (today `hooks/local/mirror-skills.sh:32`, `hooks/local/mirror-agents.sh:30`, both hard-coding both providers); the project's one install manifest; `--wire-hooks` per provider. **FR-07:** no in the Flow repository (all under `maintainer/`), unless a commit also edits a protected path.

## Delivers

- `flow install --providers claude,codex` (default both). The declaration is a top-level `providers` key in the project's one install manifest (decision 5a); install, health and migrate read it.
- Installs exactly the core list: **53 Flow files** (owner, second message): 3 root files (`FLOW_RULES.md`, `VERSION`, `LICENSE`), 2 pages (lifecycle and quickstart), 4 templates, 3 canonical agents, 5 shipped policies, 34 hook files, `hooks/requirements.txt`, 1 install manifest. `agent-tools.yml`, `evidence-classes.yml` and the baseline are created by the project.
- Mirrors for declared providers only, counted apart: Claude Code 9 (6 skills, 3 agents), Codex 8 (6 skills, 2 TOML agents) — **70** with both. Skills exist only as provider mirrors (ask 4).
- Codex agents are TOML, planner and builder only (decision 5e); no reader TOML, so no fake reader exists.
- Never writes `.codex-plugin/plugin.json` (publisher-only, `hooks/local/lib/managed_content_manifest.py:39-41`; decision 5b), no Cursor, Copilot or Gemini file (5c), no frozen CLI snapshot (5d).
- Prints and records the scheduled-task line for `reader.py --once` (`schtasks` or crontab; H non-negotiable 5); `--watch` stays the terminal form.
- `--wire-hooks` per provider, opt-in (H non-negotiable 4): Claude Code merges the two kept handlers into `.claude/settings.json`; Codex writes `.codex/hooks.json` in the documented schema and prints the hook-trust step; it never touches `.codex/config.toml`.
- Folds in backlog `install-into-existing-fusebase-cli-project` (with `flow-migrate`).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Decision 5 (a) to (e) | Provider declaration, no plugin mirror, two providers only, no CLI snapshot, Codex TOML agents |
| Ask 4 (exact counts; skills only as mirrors) | Acceptance counts below, now 53 and 70 |
| Second message (row 35 withdrawn) | 53 Flow files, 70 with both mirrors |
| Ask 9 (wire Claude Code hooks in phase 7; Codex unwired until its slice) | `--wire-hooks claude` is the phase 7 step; Codex stays `unenforced` |
| Decision 7 (keep `install-git-hooks.sh` and one install manifest) | Install runs `install-git-hooks.sh`, which writes the per-clone excludes (`core-hook-inventory`) |
| Decision 1 (6.0.0, no in-place upgrade from 5.x) | Install is for fresh projects; 5.x projects go through `flow migrate` |

## Estimate

R §2 WP 1: 18 to 28 agent-h (mid 23) for 1a and 1b together; this entry's share 7 to 12 (mid 9.5), on the critical path (R §2: 9 h step). Review: independent (install authority).

## Depends

The final core inventory: `four-document-model`, `reader-agent-and-dispatch-check`, `six-skills-and-optional-pack` (final), `task-slicer`, and the four WP 11 entries; `maintainer-tree-split`. Blocks: `flow-migrate` integration (its install step), the release count.

## Acceptance

1. A fresh project with Claude Code and Codex declared and no optional pack receives exactly the published core list: 53 Flow files, plus 9 and 8 mirror files, 70 in total. Nothing under `maintainer/` is installed (fixture, H WP 1 with R's counts).
2. A per-provider fixture: `--providers claude` writes no Codex file; `--providers codex` writes no `.claude/` file.
3. `.codex-plugin/plugin.json`, `.codex/config.toml` and every CLI-owned path are untouched (sha256 before and after).
4. The install manifest carries `providers`; a second install with the same providers changes nothing.
5. The scheduled-task line is printed and recorded; with no registration, `state/status.line` later reads "last seen: never".
6. `--wire-hooks` per provider; without it Flow writes neither `.claude/settings.json` nor `.codex/hooks.json`.

## Wave split

Wave 4, after the inventory is final. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
