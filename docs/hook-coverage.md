# Hook coverage matrix — Fusebase Flow Local v0.1

Lists every Fusebase Flow lifecycle hook handler and which provider / fallback surface invokes it.

## Coverage table

| Hook handler | Anthropic Claude Code | OpenAI / ChatGPT Codex | Git fallback | Local script | Status |
|---|---|---|---|---|---|
| `session_start` | yes (`SessionStart`) | yes (`session_start`) | n/a | `preflight.sh` runs equivalent checks | implemented |
| `user_prompt_submit` | yes (`UserPromptSubmit`) | yes (`user_prompt_submit`) | n/a | n/a | implemented |
| `pre_tool_use` | yes (`PreToolUse`; matchers: Bash, Edit, Write, MultiEdit) | yes (`pre_tool_use`; matchers: Bash, Edit, Write, MultiEdit) | partial (`pre-commit` blocks at commit time) | n/a | implemented |
| `permission_request` | reserved (returned `ask` decision honored when host invokes) | yes (`permission_request`) | n/a | `approve-local.sh` authors approval artifacts the handler reads | implemented |
| `post_tool_use` | yes (`PostToolUse`; matchers: Edit, Write, MultiEdit) | yes (`post_tool_use`; matchers: Edit, Write, MultiEdit) | n/a | n/a | implemented |
| `stop` | yes (`Stop`) | yes (`stop`) | partial (`verify-gate.sh` checks pasted gate report shape) | `verify-gate.sh` for ad-hoc validation | implemented |
| `task_complete` | n/a (Stop covers this) | n/a (stop covers this) | n/a | `task_complete.py` runnable directly when host emits it | implemented |
| `pre_compact` | yes (`PreCompact`) | reserved (host-dependent) | n/a | n/a | implemented |

## Surface notes

- **Cursor** has no native lifecycle-hook surface in v0.1. Enforcement on Cursor sessions falls back to git hooks (`pre-commit`, `commit-msg`) and operator vigilance.
- **GitHub Copilot / VS Code** has no native lifecycle-hook surface in v0.1 for arbitrary command interception. Same fallback as Cursor.
- **Gemini-style IDE agents** have no documented lifecycle-hook surface in v0.1. Same fallback.
- **Generic local repo workflow** uses git fallback hooks only; no provider event integration.

## Hook event protocol

All handlers read a JSON event from stdin matching `flow_hook_event.schema.json` and write a JSON decision to stdout. Hosts that read exit codes also receive `0` (allow), `2` (deny), or `1` (handler error).

## Test coverage

11 deterministic fixtures at `hooks/tests/fixtures/*.json`, runner at `hooks/tests/run-tests.sh`. Latest run output is written to `state/audit/hook-test-results.md` (gitignored runtime path) and uploaded by the GitHub Action as the `fusebase-flow-audit` workflow artifact. Coverage matrix:

| Test | Hook tested | Decision |
|---|---|---|
| 01 | `pre_tool_use` | deny `rm -rf` |
| 02 | `pre_tool_use` | deny `git add .` |
| 03 | `pre_tool_use` | deny `git add -A` |
| 04 | `pre_tool_use` | deny `git reset --hard` |
| 05 | `pre_tool_use` | deny `--no-verify` |
| 06 | `pre_tool_use` | deny `.env` write |
| 07 | `pre_tool_use` | deny deployment-config edit (protected path) |
| 08 | `pre_tool_use` | allow `git status --short` |
| 09 | `stop` | deny "implementation complete" without gate evidence |
| 10 | `user_prompt_submit` | warn on pasted GitHub PAT |
| 11 | `pre_tool_use` | deny write that introduces `sk-ant-*` value |

## Audit-log integration

Every hook execution appends a JSONL record to `state/audit.log.jsonl` (gitignored) with: timestamp, event, decision, reason, rule_id, session_id, host_tool, plus event-specific extras. Operators can grep / aggregate audit log post-hoc.

## Last amended

```
2026-05-08 — Phase 4; added GitHub Action verification of hook tests + preflight.
```
