#!/usr/bin/env bash
# Fusebase Flow — INSTALLED_FROM consumed-source provenance (S1, spec consumer-escalation-v480).
#
# Contract home: docs/install-existing-project.md § What an upgrade records (`INSTALLED_FROM`).
# This is ATTRIBUTION, never detection: it records which tree a provenance-aware upgrade
# actually consumed. It cannot notice a moved tag and says nothing about a consumer that
# never upgrades (that consumer stays `unknown`).
#
# TRIPWIRE (decision M10): a PLAIN-directory source is supported and has NO commit SHA
# (materialize-managed-source.sh:83-92). Never make an exact SHA the only representable
# state — a git-only schema would fail on a supported source shape.
#
# API — all state lands in FF_PROV_* globals the caller reads:
#   ff_prov_record <root> <consumed-tree> <source-commit>  write after a SUCCESSFUL upgrade; rc always 0
#   ff_prov_read <root>                                    -> FF_PROV_STATE/VALUE/REASON; rc 1 iff invalid
#   ff_prov_health_line                                    one health line for the last ff_prov_read
#   ff_prov_render <kind> <value>                          canonical marker body (no newline); rc 1 if untypable
#   ff_prov_write <root> <kind> <value>                    atomic same-directory replace
#   ff_prov_tree_digest <tree>                             64-hex snapshot digest, or nothing
#
#   FF_PROV_STATE   git | plain | unknown | invalid
#   FF_PROV_VALUE   the 40-hex commit, or "sha256:<64-hex>"
#   FF_PROV_REASON  why the state is unknown or invalid

FF_PROV_REL="INSTALLED_FROM"
FF_PROV_SCHEMA="fusebase-flow/installed-from/v1"
FF_PROV_STATE=""
FF_PROV_VALUE=""
FF_PROV_REASON=""

_ff_prov_hex() {   # <string> <expected length>
  case "${1:-}" in ""|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq "$2" ]
}

# The ONE canonical form per state: one-line UTF-8 JSON, fixed key order, no insignificant
# whitespace, no trailing newline (ff_prov_write adds exactly one). ff_prov_read validates by
# re-rendering and comparing bytes, so this function is also the schema check — an extra,
# missing, reordered or wrongly-typed member cannot round-trip through it.
ff_prov_render() {   # <git|plain> <40-hex | 64-hex>
  case "${1:-}" in
    git)
      _ff_prov_hex "${2:-}" 40 || return 1
      printf '{"schema":"%s","source_kind":"git","git_commit":"%s"}' "$FF_PROV_SCHEMA" "$2" ;;
    plain)
      _ff_prov_hex "${2:-}" 64 || return 1
      printf '{"schema":"%s","source_kind":"plain","content_digest":"sha256:%s"}' \
        "$FF_PROV_SCHEMA" "$2" ;;
    *) return 1 ;;
  esac
}

# TRIPWIRE (re-review B5, mirrors _ff_mms_py): -I -S so a sitecustomize/.pth on an inherited
# PYTHONPATH — or a json.py sitting in the JUDGED tree next to the script dir — cannot forge
# the digest of the very tree being digested.
_ff_prov_py() { python3 -I -S "$@"; }

# Canonical serialization, so a third party can recompute the digest: for every REGULAR file,
# ordered by its UTF-8 repo-relative POSIX path, feed  <path>\0<byte-length>\0<bytes>  into one
# sha256. `__pycache__/` and *.pyc/*.pyo are excluded (a verifier run inside the snapshot can
# create them; they are already outside every shipped manifest), symlinks are never followed.
ff_prov_tree_digest() {   # <tree> -> 64-hex on stdout, nothing when uncomputable
  [ -d "${1:-}" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  _ff_prov_py -c '
import hashlib, os, sys
root = sys.argv[1]
files = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != "__pycache__"]
    for name in filenames:
        if name.endswith((".pyc", ".pyo")):
            continue
        full = os.path.join(dirpath, name)
        if os.path.islink(full) or not os.path.isfile(full):
            continue
        files.append((os.path.relpath(full, root).replace(os.sep, "/"), full))
h = hashlib.sha256()
for rel, full in sorted(files, key=lambda p: p[0].encode("utf-8")):
    with open(full, "rb") as fh:
        data = fh.read()
    h.update(rel.encode("utf-8") + b"\0" + str(len(data)).encode("ascii") + b"\0" + data)
print(h.hexdigest())
' "$1" 2>/dev/null
}

