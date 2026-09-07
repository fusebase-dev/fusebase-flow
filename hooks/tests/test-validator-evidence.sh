#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t validator-evidence)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
ONLY=""
if [ "${1:-}" = "--only" ] && [ "$#" -eq 2 ]; then
    case "$2" in
        t48|t48-remaining|t53) ONLY="$2" ;;
        *) echo "usage: $0 [--only t48|t48-remaining|t53]" >&2; exit 2 ;;
    esac
elif [ "$#" -ne 0 ]; then
    echo "usage: $0 [--only t48|t48-remaining|t53]" >&2
    exit 2
fi

ok() { pass=$((pass + 1)); echo "PASS: validator-evidence $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: validator-evidence $1 ($2)"; }
finish() { echo "[test-validator-evidence] $pass/$((pass + fail)) PASS"; exit "$fail"; }

new_fixture() {
    local name="$1"
    D="$TMP/$name/repo"
    COUNT="$TMP/$name/count"
    TOOL="$TMP/$name/validator.py"
    NESTED="$TMP/$name/nested-tool.sh"
    mkdir -p "$D/hooks/git" "$D/hooks/local/lib" "$D/hooks/shared" "$D/policies" "$COUNT"
    cp "$ROOT/hooks/git/pre-commit" "$D/hooks/git/pre-commit"
    cp "$ROOT/hooks/local/run-validators.sh" "$D/hooks/local/run-validators.sh"
    cp "$ROOT/hooks/local/lib/validator-evidence.py" "$D/hooks/local/lib/validator-evidence.py"
    cp "$ROOT/hooks/local/lib/validator-runner.py" "$D/hooks/local/lib/validator-runner.py"
    cp "$ROOT/hooks/local/lib/precommit-validator-reuse.sh" "$D/hooks/local/lib/precommit-validator-reuse.sh"
    cp "$ROOT"/hooks/shared/*.py "$D/hooks/shared/"
    cp "$ROOT"/policies/*.yml "$D/policies/"
    cat > "$TOOL" <<'PY'
import os
import pathlib
import sys

kind = sys.argv[1]
path = pathlib.Path(os.environ["FUSEBASE_FLOW_TEST_COUNT_DIR"]) / kind
with path.open("a", encoding="utf-8") as handle:
    handle.write("x")
raise SystemExit(1 if os.environ.get("FUSEBASE_FLOW_TEST_FAIL") == kind else 0)
PY
    chmod +x "$TOOL"
    printf '#!/usr/bin/env bash\n:\n' > "$NESTED"
    chmod +x "$NESTED"
    to_command_path() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }
    TOOL_CMD="$(to_command_path "$TOOL")"
    LINT="python3 $TOOL_CMD lint"
    TYPECHECK="python3 $TOOL_CMD typecheck"
    RUN_LINT="$LINT"
    RUN_TYPECHECK="$TYPECHECK"
    RUN_NODE_ENV="baseline"
    RUN_CUSTOM_ENV="baseline"
    RUN_STRICT_ENV="baseline"
    RUN_CONTEXT="{\"schema\":1,\"complete\":true,\"inputs\":[\"ignored-input.txt\"],\"dependencies\":[\"ignored-dependency.lock\"],\"environment\":[\"CUSTOM_VALIDATOR_MODE\",\"VALIDATOR_STRICT\"],\"toolchains\":[\"$(to_command_path "$NESTED")\"]}"
    printf 'base\n' > "$D/src.txt"
    printf '{}\n' > "$D/eslint.config.js"
    printf '{}\n' > "$D/package-lock.json"
    printf 'ignored-input\n' > "$D/ignored-input.txt"
    printf 'ignored-dependency\n' > "$D/ignored-dependency.lock"
    printf 'ignored-input.txt\nignored-dependency.lock\n' > "$D/.gitignore"
    ( cd "$D" && git init -q && git config user.email fixture@example.test \
      && git config user.name fixture && git add -- hooks policies src.txt eslint.config.js package-lock.json .gitignore \
      && git commit -qm base )
    printf 'change\n' >> "$D/src.txt"
    ( cd "$D" && git add -- src.txt )
}

with_env() {
    env FUSEBASE_FLOW_LINT="$RUN_LINT" \
        FUSEBASE_FLOW_TYPECHECK="$RUN_TYPECHECK" \
        FUSEBASE_FLOW_TEST_COUNT_DIR="$(to_command_path "$COUNT")" \
        FUSEBASE_FLOW_VALIDATOR_CONTEXT="$RUN_CONTEXT" \
        CUSTOM_VALIDATOR_MODE="$RUN_CUSTOM_ENV" VALIDATOR_STRICT="$RUN_STRICT_ENV" \
        NODE_ENV="$RUN_NODE_ENV" "$@"
}

make_receipt() {
    ( cd "$D" && with_env bash hooks/local/run-validators.sh ) >"$TMP/runner.out" 2>&1
}

run_hook() {
    ( cd "$D" && with_env bash hooks/git/pre-commit ) >"$TMP/hook.out" 2>&1
}

verify_receipt() {
    ( cd "$D" && with_env python3 -S hooks/local/lib/validator-evidence.py verify \
      --root . --lint "$RUN_LINT" --typecheck "$RUN_TYPECHECK" ) >"$TMP/verify.out" 2>&1
}

invalidate() {
    ( cd "$D" && python3 -S hooks/local/lib/validator-evidence.py invalidate --root . ) >/dev/null 2>&1
}

receipt_path() {
    local raw
    raw="$(cd "$D" && python3 -S hooks/local/lib/validator-evidence.py path --root .)"
    command -v cygpath >/dev/null 2>&1 && cygpath -u "$raw" || printf '%s' "$raw"
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
    if [ -f "$(receipt_path)" ]; then
        expect_reuse "complete-context-supported-positive-reuses"
    else
        expect_rerun "complete-context-positive-authority-unavailable-reruns"
    fi
    invalidate
}

case_incomplete_context_reruns() {
    local name="$1" context="$2" mutation="${3:-}"
    new_fixture "$name"
    RUN_CONTEXT="$context"
    make_receipt
    runner_rc=$?
    [ -z "$mutation" ] || "$mutation"
    run_hook
    hook_rc=$?
    receipt="$(receipt_path)"
    if [ "$runner_rc" -eq 0 ] && [ "$hook_rc" -eq 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" = 2 ] && [ "$(count_of typecheck)" = 2 ] \
       && grep -q "reuse unavailable" "$TMP/runner.out" \
       && ! grep -q "reusing authentic exact-state" "$TMP/hook.out"; then
        ok "$name-reruns-without-receipt"
    else
        bad "$name-reruns-without-receipt" \
          "runner=$runner_rc hook=$hook_rc receipt=$([ -f "$receipt" ] && echo yes || echo no) lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
    invalidate
}

mutate_undeclared_ignored_input() { printf 'changed\n' >> "$D/ignored-input.txt"; }
mutate_undeclared_environment() { RUN_STRICT_ENV="changed"; }

case_t48() {
    case_reuse
    case_incomplete_context_reruns absent-context ""
    case_incomplete_context_reruns incomplete-context \
      '{"schema":1,"complete":true,"inputs":[],"dependencies":[],"environment":[]}'
    case_incomplete_context_reruns empty-declarations \
      '{"inputs":[],"dependencies":[],"environment":[],"toolchains":[]}'
    case_incomplete_context_reruns undeclared-ignored-input \
      '{"schema":1,"inputs":[],"dependencies":[],"environment":[],"toolchains":[]}' \
      mutate_undeclared_ignored_input
    case_incomplete_context_reruns undeclared-environment \
      '{"schema":1,"inputs":[],"dependencies":[],"environment":[],"toolchains":[]}' \
      mutate_undeclared_environment
}

run_reuse_boundary() {
    local output="$1"
    ( cd "$D" && with_env bash -c \
      '. hooks/local/lib/precommit-validator-reuse.sh; run_precommit_validators "$PWD" "$PATH"' \
    ) >"$output" 2>&1
}

case_t48_remaining() {
    new_fixture t48-remaining
    RUN_CONTEXT='{"schema":1,"inputs":[],"dependencies":[],"environment":[],"toolchains":[]}'
    make_receipt
    runner_rc=$?
    receipt="$(receipt_path)"
    if [ "$runner_rc" -eq 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" = 1 ] && [ "$(count_of typecheck)" = 1 ] \
       && grep -q "reuse unavailable" "$TMP/runner.out"; then
        ok "remaining-real-runner-refuses-incomplete-receipt"
    else
        bad "remaining-real-runner-refuses-incomplete-receipt" \
          "runner=$runner_rc receipt=$([ -f "$receipt" ] && echo yes || echo no) lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi

    mutate_undeclared_ignored_input
    run_reuse_boundary "$TMP/remaining-input.out"
    input_rc=$?
    if [ "$input_rc" -eq 0 ] && [ "$(count_of lint)" = 2 ] \
       && [ "$(count_of typecheck)" = 2 ] \
       && ! grep -q "reusing authentic exact-state" "$TMP/remaining-input.out"; then
        ok "remaining-undeclared-ignored-input-reruns"
    else
        bad "remaining-undeclared-ignored-input-reruns" \
          "rc=$input_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi

    mutate_undeclared_environment
    run_reuse_boundary "$TMP/remaining-environment.out"
    environment_rc=$?
    if [ "$environment_rc" -eq 0 ] && [ "$(count_of lint)" = 3 ] \
       && [ "$(count_of typecheck)" = 3 ] \
       && ! grep -q "reusing authentic exact-state" "$TMP/remaining-environment.out"; then
        ok "remaining-undeclared-environment-reruns"
    else
        bad "remaining-undeclared-environment-reruns" \
          "rc=$environment_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi

    FUSEBASE_FLOW_TEST_FAIL=lint run_reuse_boundary "$TMP/remaining-failure.out"
    failure_rc=$?
    if [ "$failure_rc" -ne 0 ] && [ "$(count_of lint)" = 4 ] \
       && [ "$(count_of typecheck)" = 3 ] \
       && grep -q "BLOCK.*lint failed" "$TMP/remaining-failure.out"; then
        ok "remaining-lint-failure-boundary-stays-red"
    else
        bad "remaining-lint-failure-boundary-stays-red" \
          "rc=$failure_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
    invalidate
}

case_t53() {
    new_fixture t53
    RUN_CONTEXT="{\"schema\":1,\"complete\":true,\"inputs\":[\"src.txt\"],\"dependencies\":[\"package-lock.json\"],\"environment\":[\"CUSTOM_VALIDATOR_MODE\"],\"toolchains\":[\"$(to_command_path "$NESTED")\"]}"
    make_receipt
    runner_rc=$?
    receipt="$(receipt_path)"
    if [ "$runner_rc" -eq 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" = 1 ] && [ "$(count_of typecheck)" = 1 ] \
       && grep -q "independent proof is unavailable" "$TMP/runner.out"; then
        ok "t53-caller-complete-context-cannot-mint-reuse"
    else
        bad "t53-caller-complete-context-cannot-mint-reuse" \
          "runner=$runner_rc receipt=$([ -f "$receipt" ] && echo yes || echo no) lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi

    mutate_undeclared_ignored_input
    mutate_undeclared_environment
    run_reuse_boundary "$TMP/t53-fallback.out"
    fallback_rc=$?
    if [ "$fallback_rc" -eq 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" = 2 ] && [ "$(count_of typecheck)" = 2 ] \
       && ! grep -q "reusing authentic exact-state" "$TMP/t53-fallback.out"; then
        ok "t53-omitted-input-and-environment-rerun-real-validators"
    else
        bad "t53-omitted-input-and-environment-rerun-real-validators" \
          "rc=$fallback_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi

    FUSEBASE_FLOW_TEST_FAIL=lint run_reuse_boundary "$TMP/t53-failure.out"
    failure_rc=$?
    if [ "$failure_rc" -ne 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" = 3 ] && [ "$(count_of typecheck)" = 2 ] \
       && grep -q "BLOCK.*lint failed" "$TMP/t53-failure.out"; then
        ok "t53-fallback-validator-failure-stays-red"
    else
        bad "t53-fallback-validator-failure-stays-red" \
          "rc=$failure_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
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
    verify_receipt
    verify_rc=$?
    if [ "$verify_rc" -ne 0 ]; then
        ok "forged-receipt-disables-reuse"
    else
        bad "forged-receipt-disables-reuse" "verify=$verify_rc"
    fi
    invalidate
}

case_edited() {
    new_fixture edited
    make_receipt
    receipt="$(receipt_path)"
    if [ ! -f "$receipt" ]; then
        ok "edited-receipt-authority-host-unavailable"
        invalidate
        return
    fi
    python3 - "$receipt" <<'PY'
import json
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d["evidence"]["result"] = "failure"
p.write_text(json.dumps(d))
PY
    verify_receipt
    verify_rc=$?
    if [ "$verify_rc" -ne 0 ]; then
        ok "edited-receipt-disables-reuse"
    else
        bad "edited-receipt-disables-reuse" "verify=$verify_rc"
    fi
    invalidate
}

case_failed() {
    new_fixture failed
    FUSEBASE_FLOW_TEST_FAIL=lint make_receipt
    runner_rc=$?
    receipt="$(receipt_path)"
    if [ "$runner_rc" -ne 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" = 1 ] && [ "$(count_of typecheck)" = 0 ]; then
        ok "failed-validation-never-signs"
    else
        bad "failed-validation-never-signs" "runner=$runner_rc receipt=$([ -f "$receipt" ] && echo yes || echo no)"
    fi
    invalidate
}

reject_reuse_after() {
    local name="$1" mutation="$2"
    new_fixture "$name"
    make_receipt
    "$mutation"
    verify_receipt
    verify_rc=$?
    if [ "$verify_rc" -ne 0 ] && [ "$(count_of lint)" = 1 ] && [ "$(count_of typecheck)" = 1 ]; then
        ok "$name-disables-reuse"
    else
        bad "$name-disables-reuse" "verify=$verify_rc lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
    invalidate
}

mutate_staged() { printf 'staged\n' >> "$D/src.txt"; ( cd "$D" && git add -- src.txt ); }
mutate_unstaged() { printf 'unstaged\n' >> "$D/src.txt"; }
mutate_untracked() { printf 'untracked\n' > "$D/new-source.txt"; }
mutate_config() { printf '{"changed":true}\n' > "$D/eslint.config.js"; }
mutate_dependency() { printf '{"lock":2}\n' > "$D/package-lock.json"; }
mutate_environment() { RUN_NODE_ENV=changed; }
mutate_custom_environment() { RUN_CUSTOM_ENV=changed; }
mutate_command() { RUN_LINT="$LINT alternate"; }
mutate_toolchain() { printf '\n:\n' >> "$TOOL"; }
mutate_nested_toolchain() { printf '\n:\n' >> "$NESTED"; }
mutate_ignored_input() { printf 'changed\n' >> "$D/ignored-input.txt"; }
mutate_ignored_dependency() { printf 'changed\n' >> "$D/ignored-dependency.lock"; }
mutate_missing_declared_input() { RUN_CONTEXT='{"inputs":["missing-input.txt"],"dependencies":[],"environment":[],"toolchains":[]}'; }

case_incomplete_identity() {
    new_fixture incomplete-identity
    RUN_CONTEXT='{"unknown":[]}'
    make_receipt
    runner_rc=$?
    receipt="$(receipt_path)"
    if [ "$runner_rc" -eq 0 ] && [ ! -f "$receipt" ] \
       && [ "$(count_of lint)" -eq 1 ] && [ "$(count_of typecheck)" -eq 1 ]; then
        ok "incomplete-identity-reruns-without-receipt"
    else
        bad "incomplete-identity-reruns-without-receipt" \
          "runner=$runner_rc receipt=$([ -f "$receipt" ] && echo yes || echo no) lint=$(count_of lint) typecheck=$(count_of typecheck)"
    fi
    invalidate
}

case_symlink_target() {
    new_fixture symlink-target-state
    printf 'target\n' > "$D/ignored-target.txt"
    if ln -s ignored-target.txt "$D/linked-input.txt" 2>/dev/null && [ -L "$D/linked-input.txt" ]; then
        RUN_CONTEXT='{"inputs":["linked-input.txt"],"dependencies":[],"environment":[],"toolchains":[]}'
        make_receipt
        printf 'changed\n' >> "$D/ignored-target.txt"
        verify_receipt
        verify_rc=$?
        if [ "$verify_rc" -ne 0 ]; then
            ok "symlink-target-state-disables-reuse"
        else
            bad "symlink-target-state-disables-reuse" "verify=$verify_rc"
        fi
        invalidate
    else
        ok "symlink-target-state-host-unavailable"
    fi
}

case_unavailable_symlink_target() {
    new_fixture unavailable-symlink-target
    printf 'target\n' > "$D/ignored-target.txt"
    if ln -s ignored-target.txt "$D/linked-input.txt" 2>/dev/null && [ -L "$D/linked-input.txt" ]; then
        RUN_CONTEXT='{"inputs":["linked-input.txt"],"dependencies":[],"environment":[],"toolchains":[]}'
        make_receipt
        mv "$D/ignored-target.txt" "$D/ignored-target-away.txt"
        verify_receipt
        verify_rc=$?
        if [ "$verify_rc" -ne 0 ]; then
            ok "unavailable-symlink-target-disables-reuse"
        else
            bad "unavailable-symlink-target-disables-reuse" "verify=$verify_rc"
        fi
        invalidate
    else
        ok "unavailable-symlink-target-host-unavailable"
    fi
}

case_replay() {
    new_fixture replay
    make_receipt
    if [ ! -f "$(receipt_path)" ]; then
        ok "replayed-receipt-authority-host-unavailable"
        invalidate
        return
    fi
    verify_receipt || bad "matching-receipt-verifies-before-replay" "initial verify failed"
    printf 'later\n' >> "$D/src.txt"
    ( cd "$D" && git add -- src.txt )
    verify_receipt
    verify_rc=$?
    if [ "$verify_rc" -ne 0 ] && [ "$(count_of lint)" = 1 ] && [ "$(count_of typecheck)" = 1 ]; then
        ok "replayed-receipt-on-new-state-disables-reuse"
    else
        bad "replayed-receipt-on-new-state-disables-reuse" "verify=$verify_rc"
    fi
    invalidate
}

case_public_mint_rejected() {
    new_fixture public-mint
    ( cd "$D" && with_env python3 -I -S hooks/local/lib/validator-evidence.py begin \
      --root . --lint "$RUN_LINT" --typecheck "$RUN_TYPECHECK" ) >"$TMP/direct.out" 2>&1
    begin_rc=$?
    ( cd "$D" && with_env python3 -I -S hooks/local/lib/validator-evidence.py finish \
      --root . ) >>"$TMP/direct.out" 2>&1
    finish_rc=$?
    if [ "$begin_rc" -ne 0 ] && [ "$finish_rc" -ne 0 ] && [ ! -f "$(receipt_path)" ] \
       && [ "$(count_of lint)" = 0 ] && [ "$(count_of typecheck)" = 0 ]; then
        ok "public-success-mint-api-rejected"
    else
        bad "public-success-mint-api-rejected" "begin=$begin_rc finish=$finish_rc"
    fi
}

case_substituted_runner() {
    new_fixture substituted-runner
    mkdir -p "$TMP/substituted"
    cp "$D/hooks/local/lib/validator-runner.py" "$TMP/substituted/validator-runner.py"
    cp "$D/hooks/local/lib/validator-evidence.py" "$TMP/substituted/validator-evidence.py"
    ( cd "$D" && with_env python3 -I -S "$TMP/substituted/validator-runner.py" \
      --root . --lint "$RUN_LINT" --typecheck "$RUN_TYPECHECK" ) >"$TMP/substituted.out" 2>&1
    runner_rc=$?
    if [ "$runner_rc" -ne 0 ] && [ ! -f "$(receipt_path)" ] \
       && [ "$(count_of lint)" = 0 ] && [ "$(count_of typecheck)" = 0 ]; then
        ok "substituted-runner-rejected-before-execution"
    else
        bad "substituted-runner-rejected-before-execution" "runner=$runner_rc"
    fi
}

case_skipped_validator() {
    new_fixture skipped-validator
    ( cd "$D" && with_env python3 -I -S hooks/local/lib/validator-runner.py \
      --root . --lint "" --typecheck "$RUN_TYPECHECK" ) >"$TMP/skipped.out" 2>&1
    verify_receipt
    verify_rc=$?
    if [ "$verify_rc" -ne 0 ] && [ "$(count_of lint)" = 0 ] && [ "$(count_of typecheck)" = 1 ]; then
        ok "skipped-required-validator-cannot-produce-reusable-evidence"
    else
        bad "skipped-required-validator-cannot-produce-reusable-evidence" "verify=$verify_rc"
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
    verify_receipt
    verify_rc=$?
    wait "$race_pid"
    if [ "$verify_rc" -ne 0 ]; then
        ok "concurrent-mutation-disables-reuse"
    else
        bad "concurrent-mutation-disables-reuse" "verify=$verify_rc"
    fi
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

if [ "$ONLY" = "t48" ]; then
    case_t48
    finish
fi
if [ "$ONLY" = "t48-remaining" ]; then
    case_t48_remaining
    finish
fi
if [ "$ONLY" = "t53" ]; then
    case_t53
    finish
fi

case_reuse
case_missing
case_forged
case_edited
case_failed
reject_reuse_after staged-state mutate_staged
reject_reuse_after unstaged-state mutate_unstaged
reject_reuse_after untracked-state mutate_untracked
reject_reuse_after config-state mutate_config
reject_reuse_after dependency-state mutate_dependency
reject_reuse_after environment-state mutate_environment
reject_reuse_after custom-environment-state mutate_custom_environment
reject_reuse_after command-state mutate_command
reject_reuse_after wrapper-toolchain-state mutate_toolchain
reject_reuse_after nested-toolchain-state mutate_nested_toolchain
reject_reuse_after ignored-input-state mutate_ignored_input
reject_reuse_after ignored-dependency-state mutate_ignored_dependency
reject_reuse_after declared-input-set-state mutate_missing_declared_input
case_incomplete_identity
case_symlink_target
case_unavailable_symlink_target
case_replay
case_concurrent
case_public_mint_rejected
case_substituted_runner
case_skipped_validator
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
