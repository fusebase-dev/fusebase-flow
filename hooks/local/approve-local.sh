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
#   bash hooks/local/approve-local.sh <action> <slug> [reason] --command '<exact command>'
#     --command is MANDATORY for any command-gated action (decision K19); it is optional
#     only for actions no command-policy rule references (e.g. protected_path_edit).
#   bash hooks/local/approve-local.sh protected_path_edit <slug> --path <p> [--path <p>]…
#     --path is MANDATORY for protected_path_edit (MAJOR 11): path_policy authorizes a
#     concrete path by membership in the artifact's `paths` array, so an artifact without
#     it is a file that LOOKS like an approval and can never authorize anything. Paths in
#     a DIGEST-BOUND category (fusebase_flow_internals, ci_cd_config) are refused here and
#     redirected to hooks/local/write-bootstrap-approval.sh, whose artifact is single-use.
#   bash hooks/local/approve-local.sh --inventory      # AC12: what is on disk + strict verdict
#   bash hooks/local/approve-local.sh --receipt emit <action> <slug> --deploy-hash <hash> \
#        [--command '<exact command>']                 # clone-durable deploy-report evidence
#   bash hooks/local/approve-local.sh --receipt verify <committed-report-file>
#     --receipt must be the FIRST argument; it dispatches to hooks/local/lib/approval-receipt.sh.
#     The artifact here is gitignored, so a committed report cites the RECEIPT, never this path.
# Example (Deploy session, on the operator's typed DP.6 phrase):
#   bash hooks/local/approve-local.sh production_deploy priority-fix 'approve deploy now' --command 'fusebase deploy'
#
# Binding (decision K2/K6 revised): --command records a sha256 of the exact command
# string TRIMMED ONLY — interior whitespace is never collapsed, because inside a quoted
# argument it is data. Pass the command byte-for-byte as it will be run. repo_id is
# always recorded. Both are enforced by the gate when present; an artifact without them
# stays action-scoped (legacy-compatible).
#
# Exit: 0 written and re-parsed OK; 2 bad usage / unknown action / unsafe slug (NO file
# written); 1 write or verification failure. Exit 2 also when --command is missing for a
# command-gated action (K19).

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

if [ "${1:-}" = "--receipt" ]; then
    shift
    exec bash "$ROOT/hooks/local/lib/approval-receipt.sh" "$@"
fi

ACTION=""
SLUG=""
REASON="operator local approval"
COMMAND_STR=""
PATHS_NL=""          # newline-separated --path values; crosses to python as ONE argv
INVENTORY=0
positional=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --inventory) INVENTORY=1; shift ;;
        --command) COMMAND_STR="${2:-}"; shift 2 ;;
        --path) PATHS_NL="${PATHS_NL}${2:-}"$'\n'; shift 2 ;;
        --help|-h) sed -n '2,44p' "$0"; exit 0 ;;
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

if [ "$INVENTORY" -eq 1 ]; then
    exec python3 "$ROOT/hooks/local/lib/approval_inventory.py" --root "$ROOT"
fi

if [ -z "$ACTION" ] || [ -z "$SLUG" ]; then
    cat >&2 <<EOF
Usage: $0 <action> <slug> [reason] --command '<exact command>'
       $0 --inventory

--command is mandatory for command-gated actions (K19); without it the artifact would
authorize every matching command in this repository.

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
    "$ROOT" "$ACTION" "$SLUG" "$REASON" "$COMMAND_STR" "$PATHS_NL" <<'PY'
import json, os, re, sys, tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

