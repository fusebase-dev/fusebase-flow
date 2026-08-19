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
# TRIPWIRE (detection contract): enforcement presence is the CANONICAL HANDLER SUBSTRING
#   `hooks/handlers/pre_tool_use.py`, never the `"PreToolUse":` event key. Every wiring
#   form — the run-handler.sh wrapper in .claude/settings.json.example, and the legacy
#   `python3 .../hooks/handlers/<stem>.py` forms settings-json-merge.py still recognises —
#   carries that substring; a PreToolUse chain without it is somebody else's hook, not
#   Flow enforcement. Same rule the engine already applies to stop.py.
#
# TRIPWIRE (false-drift budget): a false alarm here is WORSE than the silence it replaces
#   — it trains operators to ignore the one check that reports missing FR-06/07/12
#   enforcement. Only two states may reach record_drift: a VALID, ENABLED, THIS-TREE
#   marker with the handler absent, and the same with settings.json absent. Every other
#   shape (absent / revoked / malformed / unparseable / inherited from another checkout)
#   reports UNVERIFIED or stays silent.

FFHC_HWI_REL="state/audit/flow-hook-wiring-intent.json"
FFHC_HWI_HANDLER="hooks/handlers/pre_tool_use.py"
FFHC_HWI_SCHEMA=1
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
  local root="$1" enabled="$2" path="$1/$FFHC_HWI_REL"
  mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
  printf '{\n  "schema_version": %s,\n  "enabled": %s,\n  "repo_root": "%s",\n  "updated_at": "%s",\n  "written_by": "post-fusebase-update.sh"\n}\n' \
    "$FFHC_HWI_SCHEMA" "$enabled" \
    "$(printf '%s' "$root" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$path" || return 1
  return 0
}

# ffhc_hwi_record_wiring <root> <merge_rc> — the ONLY creation path. Records intent iff the
# settings merge actually SUCCEEDED; a failed or aborted merge leaves no marker, so the
# engine never reports drift against wiring that was never installed.
ffhc_hwi_record_wiring() {
  local root="$1" rc="$2"
  [ "$rc" = "0" ] || return 0
  ffhc_hwi_write "$root" true
}

# ffhc_hwi_revoke <root> — the revocation lifecycle. Intent that can only ever be created is
# a false-drift generator: a tree that removed the block ON PURPOSE would alarm forever.
ffhc_hwi_revoke() {
  ffhc_hwi_write "$1" false
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
  out="$(FFHC_HWI_WANT="$FFHC_HWI_SCHEMA" ffhc_hwi_py -c '
import json, os, sys
try:
    doc = json.loads(open(sys.argv[1], encoding="utf-8").read())
except Exception:
    print("INVALID"); print(""); sys.exit(0)
# Presence alone must never imply opt-in: the shape is validated, not assumed.
if not isinstance(doc, dict) or doc.get("schema_version") != int(os.environ["FFHC_HWI_WANT"]) \
        or not isinstance(doc.get("enabled"), bool):
    print("INVALID"); print(""); sys.exit(0)
print("ENABLED" if doc["enabled"] else "REVOKED")
recorded = doc.get("repo_root")
print(recorded if isinstance(recorded, str) else "")
' "$path" 2>/dev/null)" || { echo "INVALID"; return 0; }
  token="$(printf '%s' "$out" | sed -n '1p' | tr -d '\r')"
  recorded="$(printf '%s' "$out" | sed -n '2p' | tr -d '\r')"
  case "$token" in
    ENABLED|REVOKED) ;;
    *) echo "INVALID"; return 0 ;;
  esac
  if [ -n "$recorded" ] && [ "$(ffhc_hwi_norm "$recorded")" != "$(ffhc_hwi_norm "$root")" ]; then
    echo "FOREIGN"; return 0
  fi
  echo "$token"
}

# ffhc_hwi_wired <root> — 0 iff .claude/settings.json carries the canonical Flow PreToolUse
# handler. Absent settings.json is rc 2 (a distinct state the old arm had no branch for).
ffhc_hwi_wired() {
  local settings="$1/.claude/settings.json"
  [ -f "$settings" ] || return 2
  grep -q "$FFHC_HWI_HANDLER" "$settings" 2>/dev/null
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
