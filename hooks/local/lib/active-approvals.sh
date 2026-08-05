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
#   ARTIFACT_NOTES[]        "<basename>: <summary>" lines for the report (ONE line each)
#   DEFERRED_CHECKS[]       check_ids deferred via health_check_deferral-*.json
#   DEFERRED_BY_ARTIFACT[]  parallel array — the artifact that authorized each check_id
#   APPROVAL_WARNINGS[]     "<basename>: <age/expiry/paths>" for still-active
#                           protected_path_edit artifacts older than
#                           approval-policy.yml: stale_approval_warn_after_days (M9).
#                           VISIBILITY ONLY: the engine prints these OUTSIDE every verdict
#                           array and count — never LOCAL_DRIFT / LOCAL_BROKEN /
#                           LOCAL_UNVERIFIED — and they invalidate no approval. An artifact
#                           that warns still authorizes and still lands in ACTIVE_ARTIFACTS.
#   APPROVAL_POLICY_ERRORS[]  configuration errors that make approval-policy unloadable.
#                           FAIL CLOSED: while one is present NO artifact is reported active,
#                           because the merged policy that decides acceptance strictness could
#                           not be read. Substituting strict=false + the shipped threshold is
#                           what let a local file enabling strict_approvals disable its own
#                           strict mode. The FR-07 gates deny in this state (path_policy raises
#                           ApprovalPolicyError); this array is how the operator SEES why.
#
# Two artifact types under state/approvals/:
#   - protected_path_edit-*.json  — authorizes protected-path edits (lists `paths`).
#   - health_check_deferral-*.json — authorizes deferral of specific check_ids
#     (lists `deferred_checks`; the engine reclassifies matching drift to
#     LOCAL_DEFERRED -> EXCEPTION_IN_EFFECT). See docs/health-check-deferrals.md.

# Report a configuration error that makes the merged approval policy unreadable. Runs BEFORE the
# artifact loop and independently of it: a broken policy with zero artifacts on disk is still a
# finding, and the loop body would never execute to surface it.
_ffhc_probe_approval_policy() {   # <flow-code-root> <inspected-project-root>
  local out rc
  out=$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$1" "$2" <<'PY' 2>&1
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "hooks"))
# An ImportError / SystemExit here is a missing hook runtime, not a policy defect: it exits
# non-3 and is reported by the environment checks, not as a configuration error.
from shared.policy_loader import get_policy
try:
    get_policy("approval-policy", root=Path(sys.argv[2]))
except Exception as e:
    print(str(e).replace("\n", " ")[:300])
    sys.exit(3)
sys.exit(0)
PY
)
  rc=$?
  [ "$rc" -eq 3 ] || return 0
  out="${out//$'\r'/}"; out="${out//$'\n'/ }"
  APPROVAL_POLICY_ERRORS+=("approval-policy did not load: ${out:-unknown error}")
  return 1
}

