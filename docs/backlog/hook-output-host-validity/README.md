# hook-output-host-validity

**Status:** partly done in v5.11 (four handlers); `stop.py`, `pre_compact.py`, `permission_request.py` remain. **Filed:** 2026-10-15 (operator decision 8; `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** medium (Stop warns never reach the model; Stop denies still block). **Surface:** `hooks/handlers/stop.py`, `pre_compact.py`, `permission_request.py` (FR-07, protected); `hooks/tests/run_hook_tests.py` `_HOST_EVENT`.

## Why

Claude Code rejects a hook reply whose top-level `decision` is not `"block"` ('Hook JSON output validation failed' → a 'hook error' notice, the output dropped). v5.11 O22 fixed `pre_tool_use`, `user_prompt_submit`, `post_tool_use` and `session_start` (`docs/hook-coverage.md` § Host output shape). `stop.py` still prints `decision` allow/warn/deny (rejected the same way); `pre_compact.py` prints `decision: allow` on every `PreCompact`; `permission_request.py` is not wired for Claude Code, where a deny needs `hookSpecificOutput.decision.behavior`.

## Ask

- `stop.py`: deferred to the minimal-core rebuild, which retires the Stop gate. If Stop survives it, move the verdict to `flow_decision` (top-level `decision` only as `"block"` on deny) and add `stop.py` to `_HOST_EVENT`.
- `pre_compact.py`: `decision` → `flow_decision` (one line).
- `permission_request.py`: emit `hookSpecificOutput.decision.behavior` before it is wired for Claude Code.
- Acceptance: fixtures keep their verdicts; one wired consumer session shows no 'hook error' notice.
