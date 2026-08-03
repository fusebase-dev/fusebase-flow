#!/usr/bin/env bash
# Fusebase Flow — bootstrap-upgrade.sh  (U5: first-hop upgrade for pre-3.6.0 installs)
#
# PROVENANCE:
#   Shipped Fusebase Flow v3.8.0+. Lives at hooks/local/ — outside the FuseBase CLI
#   refresh manifest.
#
# PURPOSE:
#   The blessed in-place upgrade path is `upgrade.sh`, but it ships *inside* the
#   version you're trying to reach. A pre-3.6.0 "append-only overlay" install has
#   no upgrade.sh / sync-version-strings.sh / .fusebase-flow-source/. This script
#   is the one-shot first hop: it stages an upstream copy and EXECUTES the engine
#   FROM THAT SOURCE TREE, so classification decides every consumer write.
#
#   For an install that ALSO lacks this bootstrap script (truly old), copy-paste
#   the equivalent one-liner from the README "Upgrading an installed overlay"
#   section — it does the same clone + run.
#
# What it does:
#   1. Ensure .fusebase-flow-source/ exists — clone upstream if absent (or reuse a
#      plain dir you already staged).
#   2. Synthesize the classifier's base manifest from the upstream tag equal to the
#      consumer's installed VERSION (K13a) — the ONE pre-classification write, and it
#      is the classifier's own input, not consumer content.
#   3. `exec` the SOURCE clone's hooks/local/upgrade.sh (passing through any flags,
#      e.g. --dry-run / --auto-yes). Managed consumer paths — engine scripts and
#      hooks/local/lib/ included — are written only by that engine's classified
#      per-file apply loop.
#
# What it does NOT do (AC25 / K10 / K20):
#   - Copy the engine, lib, or any other managed path into the consumer tree before
#     classification authorizes it; an aborted hop leaves the tree byte-identical
#     except the base manifest above and logs.
#   - Touch application code, .claude/settings.json, or CLI-owned assets.
#   - Delete anything. It writes no backup of its own either (there is nothing to back
#     up before handoff); the engine's .pre-upgrade-<ts> snapshot is the backup. The
#     *.pre-bootstrap-<ts> git-exclude below is retained for trees that still carry
#     snapshots from the older copy-then-handoff hop.
#
# Usage:
#   bash hooks/local/bootstrap-upgrade.sh [--source <dir>] [--repo <url>] [--ref <branch>] [-- <upgrade.sh flags>]
#   bash hooks/local/bootstrap-upgrade.sh --repair-managed <repo-relative-path> [--repair-managed <path> ...]
# Examples:
#   bash hooks/local/bootstrap-upgrade.sh --dry-run
#   bash hooks/local/bootstrap-upgrade.sh -- --auto-yes
#   bash hooks/local/bootstrap-upgrade.sh --source ../fusebase-flow
#   bash hooks/local/bootstrap-upgrade.sh --repair-managed hooks/handlers/stop.py
#
# --repair-managed (AC3): repeatable, deliberate byte repair for a managed path a manifest
# verifier reported as drifted. It materializes + verifies the source, then replaces ONLY the
# named paths from those verified bytes and re-runs both verifiers. Naming each path IS the
# authorization: --auto-yes never repairs, and an unreported/unmanaged path is refused.
#
# Exit: 0 success; 1 error; 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SOURCE_CLONE=".fusebase-flow-source"
FF_MCM_REL="audit/managed-content-manifest.json"
REPO_URL="https://github.com/fusebase-dev/fusebase-flow.git"
REF="main"
SRC_OVERRIDE=""
PASSTHROUGH=()
REPAIR_PATHS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SRC_OVERRIDE="${2:-}"; shift 2 ;;
    --repo)   REPO_URL="${2:-}"; shift 2 ;;
    --ref)    REF="${2:-}"; shift 2 ;;
    --repair-managed)   REPAIR_PATHS+=("${2:-}"); shift 2 ;;
    --repair-managed=*) REPAIR_PATHS+=("${1#*=}"); shift ;;
    --help|-h) sed -n '2,46p' "$0"; exit 0 ;;
    --) shift; PASSTHROUGH=("$@"); break ;;
    *) echo "[bootstrap-upgrade] Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y%m%dT%H%M%SZ)

# ---- Step 1: ensure a source copy ----
if [ -n "$SRC_OVERRIDE" ]; then
  if [ ! -d "$SRC_OVERRIDE" ]; then
    echo "[bootstrap-upgrade] FATAL: --source '$SRC_OVERRIDE' is not a directory." >&2
    exit 1
  fi
  SOURCE_CLONE="$SRC_OVERRIDE"
  echo "[bootstrap-upgrade] Using source: $SOURCE_CLONE"
elif [ -d "$SOURCE_CLONE" ]; then
  echo "[bootstrap-upgrade] Reusing existing $SOURCE_CLONE/"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] FATAL: git not found and no $SOURCE_CLONE/ present." >&2
    echo "                    Stage an upstream copy at $SOURCE_CLONE/ manually, then re-run." >&2
    exit 1
  fi
  echo "[bootstrap-upgrade] Cloning $REPO_URL ($REF) -> $SOURCE_CLONE/ ..."
  # TRIPWIRE (line endings): the staging clone MUST check out with the consumer's own
  # core.autocrlf. If it inherits a different global value, every managed file differs by
  # EOL alone — the classifier then reads the whole tree as upstream-changed (or
  # consumer-changed) and either overwrites or preserves everything for the wrong reason.
  FF_EOL="$(git config --get core.autocrlf 2>/dev/null || true)"
  [ -n "$FF_EOL" ] || FF_EOL="false"
  git -c core.autocrlf="$FF_EOL" clone --depth 1 --branch "$REF" "$REPO_URL" "$SOURCE_CLONE"
fi

