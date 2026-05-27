#!/usr/bin/env bash
# Claude Code Stop hook: run lint before allowing Claude to stop.
# If lint fails, block stop and pass lint output as reason so Claude continues and fixes.
# See https://code.claude.com/docs/en/hooks

LINT_OUTPUT=$(npm run lint 2>&1) || LINT_EXIT=$?
if [ -z "${LINT_EXIT:-}" ]; then
  exit 0
fi
# Lint failed: stdout must be only JSON so Claude Code can parse it
jq -n --arg out "$LINT_OUTPUT" '{decision: "block", reason: ("Lint failed. Fix the following and try again:\n\n" + $out)}'
exit 0
