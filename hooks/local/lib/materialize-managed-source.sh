#!/usr/bin/env bash
# Fusebase Flow — canonical managed-source boundary (decisions M1, M10).
#
# TRIPWIRE (decision M1): incoming content comes from git OBJECTS, never from the staging
# clone's working tree — a worktree populated under core.autocrlf=true before an EOL pin keeps
# its pre-pin bytes forever (changing .gitattributes does not rewrite an unchanged file), so the
# consumer receives CRLF where the byte-exact manifest expects LF: permanent FLOW_LAYER_DRIFT.
#
# API — all state lands in FF_SOURCE_* globals the caller reads:
#   ff_source_boundary <source-dir> [<ref>]        materialize + verify; rc 1 => abort before writes
#   ff_source_adopt <tree> <owned>                 adopt a tree a caller already materialized
#   ff_source_verify_tree <tree>                   M10 verdict on a caller-materialized tree
#   ff_source_cleanup                              remove the temp tree we own (idempotent)
#   ff_managed_drift_paths <root>                  manifest-reported drift paths, one per line
#   ff_repair_managed <root> <tree> <ts> <path>...  exact-path repair from verified U
#
#   FF_SOURCE_REPO   absolute source dir — metadata / ref resolution / kind detection ONLY
#   FF_SOURCE_TREE   absolute canonical tree — EVERY incoming content read uses this
#   FF_SOURCE_COMMIT full OID for a git source, "" otherwise
#   FF_SOURCE_KIND   git | plain
#   FF_SOURCE_STATE  VERIFIED | UNVERIFIED_LEGACY_SOURCE
#   FF_SOURCE_REASON why the state is not VERIFIED, or the abort reason
#   FF_SOURCE_DRIFT  offending paths on an abort

FF_SOURCE_REPO=""
FF_SOURCE_TREE=""
FF_SOURCE_COMMIT=""
FF_SOURCE_KIND=""
FF_SOURCE_STATE=""
FF_SOURCE_REASON=""
FF_SOURCE_DRIFT=""
FF_SOURCE_TREE_TEMP=0

ff_source_cleanup() {
  [ "${FF_SOURCE_TREE_TEMP:-0}" = "1" ] || return 0
  local t="${FF_SOURCE_TREE:-}"
  FF_SOURCE_TREE_TEMP=0
  # TRIPWIRE (destructive): only a directory WE created from the ff-source- template is
  # removable here — a caller-supplied --source-tree must never be deletable this way.
  case "${t##*/}" in
    ff-source-*) [ -d "$t" ] && rm -rf -- "$t" ;;
  esac
  return 0
}

ff_source_adopt() {   # <tree> <owned:0|1>
  FF_SOURCE_TREE="$1"
  FF_SOURCE_TREE_TEMP="${2:-0}"
  return 0
}

# Resolve the selected ref to a full OID. Order: the caller's ref, its remote-tracking
# form, then HEAD — a `clone --depth 1 --branch X` carries no other local branch.
_ff_mms_resolve() {   # <repo> <ref> -> echoes full OID
  local repo="$1" ref="$2" cand oid
  for cand in "$ref" "origin/$ref" "HEAD"; do
    [ -n "$cand" ] || continue
    oid="$(git -C "$repo" rev-parse --verify -q "${cand}^{commit}" 2>/dev/null || true)"
    [ -n "$oid" ] && { printf '%s\n' "$oid"; return 0; }
  done
  return 1
}

_ff_mms_git() {   # <repo> <ref> <dest>
  local repo="$1" ref="$2" dest="$3" oid
  oid="$(_ff_mms_resolve "$repo" "$ref")" || {
    FF_SOURCE_REASON="cannot resolve '$ref', 'origin/$ref' or HEAD to a commit in $repo"
    return 1
  }
  # TRIPWIRE (decision M1) — incoming U is forced core.autocrlf=false + core.eol=lf on
  # EVERY OS so the materialized bytes match the shipped byte-exact manifest. Inheriting
  # the consumer's / global EOL setting here recreates F2 (the CRLF FLOW_LAYER_DRIFT bug).
  # The OPPOSITE rule governs K13's historical base B in bootstrap-upgrade.sh: B keeps the
  # CONSUMER's EOL because it must match the consumer's existing tree. Never collapse them.
  if ! git -C "$repo" -c core.autocrlf=false -c core.eol=lf archive "$oid" | tar -x -C "$dest"; then
    FF_SOURCE_REASON="git archive of $oid failed"
    return 1
  fi
  FF_SOURCE_COMMIT="$oid"
  return 0
}

