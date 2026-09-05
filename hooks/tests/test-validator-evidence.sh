#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t validator-evidence)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "PASS: validator-evidence $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: validator-evidence $1 ($2)"; }
finish() { echo "[test-validator-evidence] $pass/$((pass + fail)) PASS"; exit "$fail"; }

new_fixture() {
    local name="$1"
    D="$TMP/$name/repo"
    COUNT="$TMP/$name/count"
    TOOL="$TMP/$name/validator.sh"
    mkdir -p "$D/hooks/git" "$D/hooks/local/lib" "$D/hooks/shared" "$D/policies" "$COUNT"
    cp "$ROOT/hooks/git/pre-commit" "$D/hooks/git/pre-commit"
    cp "$ROOT/hooks/local/run-validators.sh" "$D/hooks/local/run-validators.sh"
    cp "$ROOT/hooks/local/lib/validator-evidence.py" "$D/hooks/local/lib/validator-evidence.py"
    cp "$ROOT"/hooks/shared/*.py "$D/hooks/shared/"
    cp "$ROOT"/policies/*.yml "$D/policies/"
    cat > "$TOOL" <<'SH'
#!/usr/bin/env bash
kind="$1"
printf x >> "$FUSEBASE_FLOW_TEST_COUNT_DIR/$kind"
[ "${FUSEBASE_FLOW_TEST_FAIL:-}" != "$kind" ]
SH
    chmod +x "$TOOL"
    TOOL_WIN="$(cygpath -m "$TOOL")"
    LINT="$TOOL_WIN lint"
    TYPECHECK="$TOOL_WIN typecheck"
    RUN_LINT="$LINT"
    RUN_TYPECHECK="$TYPECHECK"
    RUN_NODE_ENV="baseline"
    printf 'base\n' > "$D/src.txt"
    printf '{}\n' > "$D/eslint.config.js"
    printf '{}\n' > "$D/package-lock.json"
    ( cd "$D" && git init -q && git config user.email fixture@example.test \
      && git config user.name fixture && git add -- hooks policies src.txt eslint.config.js package-lock.json \
      && git commit -qm base )
    printf 'change\n' >> "$D/src.txt"
    ( cd "$D" && git add -- src.txt )
}

with_env() {
    env FUSEBASE_FLOW_LINT="$RUN_LINT" \
        FUSEBASE_FLOW_TYPECHECK="$RUN_TYPECHECK" \
        FUSEBASE_FLOW_TEST_COUNT_DIR="$(cygpath -m "$COUNT")" \
        NODE_ENV="$RUN_NODE_ENV" "$@"
}

make_receipt() {
    ( cd "$D" && with_env bash hooks/local/run-validators.sh ) >"$TMP/runner.out" 2>&1
}

run_hook() {
    ( cd "$D" && with_env bash hooks/git/pre-commit ) >"$TMP/hook.out" 2>&1
}

invalidate() {
    ( cd "$D" && python3 -S hooks/local/lib/validator-evidence.py invalidate --root . ) >/dev/null 2>&1
}

receipt_path() {
    local raw
    raw="$(cd "$D" && python3 -S hooks/local/lib/validator-evidence.py path --root .)"
    cygpath -u "$raw"
}

count_of() {
    [ -f "$COUNT/$1" ] && wc -c < "$COUNT/$1" | tr -d ' ' || printf 0
}

expect_reuse() {
    local name="$1"
    if [ "$(count_of lint)" = 1 ] && [ "$(count_of typecheck)" = 1 ] \
       && grep -q "reusing authentic exact-state" "$TMP/hook.out"; then
        ok "$name"
    else
        bad "$name" "lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
}

expect_rerun() {
    local name="$1"
    if [ "$(count_of lint)" = 2 ] && [ "$(count_of typecheck)" = 2 ] \
       && ! grep -q "reusing authentic exact-state" "$TMP/hook.out"; then
        ok "$name"
    else
        bad "$name" "lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
}

case_reuse() {
    new_fixture reuse
    make_receipt && run_hook
    expect_reuse "authentic-matching-success-skips"
    invalidate
}

case_missing() {
    new_fixture missing
    make_receipt
    invalidate
    run_hook
    expect_rerun "missing-receipt-reruns"
}

case_forged() {
    new_fixture forged
    make_receipt
    printf '{"evidence":{"result":"success"},"signature":"forged"}\n' > "$(receipt_path)"
    run_hook
    expect_rerun "forged-receipt-reruns"
    invalidate
}

case_edited() {
    new_fixture edited
    make_receipt
    python3 - "$(receipt_path)" <<'PY'
import json
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d["evidence"]["result"] = "failure"
p.write_text(json.dumps(d))
PY
    run_hook
    expect_rerun "edited-receipt-reruns"
    invalidate
}

case_failed() {
    new_fixture failed
    FUSEBASE_FLOW_TEST_FAIL=lint make_receipt
    runner_rc=$?
    run_hook
    if [ "$runner_rc" -ne 0 ] && [ "$(count_of lint)" = 2 ] && [ "$(count_of typecheck)" = 1 ]; then
        ok "failed-validation-never-reuses"
    else
        bad "failed-validation-never-reuses" "runner=$runner_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
    invalidate
}

rerun_after() {
    local name="$1" mutation="$2"
    new_fixture "$name"
    make_receipt
    "$mutation"
    run_hook
    expect_rerun "$name-reruns"
    invalidate
}

mutate_staged() { printf 'staged\n' >> "$D/src.txt"; ( cd "$D" && git add -- src.txt ); }
mutate_unstaged() { printf 'unstaged\n' >> "$D/src.txt"; }
mutate_untracked() { printf 'untracked\n' > "$D/new-source.txt"; }
mutate_config() { printf '{"changed":true}\n' > "$D/eslint.config.js"; }
mutate_dependency() { printf '{"lock":2}\n' > "$D/package-lock.json"; }
mutate_environment() { RUN_NODE_ENV=changed; }
mutate_command() { RUN_LINT="$LINT alternate"; }
mutate_toolchain() { printf '\n:\n' >> "$TOOL"; }

case_replay() {
    new_fixture replay
    make_receipt
    run_hook
    printf 'later\n' >> "$D/src.txt"
    ( cd "$D" && git add -- src.txt )
    run_hook
    if [ "$(count_of lint)" = 2 ] && [ "$(count_of typecheck)" = 2 ]; then
        ok "replayed-receipt-on-new-state-reruns"
    else
        bad "replayed-receipt-on-new-state-reruns" "lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
    invalidate
}

case_concurrent() {
    new_fixture concurrent
    make_receipt
    (
      for n in $(seq 1 200); do
        printf '%s\n' "$n" > "$D/racing-source.txt"
      done
    ) & race_pid=$!
    run_hook
    wait "$race_pid"
    expect_rerun "concurrent-mutation-reruns"
    invalidate
}

case_secret() {
    new_fixture secret
    printf 'blocked\n' > "$D/.env"
    ( cd "$D" && git add -- .env )
    make_receipt
    run_hook; hook_rc=$?
    if [ "$hook_rc" -ne 0 ] && grep -q "secret-like files staged" "$TMP/hook.out" \
       && [ "$(count_of lint)" = 1 ]; then
        ok "secret-check-remains-live"
    else
        bad "secret-check-remains-live" "rc=$hook_rc lint=$(count_of lint)"
    fi
    invalidate
}

case_protected() {
    new_fixture protected
    printf '\n' >> "$D/hooks/git/pre-commit"
    ( cd "$D" && git add -- hooks/git/pre-commit )
    make_receipt
    run_hook; hook_rc=$?
    if [ "$hook_rc" -ne 0 ] && grep -q "protected paths edited" "$TMP/hook.out" \
       && [ "$(count_of lint)" = 1 ]; then
        ok "protected-check-remains-live"
    else
        bad "protected-check-remains-live" "rc=$hook_rc lint=$(count_of lint)"
    fi
    invalidate
}

case_reuse
case_missing
case_forged
case_edited
case_failed
rerun_after staged-state mutate_staged
rerun_after unstaged-state mutate_unstaged
rerun_after untracked-state mutate_untracked
rerun_after config-state mutate_config
rerun_after dependency-state mutate_dependency
rerun_after environment-state mutate_environment
rerun_after command-state mutate_command
rerun_after toolchain-state mutate_toolchain
case_replay
case_concurrent
case_secret
case_protected

cli_hashes="$(sha256sum "$ROOT/.claude/hooks/run-lint-on-stop.sh" \
  "$ROOT/.claude/hooks/run-typecheck-on-stop.sh" "$ROOT/.claude/hooks/quality-check-apps.js" \
  | awk '{print $1}' | tr '\n' ' ')"
if [ "$cli_hashes" = "ff363486b4e0657dd1285ba8ad3089689db2f012607dc2fd925cfb39b0a419c0 da6412f2f49e75175bbb718ef887bb9140189e0a225e9fbd0e03567f1801a4f7 f4e3a17991dbc7160d430c2dcbea3d2a625255057700697591059e1edeafac40 " ]; then
    ok "cli-stop-validators-outside-reuse"
else
    bad "cli-stop-validators-outside-reuse" "hashes changed: $cli_hashes"
fi

finish
