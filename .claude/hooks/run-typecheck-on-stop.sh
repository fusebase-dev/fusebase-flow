#!/usr/bin/env bash
# DEPRECATED (Fusebase Flow v3.2.0 / B5): this jq+bash Stop hook is no longer
# wired by .claude/settings.json.example. It fails out-of-the-box on Windows,
# where `jq` and bash are typically absent. Use the cross-platform node hook
# `run-typecheck-apps.js` instead — it carries the CVE-2024-27980 shell:win32
# patch and fully covers typecheck. This file is kept on disk for one release
# so downstream projects that still reference it keep working.
#
# Claude Code Stop hook: run TypeScript typecheck across apps before allowing stop.
# Mirrors deploy-time tsc (without Vite). See run-typecheck-apps.js.
# See https://code.claude.com/docs/en/hooks

TYPECHECK_OUTPUT=$(npm run typecheck 2>&1) || TYPECHECK_EXIT=$?
if [ -z "${TYPECHECK_EXIT:-}" ]; then
  exit 0
fi
jq -n --arg out "$TYPECHECK_OUTPUT" '{decision: "block", reason: ("Typecheck failed. Fix the following and try again:\n\n" + $out)}'
exit 0