_ff_mms_snapshot() {   # <src> <dest> — non-git source (decision M10)
  local src="$1" dest="$2"
  # An immutable snapshot also stops the caller changing source bytes between the
  # verification below and the copy the engine performs from it.
  cp -R "$src/." "$dest/" 2>/dev/null || {
    FF_SOURCE_REASON="could not snapshot the plain source directory"
    return 1
  }
  rm -rf "$dest/.git" 2>/dev/null || true
  return 0
}

_ff_mms_json_paths() {   # <verify --json output> -> "p1, p2 (+N more)"
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
fs = [f.get("path", "?") for f in d.get("files", []) or []]
s = ", ".join(fs[:8])
if len(fs) > 8:
    s += " (+%d more)" % (len(fs) - 8)
print(s)
' 2>/dev/null
}

# Verify the materialized tree against its OWN shipped manifest (decision M10):
#   manifest ABSENT -> UNVERIFIED_LEGACY_SOURCE (pre-4.7.0 sources keep upgrading)
#   manifest PRESENT -> only an explicit MATCH proceeds; EVERY other outcome is rc 1
#
# TRIPWIRE (decision M10): UNVERIFIED_LEGACY_SOURCE is reachable ONLY from the manifest-ABSENT
# branch. A manifest-bearing source with a missing/emptied/replaced verifier, no verdict, or an
# unexpected rc must ABORT — routing any of those to the legacy fallback installs bytes nobody
# can prove upstream shipped, and an emptied verifier is exactly what an attacker or a truncated
# transport produces. Never widen the rc-0 success case beyond a literal MATCH verdict either.
_ff_mms_verify() {   # <tree>
  local tree="$1" mcm="$1/hooks/local/lib/managed_content_manifest.py"
  local mrel="audit/managed-content-manifest.json"
  if [ ! -f "$tree/$mrel" ]; then
    FF_SOURCE_STATE="UNVERIFIED_LEGACY_SOURCE"
    FF_SOURCE_REASON="source ships no $mrel (pre-4.7.0 source)"
    return 0
  fi
  if [ ! -f "$mcm" ]; then
    FF_SOURCE_REASON="source ships $mrel but no hooks/local/lib/managed_content_manifest.py to check it against — these bytes cannot be proven to be what upstream shipped"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    FF_SOURCE_REASON="source ships $mrel but python3 is unavailable to verify it — these bytes cannot be proven to be what upstream shipped"
    return 1
  fi
  local out rc
  out="$(python3 "$mcm" verify --root "$tree" --json 2>/dev/null)"; rc=$?
  case "$rc" in
    0)
      case "$out" in
        *'"verdict": "MATCH"'*|*'"verdict":"MATCH"'*) FF_SOURCE_STATE="VERIFIED"; return 0 ;;
        *) FF_SOURCE_REASON="the source verifier exited 0 without a MATCH verdict for $mrel (truncated or replaced managed_content_manifest.py?)"
           FF_SOURCE_DRIFT="$(_ff_mms_json_paths "$out")"; return 1 ;;
      esac ;;
    1)
      FF_SOURCE_REASON="the source tree does not match its own shipped $mrel (DRIFT)"
      FF_SOURCE_DRIFT="$(_ff_mms_json_paths "$out")"; return 1 ;;
    2)
      FF_SOURCE_REASON="the source tree's $mrel is corrupt or self-hash mismatched (BROKEN)"
      return 1 ;;
    *)
      FF_SOURCE_REASON="the source verifier could not check $mrel (exited rc=$rc)"
      FF_SOURCE_DRIFT="$(_ff_mms_json_paths "$out")"; return 1 ;;
  esac
}

