#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POST="$ROOT/hooks/local/post-fusebase-update.sh"
HANDOFF="$ROOT/templates/handoff-implement.md"
WORKFLOW="$ROOT/workflows/greenlight-implement.md"
SKILL="$ROOT/flow-skills/validation-and-qa/SKILL.md"
PRECOMMIT="$ROOT/hooks/git/pre-commit"
REUSE_HELPER="$ROOT/hooks/local/lib/precommit-validator-reuse.sh"
VALIDATOR_RUNNER="$ROOT/hooks/local/lib/validator-runner.py"
RUNNER="$ROOT/hooks/tests/run-tests.sh"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t validation-instructions)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "PASS: validation-instructions $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: validation-instructions $1 ($2)"; }
finish() { echo "[test-validation-instructions] $pass/$((pass + fail)) PASS"; exit "$fail"; }

check_recovery() {
    local file="$1" text
    text="$(awk '/^echo "Recommended next steps:"/{p=1} p{print}' "$file")"
    printf '%s' "$text" | grep -qF 'bash hooks/local/mirror-skills.sh --check' \
        && printf '%s' "$text" | grep -qF 'bash hooks/tests/test-hook-wiring-intent.sh' \
        && ! printf '%s' "$text" | grep -qF 'hooks/tests/run-tests.sh'
}

if check_recovery "$POST"; then
    ok "consumer-recovery-uses-focused-hash-and-wiring-checks"
else
    bad "consumer-recovery-uses-focused-hash-and-wiring-checks" "missing focused checks or full maintainer suite still advised"
fi

cp "$POST" "$TMP/post.sh"
sed -i 's#bash hooks/local/mirror-skills.sh --check && bash hooks/tests/test-hook-wiring-intent.sh#bash hooks/tests/run-tests.sh#' "$TMP/post.sh"
if check_recovery "$TMP/post.sh"; then
    bad "consumer-recovery-negative-control" "planted full-suite advice passed"
else
    ok "consumer-recovery-negative-control"
fi

for file in "$HANDOFF" "$WORKFLOW" "$SKILL"; do
    name="${file#"$ROOT/"}"
    if grep -qF 'hooks/local/run-validators.sh' "$file" \
       && grep -qi 'authenticated' "$file" \
       && grep -qi 'exact-state' "$file" \
       && grep -qi 'rerun' "$file" \
       && grep -qiE 'same[- ]user' "$file" \
       && grep -qiE 'secret.*protected-path.*module-size.*release' "$file"; then
        ok "instruction-contract-$name"
    else
        bad "instruction-contract-$name" "runner, trust boundary, fallback, or live controls missing"
    fi
done

secret_line="$(grep -n '^# 2\. Secret content scan' "$PRECOMMIT" | cut -d: -f1)"
protected_line="$(grep -n '^# 3\. Reject protected-path' "$PRECOMMIT" | cut -d: -f1)"
module_line="$(grep -n '^# 4\. Module-size' "$PRECOMMIT" | cut -d: -f1)"
reuse_line="$(grep -n '^# 5\. Lint + typecheck' "$PRECOMMIT" | cut -d: -f1)"
if [ -n "$secret_line" ] && [ "$secret_line" -lt "$reuse_line" ] \
   && [ -n "$protected_line" ] && [ "$protected_line" -lt "$reuse_line" ] \
   && [ -n "$module_line" ] && [ "$module_line" -lt "$reuse_line" ]; then
    ok "precommit-reuse-boundary-follows-live-controls"
else
    bad "precommit-reuse-boundary-follows-live-controls" "secret=$secret_line protected=$protected_line module=$module_line reuse=$reuse_line"
fi

if [ "$(wc -l < "$PRECOMMIT" | tr -d ' ')" -lt 800 ] \
   && grep -qF 'run_precommit_validators' "$PRECOMMIT" \
   && grep -qF 'def run_validators' "$ROOT/hooks/local/lib/validator-evidence.py" \
   && grep -qF 'evidence.run_validators' "$VALIDATOR_RUNNER" \
   && ! grep -qE 'choices=.*begin|choices=.*finish' "$ROOT/hooks/local/lib/validator-evidence.py"; then
    ok "trusted-runner-and-extracted-reuse-boundary"
else
    bad "trusted-runner-and-extracted-reuse-boundary" "public mint remains, runner ownership missing, or pre-commit not reduced"
fi

if grep -qF 'git -C "$root" show HEAD:hooks/local/lib/validator-evidence.py' "$REUSE_HELPER" \
   && grep -qF 'reuse unavailable' "$ROOT/hooks/local/lib/validator-evidence.py"; then
    ok "reuse-verifier-is-tracked-and-authority-fails-closed"
else
    bad "reuse-verifier-is-tracked-and-authority-fails-closed" "trusted verifier or fallback missing"
fi

if grep -qE 'run_shell_phase test-release-evidence-authority\.sh +"release-authority"' "$RUNNER" \
   && ! grep -qF 'validator-evidence' "$ROOT/hooks/tests/test-release-evidence-authority.sh"; then
    ok "release-authority-remains-independent"
else
    bad "release-authority-remains-independent" "release authority missing or coupled to validator reuse"
fi

if bash "$ROOT/hooks/local/mirror-skills.sh" --check >/dev/null 2>&1; then
    ok "validation-skill-mirrors-current"
else
    bad "validation-skill-mirrors-current" "mirror hash drift"
fi

finish
