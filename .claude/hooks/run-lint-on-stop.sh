#!/usr/bin/env bash
# DEPRECATED (Fusebase Flow v3.2.0 / B5): this jq+bash Stop hook is no longer
# wired by .claude/settings.json.example. It fails out-of-the-box on Windows,
# where `jq` and bash are typically absent. It is kept on disk for one release
# so downstream projects that still reference it keep working; new installs
# should rely on the cross-platform node Stop hooks instead. There is currently
# no node lint hook, so a project that wants lint-on-stop can re-wire this file
# (after installing jq + bash) or add its own node lint hook.
#
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