# ---- Step 1b: canonical source boundary BEFORE any source-derived read (decision M1 / AC2) ----
# TRIPWIRE (source trust): the VERDICT is always reached by TRUSTED CODE — the installed lib, or,
# when this install predates it, the minimal embedded materialize+verify pair below. NEVER by
# shell sourced out of the source: neither $SOURCE_CLONE's mutable worktree nor the snapshot taken
# from it. A source-supplied materialize-managed-source.sh can redefine ff_source_verify_tree and
# approve itself, so "source it, then verify with it" proves nothing. Source-derived shell may
# enter this process only AFTER trusted code has proven the tree, and only for the repair API.
FF_MMS_LIB="$ROOT/hooks/local/lib/materialize-managed-source.sh"
SOURCE_TREE="$SOURCE_CLONE"
SOURCE_TREE_FLAGS=()
FF_BOOT_TREE=""
FF_BOOT_TREE_OWNED=0
BOOT_COMMIT=""
FF_SOURCE_REPO=""; FF_SOURCE_COMMIT=""; FF_SOURCE_KIND=""
FF_SOURCE_STATE=""; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""

ff_boot_cleanup() {
  [ "${FF_BOOT_TREE_OWNED:-0}" = "1" ] || return 0
  local t="$FF_BOOT_TREE"
  FF_BOOT_TREE_OWNED=0
  # TRIPWIRE (destructive): only a directory WE created from the ff-source- template.
  case "${t##*/}" in
    ff-source-*) [ -d "$t" ] && rm -rf -- "$t" ;;
  esac
  return 0
}

# The M10/M11 verdict, embedded. Mirrors _ff_mms_verify in the shared lib on purpose: this is the
# one piece of the boundary that cannot be borrowed from the tree it judges (R3 / re-review B1).
# What it drives IS the source's own managed_content_manifest.py — the same trust model the
# installed lib uses: a manifest-bearing tree is proven by its shipped verifier or it aborts, and
# a manifest+verifier source needs no materialize-managed-source.sh to be provable (M11).
# TRIPWIRE (re-review B4): $2 exists so a caller can supply a verifier it ALREADY PROVED. A tree
# whose own verifier is part of what is in question — the mutable worktree at Step 2c — must be
# judged with that argument, never with the default below.
#
# TRIPWIRE (re-review B5): EVERY interpreter that carries this verdict runs through ff_boot_py.
# Choosing a trusted verifier FILE is not enough — the interpreter runs other people's code
# before the file does, and there are TWO ways in:
#   site   — sitecustomize.py / usercustomize.py / .pth reachable from the JUDGED tree (an
#            inherited PYTHONPATH is all it takes); closed by -S.
#   sys.path[0] — for a file script that is the SCRIPT'S OWN DIRECTORY, which at Step 1b is
#            hooks/local/lib/ INSIDE THE TREE BEING JUDGED, and for `-c` it is the CWD. A
#            judged-tree hooks/local/lib/json.py therefore shadows stdlib `json` and runs at
#            `import json`, BEFORE the verifier can report it as drift. Proven: under `-S -E`
#            that shadow prints MATCH and os._exit(0)s; under `-I -S` it is not on the path.
#            -E alone does NOT close this — only -I (isolated: no script dir, no user site, no
#            PYTHON* env) does. managed_content_manifest.py / hook_manifest.py are stdlib-only,
#            so neither -I nor -S costs them anything.
# This is B4 one layer down, in the interpreter instead of the script; same class the pre-commit
# closed in T29/T30. Never call a bare `python3` for anything that decides, or feeds, a verdict.
ff_boot_py() { python3 -I -S "$@"; }

# The verdict is PARSED and matched EXACTLY (re-review B5/R1). Not a substring: output that
# merely CONTAINS `"verdict": "MATCH"` is not a MATCH. Not a prefix either: `"MATCH\nanything"`
# is not a MATCH — this function emits the literal token only on exact equality, so no
# line-oriented reserialization downstream can promote a near-miss. Duplicate keys are rejected
# outright rather than silently last-wins. Prints line 1 = MATCH or empty, line 2 = drifted paths.
ff_boot_verdict() {   # stdin = `verify --json` output
  ff_boot_py -c '
import json, sys
def _nodup(pairs):
    d = {}
    for k, v in pairs:
        if k in d:
            raise ValueError("duplicate key in verifier output")
        d[k] = v
    return d
verdict = ""; paths = ""
try:
    d = json.load(sys.stdin, object_pairs_hook=_nodup)
    if isinstance(d, dict):
        if d.get("verdict") == "MATCH":
            verdict = "MATCH"
        fs = [f.get("path", "?") for f in (d.get("files") or []) if isinstance(f, dict)]
        paths = ", ".join(str(p) for p in fs[:8])
        if len(fs) > 8:
            paths += " (+%d more)" % (len(fs) - 8)
except Exception:
    verdict = ""; paths = ""
print(verdict)
print(paths.replace("\r", " ").replace("\n", " "))
' 2>/dev/null
}

ff_boot_verify() {   # <tree> [<trusted verifier>]; sets FF_SOURCE_STATE/_REASON/_DRIFT. rc 1 => abort
  local tree="$1" mcm="${2:-}" mrel="$FF_MCM_REL" out rc parsed verdict
  [ -n "$mcm" ] || mcm="$tree/hooks/local/lib/managed_content_manifest.py"
  FF_SOURCE_STATE=""; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""
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
  out="$(ff_boot_py "$mcm" verify --root "$tree" --json 2>/dev/null)"; rc=$?
  parsed="$(printf '%s' "$out" | ff_boot_verdict)"
  verdict="$(printf '%s\n' "$parsed" | sed -n '1p')"
  FF_SOURCE_DRIFT="$(printf '%s\n' "$parsed" | sed -n '2p')"
  # TRIPWIRE (decision M10): UNVERIFIED_LEGACY_SOURCE is reachable ONLY from the manifest-ABSENT
  # branch above. Never widen the rc-0 success case beyond a PARSED, literal MATCH verdict either.
  case "$rc" in
    0)
      case "$verdict" in
        MATCH)
          FF_SOURCE_STATE="VERIFIED"; FF_SOURCE_DRIFT=""; return 0 ;;
        *) FF_SOURCE_REASON="the source verifier exited 0 without a parseable MATCH verdict for $mrel (truncated or replaced managed_content_manifest.py?)"
           return 1 ;;
      esac ;;
    1) FF_SOURCE_REASON="the source tree does not match its own shipped $mrel (DRIFT)"; return 1 ;;
    2) FF_SOURCE_REASON="the source tree's $mrel is corrupt or self-hash mismatched (BROKEN)"; return 1 ;;
    *) FF_SOURCE_REASON="the source verifier could not check $mrel (exited rc=$rc)"; return 1 ;;
  esac
}

