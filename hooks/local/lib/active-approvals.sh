#!/usr/bin/env bash
# Fusebase Flow — active approval / deferral artifact discovery (health-check lib).
#
# PROVENANCE:
#   Extracted from fusebase-flow-health-check.sh per FR-25 (the engine reached the
#   800-line ceiling when the U7 PARTIAL_UPGRADE section landed). This is a genuine
#   responsibility seam — "discover non-expired approval/deferral artifacts" — not a
#   mechanical split. Lives at hooks/local/lib/ (outside the CLI refresh manifest).
#   Sourced by the engine; populates arrays in the CALLER's scope.
#
# WHAT IT POPULATES (in the sourcing shell's scope — same as the inline code it
# replaced; the engine declares these arrays before sourcing/calling):
#   ACTIVE_ARTIFACTS[]      basenames of non-expired approval artifacts
#   ARTIFACT_NOTES[]        "<basename>: <summary>" lines for the report
#   DEFERRED_CHECKS[]       check_ids deferred via health_check_deferral-*.json
#   DEFERRED_BY_ARTIFACT[]  parallel array — the artifact that authorized each check_id
#
# Two artifact types under state/approvals/:
#   - protected_path_edit-*.json  — authorizes protected-path edits (lists `paths`).
#   - health_check_deferral-*.json — authorizes deferral of specific check_ids
#     (lists `deferred_checks`; the engine reclassifies matching drift to
#     LOCAL_DEFERRED -> EXCEPTION_IN_EFFECT). See docs/health-check-deferrals.md.

ffhc_collect_active_approvals() {
  [ -d "state/approvals" ] && command -v python3 >/dev/null 2>&1 || return 0
  local artifact_file artifact_basename summary rc deferred_list cid
  while IFS= read -r artifact_file; do
    if [ -z "$artifact_file" ]; then continue; fi
    artifact_basename=$(basename "$artifact_file")
    summary=$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$artifact_file" <<'PY' 2>/dev/null
import json, sys, time
try:
    p = sys.argv[1]
    data = json.loads(open(p, encoding='utf-8').read())
    expires = data.get('expires_at', '')
    now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    if expires and expires < now:
        sys.exit(1)  # expired - skip
    # Restrict scope to ASCII so it renders cleanly on any console codec
    scope = (data.get('scope', '') or '').encode('ascii', errors='replace').decode('ascii')[:80]
    # Different artifact types use different list fields
    paths = data.get('paths', []) or []
    deferred = data.get('deferred_checks', []) or []
    if deferred:
        print(f"deferred_checks={len(deferred)} expires={expires} scope=\"{scope}\"")
    else:
        print(f"paths={len(paths)} expires={expires} scope=\"{scope}\"")
    sys.exit(0)
except Exception:
    sys.exit(2)
PY
)
    rc=$?
    # Windows CRLF guard: Python print() on Windows emits CRLF; bash $() strips the
    # trailing LF only, leaving a stray CR. Defensive strip so ARTIFACT_NOTES renders
    # cleanly on any platform.
    summary="${summary//$'\r'/}"
    if [ "$rc" -eq 0 ]; then
      ACTIVE_ARTIFACTS+=("$artifact_basename")
      ARTIFACT_NOTES+=("$artifact_basename: $summary")
      if [[ "$artifact_basename" == health_check_deferral-* ]]; then
        deferred_list=$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$artifact_file" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.loads(open(sys.argv[1], encoding='utf-8').read())
    for cid in (data.get('deferred_checks') or []):
        if isinstance(cid, str) and cid:
            print(cid)
except Exception:
    pass
PY
)
        while IFS= read -r cid; do
          # Windows CRLF guard (idempotent on Linux/Mac): strip the stray CR so a
          # multi-entry deferral list still matches check_ids in record_drift.
          cid="${cid%$'\r'}"
          [ -z "$cid" ] && continue
          DEFERRED_CHECKS+=("$cid")
          DEFERRED_BY_ARTIFACT+=("$artifact_basename")
        done <<< "$deferred_list"
      fi
    fi
  done < <(find state/approvals -maxdepth 2 -name '*.json' -type f 2>/dev/null)
  return 0
}
