#!/usr/bin/env bash
# Fusebase Flow — hook-wiring INTENT marker + the health engine's PreToolUse
# enforcement arm (S1).
#
# PROVENANCE:
#   Shipped v4.11.1+. Lives at hooks/local/lib/ — outside the FuseBase CLI refresh
#   manifest. Sourced by hooks/local/fusebase-flow-health-check.sh (reader) and
#   hooks/local/post-fusebase-update.sh (writer); never run standalone.
#
# WHY A DEDICATED MARKER:
#   The engine keyed only on the lifecycle event COUNT and on stop.py, so a tree whose
#   .claude/settings.json was wholesale-rewritten (every Flow hook stripped) was
#   indistinguishable from a tree that never opted in — both printed the benign
#   "opt-in default" line. Separating those two needs a record of INTENT. Reusing an
#   existing artifact (state/audit/cli-stop-baseline.json) was rejected: it couples
#   unrelated lifecycles, a future diagnostic writer could create it without opting in,
#   and file-presence carries no schema and no corruption handling.
#
# TRIPWIRE (detection contract): enforcement requires an exact canonical current or legacy
# PreToolUse command. A command that merely contains the handler path remains custom.
#
# TRIPWIRE (false-drift budget): a false alarm here is WORSE than the silence it replaces
#   — it trains operators to ignore the one check that reports missing FR-06/07/12
#   enforcement. Only two states may reach record_drift: a VALID, ENABLED, THIS-TREE
#   marker with the handler absent, and the same with settings.json absent. Every other
#   shape (absent / revoked / malformed / unparseable / inherited from another checkout)
#   reports UNVERIFIED or stays silent.

FFHC_HWI_REL="state/audit/flow-hook-wiring-intent.json"
FFHC_HWI_HANDLER="hooks/handlers/pre_tool_use.py"
FFHC_HWI_SCHEMA=2
FFHC_HWI_CHECK_ID="settings_json_flow_enforcement"
FFHC_HWI_RECOVER="bash hooks/local/post-fusebase-update.sh --wire-hooks"
FFHC_HWI_OPTOUT="bash hooks/local/post-fusebase-update.sh --forget-hook-wiring"

# ffhc_hwi_py: the interpreter used for the marker's JSON. -I isolates it (no script dir,
# no user site, no PYTHON* env), matching the boundary bootstrap-upgrade.sh established for
# anything that feeds a verdict.
ffhc_hwi_py() {
  local bin
  for bin in "${FUSEBASE_FLOW_PYTHON:-}" python3 python; do
    [ -n "$bin" ] || continue
    command -v "$bin" >/dev/null 2>&1 || continue
    "$bin" -I -S "$@"
    return $?
  done
  return 127
}

ffhc_hwi_have_py() {
  local bin
  for bin in "${FUSEBASE_FLOW_PYTHON:-}" python3 python; do
    [ -n "$bin" ] || continue
    command -v "$bin" >/dev/null 2>&1 && return 0
  done
  return 1
}