# The layers a repair must confirm, and the shape of one bound record:
#   <module>|<manifest-rel>|<verify wrapper>|<wrapper shipped by the verified source>
FF_REPAIR_LAYERS=(
  "hook_manifest.py|audit/hook-layer-manifest.json|hooks/local/verify-hook-manifest.sh"
  "managed_content_manifest.py|$FF_MCM_REL|hooks/local/verify-managed-content-manifest.sh"
)
FF_REPAIR_BOUND=()

# TRIPWIRE (decision M16): membership is read from $SOURCE_TREE — the tree this run already PROVED
# — and NEVER from $ROOT, the tree being repaired. Never restore a predicate over consumer-side
# artifacts (M14's "either the manifest or the wrapper is present here"): whoever can delete those
# artifacts deletes themselves out of the bound set before authorization, so "this install never
# carried the layer" reads identically to "both were removed a second ago" — a downgrade with no
# race. The anchor is outside the REPAIRED TREE's control, not outside the consumer's: M17 locks
# the same-principal threat model, so this raises a downgrade's cost (author a self-consistent
# source tree) rather than removing it.
# TRIPWIRE (decision M13, unchanged): the set is decided HERE — before ff_repair_managed writes a
# byte — and never re-derived afterwards; a layer that loses an artifact mid-run is a
# contradiction, not an input to the decision.
ff_boot_bind_repair_layers() {
  local spec rest mod mrel wrapper need_w
  FF_REPAIR_BOUND=()
  for spec in "${FF_REPAIR_LAYERS[@]}"; do
    mod="${spec%%|*}"; rest="${spec#*|}"; mrel="${rest%%|*}"; wrapper="${rest#*|}"
    if [ ! -f "$SOURCE_TREE/$mrel" ]; then
      echo "[bootstrap-upgrade] repair layer NOT DECLARED by the verified source at this version: no $mrel — not required."
      continue
    fi
    need_w=0
    [ -f "$SOURCE_TREE/$wrapper" ] && need_w=1
    FF_REPAIR_BOUND+=("$mod|$mrel|$wrapper|$need_w")
    echo "[bootstrap-upgrade] repair layer REQUIRED — the verified source declares it (bound at authorization): $mrel (wrapper required=$need_w)."
  done
  [ "${#FF_REPAIR_BOUND[@]}" -gt 0 ] && return 0
  # FAIL-CLOSED floor, not an unreachable branch: VERIFIED implies a source-side $FF_MCM_REL at
  # VERIFICATION time, and $SOURCE_TREE stays mutable until this bind. "Every bound layer MATCHed"
  # is vacuously true over an empty set, so an empty set must never reach the verdict.
  echo "[bootstrap-upgrade] FATAL: the verified source declares no manifest layer, so nothing could" >&2
  echo "                    confirm the repair. Refusing before any pre-existing file is touched (M13/M16)." >&2
  return 1
}

# The post-repair verdict, reached the way every other verdict in this hop is: a PROVEN verifier,
# an ISOLATED interpreter, rc 0 AND a PARSED exact MATCH.
# TRIPWIRE (re-review B8): this used to shell out to hooks/local/verify-*.sh and branch on their
# EXIT CODES. Those wrappers exec a bare python3 — and verify-hook-manifest.sh took the
# interpreter from a caller-supplied $PYTHON — so `PYTHON=/bin/true`, a sitecustomize on an
# inherited PYTHONPATH, or a json.py beside the module all reported a repair that never happened.
# Repair is the one operation whose entire product is the claim "these bytes are now provably what
# upstream shipped"; an exit code nobody parsed cannot carry that claim. The verifier comes from
# $SOURCE_TREE, which this run already proved VERIFIED (repair refuses otherwise) — never from the
# tree being judged, which is the consumer root we just wrote into (B4).
# TRIPWIRE (decision M13): rc is half the verdict. ff_boot_verify and _ff_mms_verify both require
# rc 0 AND an exact MATCH; this function once required only the latter, so a verifier that printed
# MATCH and then died — truncated write, an error after the report, a signal — confirmed a repair.
# TRIPWIRE (round-6): `[ -f ]` and BOTH hashers follow symlinks, so a bound layer's artifact linked
# to byte-identical content OUTSIDE this tree satisfied presence AND hash — "this tree carries the
# layer" about a file it does not own, which no --repair-managed can restore (the link, not the
# bytes, is the drift). Same shape as _ff_repair_dest_ok (R2, repair TARGETS only): leaf or ANY parent.
ff_boot_linked_seg() {   # <repo-relative path> -> echoes the first symlinked component, else ""
  local rest="$1" cur="$ROOT" rel="" seg
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    [ -n "$seg" ] || continue
    cur="$cur/$seg"; rel="${rel:+$rel/}$seg"
    [ -L "$cur" ] && { printf '%s' "$rel"; return 0; }
  done
  return 0
}

ff_boot_link_refused() {   # <mod> <repo-relative artifact> <first symlinked component>
  echo "[bootstrap-upgrade] REPAIR UNVERIFIED ($1): '$3' is a symlink, so $2 is not a file THIS tree" >&2
  echo "                    owns — presence and hash both follow the link and would confirm the layer" >&2
  echo "                    from bytes stored elsewhere. Replace the link with the real file." >&2
}

# TRIPWIRE (round-6): the remediation must be a command that RUNS. `--repair-managed <path>`
# authorizes only paths a verifier REPORTED; an absent audit/managed-content-manifest.json makes
# its own verifier return ABSENT with an EMPTY file list and no other layer covers audit/, so
# naming it hits "not reported as drifted". Derive from the live report, never assume. The
# `RECOVER:` line is EXECUTED by test-upgrade-repair-managed.sh, so the operator's --source path
# MUST stay shell-quoted — this repo's own directory name has spaces.
ff_boot_recover_advice() {   # <repo-relative artifact>
  local p="$1" rep="" src=""
  [ -n "$SRC_OVERRIDE" ] && src=" --source $(printf '%q' "$SRC_OVERRIDE")"
  command -v ff_managed_drift_paths >/dev/null 2>&1 \
    && rep="$(ff_managed_drift_paths "$ROOT" "$SOURCE_TREE/hooks/local/lib" 2>/dev/null || true)"
  case $'\n'"$rep"$'\n' in
    *$'\n'"$p"$'\n'*)
      echo "[bootstrap-upgrade]        RECOVER: bash hooks/local/bootstrap-upgrade.sh$src --repair-managed $p" >&2 ;;
    *)
      echo "                    No verifier REPORTS $p, so a repair cannot authorize it; an ordinary" >&2
      echo "                    upgrade reinstalls it as managed content (decision K13b)." >&2
      echo "[bootstrap-upgrade]        RECOVER: bash hooks/local/bootstrap-upgrade.sh$src" >&2 ;;
  esac
}

