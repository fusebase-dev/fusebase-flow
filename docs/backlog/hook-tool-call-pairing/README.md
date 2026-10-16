# hook-tool-call-pairing

**Status:** folded into `audit-line-command-hash` (6.0.0 WP 11, 2026-10-16); unpaired calls are listed by `heartbeat-reader`. **Filed:** 2026-10-15 (consumer handoff 2026-10-14 A3 item 6; `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** low (observability only). **Surface:** `hooks/handlers/{pre_tool_use,post_tool_use}.py` + audit logger (FR-07), `.claude/settings.json.example`, `settings-json-merge.py`, health-check event counts.

## Ask

Wire `PostToolUseFailure` to the same audit line as `PostToolUse` and record `tool_use_id` / `agent_id` (documented in Claude Code hook input) so an in-flight call is visible as an unpaired PreToolUse. Deferred in v5.11: nothing reads the pairing yet; it adds a handler spawn per Bash/PowerShell call (~1 s on MSYS, up to 16 concurrent Workflow agents); every wired consumer would report lifecycle-event drift until `settings-json-merge.py` and both health engines move in lockstep.

## Acceptance

A failed Bash call writes an audit line with `tool_use_id`; a watcher can list unpaired calls older than N min; health engines and merge stay in lockstep (two-engine rule); no per-call `git` spawn.
