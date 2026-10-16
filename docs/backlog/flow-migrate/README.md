# flow-migrate

**Status:** open — 6.0.0 rebuild, **wave 1 (classifier and dry-run inventory)**, integration in **wave 4**. Folds in `install-into-existing-fusebase-cli-project` (with `flow-install-declared-providers`). **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 12 (R §2). **Surface:** a new stdlib module under `maintainer/` run as the installer's `migrate` mode (path per the design pass's WP 12 plan); reuses `hooks/local/lib/managed_content_manifest.py` (classifier), `overlay-block-replace.py`, `write-bootstrap-approval.sh`, `install-git-hooks.sh`; the upstream refusal file at `hooks/local/upgrade.sh`. **FR-07:** no in the Flow repository (`maintainer/`); a consumer's migration commit mints its own single-use `protected_path_edit` approval.

## Delivers

- **`flow migrate`, a mode of the upstream installer** (decision 8), run from the upstream source and never from a project's installed 5.x engine (H non-negotiable 11). `--dry-run` first, always.
- **Its own action table** (decision 8): write the core for `current`, `upstream-only` and `upstream-added`; move `upstream-deleted-clean` files into one `.flow-migrate-<ts>/` folder; **abort on `changed-by-both` and `upstream-deleted-dirty`, name each file, write nothing**; keep and report the rest. The upgrader's default would keep edited files that upstream deleted (`managed_content_manifest.py:497, 509`), which in a restructuring leaves them orphaned.
- **Never touches a CLI-owned path** (R §4 lock): `fusebase.json`, `skills-lock.json`, `.claude/hooks/**`, CLI provider skills, `.claude/agents/app-*.md`, `.codex/agents/app-*.md`, MCP config, `.codex/config.toml`, `.codex-plugin/plugin.json`, and the project's `docs/{north-star,audience,product,business-logic}.md` (H WP 12 step 1).
- **The upstream refusal file** (decision 8): upstream keeps `VERSION` and a file of 10 lines or fewer at `hooks/local/upgrade.sh`, so an installed 5.11 engine stops and prints the `flow migrate` command. It lands before `main` reaches a tree without the 5.11 upgrader (`maintainer-tree-split` moves it; owner question B1, asked 2026-10-16: on a `release/6.0` integration branch, before `main` fast-forwards; on `main`, the upgrader move waits for this file's commit in wave 4).
- **The migration report**, written as the first entries of the project's new `ledger.md`: open task ids, cited question ids and the highest T-number (no `--seed-backlog`, decision 8); consumer references to retired Flow files and agent types (H WP 12 step 2), which for the Onboarding repository include the six H names and `scripts/ticket-slice.mjs`, retired at the migration (decision 2); hook wiring per provider.
- **The one named exception to byte-identical project files** (ask 3): the agent keys in the project's `policies/agent-tools.yml` are rewritten from `ai-developer` and `product-owner` to `builder` and `planner` (`agent_tool_profile.py:148, 154` refuse unknown ids).
- **Carried project values:** a 5.11 `validator-free-paths.yml` list goes into `evidence-classes.yml` (ask 11b); the project's baseline rows are merged; the `FLOW:PRESERVE` region of the overlay is carried verbatim inside the CLI's `CUSTOM:SKILL` wrapper (H step 6).
- **Wiring:** when the wiring intent is enabled, exactly the retired handlers' canonical entries are removed (`stop-gate-retirement`); otherwise the settings files are untouched. Ask 9: the owner wires Claude Code in phase 7; Codex stays unwired until its slice.
- **Steps that already exist:** reinstall the three git hooks (step 4a); mint and consume one digest-bound approval for the migration commit through `write-bootstrap-approval.sh` (4b); write `/state/audit/liveness/` into `.git/info/exclude` (decision D).
- Timing: at a phase boundary, on a branch; if 6.0.0 is not ready at the phase 6 to 7 boundary, phase 7 runs on 5.11 (decision 1).

## Decisions and asks carried

Decision 1 (6.0.0; phase 7 on 5.11 if not ready); decision 2 (`ticket-slice.mjs` retired at migration); decision 8 (installer mode, own action table, refusal file, no `--seed-backlog`); ask 3 (key rewrite); ask 9 (wiring); ask 11b (fold); decision D (heartbeat exclude); R §4 lock (never write a CLI-owned path; abort on `changed-by-both` and `upstream-deleted-dirty`).

## Estimate

R §2: 13.5 to 18.5 agent-h (mid 16); the integration is on the critical path (R §2: 12 h step), plus the owner's dry run and one fix round (3 h). Review: independent (upgrade authority over consumer data).

## Depends

Classifier (wave 1): the 5.11 manifests and the fixed core list (R §3 with the second message's 34 hook files). Integration (wave 4): `flow-install-declared-providers` (the install step), `trivial-tier-and-task-ids` (the first commit after migration must pass), `stop-gate-retirement` (retired entries), `seven-policies` (the fold key), `reader-agent-and-dispatch-check` (the renamed agents). Blocks: the tag (the owner's dry run is an acceptance item, H §7).

## Acceptance

On a fixture project built from a 5.11 install plus CLI-owned assets and project edits (H WP 12, with R's counts):
1. After `flow migrate`, the Flow-owned files are the 53 core files plus the declared mirrors; plan proposal: they equal a fresh `flow install` for the same providers, byte for byte.
2. The sha256 of every CLI-owned file is unchanged against `audit/cli-vendor-manifest.json`; every project-owned file is byte-identical except the `agent-tools.yml` key rewrite.
3. A planted project edit inside a Flow-owned file aborts the run with the file named, and nothing is written.
4. `git status` shows only Flow-owned removals and additions; the first commit after migration passes the new pre-commit; `git checkout` of the pre-migration commit restores the old tree in one step; a second run changes nothing.
5. The owner's dry run of the Onboarding repository lists no CLI-owned or project-owned path for removal and lists the consumer references (H WP 12); its report is attached to the release note.

## Wave split

- **Wave 1:** the classifier and the dry-run inventory with its fixtures (Python, local); no install step.
- **Wave 4:** the install and replace steps, the report, the wiring cleanup, the approval mint, the refusal file if not already landed, and the end-to-end fixture (hosted `migrate` group, new).
- **Wave 5:** the owner's dry run on the Onboarding repository.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