ff_boot_repair_verify() {   # <mod> <manifest-rel> <wrapper> <wrapper-required-by-source>
  local mod="$1" mrel="$2" wrapper="$3" need_w="$4" lib out rc parsed verdict drift linked
  linked="$(ff_boot_linked_seg "$mrel")"
  if [ -n "$linked" ]; then
    ff_boot_link_refused "$mod" "$mrel" "$linked"; return 1
  fi
  if [ "$need_w" = "1" ]; then
    linked="$(ff_boot_linked_seg "$wrapper")"
    if [ -n "$linked" ]; then
      ff_boot_link_refused "$mod" "$wrapper" "$linked"; return 1
    fi
  fi
  if [ ! -f "$ROOT/$mrel" ]; then
    echo "[bootstrap-upgrade] REPAIR UNVERIFIED ($mod): $mrel is not in this tree, and the verified" >&2
    echo "                    source DECLARES this layer at this version — so it was REQUIRED when the" >&2
    echo "                    repair was authorized, and the bound layer set cannot shrink. This tree" >&2
    echo "                    does not decide its own coverage (decisions M13/M16)." >&2
    ff_boot_recover_advice "$mrel"
    return 1
  fi
  if [ "$need_w" = "1" ] && [ ! -f "$ROOT/$wrapper" ]; then
    echo "[bootstrap-upgrade] REPAIR UNVERIFIED ($mod): $wrapper is not in this tree, and the verified" >&2
    echo "                    source ships it for this layer — so it was REQUIRED when the repair was" >&2
    echo "                    authorized and the bound layer set cannot shrink (decisions M13/M16)." >&2
    ff_boot_recover_advice "$wrapper"
    return 1
  fi
  lib="$SOURCE_TREE/hooks/local/lib/$mod"
  if [ ! -f "$lib" ]; then
    echo "[bootstrap-upgrade] REPAIR UNVERIFIED ($mod): the proven source tree ships no $mod, so the" >&2
    echo "                    repaired bytes cannot be re-checked with code this run trusts." >&2
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] REPAIR UNVERIFIED ($mod): python3 is unavailable to re-check the repair." >&2
    return 1
  fi
  out="$(ff_boot_py "$lib" verify --root "$ROOT" --json 2>/dev/null)"; rc=$?
  parsed="$(printf '%s' "$out" | ff_boot_verdict)"
  verdict="$(printf '%s\n' "$parsed" | sed -n '1p')"
  drift="$(printf '%s\n' "$parsed" | sed -n '2p')"
  if [ "$rc" -eq 0 ] && [ "$verdict" = "MATCH" ]; then
    echo "[bootstrap-upgrade] repair re-verified with the proven canonical $mod: MATCH"
    return 0
  fi
  echo "[bootstrap-upgrade] REPAIR UNVERIFIED ($mod): the repaired tree did not return rc 0 with a" >&2
  echo "                    parsed MATCH (verifier rc=$rc, verdict=${verdict:-<none>})." >&2
  [ -n "$drift" ] && echo "[bootstrap-upgrade]        still-drifted path(s): $drift" >&2
  return 1
}

# Minimal embedded materialization for an install that predates hooks/local/lib/
# materialize-managed-source.sh. Deliberately duplicates only the primitives that cannot be
# borrowed from the source without trusting it first: the two materializations and the verdict.
ff_boot_materialize() {
  local dest cand oid lib repo kind
  dest="$(mktemp -d "${TMPDIR:-/tmp}/ff-source-XXXXXX" 2>/dev/null || true)"
  if [ -z "$dest" ] || [ ! -d "$dest" ]; then
    echo "[bootstrap-upgrade] FATAL: could not create a temporary source tree." >&2
    return 1
  fi
  FF_BOOT_TREE="$dest"; FF_BOOT_TREE_OWNED=1
  trap 'ff_boot_cleanup' EXIT
  trap 'rc=$?; ff_boot_cleanup; exit $rc' INT TERM
  if [ -e "$SOURCE_CLONE/.git" ] && command -v git >/dev/null 2>&1; then
    for cand in "$REF" "origin/$REF" "HEAD"; do
      [ -n "$cand" ] || continue
      oid="$(git -C "$SOURCE_CLONE" rev-parse --verify -q "${cand}^{commit}" 2>/dev/null || true)"
      [ -n "$oid" ] && break
    done
    if [ -z "${oid:-}" ]; then
      echo "[bootstrap-upgrade] FATAL: cannot resolve '$REF', 'origin/$REF' or HEAD to a commit in $SOURCE_CLONE." >&2
      return 1
    fi
    # TRIPWIRE (decision M1): incoming U is forced core.autocrlf=false + core.eol=lf on EVERY OS,
    # exactly as materialize-managed-source.sh does. The consumer's EOL belongs to the K13
    # historical base B below — never to incoming content.
    if ! git -C "$SOURCE_CLONE" -c core.autocrlf=false -c core.eol=lf archive "$oid" | tar -x -C "$dest"; then
      echo "[bootstrap-upgrade] FATAL: git archive of $oid failed." >&2
      return 1
    fi
    BOOT_COMMIT="$oid"
    echo "[bootstrap-upgrade] materialized git source @ $oid from objects (embedded boundary)."
  else
    if ! cp -R "$SOURCE_CLONE/." "$dest/" 2>/dev/null; then
      echo "[bootstrap-upgrade] FATAL: could not snapshot the plain source directory." >&2
      return 1
    fi
    rm -rf "$dest/.git" 2>/dev/null || true
    echo "[bootstrap-upgrade] materialized plain source -> private writable copy (embedded boundary)."
  fi
  SOURCE_TREE="$dest"
  repo="$(cd "$SOURCE_CLONE" && pwd)"
  kind="$([ -n "$BOOT_COMMIT" ] && echo git || echo plain)"
  # The verdict runs on THIS script's code, before any shell comes out of $dest.
  if ! ff_boot_verify "$dest"; then
    echo "[bootstrap-upgrade] ABORT: $FF_SOURCE_REASON" >&2
    [ -n "$FF_SOURCE_DRIFT" ] && echo "[bootstrap-upgrade]        offending path(s): $FF_SOURCE_DRIFT" >&2
    echo "[bootstrap-upgrade] NOTHING was written. Re-stage a clean source tree and retry." >&2
    return 1
  fi
  echo "[bootstrap-upgrade] embedded-boundary verdict on the materialized tree: state=$FF_SOURCE_STATE"
  [ "$FF_SOURCE_STATE" = "UNVERIFIED_LEGACY_SOURCE" ] \
    && echo "[bootstrap-upgrade] UNVERIFIED_LEGACY_SOURCE: $FF_SOURCE_REASON — proceeding for pre-manifest source compatibility (decision M10)."
  # Only a PROVEN tree may contribute shell to this process, and only for the shared repair API
  # (--repair-managed). Sourcing the lib resets the FF_SOURCE_* contract, so re-assert it after.
  lib="$dest/hooks/local/lib/materialize-managed-source.sh"
  if [ "$FF_SOURCE_STATE" = "VERIFIED" ] && [ -f "$lib" ]; then
    # shellcheck source=/dev/null
    . "$lib"
    ff_source_adopt "$dest" 0        # ownership stays with ff_boot_cleanup — one owner only
    FF_SOURCE_STATE="VERIFIED"; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""
  fi
  FF_SOURCE_REPO="$repo"; FF_SOURCE_COMMIT="$BOOT_COMMIT"; FF_SOURCE_KIND="$kind"
  return 0
}

