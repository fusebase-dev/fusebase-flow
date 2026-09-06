#!/usr/bin/env bash

run_precommit_validators() {
    local root="$1" original_path="$2" lint_cmd typecheck_cmd reuse temp
    lint_cmd="${FUSEBASE_FLOW_LINT:-}"
    typecheck_cmd="${FUSEBASE_FLOW_TYPECHECK:-}"
    [ -n "$lint_cmd" ] || ! grep -q '"lint"' "$root/package.json" 2>/dev/null || lint_cmd="npm run -s lint"
    [ -n "$typecheck_cmd" ] || ! grep -q '"typecheck"' "$root/package.json" 2>/dev/null || typecheck_cmd="npm run -s typecheck"

    reuse=0
    temp="$(mktemp -d 2>/dev/null || mktemp -d -t ff-validator-evidence)"
    if [ -n "$lint_cmd$typecheck_cmd" ] && [ -d "$temp" ] \
       && git -C "$root" show HEAD:hooks/local/lib/validator-evidence.py > "$temp/validator-evidence.py" 2>/dev/null; then
        FFVE_ORIGINAL_PATH="$original_path" PYTHONPATH="$temp" \
          python3 -I -S "$temp/validator-evidence.py" verify --root "$root" \
            --lint "$lint_cmd" --typecheck "$typecheck_cmd" >/dev/null 2>&1 && reuse=1
    fi
    rm -rf "$temp"

    if [ "$reuse" -eq 1 ]; then
        echo "[fusebase-flow:pre-commit] reusing authentic exact-state lint/typecheck evidence" >&2
        return 0
    fi
    if [ -n "$lint_cmd" ]; then
        echo "[fusebase-flow:pre-commit] running lint: $lint_cmd" >&2
        if ! eval "$lint_cmd"; then
            echo "[fusebase-flow:pre-commit] BLOCK — lint failed (FR-13)." >&2
            return 1
        fi
    fi
    if [ -n "$typecheck_cmd" ]; then
        echo "[fusebase-flow:pre-commit] running typecheck: $typecheck_cmd" >&2
        if ! eval "$typecheck_cmd"; then
            echo "[fusebase-flow:pre-commit] BLOCK — typecheck failed (FR-13)." >&2
            return 1
        fi
    fi
}