# Atomic by same-directory temp + rename: a reader never sees a half-written marker, and a
# failed write leaves the PRIOR marker byte-identical.
ff_prov_write() {   # <root> <git|plain> <value>
  local root="$1" body tmp
  body="$(ff_prov_render "$2" "$3")" || return 1
  tmp="$root/.$FF_PROV_REL.ff-prov-tmp.$$"
  printf '%s\n' "$body" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$root/$FF_PROV_REL" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

ff_prov_read() {   # <root>
  FF_PROV_STATE=""; FF_PROV_VALUE=""; FF_PROV_REASON=""
  local f="${1:-.}/$FF_PROV_REL" line="" bytes v
  if [ ! -e "$f" ]; then
    FF_PROV_STATE="unknown"; FF_PROV_REASON="provenance marker unavailable"; return 0
  fi
  if [ ! -f "$f" ]; then
    FF_PROV_STATE="invalid"; FF_PROV_REASON="$FF_PROV_REL is not a regular file"; return 1
  fi
  bytes="$(wc -c < "$f" 2>/dev/null | tr -cd '0-9')"
  IFS= read -r line < "$f" || true
  # An INVALID marker is never normalized to `unknown`: extra bytes after the first line, a
  # missing trailing newline, or CRLF all mean somebody or something rewrote it.
  if [ -z "${bytes:-}" ] || [ "$bytes" != "$(( ${#line} + 1 ))" ]; then
    FF_PROV_STATE="invalid"
    FF_PROV_REASON="not exactly one line ending in a single newline"
    return 1
  fi
  v="$(printf '%s' "$line" | sed -n 's/^.*"git_commit":"\([^"]*\)".*$/\1/p')"
  if [ -n "$v" ] && [ "$(ff_prov_render git "$v" 2>/dev/null)" = "$line" ]; then
    FF_PROV_STATE="git"; FF_PROV_VALUE="$v"; return 0
  fi
  v="$(printf '%s' "$line" | sed -n 's/^.*"content_digest":"sha256:\([^"]*\)".*$/\1/p')"
  if [ -n "$v" ] && [ "$(ff_prov_render plain "$v" 2>/dev/null)" = "$line" ]; then
    FF_PROV_STATE="plain"; FF_PROV_VALUE="sha256:$v"; return 0
  fi
  FF_PROV_STATE="invalid"
  FF_PROV_REASON="does not match the $FF_PROV_SCHEMA canonical form"
  return 1
}

ff_prov_health_line() {
  case "$FF_PROV_STATE" in
    git)   printf 'installed source provenance: git commit %s\n' "$FF_PROV_VALUE" ;;
    plain) printf 'installed source provenance: plain content_digest %s\n' "$FF_PROV_VALUE" ;;
    unknown)
      printf 'installed source provenance: unknown (provenance marker unavailable) — possible causes: a pre-marker install, an early already-current no-op before the first marker write, or a removed marker\n' ;;
    *)
      printf 'installed source provenance: INVALID marker (%s) — integrity failure; re-run the upgrade to rewrite %s\n' \
        "$FF_PROV_REASON" "$FF_PROV_REL" ;;
  esac
}

# ff_prov_record: call ONLY after an upgrade has fully succeeded — every earlier exit path
# (early no-op, abort, FATAL) must leave a prior marker untouched, which is why nothing here
# runs before the last step.
#
# TRIPWIRE (honesty over preservation): when the consumed source cannot be typed, a PRIOR
# marker is REMOVED, not kept. It described a tree this upgrade did not install, so keeping it
# turns the marker into a false attribution; health then reads the honest `unknown`. rc is
# always 0 — provenance is evidence, never a gate on an upgrade that already succeeded.
ff_prov_record() {   # <root> <consumed-tree> <source-commit>
  local root="$1" tree="${2:-}" commit="${3:-}" kind="" value="" digest=""
  if [ -n "$commit" ]; then
    _ff_prov_hex "$commit" 40 && { kind="git"; value="$commit"; }
  else
    digest="$(ff_prov_tree_digest "$tree" 2>/dev/null || true)"
    _ff_prov_hex "${digest:-}" 64 && { kind="plain"; value="$digest"; }
  fi
  if [ -n "$kind" ] && ff_prov_write "$root" "$kind" "$value"; then
    echo "[provenance] recorded consumed source in $FF_PROV_REL (source_kind=$kind)"
    return 0
  fi
  echo "[provenance] WARN: could not type the consumed source, so $FF_PROV_REL was NOT written." >&2
  if [ -e "$root/$FF_PROV_REL" ]; then
    rm -f "$root/$FF_PROV_REL" 2>/dev/null || true
    echo "[provenance] WARN: removed the prior $FF_PROV_REL — it named a tree this upgrade did not install." >&2
  fi
  return 0
}