ff_source_boundary() {   # <source-dir> [<ref>]
  local src="$1" ref="${2:-}" dest
  FF_SOURCE_REPO=""; FF_SOURCE_TREE=""; FF_SOURCE_COMMIT=""; FF_SOURCE_KIND=""
  FF_SOURCE_STATE=""; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""; FF_SOURCE_TREE_TEMP=0
  if [ ! -d "$src" ]; then
    FF_SOURCE_REASON="source '$src' is not a directory"
    return 1
  fi
  FF_SOURCE_REPO="$(cd "$src" && pwd)"
  dest="$(mktemp -d "${TMPDIR:-/tmp}/ff-source-XXXXXX" 2>/dev/null || true)"
  if [ -z "$dest" ] || [ ! -d "$dest" ]; then
    FF_SOURCE_REASON="could not create a temporary source tree"
    return 1
  fi
  # Ownership is recorded BEFORE the first read/verify so the caller's trap (armed
  # immediately after this call) always has a tree to clean up on any abort path.
  FF_SOURCE_TREE="$dest"; FF_SOURCE_TREE_TEMP=1
  # `-e` not `-d`: a linked worktree's .git is a FILE, and `git -C` handles both. Never
  # probe with `git rev-parse` — inside a consumer repo that walks UP and would mistake the
  # CONSUMER's .git for the plain source directory's.
  if [ -e "$FF_SOURCE_REPO/.git" ] && command -v git >/dev/null 2>&1; then
    FF_SOURCE_KIND="git"
    _ff_mms_git "$FF_SOURCE_REPO" "$ref" "$dest" || return 1
  else
    FF_SOURCE_KIND="plain"
    _ff_mms_snapshot "$FF_SOURCE_REPO" "$dest" || return 1
  fi
  _ff_mms_verify "$dest" || return 1
  return 0
}

# ff_source_open <source-repo> <adopt-tree> <adopt-owned> [<ref>]
#   The single entry point both entry scripts use. On rc 0, FF_SOURCE_TREE is the tree every
#   incoming content read must use. rc 1 => the caller MUST abort before any write.
ff_source_open() {
  local repo="$1" adopt="${2:-}" owned="${3:-0}" ref="${4:-}"
  if [ -n "$adopt" ]; then
    ff_source_adopt "$adopt" "$owned"
    FF_SOURCE_REPO="$repo"; FF_SOURCE_STATE="VERIFIED-BY-CALLER"
    echo "[source] using the caller-materialized canonical tree (decision M1)."
    return 0
  fi
  if ff_source_boundary "$repo" "$ref"; then
    echo "[source] materialized $FF_SOURCE_KIND source${FF_SOURCE_COMMIT:+ @ $FF_SOURCE_COMMIT} -> canonical tree; state=$FF_SOURCE_STATE"
    if [ "$FF_SOURCE_STATE" = "UNVERIFIED_LEGACY_SOURCE" ]; then
      echo "[source] UNVERIFIED_LEGACY_SOURCE: $FF_SOURCE_REASON — proceeding for pre-manifest source compatibility (decision M10)."
    fi
    return 0
  fi
  _ff_mms_report_abort
  return 1
}

_ff_mms_report_abort() {
  echo "[source] ABORT: $FF_SOURCE_REASON" >&2
  [ -n "$FF_SOURCE_DRIFT" ] && echo "[source]        offending path(s): $FF_SOURCE_DRIFT" >&2
  echo "[source] NOTHING was written. Re-stage a clean source tree and retry." >&2
  return 0
}

# ff_source_verify_tree <tree>: run the M10 verdict on a tree the caller materialized ITSELF,
# from a copy of this lib the caller ALREADY TRUSTS. rc 1 => the caller MUST abort before any write.
#
# TRIPWIRE (R3): the bootstrap hop deliberately does NOT call this on the tree it just made when
# the consumer has no installed copy of this lib — sourcing this file OUT OF that tree and then
# asking it for the verdict lets a tampered source redefine this very function and approve itself.
# That path uses bootstrap-upgrade.sh's own embedded ff_boot_verify instead. Never "simplify" the
# hop back onto this entry point.
ff_source_verify_tree() {
  FF_SOURCE_STATE=""; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""
  if _ff_mms_verify "$1"; then
    echo "[source] verified the caller-materialized canonical tree; state=$FF_SOURCE_STATE"
    if [ "$FF_SOURCE_STATE" = "UNVERIFIED_LEGACY_SOURCE" ]; then
      echo "[source] UNVERIFIED_LEGACY_SOURCE: $FF_SOURCE_REASON — proceeding for pre-manifest source compatibility (decision M10)."
    fi
    return 0
  fi
  _ff_mms_report_abort
  return 1
}

