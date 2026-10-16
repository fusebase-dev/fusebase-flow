#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t validator-evidence)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "PASS: validator-evidence $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: validator-evidence $1 ($2)"; }
to_command_path() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }

new_fixture() {
    local tool="$TMP/$1/validator.py"
    D="$TMP/$1/repo"
    COUNT="$TMP/$1/count"
    OUT="$TMP/$1/out"
    mkdir -p "$D/hooks/git" "$D/hooks/local/lib" "$D/hooks/shared" "$D/policies" "$COUNT"
    cp "$ROOT/hooks/git/pre-commit" "$D/hooks/git/pre-commit"
    cp "$ROOT/hooks/local/lib/precommit-validator-reuse.sh" "$D/hooks/local/lib/precommit-validator-reuse.sh"
    cp "$ROOT/hooks/local/lib/validator_tier.py" "$D/hooks/local/lib/validator_tier.py"
    cp "$ROOT"/hooks/shared/*.py "$D/hooks/shared/"
    cp "$ROOT"/policies/*.yml "$D/policies/"
    rm -f "$D/policies/validator-free-paths.yml"
    [ "$#" -lt 2 ] || { printf 'schema_version: 1\nvalidator_free_paths:\n'; printf '  - "%s"\n' "${@:2}"; } \
        > "$D/policies/validator-free-paths.yml"
    cat > "$tool" <<'PY'
import os
import pathlib
import sys

kind = sys.argv[1]
path = pathlib.Path(os.environ["FUSEBASE_FLOW_TEST_COUNT_DIR"]) / kind
with path.open("a", encoding="utf-8") as handle:
    handle.write("x")
raise SystemExit(1 if os.environ.get("FUSEBASE_FLOW_TEST_FAIL") == kind else 0)
PY
    LINT="python3 $(to_command_path "$tool") lint"
    TYPECHECK="python3 $(to_command_path "$tool") typecheck"
    printf 'base\n' > "$D/src.txt"
    ( cd "$D" && git init -q && git config user.email fixture@example.test \
      && git config user.name fixture && git add -- hooks policies src.txt \
      && git commit -qm base )
    printf 'change\n' >> "$D/src.txt"
    ( cd "$D" && git add -- src.txt )
}

in_fixture() {
    local failing="$1"
    shift
    ( cd "$D" && env FUSEBASE_FLOW_LINT="$LINT" FUSEBASE_FLOW_TYPECHECK="$TYPECHECK" \
        FUSEBASE_FLOW_TEST_COUNT_DIR="$(to_command_path "$COUNT")" \
        FUSEBASE_FLOW_TEST_FAIL="$failing" "$@" ) >"$OUT" 2>&1
}

run_hook() { in_fixture "${1:-}" bash hooks/git/pre-commit; }

count_of() {
    [ -f "$COUNT/$1" ] && wc -c < "$COUNT/$1" | tr -d ' ' || printf 0
}

check() {
    local name="$1" rc="$2" want="$3" lint="$4" typecheck="$5" mode="$6" text="$7" rc_ok=1
    if [ "$want" = 0 ]; then [ "$rc" -eq 0 ] || rc_ok=0; else [ "$rc" -ne 0 ] || rc_ok=0; fi
    if [ "$rc_ok" -eq 1 ] && [ "$(count_of lint)" = "$lint" ] \
       && [ "$(count_of typecheck)" = "$typecheck" ] && grep -q "$mode" -- "$text" "$OUT"; then
        ok "$name"
    else
        bad "$name" "rc=$rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
}

stage_only() {
    local f
    mkdir -p "$D/docs"
    for f in "$@"; do [ -f "$D/$f" ] || printf 'doc\n' > "$D/$f"; done
    ( cd "$D" && git reset -q -- src.txt && git add -- "$@" )
}

stages_of() {
    sed -n 's/^\[fusebase-flow:pre-commit\] stage=\([a-z-]*\) elapsed=[0-9][0-9]*\.[0-9][0-9]s$/\1/p' "$OUT" | tr '\n' ' '
}

new_fixture once
run_hook; check once-per-commit-runs-lint-and-typecheck-once "$?" 0 1 1 -F "all checks passed"
stages="$(stages_of)"
if [ "$stages" = "secret-scan protected-paths module-size validators " ]; then ok "stage-timings-print-each-stage-in-order"
else bad "stage-timings-print-each-stage-in-order" "stages=[$stages]"; fi

new_fixture lint-failure
run_hook lint; check lint-failure-blocks-with-t117-text "$?" nonzero 1 0 -F \
  "lint failed (FR-13): your project's command \"$LINT\" exited 1; its output is above. Flow runs it before each commit; the failure is in the project, not in Flow."
if grep -q "stage=validators elapsed=" "$OUT"; then ok "stage-timing-printed-when-validators-block"
else bad "stage-timing-printed-when-validators-block" "no validators timing line"; fi

new_fixture typecheck-failure
run_hook typecheck; check typecheck-failure-blocks-with-t117-text "$?" nonzero 1 1 -F \
  "typecheck failed (FR-13): your project's command \"$TYPECHECK\" exited 1; its output is above. Flow runs it before each commit; the failure is in the project, not in Flow."

new_fixture helper-absent
rm -f "$D/hooks/local/lib/precommit-validator-reuse.sh"
run_hook; check helper-absent-blocks-before-validators "$?" nonzero 0 0 -E "BLOCK.*missing"
if grep -qF -- "--repair-managed hooks/local/lib/precommit-validator-reuse.sh" "$OUT" \
   && grep -qF "NEVER use --no-verify" "$OUT"; then ok "helper-absent-names-repair-command"
else bad "helper-absent-names-repair-command" "$(tr '\n' '|' < "$OUT")"; fi

now_def="$(grep -m1 '^_ffpc_now() ' "$ROOT/hooks/git/pre-commit")"
comma_us="$(bash -c 'unset EPOCHREALTIME; EPOCHREALTIME="1700000000,250000"; eval "$1"; _ffpc_now; echo "$FFPC_NOW_US"' _ "$now_def")"
if [ "$comma_us" = "1700000000250000" ]; then ok "stage-clock-strips-decimal-comma"
else bad "stage-clock-strips-decimal-comma" "got [$comma_us] from [$now_def]"; fi
fallback_us="$(bash -c 'unset EPOCHREALTIME; SECONDS=7; eval "$1"; _ffpc_now; echo "$FFPC_NOW_US"' _ "$now_def")"
case "$fallback_us" in
    7000000|8000000) ok "stage-clock-falls-back-to-seconds" ;;
    *) bad "stage-clock-falls-back-to-seconds" "got [$fallback_us]" ;;
esac

new_fixture helper-two-arg-call
in_fixture "" bash -c '. hooks/local/lib/precommit-validator-reuse.sh; run_precommit_validators "$PWD" "$PATH"'
check helper-two-arg-call-runs-each-once "$?" 0 1 1 -F "running typecheck"

new_fixture secret
printf 'blocked\n' > "$D/.env"
( cd "$D" && git add -- .env )
run_hook; check secret-check-remains-live "$?" nonzero 0 0 -F "secret-like files staged"

new_fixture protected
printf '\n' >> "$D/hooks/git/pre-commit"
( cd "$D" && git add -- hooks/git/pre-commit )
run_hook; check protected-check-remains-live "$?" nonzero 0 0 -F "protected paths edited"
if grep -q "stage=protected-paths elapsed=" "$OUT"; then ok "stage-timing-printed-when-protected-paths-block"
else bad "stage-timing-printed-when-protected-paths-block" "no protected-paths timing line"; fi

if python3 "$ROOT/hooks/tests/test-validator-tier.py" >"$TMP/tier-unit.out" 2>&1; then ok "tier-unit"
else bad "tier-unit" "$(tail -n 5 "$TMP/tier-unit.out" | tr '\n' '|')"; fi

new_fixture tier-none
run_hook; check tier-full-no-declaration "$?" 0 1 1 -F "tier=full: lint/typecheck run - no declaration"

new_fixture tier-docs 'docs/**'
stage_only docs/a.md
run_hook; check tier-validator-free-docs-only "$?" 0 0 0 -F "tier=validator-free"
if grep -q "stage=validators elapsed=" "$OUT" && grep -qF "all checks passed" "$OUT"; then ok "tier-validator-free-completes-hook"
else bad "tier-validator-free-completes-hook" "$(tr '\n' '|' < "$OUT")"; fi

new_fixture tier-undeclared 'docs/**'
mkdir -p "$D/docs"; printf 'doc\n' > "$D/docs/a.md"; ( cd "$D" && git add -- docs/a.md )
run_hook; check tier-full-undeclared-path "$?" 0 1 1 -F "src.txt is not declared validator-free"

new_fixture tier-widening 'docs/**'
printf '  - "src.txt"\n' >> "$D/policies/validator-free-paths.yml"
run_hook; check tier-worktree-widening-ignored "$?" 0 1 1 -F "src.txt is not declared validator-free"

new_fixture tier-rename 'docs/**'
mkdir -p "$D/docs"; ( cd "$D" && git mv src.txt docs/src.md )
run_hook; check tier-rename-both-sides "$?" 0 1 1 -F "src.txt is not declared validator-free"

new_fixture tier-invalid '**'
stage_only docs/a.md
run_hook; check tier-invalid-declaration-runs "$?" 0 1 1 -F "is invalid"

new_fixture tier-secret 'docs/**'
mkdir -p "$D/docs"; printf 'k = "%s"\n' "AKIA""IOSFODNN7EXAMPLE" > "$D/docs/leak.md"
stage_only docs/leak.md
run_hook; check tier-secret-scan-still-runs "$?" nonzero 0 0 -F "secret pattern in staged added lines"

new_fixture tier-protected '**/*.md'
( cd "$D" && printf 'rules\n' > FLOW_RULES.md && git add -- FLOW_RULES.md && git commit -qm rules \
  && printf 'edit\n' >> FLOW_RULES.md && git add -- FLOW_RULES.md )
run_hook; check tier-protected-check-still-runs "$?" nonzero 0 0 -F "protected paths edited"

new_fixture tier-module-size 'scripts/**'
mkdir -p "$D/hooks/local" "$D/scripts"
cp "$ROOT/hooks/local/check-module-size.sh" "$D/hooks/local/check-module-size.sh"
: > "$D/policies/module-size-baseline.txt"
( cd "$D" && git add -- hooks/local/check-module-size.sh policies/module-size-baseline.txt && git commit -qm size )
for _ in $(seq 1 801); do echo 'echo x'; done > "$D/scripts/big.sh"
( cd "$D" && git add -- scripts/big.sh )
run_hook; check tier-module-size-still-runs "$?" nonzero 0 0 -F "module-size ratchet failed"

new_fixture tier-old-hook 'docs/**'
stage_only docs/a.md
in_fixture "" bash -c '. hooks/local/lib/precommit-validator-reuse.sh; run_precommit_validators "$PWD" "$PATH"'
check tier-old-hook-copy "$?" 0 0 0 -F "tier=validator-free"

cli_hashes="$(sha256sum "$ROOT/.claude/hooks/run-lint-on-stop.sh" \
  "$ROOT/.claude/hooks/run-typecheck-on-stop.sh" "$ROOT/.claude/hooks/quality-check-apps.js" \
  | awk '{print $1}' | tr '\n' ' ')"
if [ "$cli_hashes" = "ff363486b4e0657dd1285ba8ad3089689db2f012607dc2fd925cfb39b0a419c0 da6412f2f49e75175bbb718ef887bb9140189e0a225e9fbd0e03567f1801a4f7 f4e3a17991dbc7160d430c2dcbea3d2a625255057700697591059e1edeafac40 " ]; then
    ok "cli-stop-validators-unchanged"
else
    bad "cli-stop-validators-unchanged" "hashes changed: $cli_hashes"
fi

echo "[test-validator-evidence] $pass/$((pass + fail)) PASS"
exit "$fail"
