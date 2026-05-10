#!/usr/bin/env bash
# Fusebase Flow — approve-local
# Author an approval artifact in state/approvals/ for an action
# defined in policies/approval-policy.yml.
#
# Usage:
#   bash hooks/local/approve-local.sh <action> <slug> [reason]
# Example:
#   bash hooks/local/approve-local.sh production_deploy priority-fix "ship D2 fix"

set -euo pipefail

ACTION="${1:-}"
SLUG="${2:-}"
REASON="${3:-operator local approval}"

if [ -z "$ACTION" ] || [ -z "$SLUG" ]; then
    cat >&2 <<EOF
Usage: $0 <action> <slug> [reason]

Available actions (from approval-policy.yml):
  production_deploy
  database_migration
  destructive_file_delete
  auth_or_permission_change
  external_customer_visible_message
  session_key_or_cookie_use
  secret_file_write
  protected_path_edit
EOF
    exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
POLICY="$ROOT/policies/approval-policy.yml"
APPROVALS_DIR="$ROOT/state/approvals"
mkdir -p "$APPROVALS_DIR"

# Read TTL for this action from the policy (default 60 minutes).
#
# v2.7.0+ supports mode-aware TTL: artifact_ttl_minutes may be either a flat
# integer (legacy v1 schema) OR a mode-keyed object
# { direct_to_main: <int>, branch_pr: <int> } (v2 schema). When mode-keyed,
# the reader looks up the project's workflow_mode and applies the matching
# value. Falls back to direct_to_main, then to 60 if both are absent.
TTL_MIN="$(python3 - <<PY
import yaml
p = yaml.safe_load(open("$POLICY"))
ra = (p.get("require_approval") or {}).get("$ACTION") or {}
val = ra.get("artifact_ttl_minutes", 60)
if isinstance(val, dict):
    # Mode-keyed object (v2 schema). Look up workflow_mode.
    workflow_mode = p.get("workflow_mode", "direct_to_main")
    val = val.get(workflow_mode, val.get("direct_to_main", 60))
print(int(val))
PY
)"

DATE_STAMP="$(date -u +%Y%m%d)"
EXPIRES_AT="$(python3 -c "import datetime;print((datetime.datetime.utcnow()+datetime.timedelta(minutes=$TTL_MIN)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
ARTIFACT="$APPROVALS_DIR/${ACTION}-${SLUG}-${DATE_STAMP}.json"

OPERATOR="${USER:-operator}"

cat > "$ARTIFACT" <<JSON
{
  "approved_by": "$OPERATOR",
  "scope": "$SLUG",
  "expires_at": "$EXPIRES_AT",
  "reason": "$REASON",
  "action": "$ACTION"
}
JSON

# protected_path_edit needs an additional `paths` array; remind operator.
if [ "$ACTION" = "protected_path_edit" ]; then
    echo "[approve-local] note: protected_path_edit also needs a 'paths' array. Edit $ARTIFACT to add the approved paths."
fi

echo "[approve-local] artifact written: $ARTIFACT (expires $EXPIRES_AT)"
echo "[approve-local] hooks will honor this for the TTL window. Delete the file to revoke."
