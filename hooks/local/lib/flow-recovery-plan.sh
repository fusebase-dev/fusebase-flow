#!/usr/bin/env bash

FFRP_STATUS_REL="state/audit/flow-recovery-status.json"
FFRP_APPLIED=""
FFRP_PLANNED=""
FFRP_ROOT=""

ffrp_write() {
  local status="$1" exit_code="$2" note="${3:-}" path="$FFRP_ROOT/$FFRP_STATUS_REL"
  mkdir -p "$(dirname "$path")" || return 1
  FFRP_STATUS="$status" FFRP_EXIT="$exit_code" FFRP_NOTE="$note" \
  FFRP_ROOT_ENV="$FFRP_ROOT" FFRP_APPLIED_ENV="$FFRP_APPLIED" FFRP_PLANNED_ENV="$FFRP_PLANNED" \
    python3 -I -S -c '
import datetime, json, os, pathlib, tempfile
path = pathlib.Path(os.sys.argv[1])
applied = [x for x in os.environ["FFRP_APPLIED_ENV"].split(",") if x]
planned = [x for x in os.environ["FFRP_PLANNED_ENV"].split(",") if x]
doc = {
    "schema_version": 1,
    "status": os.environ["FFRP_STATUS"],
    "exit_code": None if os.environ["FFRP_EXIT"] == "" else int(os.environ["FFRP_EXIT"]),
    "repo_root": os.environ["FFRP_ROOT_ENV"],
    "applied_surfaces": applied,
    "pending_surfaces": [x for x in planned if x not in applied],
    "backup_paths": sorted(
        str(item.relative_to(pathlib.Path(os.environ["FFRP_ROOT_ENV"]))).replace("\\", "/")
        for pattern in ("*.pre-refresh-*", ".claude/settings.json.pre-flow-merge", ".git/hooks/*.pre-flow*")
        for item in pathlib.Path(os.environ["FFRP_ROOT_ENV"]).glob(pattern)
        if item.is_file()
    ),
    "note": os.environ["FFRP_NOTE"],
    "updated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(doc, handle, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(tmp, path)
' "$path"
}

ffrp_begin() {
  FFRP_ROOT="$1"
  FFRP_PLANNED="$2"
  FFRP_APPLIED=""
  ffrp_write "in_progress" "" "prevalidated repair plan"
}

ffrp_applied() {
  local surface="$1"
  case ",$FFRP_APPLIED," in
    *,"$surface",*) ;;
    *) FFRP_APPLIED="${FFRP_APPLIED:+$FFRP_APPLIED,}$surface" ;;
  esac
  ffrp_write "in_progress" "" "surface applied and pending surfaces require verification"
  if [ "${FUSEBASE_FLOW_TEST_FAIL_AFTER_SURFACE:-}" = "$surface" ]; then
    return 70
  fi
}

ffrp_finish() {
  ffrp_write "$1" "$2" "${3:-}"
}
