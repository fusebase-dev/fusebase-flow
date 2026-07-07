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

# --- interpreter resolution ---------------------------------------------------------
# A candidate is only accepted if it is a REAL, WORKING Python 3. Two traps on Windows:
#   - Microsoft Store "App Execution Alias" stubs (python.exe/python3.exe under
#     .../WindowsApps/) satisfy `command -v python3` on a stock machine before Python is
#     installed, but running them does NOT run Python (they open the Store / exit nonzero).
#     Accepting one re-creates the per-event error this wrapper exists to remove.
#   - a bare `python` may be Python 2 (handlers are py3 -> SyntaxError every event).
# We pick the resolved command into an ARRAY so a space-containing path
# (C:\Program Files\PythonXY\python.exe) and a multi-word launcher ("py -3") both work.
_ff_is_store_stub() {  # $1 = command name; true if it resolves under WindowsApps (alias stub)
    case "$(command -v "$1" 2>/dev/null)" in *[/\\]WindowsApps[/\\]*) return 0 ;; esac
    return 1
}
_ff_is_py3() {  # runs the candidate as an interpreter; true iff it is a working Python >= 3
    "$@" -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" >/dev/null 2>&1
}

FF_PY_CMD=()
# 1. Explicit override: accept a whole-string executable (handles spaces) OR a multi-word
#    launcher; verify it is really py3. If set but unusable, WARN (never silently ignore).
if [ -n "${FUSEBASE_FLOW_PYTHON:-}" ]; then
    if command -v "$FUSEBASE_FLOW_PYTHON" >/dev/null 2>&1 && _ff_is_py3 "$FUSEBASE_FLOW_PYTHON"; then
        FF_PY_CMD=("$FUSEBASE_FLOW_PYTHON")
    elif command -v "${FUSEBASE_FLOW_PYTHON%% *}" >/dev/null 2>&1; then
        read -r -a _ff_ovr <<< "$FUSEBASE_FLOW_PYTHON"
        _ff_is_py3 "${_ff_ovr[@]}" && FF_PY_CMD=("${_ff_ovr[@]}")
    fi
    if [ ${#FF_PY_CMD[@]} -eq 0 ]; then
        echo "[fusebase-flow:run-handler] FUSEBASE_FLOW_PYTHON='$FUSEBASE_FLOW_PYTHON' is not a working Python 3 -- falling back to auto-detect." >&2
    fi
fi
# 2. Auto-detect: skip Store alias stubs; `py -3` forces py3; verify a bare `python` is py3.
if [ ${#FF_PY_CMD[@]} -eq 0 ]; then
    if command -v python3 >/dev/null 2>&1 && ! _ff_is_store_stub python3; then FF_PY_CMD=(python3)
    elif command -v py >/dev/null 2>&1; then FF_PY_CMD=(py -3)
    elif command -v python >/dev/null 2>&1 && ! _ff_is_store_stub python && _ff_is_py3 python; then FF_PY_CMD=(python)
    fi
fi

if [ ${#FF_PY_CMD[@]} -eq 0 ]; then
    # No WORKING interpreter. Emit ONE warning -- routed to the lowest-frequency event
    # (SessionStart) and silent on the high-frequency ones (Pre/PostToolUse, ...) so a
    # python-less machine sees a single clear message, not one per tool call. The warning
    # MUST go to stderr: stdout may be parsed as a hook decision.
    case "$HANDLER" in
        *session_start.py)
            echo "[fusebase-flow] No working Python 3 found (checked python3 / py / python; Microsoft Store alias stubs and Python 2 are rejected) -- Fusebase Flow lifecycle hooks are DISABLED for this session. Install Python 3.11+ or set FUSEBASE_FLOW_PYTHON to your interpreter. (Git fallback hooks still enforce protected paths and secrets.)" >&2
            ;;
    esac
    exit 0
fi

if [ ! -f "$HANDLER" ]; then
    echo "[fusebase-flow:run-handler] handler not found: $HANDLER -- skipping (allow)." >&2
    exit 0
fi

# Run the handler under the resolved interpreter, passing stdin through and propagating
# its EXACT exit code. Array expansion keeps a space-containing path intact and a
# multi-word launcher split correctly; the handler path stays a single quoted arg.
exec "${FF_PY_CMD[@]}" "$HANDLER"
