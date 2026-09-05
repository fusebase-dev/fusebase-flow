#!/usr/bin/env bash

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROUTER="$ROOT/hooks/local/lane-router.sh"
PYTHON_BIN="${PYTHON:-python3}"
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "PASS: lane-router $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: lane-router $1 (${2:-})"; }
finish() { echo "[test-lane-router] $pass/$((pass + fail)) PASS"; exit "$fail"; }

[ -f "$ROUTER" ] || { bad "setup-router-present" "missing $ROUTER"; finish; }

expect_lane() {
  local want="$1" name="$2"
  shift 2
  local out rc
  out="$(bash "$ROUTER" "$@" 2>&1)"
  rc=$?
  if [ "$rc" -eq "$want" ]; then
    ok "$name"
  else
    bad "$name" "want rc=$want got rc=$rc; $(echo "$out" | tr '\n' ' ' | cut -c1-160)"
  fi
}

expect_lane 10 "historical-gate-harness-routes-FULL" hooks/tests/run-tests.sh
expect_lane 10 "historical-manifest-engine-routes-FULL" hooks/tests/run-tests.sh hooks/local/lib/hook_manifest.py audit/hook-layer-manifest.json
expect_lane 10 "historical-approval-handling-routes-FULL" hooks/local/lib/active-approvals.sh hooks/local/fusebase-flow-health-check.sh
expect_lane 10 "policy-yml-routes-FULL" policies/command-policy.yml
expect_lane 10 "enforcement-handler-routes-FULL" hooks/handlers/pre_tool_use.py
expect_lane 10 "git-guard-routes-FULL" hooks/git/pre-commit
expect_lane 10 "ci-workflow-routes-FULL" .github/workflows/fusebase-flow-verify.yml
expect_lane 10 "approval-artifact-routes-FULL" state/approvals/production_deploy-x.json
expect_lane 10 "upgrade-path-routes-FULL" hooks/local/upgrade.sh
expect_lane 10 "mixed-diff-one-hard-surface-routes-FULL" README.md hooks/shared/approval_artifact.py
expect_lane 10 "router-governs-own-policy" hooks/local/lane-router.sh
expect_lane 10 "assessor-governs-own-policy" hooks/local/lane-assessment.py

expect_lane 0 "ordinary-doc-no-mechanical-match" README.md
expect_lane 0 "ordinary-multi-doc-no-mechanical-match" docs/a.md docs/b.md docs/c.md
expect_lane 0 "ordinary-source-no-mechanical-match" src/components/Card.tsx
expect_lane 0 "flow-skill-no-mechanical-match" flow-skills/communication/SKILL.md
expect_lane 0 "ordinary-test-no-mechanical-match" hooks/tests/test-lane-router.sh

out="$(bash "$ROUTER" --json policies/command-policy.yml README.md 2>&1)"
rc=$?
if [ "$rc" -eq 10 ] && printf '%s' "$out" | "$PYTHON_BIN" -c 'import json,sys
d=json.load(sys.stdin)
assert d["mechanical_result"] == "FULL_REQUIRED"
assert d["matches"] == [{"path":"policies/command-policy.yml","trigger_id":"AUTH_SECRET_POLICY","reason":"policy data read by enforcement hooks"}]'; then
  ok "json-full-result-is-structured"
else
  bad "json-full-result-is-structured" "rc=$rc out=$out"
fi

out="$(bash "$ROUTER" --json src/service.py 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | "$PYTHON_BIN" -c 'import json,sys
d=json.load(sys.stdin)
assert d == {"schema_version":1,"status":"ok","mechanical_result":"NO_MECHANICAL_MATCH","matches":[]}' ; then
  ok "json-no-match-does-not-claim-lightweight"
else
  bad "json-no-match-does-not-claim-lightweight" "rc=$rc out=$out"
fi

out="$(bash "$ROUTER" README.md 2>&1)"
if echo "$out" | grep -q "NO_MECHANICAL_MATCH" && ! echo "$out" | grep -q "LIGHTWEIGHT"; then
  ok "human-no-match-does-not-claim-lightweight"
else
  bad "human-no-match-does-not-claim-lightweight" "$out"
fi

for invocation in "" "--bogus" "--base refs/heads/does-not-exist"; do
  read -r -a args <<< "$invocation"
  out="$(bash "$ROUTER" "${args[@]}" 2>&1)"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "input-error-${invocation:-no-args}"
  else
    bad "input-error-${invocation:-no-args}" "want rc=2 got rc=$rc"
  fi
done

finish