root, action, slug, reason, command_str, paths_nl = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
root_path = Path(root)
sys.path.insert(0, str(root_path / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    SCHEMA_VERSION, compute_command_digest, compute_repo_id, evaluate_artifact,
)
from shared.path_policy import _DIGEST_BOUND_OPERATIONS, is_protected  # noqa: E402
from shared.policy_loader import get_policy  # noqa: E402

approved_paths = [p for p in paths_nl.split("\n") if p.strip()]

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

# TRIPWIRE (decision K19): --command is MANDATORY for any action a command-policy
# require_approval rule can demand. An unbound artifact authorizes EVERY matching command
# in the repo, so the documented mint path must not be able to produce one. Actions that
# no command rule references (protected_path_edit, health_check_deferral) stay optional.
try:
    cmd_policy = get_policy("command-policy", root=root_path)
except BaseException as e:                        # noqa: BLE001 — cannot prove gating -> stop
    print(f"[approve-local] ERROR: command-policy could not be read ({e!r}), so whether "
          f"{action!r} is command-gated cannot be determined. Refusing to write.",
          file=sys.stderr)
    sys.exit(2)
command_gated = set()
for rule in (cmd_policy.get("require_approval") if isinstance(cmd_policy, dict) else None) or []:
    if not isinstance(rule, dict):
        continue
    one = rule.get("action")
    if isinstance(one, str) and one.strip():
        command_gated.add(one.strip())
    for a in rule.get("any_of") or []:
        if isinstance(a, str) and a.strip():
            command_gated.add(a.strip())
if action in command_gated and not command_str.strip():
    print(f"[approve-local] ERROR: {action!r} is command-gated, so --command is required. "
          f"An artifact without it authorizes every matching command in this repo (K19).\n"
          f"[approve-local] Re-run with the exact command, e.g.:\n"
          f"  bash hooks/local/approve-local.sh {action} {slug} --command '<exact command>'",
          file=sys.stderr)
    sys.exit(2)

# TRIPWIRE (MAJOR 11): `protected_path_edit` is authorized by PATH MEMBERSHIP — path_policy
# accepts an artifact only when the queried path is in its `paths` array. This writer emitted
# no `paths` at all, so every artifact it produced for this action authorized NOTHING while
# printing "artifact written + re-verified". A gate-shaped file that gates nothing is worse
# than no file: the operator/agent believes the sanctioned path was taken. Refuse instead.
if action == "protected_path_edit":
    if not approved_paths:
        print("[approve-local] ERROR: protected_path_edit requires at least one --path. "
              "path_policy authorizes a concrete path by membership in the artifact's `paths` "
              "array, so an artifact without it can never authorize any edit.\n"
              f"[approve-local] e.g.  bash hooks/local/approve-local.sh {action} {slug} "
              "--path <repo-relative-path>", file=sys.stderr)
        sys.exit(2)
    # A digest-bound category needs the SINGLE-USE writer; a plain path+TTL artifact is
    # rejected there by construction (no `operation`, no `tree_digest`), so writing one here
    # would again produce a file that silently authorizes nothing.
    for p in approved_paths:
        cat = is_protected(p)[1]
        if cat in _DIGEST_BOUND_OPERATIONS:
            print(f"[approve-local] ERROR: {p!r} is in the digest-bound category {cat!r}, which "
                  "requires a SINGLE-USE artifact bound to the exact staged changeset. This "
                  "writer cannot produce one.\n"
                  "[approve-local] Stage the change, then:\n"
                  f"  bash hooks/local/write-bootstrap-approval.sh --category {cat}",
                  file=sys.stderr)
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
    # Additive (M9): drives the stale-approval age warning. Schema-optional — an artifact
    # written before this field shipped reports age=unknown; it is never a reject reason.
    "created_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "approved_by": os.environ.get("USER") or os.environ.get("USERNAME") or "operator",
    "ticket": slug,                         # AUDIT METADATA ONLY — not a binding (K3)
    "reason": reason,
    "repo_id": compute_repo_id(root_path),
}
if command_str:
    data["command_digest"] = compute_command_digest(command_str)
if approved_paths:
    data["paths"] = approved_paths          # protected-paths.yml exception_artifact contract

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
    print(f"[approve-local] paths authorized ({len(approved_paths)}): "
          f"{', '.join(approved_paths)}")
print("[approve-local] hooks honor this until it expires. Delete the file to revoke.")
PY
