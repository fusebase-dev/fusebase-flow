# reader-agent-and-dispatch-check

**Status:** open — 6.0.0 rebuild, **wave 3**. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 4 (R §2). **Surface:** `agents/` (2 canonical agents today, both `tools: Read, Glob, Grep, Bash, Write, Edit`, `agents/ai-developer/AGENT.md:4`, `agents/product-owner/AGENT.md:4`), `agents/reader/AGENT.md` (new), `hooks/local/lib/agent_tool_profile.py` (core row 29), the provider agent mirrors, possibly `hooks/handlers/pre_tool_use.py`. **FR-07:** yes only if the Claude Code arm edits `hooks/handlers/**` (`policies/protected-paths.yml:91`); `agents/**` and `hooks/local/**` are not protected.

## Delivers

- **Three canonical agents, two roles** (D §2 row 3): `agents/planner/AGENT.md` and `agents/builder/AGENT.md` (renamed from `product-owner` and `ai-developer`, ask 3) and `agents/reader/AGENT.md` with `tools: Read, Glob, Grep`. A reader cannot be derived by subtraction, because 5.11's profile variants only add tools to a canonical agent.
- **The reader can never be given a write or shell tool.** Today `agent_tool_profile.py` refuses only `AskUserQuestion`, `Agent` and `Task` (`:29`), so a project profile could give the reader `Write`. The core refuses `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `Bash` and `PowerShell` for the reader (R §4 lock).
- **The verdict-dispatch check: new code.** 5.11 generates variants and runs nothing at dispatch time (R §5b row 6). A dispatch of a reviewer, skeptic or verdict writer as any agent other than reader fails. Where the check sits (the gate and brief path, a `pre_tool_use` branch on the Agent tool, or both) is this WP's plan; the provider-neutral arm is required (H non-negotiable 12).
- **Codex reader** (decision 9): a separate `codex exec -s read-only --output-schema … -o state/returns/<slice>-<role>.json "<brief>"` process under `bounded-run`; the CLI writes the typed verdict file and the planner records it. An in-session Codex subagent used as reader prints `profile unenforced on codex` and is never recorded as a non-builder verdict.
- **Codex agent mirrors** are TOML, planner and builder only (decision 5e); there is no reader TOML.
- Self-attestation and the footer leave (decision 10a): the profile recorded at dispatch, plus the verdict agent's id in the ledger, is the role anchor.

## Decisions and asks carried

| Item | Effect here |
|---|---|
| Ask 3 (rename to planner and builder) | Agent directories and fixture names; `flow-migrate` rewrites the project's `agent-tools.yml` keys (the one named exception) |
| Decision 9 (Codex reader, polled boundary, "Codex: unproven") | The `codex exec` path; the five probes run in phase 7 (`provider-coverage-proof`) |
| Decision 10a | Profile at dispatch replaces attestation |
| Decision 5e | TOML planner and builder only |
| R §4 lock (the reader has no write or shell tool; no project profile can add one) | The refusal |
| Fixture departure (agent rename) | `hooks/tests/test-agent-tool-profile.py` rows naming `ai-developer` and `product-owner` re-point; no assertion changes |

## Estimate

R §2: 8.5 to 10.5 agent-h (mid 9.5); on the critical path (10 h step with review). Review: independent (security boundary).

## Depends

`slice-gate` (gate output), `task-slicer` (`--brief`), the WP 11 handler edits (`audit-line-command-hash`, `stop-gate-retirement`: same handler files, so serialize after them), `core-hook-inventory` (the helper copy into row 29 lands first); decision 9. Blocks: `six-skills-and-optional-pack` final (verify text), `flow-install-declared-providers` (inventory).

## Acceptance

1. A dispatch of a reviewer, skeptic or verdict writer as any agent other than reader fails the check, with a fixture proving it (H WP 4).
2. The reader agent's frontmatter carries no write tool (lint fixture); a project profile adding `Write` or `Bash` to the reader is refused (fixture).
3. A Codex dry run of an in-session reader prints `profile unenforced on codex`; a stub `codex` binary proves the `exec` reader writes `state/returns/<slice>-<role>.json` under `bounded-run`.
4. The kept 5.11 tool-profile fixtures pass with only the named rename departure.
5. No Flow text names a model (H non-negotiable 6).

## Wave split

Wave 3, after the gate and the slicer exist. Nothing in wave 1.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3, §13; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
