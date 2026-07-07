#!/usr/bin/env bash
# Fusebase Flow -- lifecycle hook wrapper: interpreter resolver + graceful self-degrade.
# fusebase-flow-managed-hook: v1
#
# WHY: .claude/settings.json wires lifecycle hooks as `python3 .../handler.py`. On a
# machine WITHOUT python3 (a fresh clone before Python is installed), Claude Code runs
# that command on EVERY lifecycle event and surfaces a "command not found" error each
# time (SessionStart, every PreToolUse/PostToolUse, Stop, ...). This wrapper resolves
# whatever Python interpreter exists and, when none does, emits ONE clear warning and
# exits 0 (allow) so the hooks self-disable quietly instead of erroring on every event.
# The git fallback hooks still enforce protected paths + secrets, so nothing security-
# critical depends on this wrapper (it is a UX/consistency layer, not an enforcement one).
#
# CONTRACT: invoked as
#     bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/<stem>.py
# Passing the FULL handler path (not a bare stem) is DELIBERATE: it keeps the literal
# substring `hooks/handlers/<stem>.py` inside the settings.json command, which
# settings-json-merge.py and fusebase-flow-health-check.sh both grep for to recognize a
# wired Flow hook. Do NOT shorten it to a stem -- that would break drift detection.
#
# Interpreter resolution order: $FUSEBASE_FLOW_PYTHON (override) -> python3 -> py -3 ->
# python. stdin is passed through untouched; the handler's stdout and EXACT exit code are
# propagated (0=allow, 2=deny, ... -- see hooks/README.md). A missing interpreter NEVER
# flattens a real deny: we only exit 0 when we did NOT run the handler at all.

set -uo pipefail

HANDLER="${1:-}"
if [ -z "$HANDLER" ]; then
    # Our own misconfiguration must never block a session.
    echo "[fusebase-flow:run-handler] no handler path argument given -- skipping (allow)." >&2
    exit 0
fi

# Resolve an interpreter. The override may itself be multi-word ("py -3"), so probe only
# its first token for existence.
FF_PY=""
if [ -n "${FUSEBASE_FLOW_PYTHON:-}" ] && command -v "${FUSEBASE_FLOW_PYTHON%% *}" >/dev/null 2>&1; then
    FF_PY="$FUSEBASE_FLOW_PYTHON"
elif command -v python3 >/dev/null 2>&1; then
    FF_PY="python3"
elif command -v py >/dev/null 2>&1; then
    FF_PY="py -3"
elif command -v python >/dev/null 2>&1; then
    FF_PY="python"
fi

if [ -z "$FF_PY" ]; then
    # No interpreter found. Emit ONE warning -- routed to the lowest-frequency event
    # (SessionStart) and silent on the high-frequency ones (Pre/PostToolUse, ...) so a
    # python-less machine sees a single clear message, not one per tool call. The warning
    # MUST go to stderr: stdout may be parsed as a hook decision.
    case "$HANDLER" in
        *session_start.py)
            echo "[fusebase-flow] Python 3 not found on PATH -- Fusebase Flow lifecycle hooks are DISABLED for this session. Install Python 3.11+ or set FUSEBASE_FLOW_PYTHON to your interpreter. (Git fallback hooks still enforce protected paths and secrets.)" >&2
            ;;
    esac
    exit 0
fi

if [ ! -f "$HANDLER" ]; then
    echo "[fusebase-flow:run-handler] handler not found: $HANDLER -- skipping (allow)." >&2
    exit 0
fi

# Run the handler under the resolved interpreter, passing stdin through and propagating
# its EXACT exit code. $FF_PY is intentionally unquoted so "py -3" word-splits into
# launcher + flag; the handler path stays quoted.
exec $FF_PY "$HANDLER"
