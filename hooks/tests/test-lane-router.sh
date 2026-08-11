#!/usr/bin/env bash
# Fusebase Flow — the hard-surface lane router routes the KNOWN-WRONG diffs to Full.
#
# THE DISCRIMINATOR, and why it is not circular:
#   The three diffs below are not invented fixtures. They are the actual changed paths of
#   cb0ff8b / 235f4a3 / 0e29ed5 — changes that were self-classified Lightweight on 2026-08-05,
#   shipped, failed adversarial review, and were reverted (5f8004f). The existing eligibility
#   gate (flow-skills/lightweight-lane/SKILL.md conditions 4 and 5) already excluded them; that
#   rule was prose and did not fire. This asserts the rule now fires mechanically.
#
#   An adversarial review called an earlier version of this test circular, because a corpus
#   written by the trigger author proves only membership. That objection is answered two ways:
#   (a) the FULL cases are historical fact, selected before the router existed, and
#   (b) the LIGHTWEIGHT cases include ordinary paths that must NOT be captured — a router that
#       simply answered FULL always would fail this file.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: lane-router <name>" / "FAIL: lane-router <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROUTER="$ROOT/hooks/local/lane-router.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: lane-router $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: lane-router $1 (${2:-})"; }
finish() { echo "[test-lane-router] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$ROUTER" ] || { bad "setup-router-present" "missing $ROUTER"; finish; }

# expect_lane <expected-rc> <name> <path>...
expect_lane() {
    local want="$1" name="$2"; shift 2
    local out rc
    out="$(bash "$ROUTER" "$@" 2>&1)"; rc=$?
    if [ "$rc" -eq "$want" ]; then
        ok "$name"
    else
        bad "$name" "want rc=$want got rc=$rc; $(echo "$out" | tr '\n' ' ' | cut -c1-160)"
    fi
}

# --- FULL arm: the exact paths of the three reverted 2026-08-05 changes ----------------------
expect_lane 10 "cb0ff8b-gate-harness-routes-FULL" \
    hooks/tests/run-tests.sh

expect_lane 10 "235f4a3-manifest-engine-routes-FULL" \
    hooks/tests/run-tests.sh hooks/local/lib/hook_manifest.py audit/hook-layer-manifest.json

expect_lane 10 "0e29ed5-approval-handling-routes-FULL" \
    hooks/local/lib/active-approvals.sh hooks/local/fusebase-flow-health-check.sh

# --- FULL arm: the other hard surfaces --------------------------------------------------------
expect_lane 10 "policy-yml-routes-FULL"            policies/command-policy.yml
expect_lane 10 "enforcement-handler-routes-FULL"   hooks/handlers/pre_tool_use.py
expect_lane 10 "git-guard-routes-FULL"             hooks/git/pre-commit
expect_lane 10 "ci-workflow-routes-FULL"           .github/workflows/fusebase-flow-verify.yml
expect_lane 10 "approval-artifact-routes-FULL"     state/approvals/production_deploy-x.json
expect_lane 10 "upgrade-path-routes-FULL"          hooks/local/upgrade.sh
expect_lane 10 "mixed-diff-one-hard-surface-routes-FULL" \
    README.md docs/notes.md hooks/shared/approval_artifact.py

# Self-governance: editing the surface list changes what must take the Full lane. A router
# exempt from its own rule could be widened or narrowed on the cheap lane.
expect_lane 10 "router-governs-its-own-surface-list" \
    hooks/local/lane-router.sh

# --- LIGHTWEIGHT arm: a router that always said FULL would fail every case below -------------
expect_lane 0 "ordinary-doc-edit-falls-through"      README.md
expect_lane 0 "ordinary-multi-doc-edit-falls-through" docs/a.md docs/b.md docs/c.md
expect_lane 0 "copy-only-source-fix-falls-through"   src/components/Card.tsx
expect_lane 0 "a-flow-skill-body-falls-through"      flow-skills/communication/SKILL.md
expect_lane 0 "an-ordinary-test-falls-through"       hooks/tests/test-lane-router.sh

# --- INPUT ERROR: never silently a lane -------------------------------------------------------
out="$(bash "$ROUTER" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "no-args-is-input-error-not-a-lane"
else bad "no-args-is-input-error-not-a-lane" "want rc=2 got rc=$rc"; fi

out="$(bash "$ROUTER" --bogus 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "unknown-flag-is-input-error-not-a-lane"
else bad "unknown-flag-is-input-error-not-a-lane" "want rc=2 got rc=$rc"; fi

# --- The router must NOT overclaim in its own output ------------------------------------------
# It reports a MATCH, never a safety judgement. A future edit that promotes the LIGHTWEIGHT
# message into "this change is safe" is the claim-wider-than-the-thing defect.
out="$(bash "$ROUTER" README.md 2>&1)"
if echo "$out" | grep -q "NOT 'this change is safe'"; then
    ok "lightweight-output-disclaims-a-safety-claim"
else
    bad "lightweight-output-disclaims-a-safety-claim" "the disclaimer is gone from the LIGHTWEIGHT path"
fi

finish
