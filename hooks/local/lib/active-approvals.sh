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
  local artifact_file artifact_basename summary rc deferred_list cid ff_root ff_project
  # CODE root (where hooks/shared lives) is resolved from THIS FILE, not the cwd or the
  # git root: artifacts are discovered relative to the cwd (the project being inspected),
  # but the shared loader must be imported from the Flow install this lib belongs to.
  ff_root="$( cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && { pwd -W 2>/dev/null || pwd; } )"
  [ -d "$ff_root/hooks/shared" ] || ff_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  # TRIPWIRE (MSYS): a Windows python cannot resolve an MSYS "/tmp/..." path, so the
  # inspected project's root must cross as a NATIVE path or the strict_approvals read
  # silently fails and every artifact is judged in compat mode.
  ff_project="$( pwd -W 2>/dev/null || pwd )"
  while IFS= read -r artifact_file; do
    if [ -z "$artifact_file" ]; then continue; fi
    artifact_basename=$(basename "$artifact_file")
    summary=$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$artifact_file" "$ff_root" "$ff_project" <<'PY' 2>/dev/null
import sys
from pathlib import Path
try:
    p, root, project = sys.argv[1], sys.argv[2], sys.argv[3]
    sys.path.insert(0, str(Path(root) / "hooks"))
    # Shared expiry/schema semantics (decision K1) — the SAME loader the gates use, so
    # this report can never disagree with them. Replaces the old `expires and expires <
    # now` string compare, under which a missing/empty expires_at read as "valid forever".
    from shared.approval_artifact import (
        evaluate_artifact, expiry_state, filename_action, is_acceptable, load,
    )
    # strict_approvals (K7) is read from the INSPECTED project's merged policy, not the
    # Flow install's: under strict an expiry-less artifact no longer authorizes anything,
    # so it must not be reported as active either (the report and the gates cannot differ).
    try:
        from shared.policy_loader import get_policy
        strict = get_policy("approval-policy", root=Path(project)).get("strict_approvals") is True
    except Exception:
        strict = False
    art = load(p)
    if art is None:
        sys.exit(2)
    data = art.data
    verdict = evaluate_artifact(data, expected_action=filename_action(p))
    # TRIPWIRE: ARRAY CONTRACT. fusebase-flow-health-check.sh reads ACTIVE_ARTIFACTS /
    # ARTIFACT_NOTES / DEFERRED_CHECKS / DEFERRED_BY_ARTIFACT and classifies
    # EXCEPTION_IN_EFFECT from them. Only artifacts that genuinely still AUTHORIZE may
    # exit 0 (= land in ACTIVE_ARTIFACTS); the new status text goes in the NOTE only.
    # Changing which artifacts exit 0, or the note/array shape, silently breaks that
    # classification.
    if not is_acceptable(verdict, strict=strict):
        sys.exit(1)
    status = expiry_state(data)
    expires = (data or {}).get('expires_at', '') or ''
    if not isinstance(expires, str):
        expires = ''
    # Restrict scope to ASCII so it renders cleanly on any console codec
    scope = ((data or {}).get('scope', '') or '')
    scope = (scope if isinstance(scope, str) else '').encode('ascii', errors='replace').decode('ascii')[:80]
    paths = (data or {}).get('paths', []) or []
    deferred = (data or {}).get('deferred_checks', []) or []
    if deferred:
        print(f"deferred_checks={len(deferred)} status={status} expires={expires} scope=\"{scope}\"")
    else:
        print(f"paths={len(paths)} status={status} expires={expires} scope=\"{scope}\"")
    sys.exit(0)
except SystemExit:
    raise
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