# ff_managed_drift_paths <root>: every path BOTH shipped manifests report as modified or
# missing, deduplicated. `extra` is excluded on purpose — repair replaces content from U
# and can never fix a file upstream does not ship.
ff_managed_drift_paths() {   # <root> [<lib-dir>]
  local root="$1" lib="${2:-$1/hooks/local/lib}" out mod
  command -v python3 >/dev/null 2>&1 || return 0
  for mod in hook_manifest.py managed_content_manifest.py; do
    [ -f "$lib/$mod" ] || continue
    out="$(python3 "$lib/$mod" verify --root "$root" --json 2>/dev/null || true)"
    printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for f in d.get("files", []) or []:
    if f.get("status") in ("modified", "missing"):
        print(f.get("path", ""))
' 2>/dev/null
  done | sed '/^$/d' | sort -u
}

# _ff_repair_dest_ok <root> <root-resolved> <repo-relative path>
#   Destination-side authority: rc 1 + FF_REPAIR_REASON when writing this path could escape
#   the repo. TRIPWIRE (destructive): a symlink at the LEAF or at ANY parent component is
#   refused outright — `cp`/`mv` write THROUGH an existing destination symlink, and the
#   verifier reports such a path in the first place because its own is_file()/hashing follow
#   the link too. Containment is then re-checked on the RESOLVED parent (defence in depth).
_ff_repair_dest_ok() {
  local root="$1" rr="$2" p="$3" cur="$root" rel="" rest="$3" seg parent res
  FF_REPAIR_REASON=""
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    [ -n "$seg" ] || continue
    cur="$cur/$seg"; rel="${rel:+$rel/}$seg"
    if [ -L "$cur" ]; then
      FF_REPAIR_REASON="'$rel' is a symlink — refused outright (a write would follow it, possibly outside the repo)"
      return 1
    fi
  done
  # A managed FILE path that is not a regular file is an anomaly, never a repair target:
  # `cp`/`mv` onto a directory silently writes INSIDE it (dir/<name>) and reports success.
  if [ -e "$root/$p" ] && [ ! -f "$root/$p" ]; then
    FF_REPAIR_REASON="the destination exists and is not a regular file — repair replaces file bytes, it never writes into a directory or a special file"
    return 1
  fi
  parent="$(dirname "$root/$p")"
  if [ -d "$parent" ]; then
    res="$(cd "$parent" 2>/dev/null && pwd -P)" || {
      FF_REPAIR_REASON="the destination's parent directory is unreachable"; return 1; }
    case "$res" in
      "$rr"|"$rr"/*) ;;
      *) FF_REPAIR_REASON="the destination resolves outside the repo root ($res)"; return 1 ;;
    esac
  fi
  return 0
}

_ff_repair_unstage() {   # <root> <ts> <staged path>...
  local root="$1" ts="$2"; shift 2
  local p
  for p in "$@"; do
    rm -f "$root/$p.ff-repair-staged" "$root/$p.ff-repair-orig" || true
  done
}

# ff_repair_managed <root> <tree> <ts> <path>...
#   Replaces ONLY paths the verifier reported, from the already-verified tree U, after a
#   per-path authority check. Refuses (rc 1, nothing written) on: path syntax, a path the
#   verifier did not report, a path the source does not ship, or a destination that a write
#   could escape through. Naming the exact paths on the command line IS the operator
#   authorization — --auto-yes never reaches here.
#
#   TRIPWIRE (write atomicity): the batch is all-or-nothing on the WRITE side too, not only on
#   validation. Every replacement is copied to a sibling `.ff-repair-staged` first, so the
#   visible change is a same-directory `mv`; a failure part-way through restores the paths
#   already swapped from their private `.ff-repair-orig` copies and removes the backup twins
#   this run created. Never "simplify" this back to a straight cp loop — path 2 failing then
#   leaves path 1 already replaced, which is the state a consumer cannot reason about.
ff_repair_managed() {
  local root="$1" tree="$2" ts="$3"; shift 3
  local reported p bad="" seen="" n=0 root_resolved
  root_resolved="$(cd "$root" 2>/dev/null && pwd -P)" || {
    echo "[repair-managed] REFUSED — cannot resolve the repo root '$root'; nothing was written." >&2
    return 1
  }
  # Verify with the CANONICAL modules from the verified tree, not the consumer's possibly
  # drifted copies — the report is the repair's only authority.
  reported="$(ff_managed_drift_paths "$root" "$tree/hooks/local/lib")"
  for p in "$@"; do
    case "$p" in
      /*|*..*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|'')
        bad="$bad
  - $p (rejected: not a plain repo-relative path)" ; continue ;;
    esac
    case $'\n'"$reported"$'\n' in
      *$'\n'"$p"$'\n'*) ;;
      *) bad="$bad
  - $p (rejected: not reported as drifted by either manifest verifier)"; continue ;;
    esac
    if [ ! -f "$tree/$p" ]; then
      bad="$bad
  - $p (rejected: the verified source tree does not ship this path)"; continue
    fi
    if ! _ff_repair_dest_ok "$root" "$root_resolved" "$p"; then
      bad="$bad
  - $p (rejected: $FF_REPAIR_REASON)"; continue
    fi
    if [ -e "$root/$p.ff-repair-staged" ] || [ -e "$root/$p.ff-repair-orig" ]; then
      bad="$bad
  - $p (rejected: a stale repair artifact is in the way — remove $p.ff-repair-staged / $p.ff-repair-orig)"; continue
    fi
    # A repeated path would stage over its own staging file and make the second swap fail into a
    # rollback — refuse it up front instead, while nothing has been written.
    case $'\n'"$seen"$'\n' in
      *$'\n'"$p"$'\n'*) bad="$bad
  - $p (rejected: named more than once)"; continue ;;
    esac
    seen="$seen
$p"
    n=$((n + 1))
  done
  if [ -n "$bad" ]; then
    echo "[repair-managed] REFUSED — nothing was written:$bad" >&2
    echo "[repair-managed] Reported drift paths are:" >&2
    printf '%s\n' "${reported:-  (none — both manifests verify MATCH)}" | sed 's/^/    /' >&2
    return 1
  fi
  [ "$n" -gt 0 ] || { echo "[repair-managed] no paths given." >&2; return 1; }

  # ---- stage: nothing visible changes here, so any failure means "nothing was written" ----
  local staged=() twinned=() origed="" failed=""
  for p in "$@"; do
    if ! mkdir -p "$(dirname "$root/$p")" 2>/dev/null; then
      failed="could not create the parent directory for $p"; break
    fi
    if ! cp "$tree/$p" "$root/$p.ff-repair-staged" 2>/dev/null; then
      failed="could not stage the verified bytes for $p"; break
    fi
    staged+=("$p")
    if [ -f "$root/$p" ]; then
      if ! cp "$root/$p" "$root/$p.ff-repair-orig" 2>/dev/null; then
        failed="could not take a rollback copy of $p"; break
      fi
      origed="$origed
$p"
      if [ ! -e "$root/$p.pre-upgrade-$ts" ]; then
        if cp "$root/$p" "$root/$p.pre-upgrade-$ts" 2>/dev/null; then twinned+=("$p"); fi
      fi
    fi
  done
  if [ -n "$failed" ]; then
    for p in ${twinned[@]+"${twinned[@]}"}; do rm -f "$root/$p.pre-upgrade-$ts" || true; done
    _ff_repair_unstage "$root" "$ts" ${staged[@]+"${staged[@]}"}
    echo "[repair-managed] REFUSED — $failed; NOTHING was written." >&2
    return 1
  fi

  # ---- apply: same-directory swaps, rolled back as a unit if any one of them fails ----
  local applied=()
  for p in "${staged[@]}"; do
    if mv -f "$root/$p.ff-repair-staged" "$root/$p" 2>/dev/null; then
      applied+=("$p")
      echo "[repair-managed] replaced from verified source: $p"
    else
      failed="could not replace $p"
      break
    fi
  done
  if [ -n "$failed" ]; then
    local q
    for q in ${applied[@]+"${applied[@]}"}; do
      case $'\n'"$origed"$'\n' in
        *$'\n'"$q"$'\n'*) mv -f "$root/$q.ff-repair-orig" "$root/$q" 2>/dev/null || true ;;
        *) rm -f "$root/$q" || true ;;
      esac
      echo "[repair-managed] rolled back: $q" >&2
    done
    for q in ${twinned[@]+"${twinned[@]}"}; do rm -f "$root/$q.pre-upgrade-$ts" || true; done
    _ff_repair_unstage "$root" "$ts" "${staged[@]}"
    echo "[repair-managed] REFUSED — $failed; the whole batch was rolled back (no path was left replaced)." >&2
    return 1
  fi
  _ff_repair_unstage "$root" "$ts" "${staged[@]}"
  return 0
}
