#!/usr/bin/env bash
# Fusebase Flow — approve-local
# Author an approval artifact in state/approvals/ for an action
# defined in policies/approval-policy.yml.
#
# WHO RUNS THIS: the operator, OR the Deploy/AI-Developer session ON THE OPERATOR'S
# BEHALF once the operator has given the authorization signal — the DP.6 deploy phrase
# `approve deploy now` (Full lane; forgiving match — any case/spacing) or a plain go-ahead
# (Lightweight lane, DP.12). The phrase/go-ahead IS the authorization; the artifact is
# bookkeeping the deploy gate consumes. The gate checks the artifact's schema, parsed
# expiry, body/filename action agreement and command/repo binding — NOT the author
# (`approved_by` is audit metadata; see policies/approval-policy.yml § trust model, K3).
# Do NOT force the operator to run this by hand after they've approved in chat. Authoring
# an approval WITHOUT that operator signal is self-approval and is forbidden
# (role-discipline Deploy phase DP.1).
#
# Usage:
#   bash hooks/local/approve-local.sh <action> <slug> [reason] [--command '<exact command>']
# Example (Deploy session, on the operator's typed DP.6 phrase):
#   bash hooks/local/approve-local.sh production_deploy priority-fix 'approve deploy now'
#
# Binding (decision K2/K6): --command records a sha256 of the exact command string after
# whitespace collapse, so the artifact authorizes THAT command only. repo_id is always
# recorded. Both are enforced by the gate when present; an artifact without them stays
# action-scoped (legacy-compatible).
#
# Exit: 0 written and re-parsed OK; 2 bad usage / unknown action / unsafe slug (NO file
# written); 1 write or verification failure.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

ACTION=""
SLUG=""
REASON="operator local approval"
COMMAND_STR=""
positional=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --command) COMMAND_STR="${2:-}"; shift 2 ;;
        --help|-h) sed -n '2,29p' "$0"; exit 0 ;;
        --*) echo "[approve-local] unknown option: $1" >&2; exit 2 ;;
        *)
            case "$positional" in
                0) ACTION="$1" ;;
                1) SLUG="$1" ;;
                2) REASON="$1" ;;
                *) echo "[approve-local] unexpected argument: $1" >&2; exit 2 ;;
            esac
            positional=$((positional + 1)); shift ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "[approve-local] python3 not on PATH — cannot author or read approval artifacts." >&2
    exit 1
fi

if [ -z "$ACTION" ] || [ -z "$SLUG" ]; then
    cat >&2 <<EOF
Usage: $0 <action> <slug> [reason] [--command '<exact command>']

Available actions come from policies/approval-policy.yml require_approval keys
(plus any approval-policy.local.yml override).
EOF
    exit 2
fi

# SINGLE-LANGUAGE SERIALIZATION (AC10). Every value crosses as argv and the whole object
# is produced by json.dumps — nothing is interpolated into JSON text or into Python source.
# The previous heredoc form interpolated $USER/$SLUG/$REASON/$ACTION unescaped into JSON
# AND $ACTION into Python source, so a quote, backslash, newline or $(...) in any of them
# produced a corrupt (or executable) artifact.
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - \
    "$ROOT" "$ACTION" "$SLUG" "$REASON" "$COMMAND_STR" <<'PY'
import json, os, re, sys, tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

root, action, slug, reason, command_str = (sys.argv[1], sys.argv[2], sys.argv[3],
                                           sys.argv[4], sys.argv[5])
root_path = Path(root)
sys.path.insert(0, str(root_path / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    SCHEMA_VERSION, compute_command_digest, compute_repo_id, evaluate_artifact,
)
from shared.policy_loader import get_policy  # noqa: E402

# TRIPWIRE: validate BEFORE any filesystem write. Both guards below are NEW — the old
# script constructed the filename from unvalidated components, so `../../escape` was a
# path-traversal write and an unknown action produced a file no gate would ever read.
SAFE_SLUG = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

policy = get_policy("approval-policy", root=root_path)          # merged with .local.yml
known = set((policy.get("require_approval") or {}).keys())
if action not in known:
    print(f"[approve-local] ERROR: unknown action {action!r}. Known actions: "
          f"{', '.join(sorted(known)) or '(none — approval-policy.yml has no require_approval)'}",
          file=sys.stderr)
    sys.exit(2)
if not SAFE_SLUG.match(slug):
    print(f"[approve-local] ERROR: slug {slug!r} must match [A-Za-z0-9._-]{{1,64}} "
          "(guards path traversal and same-day filename collisions).", file=sys.stderr)
    sys.exit(2)

ra = policy.get("require_approval", {}).get(action) or {}
ttl = ra.get("artifact_ttl_minutes", 60)
if isinstance(ttl, dict):
    mode = policy.get("workflow_mode", "direct_to_main")
    ttl = ttl.get(mode, ttl.get("direct_to_main", 60))
try:
    ttl = int(ttl)
except (TypeError, ValueError):
    ttl = 60

now = datetime.now(timezone.utc)
expires_at = (now + timedelta(minutes=ttl)).strftime("%Y-%m-%dT%H:%M:%SZ")

data = {
    "schema_version": SCHEMA_VERSION,
    "action": action,                       # MUST equal the filename action (AC1)
    "scope": slug,
    "expires_at": expires_at,               # mandatory, parseable UTC (AC2)
    "approved_by": os.environ.get("USER") or os.environ.get("USERNAME") or "operator",
    "ticket": slug,                         # AUDIT METADATA ONLY — not a binding (K3)
    "reason": reason,
    "repo_id": compute_repo_id(root_path),
}
if command_str:
    data["command_digest"] = compute_command_digest(command_str)

approvals = root_path / "state" / "approvals"
approvals.mkdir(parents=True, exist_ok=True)
artifact = approvals / f"{action}-{slug}-{now.strftime('%Y%m%d')}.json"

# Atomic: write a temp file in the SAME directory, then os.replace. An interrupted run
# leaves the temp file, never a half-written artifact a gate might read as valid.
payload = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
fd, tmp_name = tempfile.mkstemp(dir=str(approvals), prefix=".approve-local-", suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(payload)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_name, artifact)
except BaseException:
    try:
        os.unlink(tmp_name)
    except OSError:
        pass
    raise

# Re-read and re-validate through the SAME loader the gate uses, so "written" can never
# be reported for an artifact the gate would reject.
reloaded = json.loads(artifact.read_text(encoding="utf-8"))
verdict = evaluate_artifact(
    reloaded, expected_action=action,
    command_digest=data.get("command_digest"), repo_id=data["repo_id"],
)
if verdict.value != "VALID" or reloaded != data:
    print(f"[approve-local] ERROR: verification failed after write (verdict={verdict.value}); "
          f"removing {artifact}", file=sys.stderr)
    artifact.unlink(missing_ok=True)
    sys.exit(1)

bound = " command-bound" if "command_digest" in data else ""
print(f"[approve-local] artifact written + re-verified: {artifact} "
      f"(schema v{SCHEMA_VERSION}; expires {expires_at}; repo-bound{bound})")
if action == "protected_path_edit":
    print("[approve-local] note: protected_path_edit also needs a 'paths' array. For a "
          "Flow-internals changeset use hooks/local/write-bootstrap-approval.sh instead — "
          "it is digest-bound and single-use.")
print("[approve-local] hooks honor this until it expires. Delete the file to revoke.")
PY