if [ -f "$FF_MMS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$FF_MMS_LIB"
  trap 'ff_source_cleanup' EXIT
  trap 'rc=$?; ff_source_cleanup; exit $rc' INT TERM
  ff_source_open "$SOURCE_CLONE" "" 0 "$REF" || exit 1
  SOURCE_TREE="$FF_SOURCE_TREE"
else
  ff_boot_materialize || exit 1
fi

if [ ! -f "$SOURCE_TREE/VERSION" ]; then
  echo "[bootstrap-upgrade] FATAL: $SOURCE_CLONE/VERSION missing — not a Fusebase Flow source tree." >&2
  exit 1
fi
echo "[bootstrap-upgrade] Source VERSION: $(tr -d '\n\r' < "$SOURCE_TREE/VERSION")"

# ---- --repair-managed: bind the layer set BEFORE any PRE-EXISTING file is touched (M13/M16) ----
# TRIPWIRE: this sits ABOVE the .git/info/exclude write below on purpose — keeping the bind next to
# the repair call put one repository write ahead of it. Writes that precede it are legal ONLY because
# each CREATES a new location (the $TMPDIR canonical tree; .fusebase-flow-source/), touching nothing.
if [ "${#REPAIR_PATHS[@]}" -gt 0 ]; then
  if ! command -v ff_repair_managed >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] FATAL: --repair-managed needs hooks/local/lib/materialize-managed-source.sh" >&2
    echo "                    from a 4.7.0+ source tree; none was found." >&2
    exit 1
  fi
  if [ "$FF_SOURCE_STATE" != "VERIFIED" ]; then
    echo "[bootstrap-upgrade] FATAL: repair requires a VERIFIED source; state is $FF_SOURCE_STATE" >&2
    echo "                    ($FF_SOURCE_REASON). Repairing from unverified bytes would install" >&2
    echo "                    content nobody can prove upstream shipped." >&2
    exit 1
  fi
  ff_boot_bind_repair_layers || exit 1
fi

# Git-exclude the *.pre-*-<ts> backup snapshots so a downstream `git add -A` (notably
# FuseBase CLI's `fusebase update` checkpoint) never stages them — the rule and its rationale
# live in the shared lib, which upgrade.sh uses too (no second copy to drift).
# The target-version copy wins, but only out of a tree the boundary PROVED — an unverified
# legacy source contributes no shell to this process (same rule as the materializer above).
FF_BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
[ "$FF_SOURCE_STATE" = "VERIFIED" ] && [ -f "$SOURCE_TREE/hooks/local/lib/backup-hygiene.sh" ] \
  && FF_BH_LIB="$SOURCE_TREE/hooks/local/lib/backup-hygiene.sh"
# shellcheck source=/dev/null
[ -f "$FF_BH_LIB" ] && . "$FF_BH_LIB"
if command -v ff_git_exclude_backups >/dev/null 2>&1; then
  ff_git_exclude_backups || echo "[bootstrap-upgrade] WARN: could not update .git/info/exclude — backups may be stageable by a later 'git add -A' (delete or unstage before committing)." >&2
fi

# ---- --repair-managed (AC3): deliberate exact-path byte repair, then re-verify ----
# The layer set was bound above, before any pre-existing file was touched; nothing re-derives it here.
if [ "${#REPAIR_PATHS[@]}" -gt 0 ]; then
  ff_repair_managed "$ROOT" "$SOURCE_TREE" "$TS" "${REPAIR_PATHS[@]}" || exit 1
  echo "[bootstrap-upgrade] re-verifying the manifest layer(s) bound at authorization…"
  REPAIR_RC=0
  for FF_RL in "${FF_REPAIR_BOUND[@]}"; do
    FF_RL_MOD="${FF_RL%%|*}"; FF_RL_REST="${FF_RL#*|}"
    FF_RL_MREL="${FF_RL_REST%%|*}"; FF_RL_REST="${FF_RL_REST#*|}"
    FF_RL_WRAP="${FF_RL_REST%%|*}"; FF_RL_NEEDW="${FF_RL_REST#*|}"
    ff_boot_repair_verify "$FF_RL_MOD" "$FF_RL_MREL" "$FF_RL_WRAP" "$FF_RL_NEEDW" \
      || REPAIR_RC=1
  done
  [ "$REPAIR_RC" -eq 0 ] \
    || echo "[bootstrap-upgrade] the repair is NOT confirmed. The named paths were replaced from the" >&2
  [ "$REPAIR_RC" -eq 0 ] \
    || echo "                    verified source, but the tree does not verify clean — re-run the" >&2
  [ "$REPAIR_RC" -eq 0 ] \
    || echo "                    integrity check and repair the remaining paths it reports." >&2
  exit "$REPAIR_RC"
