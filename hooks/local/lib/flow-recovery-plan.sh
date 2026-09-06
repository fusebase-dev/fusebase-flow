#!/usr/bin/env bash

FFRP_STATUS_REL="state/audit/flow-recovery-status.json"
FFRP_APPLIED=""
FFRP_VERIFIED=""
FFRP_UNCERTAIN=""
FFRP_PLANNED=""
FFRP_PLAN_ID=""
FFRP_ROOT=""
FFRP_NEW_ATTEMPT=0

ffrp_write() {
  local status="$1" exit_code="$2" note="${3:-}" path="$FFRP_ROOT/$FFRP_STATUS_REL"
  mkdir -p "$(dirname "$path")" || return 1
  FFRP_STATUS="$status" FFRP_EXIT="$exit_code" FFRP_NOTE="$note" \
  FFRP_ROOT_ENV="$FFRP_ROOT" FFRP_APPLIED_ENV="$FFRP_APPLIED" \
  FFRP_VERIFIED_ENV="$FFRP_VERIFIED" FFRP_PLANNED_ENV="$FFRP_PLANNED" \
  FFRP_UNCERTAIN_ENV="$FFRP_UNCERTAIN" \
  FFRP_PLAN_ID_ENV="$FFRP_PLAN_ID" FFRP_NEW_ATTEMPT_ENV="$FFRP_NEW_ATTEMPT" \
    python3 -I -S -c '
import datetime, hashlib, json, os, pathlib, tempfile
path = pathlib.Path(os.sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
applied = [x for x in os.environ["FFRP_APPLIED_ENV"].split(",") if x]
verified = [x for x in os.environ["FFRP_VERIFIED_ENV"].split(",") if x]
uncertain = [x for x in os.environ["FFRP_UNCERTAIN_ENV"].split(",") if x]
planned = [x for x in os.environ["FFRP_PLANNED_ENV"].split(",") if x]
previous = {}
if path.is_file():
    try:
        previous = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        previous = {}
attempts = previous.get("attempts", []) if isinstance(previous.get("attempts"), list) else []
if os.environ["FFRP_NEW_ATTEMPT_ENV"] == "1":
    attempts.append({"started_at": now, "resumed_applied_surfaces": applied.copy()})
root = pathlib.Path(os.environ["FFRP_ROOT_ENV"])
backup_paths = sorted(
    str(item.relative_to(root)).replace("\\", "/")
    for pattern in ("*.pre-refresh-*", ".claude/settings.json.pre-flow-merge", ".git/hooks/*.pre-flow*")
    for item in root.glob(pattern) if item.is_file()
)
prior_artifacts = previous.get("backup_artifacts", [])
known = {row.get("path"): row for row in prior_artifacts if isinstance(row, dict)} \
    if isinstance(prior_artifacts, list) else {}
for relative in backup_paths:
    if relative not in known:
        known[relative] = {"path": relative, "sha256": hashlib.sha256((root / relative).read_bytes()).hexdigest()}
doc = {
    "schema_version": 2,
    "plan_id": os.environ["FFRP_PLAN_ID_ENV"],
    "status": os.environ["FFRP_STATUS"],
    "exit_code": None if os.environ["FFRP_EXIT"] == "" else int(os.environ["FFRP_EXIT"]),
    "repo_root": os.environ["FFRP_ROOT_ENV"],
    "planned_surfaces": planned,
    "applied_surfaces": applied,
    "verified_surfaces": verified,
    "uncertain_surfaces": uncertain,
    "pending_surfaces": [x for x in planned if x not in applied],
    "backup_paths": backup_paths,
    "backup_artifacts": [known[key] for key in sorted(known)],
    "attempts": attempts,
    "note": os.environ["FFRP_NOTE"],
    "updated_at": now,
}
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(doc, handle, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(tmp, path)
' "$path"
  FFRP_NEW_ATTEMPT=0
}

ffrp_begin() {
  FFRP_ROOT="$1"
  FFRP_PLANNED="$2"
  FFRP_PLAN_ID="$3"
  FFRP_APPLIED=""
  FFRP_VERIFIED=""
  FFRP_UNCERTAIN=""
  local path="$FFRP_ROOT/$FFRP_STATUS_REL" restored
  restored="$(FFRP_EXPECTED_PLAN="$FFRP_PLAN_ID" python3 -I -S - "$path" <<'PY'
import json, os, pathlib, sys
path = pathlib.Path(sys.argv[1])
try:
    value = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit
if value.get("schema_version") == 2 and value.get("plan_id") == os.environ["FFRP_EXPECTED_PLAN"] \
        and value.get("status") in {"in_progress", "partial"}:
    applied = value.get("applied_surfaces", [])
    verified = value.get("verified_surfaces", [])
    if isinstance(applied, list) and isinstance(verified, list):
        print(",".join(x for x in applied if isinstance(x, str)))
        print(",".join(x for x in verified if isinstance(x, str)))
PY
)"
  if [ -n "$restored" ]; then
    FFRP_APPLIED="$(printf '%s\n' "$restored" | sed -n '1p')"
    FFRP_VERIFIED="$(printf '%s\n' "$restored" | sed -n '2p')"
  fi
  FFRP_NEW_ATTEMPT=1
  ffrp_write "in_progress" "" "prevalidated recovery plan; prior progress reconciled"
}

ffrp_applied() {
  local surface="$1"
  case ",$FFRP_APPLIED," in
    *,"$surface",*) ;;
    *) FFRP_APPLIED="${FFRP_APPLIED:+$FFRP_APPLIED,}$surface" ;;
  esac
  ffrp_write "in_progress" "" "surface applied and pending surfaces require verification"
  if [ "${FUSEBASE_FLOW_TEST_FAIL_AFTER_SURFACE:-}" = "$surface" ]; then
    return 1
  fi
}

ffrp_finish() {
  ffrp_write "$1" "$2" "${3:-}"
}

ffrp_verified() {
  FFRP_VERIFIED="$1"
  FFRP_UNCERTAIN="$2"
  ffrp_write "in_progress" "" "fresh post-apply verification recorded"
}

ffrp_owned_snapshot() {
  python3 -I -S - "$1" "$2" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
relative = sys.argv[2]
path = root / relative
manifest = json.loads((root / "audit/managed-content-manifest.json").read_text(encoding="utf-8"))
expected = next((item.get("sha256") for item in manifest.get("files", manifest.get("assets", []))
                 if isinstance(item, dict) and item.get("path") == relative), None)
if not isinstance(expected, str) or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
    raise SystemExit(1)
PY
}
