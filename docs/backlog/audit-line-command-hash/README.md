# audit-line-command-hash

**Status:** open — 6.0.0 rebuild, **wave 1**. Folds in `hook-tool-call-pairing`. **Filed:** 2026-10-16 (owner accepted the rebuild reply; `docs/changes/2026-10-16-v600-minimal-core.md`). **Work package:** WP 11, audit line (R §2). **Surface:** `hooks/handlers/post_tool_use.py` (core row 22), `hooks/handlers/pre_tool_use.py` (row 21), `.claude/settings.json.example` (`:45`, `:56`), `.codex/hooks.json.example`, the maintainer merge script `hooks/local/fusebase-flow-overlays/settings-json-merge.py` (event map `:22-29`) and the two health engines in lockstep. **FR-07:** yes (`hooks/handlers/**`, `policies/protected-paths.yml:91`).

## Delivers

- **A Bash and PowerShell arm in `post_tool_use.py`** (D:27, which wins over H's "Bash arm", R §5a row 2): the audit line carries the time, the tool name, `tool_use_id`, `agent_id` and the sha256 of the command string, nothing else, and starts no git process. Today the handler serves edit tools only (`post_tool_use.py:24, 41`) and runs a `git status --short` per event (`:84`). The edit arm is unchanged.
- **One file, two events:** the same handler serves `PostToolUseFailure` by reading the event name; there is no `post_tool_use_failure.py` (R §5b row 7).
- **Start-of-call identifiers:** the `pre_tool_use` allow line (`pre_tool_use.py:171`) gains `tool_use_id`, `agent_id` and the command hash, so an in-flight call shows as an unpaired start.
- **No command text in the log** (H non-negotiable 9): a deny reason can embed the exact command (`hooks/shared/denial_message.py:105`), and the handler logs that reason (`pre_tool_use.py:75-79`). The logged reason carries the hash instead; what the agent sees on stdout and stderr is unchanged.
- **Wiring examples:** Claude Code `PostToolUse` and `PostToolUseFailure` on `Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit` (today `:56` lists edit tools only). `.codex/hooks.json.example` is rewritten to the documented schema (PascalCase events, a `matcher` regex, `hooks[]` of `{type, command, timeout}`), keeping only `PreToolUse` and `PostToolUse` (decision 9). On Codex the shell arm is unproven, the edit arm is not enforced (Codex routes edits as `apply_patch`, which Flow's matchers do not recognise), and there is no failure event.
- The merge script's event map gains `PostToolUseFailure`, changed in lockstep with both health engines (the two-engine rule from `hook-tool-call-pairing`).

## Decisions and asks carried

| Item | Effect here |
|---|---|
| H non-negotiable 9 (log identifiers and a hash, never the command) | Both arms; the deny-reason hash |
| Decision 9 (Codex rows "unproven"; documented hook schema) | The Codex example and its labels |
| Ask 9 (wire Claude Code hooks in phase 7; Codex unwired until its slice) | The audit line is the reader's fourth signal from phase 7 |
| R §6 (O22 shipped as T164) | The two kept handlers already reply in the host's format: no reply-format work |
| R §4 lock (kernel byte-identical) | `hooks/shared/` untouched here; the hash is computed in the handlers |

## Estimate

Share of R §2 WP 11 (21.5 to 29.5 agent-h for the four WP 11 entries): 4.5 to 6.5 (mid 5.5), including the Codex example rewrite. Review: independent (security boundary).

## Depends

The decision table (answered). Serialize with `stop-gate-retirement` (same example and merge files) and before `reader-agent-and-dispatch-check` (same handler files). Blocks: `heartbeat-reader` (the fourth signal and repeat counts).

## Acceptance

1. A Bash and a PowerShell call each write one audit line with time, tool name, `tool_use_id`, `agent_id` and `cmd_sha256`, and no command text; a planted secret in the command never reaches the log (new fixtures; no 5.11 fixture targets `post_tool_use`).
2. The Bash arm starts no git process (fixture).
3. A failed call delivered as `PostToolUseFailure` writes the same line.
4. The kept `pre_tool_use` fixtures pass with unchanged verdicts and exit codes (`run_hook_tests.py`), and `test-command-policy-denial-message.sh` passes unchanged (hosted `fixtures`, `denial-message`).
5. The merge script and both health engines agree on the event set (hosted `wire-hooks-beside`, `hook-wiring-intent`, `cli-0259`).
6. `hook-tool-call-pairing` closes: its acceptance (a failed call is logged with `tool_use_id`; no per-call git spawn; engines in lockstep) is met here, and the "list unpaired calls older than N min" part is the reader's.

## Wave split

Wave 1, two commits planned: (a) the handler changes with their fixtures (one FR-07 approval); (b) the example files, the merge map and the engines in lockstep (not FR-07, maintainer side). Nothing deferred.

Sources: R = the Flow team's reply of 2026-10-16 (`flow-team-reply-rebuild-2026-10-16.md` beside the handoff, H:187); D = `flow-minimal-core-2026-10-15.md` rev 3; H = `flow-handoff-2026-10-15-minimal-core.md` rev 2; the owner's two messages of 2026-10-16 are in `docs/changes/2026-10-16-v600-minimal-core.md`. Tree lines at `main` `4daa771c`.