fi

# ---- Step 2: NOTHING is written here (decision K10/K20) ----
#
# TRIPWIRE: this step used to copy the fetched engine scripts and the WHOLE
# hooks/local/lib/ into the consumer tree BEFORE any classification ran, then exec the
# installed copy. A later `changed-by-both` abort therefore could not truthfully say
# "nothing was written", and a consumer's engine/lib customizations were already gone.
# The engine now runs FROM THE SOURCE CLONE; every managed consumer path — including the
# engine scripts and hooks/local/lib/ — is written only by upgrade.sh's classified
# per-file apply loop, which already treats them as managed content.
#
# The ONE pre-classification write that remains is Step 2b's audit/managed-content-
# manifest.json: it is the classifier's own INPUT, not consumer content, and without it
# the classifier cannot distinguish the consumer's edits from upstream's at all.
ENGINE_SRC="$SOURCE_TREE/hooks/local/upgrade.sh"
if [ ! -f "$ENGINE_SRC" ]; then
  echo "[bootstrap-upgrade] FATAL: $ENGINE_SRC missing — not a usable source tree." >&2
  exit 1
fi

# ---- Step 2c: the tree we PROVED must be the tree the engine CONSUMES ----------------------
# TRIPWIRE (verified-tree/consumed-tree split): a PRE-boundary engine cannot receive
# --source-tree, so Step 3 below runs it from $SOURCE_CLONE — the MUTABLE WORKTREE — and it
# reads `.fusebase-flow-source` BY NAME. For a git source the canonical tree comes from COMMITTED
# OBJECTS, so a clean commit with a tampered worktree would verify MATCH and then install the
# tampered bytes: VERIFIED about bytes nobody installs (same fail-open class as F2 / M11).
# Keeping the canonical tree alive does NOT fix it — the engine would still read the worktree by
# name. So on this route the verdict is re-reached on $SOURCE_CLONE itself, and it is reached with
# TRUSTED CODE ONLY (re-review B4): the verifier out of the canonical tree THIS RUN ALREADY PROVED,
# plus this script's own embedded logic — NEVER the worktree's own managed_content_manifest.py,
# which is part of what is in question (a tamper that rewrites it too can print MATCH for itself:
# B1 in Python instead of shell). No trusted verifier available => abort; never "ask it about
# itself". The two manifests must also be BYTE-IDENTICAL, or a re-stamped worktree would be
# self-consistent and prove nothing — matching manifests on both trees is what makes the engine we
# grepped in the canonical tree the engine we execute from the worktree.
#
# ACCEPTED LIMITATION (TOCTOU): $SOURCE_CLONE stays mutable THROUGHOUT, and the verdict takes two
# reads (verify the tree, then compare its manifest against the canonical one), so the race window
# opens BETWEEN THOSE READS too. Accepted under the SAME-PRINCIPAL threat model (decision M17):
# whoever can win the race can edit this script instead. Do NOT "fix" it by verifying after Step
# 2b — that trades a truthful "no managed path was touched" abort for a shorter window; closing it
# means replacing the operator's staging area. Unsafe hosts (root-owned hop over a user-writable
# staging dir, shared/CI runner, bind-mount) + rationale: docs/release-notes/v4.7.0.md § Known
# limitation (pre-boundary route).

# Comparison for the unmanifested inputs below tolerates ONE difference and no others: CRLF vs
# LF. It has to tolerate that much — a legitimate staging worktree is checked out under the
# CONSUMER's core.autocrlf (Step 1a) while the canonical tree is forced LF (M1), so an exact cmp
# would abort clean Windows upgrades. It must tolerate nothing else.
#
# TRIPWIRE (re-review B7): this is BINARY-SAFE and normalizes CRLF ONLY. The round-1 version read
# both files into shell variables after `tr -d '\r'`, which silently accepted three tampers that
# a pre-boundary engine copies verbatim into the consumer: a LONE CR (a real line ending, not an
# EOL-representation artifact — `ab` vs `a\rb` compared equal), NUL bytes (dropped by command
# substitution), and any change in TRAILING-newline count (stripped from both sides). Never
# reintroduce a shell-variable or `tr -d '\r'` comparison here. Exact cmp runs first because it
# is the common case and needs no interpreter; without python3 the difference simply stands and
# the caller aborts — fail closed.
ff_boot_same_text() {   # <canonical file> <worktree file>; rc 0 = same after CRLF->LF only
  cmp -s "$1" "$2" && return 0
  command -v python3 >/dev/null 2>&1 || return 1
  ff_boot_py -c '
import sys
try:
    with open(sys.argv[1], "rb") as f: a = f.read()
    with open(sys.argv[2], "rb") as f: b = f.read()
except Exception:
    raise SystemExit(1)
sys.exit(0 if a.replace(b"\r\n", b"\n") == b.replace(b"\r\n", b"\n") else 1)
' "$1" "$2" 2>/dev/null
}

ff_boot_unbound_inputs() {   # repo-relative paths a pre-boundary engine reads outside the manifest
  local d
  {
    echo "VERSION"
    for d in "$SOURCE_TREE/docs" "$SOURCE_CLONE/docs"; do
      [ -d "$d" ] || continue
      find "$d" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sed 's|.*/|docs/|'
    done
  } | sort -u
}

