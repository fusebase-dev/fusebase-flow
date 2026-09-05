#!/usr/bin/env bash

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PYTHON_BIN="${PYTHON:-python3}"
HARD_SURFACES=(
  "policies/*.yml|AUTH_SECRET_POLICY|policy data read by enforcement hooks"
  "hooks/handlers/*|HOOK_ENFORCEMENT|lifecycle enforcement handlers"
  "hooks/shared/*|HOOK_ENFORCEMENT|shared enforcement and approval libraries"
  "hooks/git/*|HOOK_ENFORCEMENT|git-layer guards"
  "hooks/local/lib/*|HOOK_ENFORCEMENT|health and upgrade engine libraries"
  "hooks/local/approve-local.sh|APPROVAL|approval minting"
  "hooks/local/write-bootstrap-approval.sh|APPROVAL|approval minting"
  "hooks/local/fusebase-flow-health-check.sh|VERDICT_ENGINE|health verdict and exit code"
  "hooks/local/upgrade.sh|UPGRADE|consumer upgrade path"
  "hooks/local/bootstrap-upgrade.sh|UPGRADE|consumer upgrade path"
  "hooks/local/stamp-*.sh|MANIFEST|integrity manifest generation"
  "hooks/local/verify-*.sh|MANIFEST|integrity manifest verification"
  "hooks/tests/run-tests.sh|RELEASE_GATE|release verification harness"
  "audit/*manifest*.json|MANIFEST|committed integrity manifests"
  ".github/workflows/*|RELEASE_GATE|publication gate CI"
  "state/approvals/*|APPROVAL|authorization artifacts"
  "VERSION|RELEASE|release identity"
  "hooks/local/lane-router.sh|LANE_POLICY|mechanical lane policy"
  "hooks/local/lane-assessment.py|LANE_POLICY|semantic lane policy"
)

json=0
if [ "${1:-}" = "--json" ]; then
  json=1
  shift
fi

usage() {
  echo "usage: lane-router.sh [--json] [--staged | --base <ref> | <path>...]" >&2
  exit 2
}

paths=()
case "${1:-}" in
  --staged)
    [ -z "${2:-}" ] || usage
    if ! changed="$(git -C "$ROOT" diff --cached --name-only 2>&1)"; then
      echo "[lane-router] ERROR: $changed" >&2
      exit 2
    fi
    [ -z "$changed" ] || mapfile -t paths <<< "$changed"
    ;;
  --base)
    [ -n "${2:-}" ] && [ -z "${3:-}" ] || usage
    if ! changed="$(git -C "$ROOT" diff --name-only "$2"..HEAD 2>&1)"; then
      echo "[lane-router] ERROR: $changed" >&2
      exit 2
    fi
    [ -z "$changed" ] || mapfile -t paths <<< "$changed"
    ;;
  "") usage ;;
  --*) usage ;;
  *) paths=("$@") ;;
esac

if [ "${#paths[@]}" -eq 0 ]; then
  echo "[lane-router] ERROR: no changed paths to classify" >&2
  exit 2
fi

match_rows=()
for path in "${paths[@]}"; do
  [ -n "$path" ] || continue
  for entry in "${HARD_SURFACES[@]}"; do
    glob="${entry%%|*}"
    rest="${entry#*|}"
    trigger="${rest%%|*}"
    reason="${rest#*|}"
    if [[ "$path" == $glob ]]; then
      match_rows+=("$path" "$trigger" "$reason")
      break
    fi
  done
done

if [ "${#match_rows[@]}" -gt 0 ]; then
  mechanical_result="FULL_REQUIRED"
  rc=10
else
  mechanical_result="NO_MECHANICAL_MATCH"
  rc=0
fi

if [ "$json" -eq 1 ]; then
  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "[lane-router] ERROR: $PYTHON_BIN not found" >&2
    exit 2
  fi
  printf '%s\0' "$mechanical_result" "${match_rows[@]}" | "$PYTHON_BIN" -c 'import json,sys
parts=sys.stdin.buffer.read().split(b"\0")[:-1]
values=[part.decode("utf-8", "surrogateescape") for part in parts]
rows=values[1:]
matches=[{"path": rows[i], "trigger_id": rows[i+1], "reason": rows[i+2]} for i in range(0, len(rows), 3)]
print(json.dumps({"schema_version": 1, "status": "ok", "mechanical_result": values[0], "matches": matches}, separators=(",", ":")))'
else
  if [ "$rc" -eq 10 ]; then
    for ((i=0; i<${#match_rows[@]}; i+=3)); do
      echo "FULL-REQUIRED: ${match_rows[$i]} [${match_rows[$((i+1))]}] ${match_rows[$((i+2))]}"
    done
    echo "[lane-router] FULL_REQUIRED — a mechanical trigger matched"
  else
    echo "[lane-router] NO_MECHANICAL_MATCH — semantic assessment is still required"
  fi
fi

exit "$rc"