# ffhc_hwi_write <root> <true|false> — (re)write the marker with an explicit enabled state.
# The recorded repo_root is what makes an INHERITED marker (archive/zip copy of a tree that
# carries gitignored state/) legible as copied state instead of a false drift.
ffhc_hwi_write() {
  local root="$1" enabled="$2" surfaces="${3:-claude_settings}" path="$1/$FFHC_HWI_REL"
  MSYS2_ENV_CONV_EXCL=FFHC_HWI_ROOT FFHC_HWI_ROOT="$root" \
  FFHC_HWI_ENABLED="$enabled" FFHC_HWI_SURFACES="$surfaces" \
    ffhc_hwi_py -c '
import json, os, pathlib, tempfile
path = pathlib.Path(os.sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
enabled = os.environ["FFHC_HWI_ENABLED"] == "true"
surfaces = [item for item in os.environ["FFHC_HWI_SURFACES"].split(",") if item]
if path.is_file():
    try:
        current = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        current = None
    if isinstance(current, dict) and current.get("schema_version") == 2 \
            and current.get("enabled") == enabled \
            and current.get("repo_root") == os.environ["FFHC_HWI_ROOT"] \
            and current.get("surfaces") == surfaces:
        raise SystemExit
doc = {
    "schema_version": 2,
    "enabled": enabled,
    "repo_root": os.environ["FFHC_HWI_ROOT"],
    "surfaces": surfaces,
    "updated_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "written_by": "post-fusebase-update.sh",
}
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(doc, handle, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(tmp, path)
' "$path" || return 1
  return 0
}

# ffhc_hwi_record_wiring <root> <merge_rc> — the ONLY creation path. Records intent iff the
# tree ACHIEVED the wiring: ffhc_hwi_wired says the canonical handler is in .claude/settings.json
# NOW. A successful merge is necessary, never sufficient.
#
# TRIPWIRE (measured, v4.14.0): keying this on the merge's EXIT CODE recorded intent while
# enforcement was absent. settings-json-merge.py exits 0 having applied every other change, so a
# tree whose PreToolUse array was already occupied got an ENABLED marker with no handler — after
# which ffhc_hwi_check reports ENFORCEMENT STRIPPED and prescribes --wire-hooks, the command that
# produced the state. A loop that cannot converge. Do not reduce this back to `[ "$rc" = 0 ]`:
# "the merge exited 0" and "the handler is wired" are different facts.
#
# Return codes (the caller must be able to TELL — a silent no-op only moves the silence out):
#   0  intent recorded
#   1  marker write failed
#   3  merge rc nonzero        — caller may stay silent; it already reports the merge failure
#   4  merge rc 0, handler ABSENT (or settings.json gone) — caller MUST warn; nothing recorded
ffhc_hwi_record_wiring() {
  local root="$1" rc="$2" surfaces="${3:-claude_settings}"
  [ "$rc" = "0" ] || return 3
  ffhc_hwi_wired "$root" || return 4
  ffhc_hwi_write "$root" true "$surfaces" || return 1
  return 0
}

# ffhc_hwi_revoke <root> — the revocation lifecycle. Intent that can only ever be created is
# a false-drift generator: a tree that removed the block ON PURPOSE would alarm forever.
ffhc_hwi_revoke() {
  ffhc_hwi_write "$1" false ""
}

# ffhc_hwi_norm <path> — lowercased, forward-slashed, trailing-slash-free, MSYS-drive-folded.
#
# TRIPWIRE (measured): on Git-Bash the SAME tree is `/c/Users/…` from `pwd` and `C:/Users/…`
# from `git rev-parse --show-toplevel`. Without the drive fold, a writer and a reader that
# disagree on the form make every marker read FOREIGN — the arm then reports UNVERIFIED
# forever and the enforcement blind spot silently comes back.
ffhc_hwi_norm() {
  local p="${1//\\//}"
  p="${p%/}"
  p="${p,,}"
  case "$p" in
    /[a-z]/*) p="${p:1:1}:/${p:3}" ;;
    /[a-z])   p="${p:1:1}:" ;;
  esac
  printf '%s' "$p"
}

# ffhc_hwi_state <root> — one token on stdout:
#   ABSENT      no marker            -> not known to have opted in (today's line)
#   ENABLED     valid, enabled, this tree
#   REVOKED     valid, enabled:false -> deliberate opt-out
#   FOREIGN     valid but recorded for a different repo root -> copied state
#   INVALID     unparseable / wrong schema / no boolean `enabled`
#   NOPARSER    marker present, no python interpreter to validate it
#
# TRIPWIRE (MSYS): the repo-root comparison happens in SHELL, never inside the interpreter.
# Git-Bash rewrites POSIX-looking paths when it hands argv/env to a native python, so a root
# passed through the environment comes back as a different string than the one the writer
# stored — every Git-Bash tree would read FOREIGN and the whole arm would go inert.
ffhc_hwi_state() {
  local root="$1" path="$1/$FFHC_HWI_REL" out token recorded
  [ -f "$path" ] || { echo "ABSENT"; return 0; }
  ffhc_hwi_have_py || { echo "NOPARSER"; return 0; }
  out="$(ffhc_hwi_py -c '
import json, sys
allowed = {"claude_settings", "git_hooks"}
try:
    doc = json.loads(open(sys.argv[1], encoding="utf-8").read())
except Exception:
    print("INVALID"); print(""); raise SystemExit
schema = doc.get("schema_version")
enabled = doc.get("enabled")
root = doc.get("repo_root")
if schema not in (1, 2) or not isinstance(enabled, bool) or not isinstance(root, str) or not root.strip():
    print("INVALID"); print(""); raise SystemExit
if schema == 2:
    surfaces = doc.get("surfaces")
    if not isinstance(surfaces, list) or any(not isinstance(x, str) or x not in allowed for x in surfaces):
        print("INVALID"); print(""); raise SystemExit
    if enabled and not surfaces:
        print("INVALID"); print(""); raise SystemExit
print("ENABLED" if enabled else "REVOKED")
print(root)
' "$path" 2>/dev/null)" || { echo "INVALID"; return 0; }
  token="$(printf '%s' "$out" | sed -n '1p' | tr -d '\r')"
  recorded="$(printf '%s' "$out" | sed -n '2p' | tr -d '\r')"
  case "$token" in
    ENABLED|REVOKED) ;;
    *) echo "INVALID"; return 0 ;;
  esac
  if [ "$(ffhc_hwi_norm "$recorded")" != "$(ffhc_hwi_norm "$root")" ]; then
    echo "FOREIGN"; return 0
  fi
  echo "$token"
}

ffhc_hwi_surfaces() {
  local root="$1" path="$1/$FFHC_HWI_REL"
  [ "$(ffhc_hwi_state "$root")" = "ENABLED" ] || return 1
  ffhc_hwi_py -c '
import json, sys
doc = json.loads(open(sys.argv[1], encoding="utf-8").read())
if doc["schema_version"] == 1:
    print("claude_settings")
else:
    print("\n".join(doc["surfaces"]))
' "$path" 2>/dev/null
}

# ffhc_hwi_wired <root> — 0 iff .claude/settings.json carries the canonical Flow PreToolUse
# handler. Absent settings.json is rc 2 (a distinct state the old arm had no branch for).
ffhc_hwi_wired() {
  local settings="$1/.claude/settings.json"
  [ -f "$settings" ] || return 2
  ffhc_hwi_py -c '
import json, sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8"))
    blocks = value.get("hooks", {}).get("PreToolUse", [])
    commands = [hook.get("command") for block in blocks if isinstance(block, dict)
                for hook in block.get("hooks", []) if isinstance(hook, dict)]
    current = '\''bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_tool_use.py'\''
    legacy = {
        '\''python3 "$CLAUDE_PROJECT_DIR"/hooks/handlers/pre_tool_use.py'\'',
        '\''python3 "${PROJECT_DIR}"/hooks/handlers/pre_tool_use.py'\'',
    }
    raise SystemExit(0 if any(isinstance(cmd, str) and cmd.strip() in ({current} | legacy)
                              for cmd in commands) else 1)
except (OSError, ValueError, TypeError, KeyError):
    raise SystemExit(1)
' "$settings" 2>/dev/null
}

# ffhc_hwi_check <root> — the engine arm. Appends to LOCAL_OK / LOCAL_UNVERIFIED in the
# CALLER's scope and routes drift through the caller's record_drift (so the finding is
# deferrable like every other check).
ffhc_hwi_check() {
  local root="${1:-$PWD}" state wired
  state="$(ffhc_hwi_state "$root")"
  case "$state" in
    ABSENT)
      # Rows 6 + 7: manual `cp .claude/settings.json.example` wiring and every pre-marker
      # checkout land here. Marker-absence means "not known to have opted in", NOT
      # "definitely never opted in" — so this stays exactly at today's behaviour. Making it
      # drift would alarm every legacy tree in the field.
      return 0 ;;
    REVOKED)
      LOCAL_OK+=("Flow hook-wiring intent: opted out (enabled=false) — PreToolUse enforcement not expected. Re-enable with: $FFHC_HWI_RECOVER")
      return 0 ;;
    INVALID)
      LOCAL_UNVERIFIED+=("Flow hook-wiring intent marker at $FFHC_HWI_REL is invalid or unreadable — PreToolUse enforcement NOT verified (never reported as drift: presence alone does not imply opt-in). Re-record with: $FFHC_HWI_RECOVER — or delete the file.")
      return 0 ;;
    NOPARSER)
      LOCAL_UNVERIFIED+=("Flow hook-wiring intent marker at $FFHC_HWI_REL present but no python interpreter is available to validate it — PreToolUse enforcement NOT verified (never reported as drift).")
      return 0 ;;
    FOREIGN)
      LOCAL_UNVERIFIED+=("Flow hook-wiring intent marker at $FFHC_HWI_REL was recorded for a DIFFERENT repo root (state/ is gitignored but archives carry it, so a copied tree inherits another checkout's intent) — PreToolUse enforcement NOT verified for this tree. Re-record with: $FFHC_HWI_RECOVER — or record an opt-out with: $FFHC_HWI_OPTOUT")
      return 0 ;;
  esac

  ffhc_hwi_wired "$root"; wired=$?
  if [ "$wired" -eq 0 ]; then
    LOCAL_OK+=(".claude/settings.json: Flow PreToolUse enforcement wired ($FFHC_HWI_HANDLER present in the PreToolUse chain; matches this tree's recorded wiring intent)")
    return 0
  fi
  # The two drift states. Both carry the effective recovery INCLUDING --wire-hooks: the
  # default recovery deliberately does NOT modify .claude/settings.json, so a bare
  # "run post-fusebase-update.sh" would send the operator down a no-op path and this check
  # would only relocate the forensics it was built to end.
  if [ "$wired" -eq 2 ]; then
    record_drift "$FFHC_HWI_CHECK_ID" \
      ".claude/settings.json: MISSING while this tree recorded an ACTIVE Flow hook-wiring intent — Flow runtime enforcement (FR-06/07/12 PreToolUse) is NOT running. Restore with: $FFHC_HWI_RECOVER (the default recovery does NOT modify .claude/settings.json). Deliberate opt-out instead: $FFHC_HWI_OPTOUT"
  else
    record_drift "$FFHC_HWI_CHECK_ID" \
      ".claude/settings.json: Flow PreToolUse ENFORCEMENT STRIPPED — no $FFHC_HWI_HANDLER in the PreToolUse chain, while this tree recorded an ACTIVE Flow hook-wiring intent. Flow runtime enforcement (FR-06/07/12) is NOT running; content checks above can still read healthy. Restore with: $FFHC_HWI_RECOVER (the default recovery does NOT modify .claude/settings.json). Deliberate opt-out instead: $FFHC_HWI_OPTOUT"
  fi
  return 0
}