ffhc_collect_active_approvals() {
  command -v python3 >/dev/null 2>&1 || return 0
  local artifact_file artifact_basename summary warn_line rc deferred_list cid ff_root ff_project
  # CODE root (where hooks/shared lives) is resolved from THIS FILE, not the cwd or the
  # git root: artifacts are discovered relative to the cwd (the project being inspected),
  # but the shared loader must be imported from the Flow install this lib belongs to.
  ff_root="$( cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && { pwd -W 2>/dev/null || pwd; } )"
  [ -d "$ff_root/hooks/shared" ] || ff_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  # TRIPWIRE (MSYS): a Windows python cannot resolve an MSYS "/tmp/..." path, so the
  # inspected project's root must cross as a NATIVE path or the strict_approvals read
  # silently fails and every artifact is judged in compat mode.
  ff_project="$( pwd -W 2>/dev/null || pwd )"
  _ffhc_probe_approval_policy "$ff_root" "$ff_project" || return 0
  [ -d "state/approvals" ] || return 0
  # TRIPWIRE: -print0 / read -d '' — a newline in a FILENAME splits the record before any
  # per-artifact validation runs, so the traversal must be unsplittable for the same reason
  # the deferred_checks transport is (backlog self-granting-health-deferral).
  while IFS= read -r -d '' artifact_file; do
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
        accept_with_audit, evaluate_artifact, expiry_state, filename_action, load,
        now_utc, parse_expiry,
    )
    # strict_approvals (K7) is read from the INSPECTED project's merged policy, not the
    # Flow install's: under strict an expiry-less artifact no longer authorizes anything,
    # so it must not be reported as active either (the report and the gates cannot differ).
    # stale_approval_warn_after_days (M9) comes from the SAME merged read: one policy load
    # per artifact, and the age report can never be based on a different policy than the
    # strictness it reports beside it.
    # FAIL CLOSED: a policy that will not load exits 3, so this artifact is NOT reported active
    # and the caller records a configuration error. Substituting strict=False here let a local
    # file that ENABLES strict_approvals disable its own strict mode.
    threshold_days = 7
    from shared.policy_loader import get_policy
    try:
        _appr = get_policy("approval-policy", root=Path(project))
    except Exception:
        sys.exit(3)
    strict = _appr.get("strict_approvals") is True
    _thr = _appr.get("stale_approval_warn_after_days")
    if isinstance(_thr, int) and not isinstance(_thr, bool) and _thr > 0:
        threshold_days = _thr
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
    # TRIPWIRE: accept through accept_with_audit, never bare is_acceptable — a compat
    # acceptance that leaves no audit entry is the pre-fix silent behaviour (AC11 / K7).
    if not accept_with_audit(verdict, strict=strict, carrier="active-approvals",
                             artifact_path=p, action=filename_action(p),
                             root=Path(project)):
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
    # M9 age warning — SECOND line, prefixed STALE_WARN:, so ARTIFACT_NOTES stays one line
    # per artifact (the array contract above). Only still-active protected_path_edit
    # artifacts qualify: an expired/deferral artifact authorizes no protected path, so its
    # age is not a finding. Warning-or-not never affects this script's exit code.
    if filename_action(p) == "protected_path_edit" and status in ("active", "legacy-no-expiry"):
        # parse_expiry is the repo's ONE ISO-8601 parser (K1); reused for created_at so the
        # age can never be read under different rules than the expiry printed beside it.
        created = parse_expiry((data or {}).get("created_at"))
        if created is None:
            age, stale = "age=unknown (no created_at)", True
        else:
            days = (now_utc() - created).days
            age, stale = f"age={days}d", days >= threshold_days
        if stale:
            shown = [x for x in paths if isinstance(x, str) and x][:3]
            more = f" +{len(paths) - len(shown)} more" if len(paths) > len(shown) else ""
            plist = (", ".join(shown) + more) if shown else "(none listed)"
            plist = plist.encode('ascii', errors='replace').decode('ascii')[:200]
            print(f"STALE_WARN:{age}; threshold={threshold_days}d; "
                  f"expires={expires or 'none'}; protected paths: {plist}")
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
    # Split the optional STALE_WARN: second line off BEFORE the note is built — an
    # ARTIFACT_NOTES entry must stay exactly one line (array contract above), and the
    # warning must land in its own array so the engine can print it outside every count.
    warn_line=""
    case "$summary" in
      *$'\n'STALE_WARN:*)
        warn_line="${summary#*$'\n'STALE_WARN:}"
        summary="${summary%%$'\n'STALE_WARN:*}" ;;
    esac
    if [ "$rc" -eq 0 ]; then
      ACTIVE_ARTIFACTS+=("$artifact_basename")
      ARTIFACT_NOTES+=("$artifact_basename: $summary")
      if [ -n "$warn_line" ]; then APPROVAL_WARNINGS+=("$artifact_basename: $warn_line"); fi
      if [[ "$artifact_basename" == health_check_deferral-* ]]; then
        # TRIPWIRE (backlog self-granting-health-deferral): DEFERRED_CHECKS is the one
        # artifact-derived input that MOVES the verdict (record_drift reclassifies a matching
        # finding to LOCAL_DEFERRED => EXCEPTION_IN_EFFECT, exit 3). A check_id is
        # artifact-controlled text, so the old newline-delimited transport let ONE JSON element
        # split into TWO bash entries — an artifact granting itself a canonical check_id it
        # never carried. NUL-delimited: content cannot split the record. Read directly from
        # process substitution, never via $(...) — command substitution DISCARDS NUL bytes.
        while IFS= read -r -d '' entry; do
          # entry := 'K'<accepted id> | 'R'<rejected repr>. The one-char tag travels inside the
          # NUL record so the verdict never depends on a second, splittable channel.
          case "${entry:0:1}" in
            R)
              APPROVAL_WARNINGS+=("$artifact_basename: REJECTED malformed deferred check_id ${entry:1} — must full-match [A-Za-z0-9._-]{1,120}; not repaired, not deferred")
              continue ;;
            K) cid="${entry:1}" ;;
            *) continue ;;
          esac
          # Windows CRLF guard (idempotent on Linux/Mac): strip the stray CR so a
          # multi-entry deferral list still matches check_ids in record_drift.
          cid="${cid%$'\r'}"
          [ -z "$cid" ] && continue
          DEFERRED_CHECKS+=("$cid")
          DEFERRED_BY_ARTIFACT+=("$artifact_basename")
        done < <(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$artifact_file" <<'PY' 2>/dev/null
import json, re, sys
# TRIPWIRE: full-match or REJECT — NEVER sanitize. Deleting disallowed characters
# MANUFACTURES identifiers: 'claude\n_md_overlay' with the newline stripped becomes
# 'claude_md_overlay', a real canonical check_id. A repaired value that collides with a
# genuine id is strictly worse than a dropped one. re.fullmatch (not match+'$') because
# '$' also matches before a trailing newline — the exact character being defended against.
VALID = re.compile(r'[A-Za-z0-9._-]{1,120}')
out = sys.stdout.buffer
try:
    data = json.loads(open(sys.argv[1], encoding='utf-8').read())
    for cid in (data.get('deferred_checks') or []):
        if isinstance(cid, str) and VALID.fullmatch(cid):
            out.write(b'K' + cid.encode('utf-8') + b'\0')
        else:
            # repr() so a control character is shown, not replayed into the terminal;
            # ASCII-folded and capped so one hostile entry cannot flood the report.
            shown = repr(cid)[:120].encode('ascii', errors='replace')
            out.write(b'R' + shown + b'\0')
    out.flush()
except Exception:
    pass
PY
)
      fi
    fi
  done < <(find state/approvals -maxdepth 2 -name '*.json' -type f -print0 2>/dev/null)
  return 0
}