LEGACY_ENGINE=0
if ! grep -q -- '--source-tree)' "$ENGINE_SRC" 2>/dev/null; then
  LEGACY_ENGINE=1
  BOOT_PROVEN_STATE="$FF_SOURCE_STATE"
  BOOT_TRUSTED_MCM=""
  [ "$BOOT_PROVEN_STATE" = "VERIFIED" ] \
    && [ -f "$SOURCE_TREE/hooks/local/lib/managed_content_manifest.py" ] \
    && BOOT_TRUSTED_MCM="$SOURCE_TREE/hooks/local/lib/managed_content_manifest.py"
  if [ -f "$SOURCE_CLONE/$FF_MCM_REL" ] && [ -z "$BOOT_TRUSTED_MCM" ]; then
    echo "[bootstrap-upgrade] ABORT: $SOURCE_CLONE ships $FF_MCM_REL — the tree this pre-boundary" >&2
    echo "                    engine actually reads — but the canonical tree this run proved" >&2
    echo "                    (state=$BOOT_PROVEN_STATE) supplies no verifier this script can trust," >&2
    echo "                    and the worktree's own copy cannot answer a question about itself." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if ! ff_boot_verify "$SOURCE_CLONE" "$BOOT_TRUSTED_MCM"; then
    echo "[bootstrap-upgrade] ABORT: the source engine predates the canonical-tree handoff, so it reads" >&2
    echo "                    $SOURCE_CLONE directly — and $FF_SOURCE_REASON" >&2
    [ -n "$FF_SOURCE_DRIFT" ] && echo "[bootstrap-upgrade]        offending path(s): $FF_SOURCE_DRIFT" >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if [ "$BOOT_PROVEN_STATE" = "VERIFIED" ] && [ "$FF_SOURCE_STATE" != "VERIFIED" ]; then
    echo "[bootstrap-upgrade] ABORT: the canonical tree proved VERIFIED, but $SOURCE_CLONE — the tree this" >&2
    echo "                    pre-boundary engine actually reads — ships no $FF_MCM_REL, so those" >&2
    echo "                    bytes cannot be proven to be what upstream shipped (M10/M11: the legacy" >&2
    echo "                    fallback is for a source that has no manifest anywhere, not for one" >&2
    echo "                    whose worktree hides it)." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if [ -n "$BOOT_TRUSTED_MCM" ] && ! cmp -s "$SOURCE_TREE/$FF_MCM_REL" "$SOURCE_CLONE/$FF_MCM_REL"; then
    echo "[bootstrap-upgrade] ABORT: $SOURCE_CLONE ships a DIFFERENT $FF_MCM_REL than the canonical" >&2
    echo "                    tree this run proved. A worktree re-stamped against its own bytes is" >&2
    echo "                    self-consistent and proves nothing about what upstream shipped." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  # ---- the inputs the manifest does NOT cover (re-review B6) --------------------------------
  # TRIPWIRE: "the consumed worktree is VERIFIED" is only ever true of the MANAGED set.
  # managed_content_manifest.py's MANAGED_DIRS/MANAGED_FILES deliberately exclude VERSION and
  # docs/ — and a pre-boundary engine reads BOTH out of $SOURCE_CLONE: the shipped v4.7.0 tag
  # engine takes SRC_VERSION from .fusebase-flow-source/VERSION and writes it into the consumer
  # (upgrade.sh:214 -> :611), and --with-framework-docs copies .fusebase-flow-source/docs/*.md
  # verbatim (:578-586). A clean commit with ONLY those bytes tampered passes both the verifier
  # and the manifest cmp above, so they are bound to the canonical tree here instead.
  # Widening the manifest is NOT the fix: MANAGED_DIRS/MANAGED_FILES is also the upgrade
  # engine's managed set (K14), so adding VERSION there would put it under classification and
  # change what every consumer's base means. EXTEND THIS LIST when a pre-boundary engine learns
  # to read something new outside the managed set.
  BOOT_UNBOUND=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -f "$SOURCE_TREE/$rel" ] && [ -f "$SOURCE_CLONE/$rel" ]; then
      ff_boot_same_text "$SOURCE_TREE/$rel" "$SOURCE_CLONE/$rel" \
        || BOOT_UNBOUND="$BOOT_UNBOUND
$rel"
    elif [ -f "$SOURCE_TREE/$rel" ] || [ -f "$SOURCE_CLONE/$rel" ]; then
      BOOT_UNBOUND="$BOOT_UNBOUND
$rel (present in only one of the two trees)"
    fi
  done <<FF_UNBOUND
$(ff_boot_unbound_inputs)
FF_UNBOUND
  if [ -n "$BOOT_UNBOUND" ]; then
    echo "[bootstrap-upgrade] ABORT: $SOURCE_CLONE — the tree this pre-boundary engine actually reads —" >&2
    echo "                    differs from the canonical tree this run proved, on path(s) that" >&2
    echo "                    $FF_MCM_REL does not cover but the engine still consumes:" >&2
    printf '%s\n' "$BOOT_UNBOUND" | sed '/^$/d; s/^/                       /' >&2
    echo "                    The manifest proves the MANAGED set only; VERSION and docs/*.md are read" >&2
    echo "                    outside it, so they are bound to the canonical tree separately." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if [ -n "$BOOT_TRUSTED_MCM" ]; then
    echo "[bootstrap-upgrade] re-verified the tree the pre-boundary engine consumes ($SOURCE_CLONE) with the proven canonical verifier: state=$FF_SOURCE_STATE"
  else
    echo "[bootstrap-upgrade] re-verified the tree the pre-boundary engine consumes ($SOURCE_CLONE): state=$FF_SOURCE_STATE"
  fi
fi

# ---- Step 2b: SYNTHESIZE the classifier's base for a consumer arriving without one ----
#
# WHY THIS IS LOAD-BEARING (decision K13a): a consumer on <= 4.6.1 has no
# audit/managed-content-manifest.json. Without a base, EVERY managed path classifies
# `unknown-base`, K9 preserves all of them, and the upgrade reports success while
# installing NOTHING. The classifier release could not deliver its own content.
#
# The fix is not a guess: the upstream tag equal to the consumer's installed VERSION is
# BYTE-IDENTICAL to what their last install/upgrade wrote. Stamping a base from that tag
# is a reconstruction of a fact, not an inference. Only when the tag cannot be resolved
# (a forked or unreleased VERSION) does the tree fall through to `unknown-base` — which is
# preserve + report, never abort (K9 row 10).
BASE_REL="$FF_MCM_REL"
MCM_SRC="$SOURCE_TREE/hooks/local/lib/managed_content_manifest.py"

