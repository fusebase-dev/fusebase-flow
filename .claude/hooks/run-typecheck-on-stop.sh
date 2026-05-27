#!/usr/bin/env bash
# Claude Code Stop hook: run TypeScript typecheck across apps before allowing stop.
# Mirrors deploy-time tsc (without Vite). See run-typecheck-apps.js.
# See https://code.claude.com/docs/en/hooks

TYPECHECK_OUTPUT=$(npm run typecheck 2>&1) || TYPECHECK_EXIT=$?
if [ -z "${TYPECHECK_EXIT:-}" ]; then
  exit 0
fi
jq -n --arg out "$TYPECHECK_OUTPUT" '{decision: "block", reason: ("Typecheck failed. Fix the following and try again:\n\n" + $out)}'
exit 0
