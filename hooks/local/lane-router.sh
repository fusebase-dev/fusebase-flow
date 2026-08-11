#!/usr/bin/env bash
# Fusebase Flow — hard-surface lane router.
#
# WHAT THIS IS: a path-only pre-router. Given changed paths, it answers ONE question —
# does this change touch a known hard surface? If yes, the Full lane is required. If no, it
# says nothing and today's lane logic is unchanged.
#
# WHAT THIS IS NOT — and the name is deliberate: this is NOT a risk classifier. It cannot
# read semantics, it has no declaration schema, no size thresholds, no override artifacts and
# no opinion about changes it does not match. A LIGHTWEIGHT result means "no hard surface
# matched", NOT "this change is safe". Claiming more than that is the defect class this repo
# keeps shipping (a control documented wider than the thing it does).
#
# WHY IT EXISTS: flow-skills/lightweight-lane/SKILL.md already excludes security, protected-path
# and manifest/contract surfaces from the Lightweight lane (eligibility conditions 4 and 5). That
# rule is CORRECT and is pure prose, so on 2026-08-05 three changes touching approval handling,
# the manifest engine and the gate harness were self-classified Lightweight, shipped, reviewed,
# and reverted (5f8004f). The rule did not need rewriting. It needed to be executable.
#
# Usage:
#   lane-router.sh --staged              # classify the staged diff
#   lane-router.sh --base <ref>          # classify HEAD vs <ref>
#   lane-router.sh path [path...]        # classify an explicit path list
# Exit: 0 = LIGHTWEIGHT (no hard surface matched) · 10 = FULL (hard surface matched)
#       2 = usage/input error (never silently a lane)

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Hard surfaces. Each entry: <glob>|<trigger-id> <human reason>.
# TRIPWIRE: these are the surfaces the EXISTING lightweight-lane eligibility gate already
# excludes (conditions 4 and 5) — this list makes that rule executable, it does not invent a
# new policy. Adding a surface here widens what must take the Full lane; that is a policy
# change and is itself a Full-lane change. Its long-term home is a policies/*.yml file once C0
# decides the policy layout; it lives here now so this slice needs no protected-path edit.
HARD_SURFACES=(
  "policies/*.yml|AUTH_SECRET_POLICY policy data read by the enforcement hooks"
  "hooks/handlers/*|HOOK_ENFORCEMENT lifecycle enforcement handlers"
  "hooks/shared/*|HOOK_ENFORCEMENT shared enforcement/approval libraries"
  "hooks/git/*|HOOK_ENFORCEMENT git-layer guards"
  "hooks/local/lib/*|HOOK_ENFORCEMENT engine libraries behind the health/upgrade verdicts"
  "hooks/local/approve-local.sh|APPROVAL approval minting"
  "hooks/local/write-bootstrap-approval.sh|APPROVAL approval minting"
  "hooks/local/fusebase-flow-health-check.sh|VERDICT_ENGINE emits the health verdict + exit code"
  "hooks/local/upgrade.sh|UPGRADE consumer upgrade path"
  "hooks/local/bootstrap-upgrade.sh|UPGRADE consumer upgrade path"
  "hooks/local/stamp-*.sh|MANIFEST integrity manifest generation"
  "hooks/local/verify-*.sh|MANIFEST integrity manifest verification"
  "hooks/tests/run-tests.sh|RELEASE_GATE the harness CI runs as release evidence"
  "audit/*manifest*.json|MANIFEST committed integrity manifests"
  ".github/workflows/*|RELEASE_GATE CI that gates publication"
  "state/approvals/*|APPROVAL authorization artifacts"
  "VERSION|RELEASE release identity"
  # Self-governing: editing this list changes what must take the Full lane, which is itself a
  # policy change. A router exempt from its own rule is the gap that lets the rule be widened
  # or narrowed on the cheap lane.
  "hooks/local/lane-router.sh|LANE_POLICY the hard-surface list itself"
)

usage() { echo "usage: lane-router.sh [--staged | --base <ref> | <path>...]" >&2; exit 2; }

paths=()
case "${1:-}" in
  --staged)
    mapfile -t paths < <(git -C "$ROOT" diff --cached --name-only 2>/dev/null) ;;
  --base)
    [ -n "${2:-}" ] || usage
    mapfile -t paths < <(git -C "$ROOT" diff --name-only "$2"..HEAD 2>/dev/null) ;;
  "" ) usage ;;
  --* ) usage ;;
  * )   paths=("$@") ;;
esac

# An empty path set is INPUT ERROR, never a lane. A router that answers LIGHTWEIGHT for
# "nothing to classify" is the silent-green failure the gate harness already guards against.
if [ "${#paths[@]}" -eq 0 ]; then
  echo "[lane-router] ERROR: no changed paths to classify" >&2
  exit 2
fi

matched=0
for p in "${paths[@]}"; do
  [ -n "$p" ] || continue
  for entry in "${HARD_SURFACES[@]}"; do
    glob="${entry%%|*}"; rest="${entry#*|}"
    trigger="${rest%% *}"; reason="${rest#* }"
    # shellcheck disable=SC2053 — intentional glob match, not string equality
    if [[ "$p" == $glob ]]; then
      echo "FULL-REQUIRED: $p [$trigger] $reason"
      matched=1
      break
    fi
  done
done

if [ "$matched" -eq 1 ]; then
  echo "[lane-router] FULL — a hard surface was touched; the Lightweight lane is not eligible"
  echo "[lane-router] (this says a hard surface MATCHED; it makes no claim about changes that did not)"
  exit 10
fi

echo "[lane-router] LIGHTWEIGHT — no hard surface matched"
echo "[lane-router] NOTE: 'no hard surface matched' is NOT 'this change is safe'. The remaining"
echo "[lane-router]       eligibility conditions in flow-skills/lightweight-lane/SKILL.md still apply."
exit 0