ff_synthesize_base() {
  local ver tag tmp rc
  if [ -f "$BASE_REL" ]; then
    echo "[bootstrap-upgrade] base manifest already present ($BASE_REL) — no synthesis needed."
    return 0
  fi
  if [ ! -f "$MCM_SRC" ] || ! command -v python3 >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] NOTE: the source tree has no managed-content module (pre-4.7.0)" >&2
    echo "                    or python3 is unavailable — no base can be synthesized." >&2
    return 1
  fi
  [ -f VERSION ] || { echo "[bootstrap-upgrade] NOTE: no local VERSION — cannot pick a base tag." >&2; return 1; }
  ver="$(tr -d '\n\r' < VERSION)"
  tag="v$ver"
  if [ ! -d "$SOURCE_CLONE/.git" ]; then
    echo "[bootstrap-upgrade] NOTE: $SOURCE_CLONE is a plain directory (no .git), so the" >&2
    echo "                    $tag tree cannot be recovered — skipping base synthesis." >&2
    return 1
  fi
  # A --depth 1 --branch <ref> clone carries no tags; fetch just the one we need.
  if ! git -C "$SOURCE_CLONE" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    git -C "$SOURCE_CLONE" fetch --depth 1 origin "refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1 || true
  fi
  if ! git -C "$SOURCE_CLONE" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] NOTE: upstream tag $tag could not be resolved (forked or"
    echo "                    unreleased VERSION). Proceeding with NO base: every managed"
    echo "                    path will classify 'unknown-base', which PRESERVES it and"
    echo "                    reports it — nothing is overwritten, but little is refreshed."
    return 1
  fi
  tmp="$(mktemp -d)"
  # TRIPWIRE (line endings, decision M1) — VERIFIED, do not "simplify" this away, and do NOT
  # make it match the incoming-U call in materialize-managed-source.sh. This is the historical
  # base B: it models what the consumer's own git WROTE at $tag, so it must keep the
  # CONSUMER's EOL convention. `git archive` DOES apply core.autocrlf to files without an eol
  # attribute (measured: true emits CRLF, false/input emit LF), so without this flag the base
  # hashes differ from the consumer's working tree for EVERY managed path — all of them
  # classify changed-by-both and the upgrade aborts having delivered nothing. Forcing LF here
  # is the OPPOSITE error: it makes every untouched CRLF consumer file look locally edited.
  # (A 2026-07-28 review claimed archive ignores autocrlf; removing the flag reproduced the
  # whole-tree misclassification above, so the claim is false on this platform.)
  local eol
  eol="$(git config --get core.autocrlf 2>/dev/null || true)"
  [ -n "$eol" ] || eol="false"
  if ! git -C "$SOURCE_CLONE" -c core.autocrlf="$eol" archive "$tag" | tar -x -C "$tmp" 2>/dev/null; then
    echo "[bootstrap-upgrade] WARN: could not extract $tag — skipping base synthesis." >&2
    rm -rf "$tmp"; return 1
  fi
  # ff_boot_py, not python3: the synthesized base IS the classifier's input, so a startup-file
  # injection here decides what counts as a consumer edit later (re-review B5).
  ff_boot_py "$MCM_SRC" stamp --root "$tmp" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] || [ ! -f "$tmp/$BASE_REL" ]; then
    echo "[bootstrap-upgrade] WARN: base stamp from $tag failed (rc $rc) — skipping." >&2
    rm -rf "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$BASE_REL")"
  cp "$tmp/$BASE_REL" "$BASE_REL"
  rm -rf "$tmp"
  echo "[bootstrap-upgrade] synthesized the classifier base from upstream tag $tag -> $BASE_REL"
  echo "                    (this is what upstream shipped you at $ver, so the upgrade can now"
  echo "                     tell YOUR edits from upstream's.)"
  return 0
}
ff_synthesize_base || true

# ---- Step 3: hand off to the SOURCE engine (never the installed one) ----
# The boundary crosses here as ABSOLUTE internal flags (decision M1 / AC2). We `exec`, so this
# process is replaced and its EXIT trap never runs: ownership of the temp tree transfers to the
# engine via --source-tree-owned, which arms the identical cleanup on its own side. Only pass
# the flags when the source engine understands them (an older --source tree would exit 2 —
# Step 2c decided that, and re-proved the consumed tree for the legacy branch below).
if [ "$LEGACY_ENGINE" = "0" ]; then
  SOURCE_TREE_FLAGS=(--source-tree "$SOURCE_TREE" --source-repo "${FF_SOURCE_REPO:-$SOURCE_CLONE}")
  if [ "${FF_SOURCE_TREE_TEMP:-0}" = "1" ] || [ "${FF_BOOT_TREE_OWNED:-0}" = "1" ]; then
    SOURCE_TREE_FLAGS+=(--source-tree-owned)
  fi
  [ -n "${FF_SOURCE_COMMIT:-}" ] && SOURCE_TREE_FLAGS+=(--source-commit "$FF_SOURCE_COMMIT")
  # handed over; no trap of ours may delete the tree the engine now owns
  FF_SOURCE_TREE_TEMP=0; FF_BOOT_TREE_OWNED=0
else
  # TRIPWIRE (M10 legacy route): a PRE-boundary engine can neither receive nor clean up the
  # canonical tree, and it reads $SOURCE_CLONE itself — so the tree is released HERE and the
  # engine runs from $SOURCE_CLONE. NEVER `exec` a path inside the tree this branch just
  # deleted: that is what stopped a genuine pre-4.7.0 source (M10's named
  # UNVERIFIED_LEGACY_SOURCE route) from upgrading at all — bash exits 127 on a vanished engine.
  # What makes releasing it safe is Step 2c: $SOURCE_CLONE, the tree this engine reads, carries
  # the verdict below on its OWN bytes. Never reach this branch without that re-verification.
  ENGINE_SRC="$SOURCE_CLONE/hooks/local/upgrade.sh"
  if [ ! -f "$ENGINE_SRC" ]; then
    echo "[bootstrap-upgrade] FATAL: the source engine predates the canonical-tree handoff and" >&2
    echo "                    $ENGINE_SRC is missing — nothing to hand off to." >&2
    exit 1
  fi
  echo "[bootstrap-upgrade] NOTE: the source engine predates the canonical-tree handoff; it reads"
  echo "                    $SOURCE_CLONE itself, so the canonical tree is released here and the"
  echo "                    engine runs from $SOURCE_CLONE (source state: ${FF_SOURCE_STATE:-unknown})."
  command -v ff_source_cleanup >/dev/null 2>&1 && ff_source_cleanup
  ff_boot_cleanup
fi
echo "[bootstrap-upgrade] Handing off to $ENGINE_SRC ${PASSTHROUGH[*]:-}"
echo ""
exec bash "$ENGINE_SRC" ${SOURCE_TREE_FLAGS[@]+"${SOURCE_TREE_FLAGS[@]}"} ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
