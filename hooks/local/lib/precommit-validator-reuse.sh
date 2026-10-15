#!/usr/bin/env bash
# Fixed path and 2-arg call (ROOT ORIGINAL_PATH; arg 2 unused): installed .git/hooks/pre-commit copies source this file.

run_precommit_validators() {
    local root="$1" lint_cmd typecheck_cmd rc
    lint_cmd="${FUSEBASE_FLOW_LINT:-}"
    typecheck_cmd="${FUSEBASE_FLOW_TYPECHECK:-}"
    [ -n "$lint_cmd" ] || ! grep -q '"lint"' "$root/package.json" 2>/dev/null || lint_cmd="npm run -s lint"
    [ -n "$typecheck_cmd" ] || ! grep -q '"typecheck"' "$root/package.json" 2>/dev/null || typecheck_cmd="npm run -s typecheck"

    if [ -n "$lint_cmd" ]; then
        echo "[fusebase-flow:pre-commit] running lint: $lint_cmd" >&2
        rc=0; eval "$lint_cmd" || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "[fusebase-flow:pre-commit] BLOCK — lint failed (FR-13): your project's command \"$lint_cmd\" exited $rc; its output is above. Flow runs it before each commit; the failure is in the project, not in Flow." >&2
            return 1
        fi
    fi
    if [ -n "$typecheck_cmd" ]; then
        echo "[fusebase-flow:pre-commit] running typecheck: $typecheck_cmd" >&2
        rc=0; eval "$typecheck_cmd" || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "[fusebase-flow:pre-commit] BLOCK — typecheck failed (FR-13): your project's command \"$typecheck_cmd\" exited $rc; its output is above. Flow runs it before each commit; the failure is in the project, not in Flow." >&2
            return 1
        fi
    fi
}
