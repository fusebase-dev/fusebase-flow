#!/usr/bin/env bash
# Fusebase Flow — mirror-skills
# Copies canonical skills from flow-skills/ into the approved provider
# mirror dirs (.agents/skills/ for OpenAI/ChatGPT Codex; .claude/skills/ for
# Anthropic Claude Code) and writes a checksum manifest for drift detection.
#
# We copy (not symlink) for cross-platform GitHub-template reliability.
#
# v3.9.0: canonical moved root skills/ -> flow-skills/ (the FuseBase CLI now
# deprecates the root ./skills name). Legacy root skills/ is still accepted as a
# fallback so a not-yet-migrated tree keeps mirroring until upgrade.sh migrates it.
#
# Windows portability (U1, v3.24.x): Git-Bash spawns a process in ~0.8-1.4s
# (vs ~1-3ms on Linux/macOS), so a per-file sha256sum/cp/$() loop turns into a
# multi-minute stall. We batch all hashing into ONE chunked sha256sum call into
# an assoc-array cache and run a fork-free loop (no $(basename)/$(sha_cmd) per
# file). Copy scope is UNCHANGED — only SKILL.md + references/* per skill, not a
# blind `cp -R` of whole dirs — so the manifest/preflight contract (preflight §5
# validates exactly that set) and the manifest bytes stay identical.

set -euo pipefail

# --check: real read-only drift check (WS3). Compare the current canonical/mirror set
# against the COMMITTED manifest — no mkdir/cp/manifest-rewrite — and exit nonzero on
# drift. Prior to this flag there was NO argv handling and callers who wanted a check
# ran a FULL mirror (side-effecting), which raced concurrent writers into a truncated
# manifest (the self-inflicted 'no such flag' incident). Default (no flag) = write mode.
CHECK_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        *) echo "[mirror-skills] unknown arg: $arg (supported: --check)" >&2; exit 2 ;;
    esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CANON="$ROOT/flow-skills"
[ -d "$CANON" ] || CANON="$ROOT/skills"   # legacy fallback (pre-3.9.0 layout)
MIRRORS=( ".agents/skills" ".claude/skills" )

if [ ! -d "$CANON" ]; then
    echo "[mirror-skills] canonical dir missing: $ROOT/flow-skills (or legacy $ROOT/skills)" >&2
    exit 1
fi

MANIFEST="$ROOT/audit/skill-mirror-manifest.txt"
# Write mode truncates + rebuilds the manifest; --check must NOT touch it (read-only).
if [ "$CHECK_ONLY" -eq 0 ]; then
    mkdir -p "$(dirname "$MANIFEST")"
    : > "$MANIFEST"
fi

# Batched hash command (chunked for ARG_MAX safety). Reads NUL-delimited paths on
# stdin, emits "<hash>  <path>" lines. -n 256 keeps each spawn's argv well under
# any platform ARG_MAX while still collapsing hundreds of files into a handful of
# spawns. Tripwire: the cache key is the path EXACTLY as fed in (fixed 64-hex +
# two spaces + path), so callers must feed the same path string they later look up.
sha_batch() {
    if command -v sha256sum >/dev/null 2>&1; then
        xargs -0 -n 256 sha256sum --
    else
        xargs -0 -n 256 shasum -a 256 --
    fi
}
# Single-file fallback (only used if a path is somehow not primed — keeps drift
# correct even on a cache miss; on Windows this is the slow path we avoid).
sha_one() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# ---- Phase 1: enumerate the exact mirror set (SKILL.md + references/*) ----
# Build the canonical file list and the parallel target list in one pass, with no
# per-file process spawns (pure bash globbing + parameter expansion). Tripwire:
# the emission order MUST match the legacy per-file loop EXACTLY (mirror_root
# outermost; SKILL.md then references/* per skill) or the manifest bytes shift —
# preflight §5 + the audit manifest diff would flag a (false) drift.
declare -a CANON_FILES=()        # canonical source paths (cache keys), de-duped order
declare -a MIRROR_LINES=()       # "<mirror_root>/<rel>\t<canon_file>" target spec
SKILL_COUNT=0

for skill_dir in "$CANON"/*/; do
    sdir="${skill_dir%/}"                       # U1 footgun: strip trailing slash so
    skill_name="${sdir##*/}"                    # the cache key matches single-slash paths
    canon_file="$sdir/SKILL.md"
    [ -f "$canon_file" ] || { echo "[mirror-skills] skip $skill_name (no SKILL.md)"; continue; }
    SKILL_COUNT=$((SKILL_COUNT + 1))

    CANON_FILES+=("$canon_file")
    if [ -d "$sdir/references" ]; then
        for ref in "$sdir/references"/*; do
            [ -f "$ref" ] && CANON_FILES+=("$ref")
        done
    fi

    for mirror_root in "${MIRRORS[@]}"; do
        MIRROR_LINES+=("$mirror_root/$skill_name/SKILL.md"$'\t'"$canon_file")
        if [ -d "$sdir/references" ]; then
            for ref in "$sdir/references"/*; do
                [ -f "$ref" ] || continue
                ref_name="${ref##*/}"
                MIRROR_LINES+=("$mirror_root/$skill_name/references/$ref_name"$'\t'"$ref")
            done
        fi
    done
done

echo "[mirror-skills] mirroring $SKILL_COUNT skill(s) across ${#MIRRORS[@]} mirror(s)…"

# ---- Phase 2: prime the hash cache (one chunked spawn over canon + targets) ----
# Hash canonical sources AND any existing target files in a single batched pass so
# the drift comparison reads the cache directly (no per-file sha spawn).
declare -A HASHCACHE=()
# Temp cache under $TMPDIR (not repo root): an interrupt between create and the
# `rm` below otherwise leaves untracked .mirror-hash-cache.* debris in the tree
# (and in the recovery-sim's plain $PROJECT). mktemp + an EXIT trap clean it up
# on any exit path, including a signal.
HASH_RAW="$(mktemp "${TMPDIR:-/tmp}/mirror-hash-cache.XXXXXX")"
trap 'rm -f "$HASH_RAW"' EXIT
# Feed canon sources + any existing targets (NUL-delimited) to ONE chunked sha
# pass; capture the raw "<hash>  <path>" output to a temp file. Kept off a
# pipefail pipeline whose tail `read` would return EOF=1 and trip `set -e` in a
# non-git/plain-dir run (the recovery-sim's $PROJECT is a plain dir).
{
    for f in "${CANON_FILES[@]}"; do printf '%s\0' "$f"; done
    for line in "${MIRROR_LINES[@]}"; do
        target="$ROOT/${line%%$'\t'*}"
        [ -f "$target" ] && printf '%s\0' "$target"
    done
    # Tripwire: the loop's last `[ -f target ]` is FALSE on a fresh mirror (no
    # existing targets), which would make this brace group exit 1 and — under
    # `pipefail` + `set -e` — abort the whole script in a plain (non-git) dir like
    # the recovery-sim's $PROJECT. Force a 0 exit so the pipe status reflects only
    # sha_batch.
    true
} | sha_batch > "$HASH_RAW"
# sha256sum prints "<hash>  <path>"; slice fixed offsets (space-safe: the repo path
# can contain a space). 64 hex + 2 spaces => path starts at offset 66.
while IFS= read -r line; do
    [ -n "$line" ] || continue
    HASHCACHE["${line:66}"]="${line:0:64}"
done < "$HASH_RAW"
rm -f "$HASH_RAW"

cache_hash() { # cache_hash <path> -> hash (cache hit, else single-file fallback)
    local p="$1"
    if [ -n "${HASHCACHE[$p]:-}" ]; then printf '%s' "${HASHCACHE[$p]}"
    else sha_one "$p"; fi
}

# ---- Phase 3 (--check): real read-only drift check ----
# Compare the current canonical/mirror set against the COMMITTED manifest — no mkdir,
# no cp, no manifest rewrite. Drift = any of: manifest missing a rel, committed hash !=
# current canonical hash, or the mirror file on disk != canonical. Exit nonzero on any
# drift so a caller (preflight, a pre-tag self-test) can gate on it deterministically.
if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
        echo "[mirror-skills] --check: committed manifest missing ($MANIFEST) — run mirror-skills.sh" >&2
        exit 1
    fi
    declare -A COMMITTED=()
    while IFS= read -r mline; do
        [ -n "$mline" ] || continue
        COMMITTED["${mline%%  *}"]="${mline##*  }"   # "<rel>  <hash>" (two-space sep)
    done < "$MANIFEST"
    drifted=0
    for line in "${MIRROR_LINES[@]}"; do
        rel="${line%%$'\t'*}"
        canon_file="${line#*$'\t'}"
        target="$ROOT/$rel"
        canon_hash="$(cache_hash "$canon_file")"
        if [ "${COMMITTED[$rel]:-}" != "$canon_hash" ]; then
            drifted=$((drifted + 1))
            echo "[mirror-skills] --check DRIFT: $rel manifest=${COMMITTED[$rel]:-<absent>} canonical=$canon_hash" >&2
        elif [ ! -f "$target" ]; then
            drifted=$((drifted + 1))
            echo "[mirror-skills] --check DRIFT: $rel mirror file missing on disk" >&2
        elif [ "$(cache_hash "$target")" != "$canon_hash" ]; then
            drifted=$((drifted + 1))
            echo "[mirror-skills] --check DRIFT: $rel on-disk mirror != canonical" >&2
        fi
    done
    # Manifest rows with no live MIRROR_LINES counterpart = stale/extra manifest entry.
    for rel in "${!COMMITTED[@]}"; do
        found=0
        for line in "${MIRROR_LINES[@]}"; do [ "${line%%$'\t'*}" = "$rel" ] && { found=1; break; }; done
        [ "$found" -eq 0 ] && { drifted=$((drifted + 1)); echo "[mirror-skills] --check DRIFT: manifest has stale entry $rel (no live source)" >&2; }
    done
    if [ "$drifted" -eq 0 ]; then
        echo "[mirror-skills] --check: 0 drift ($SKILL_COUNT skill(s); ${#MIRROR_LINES[@]} mirror files vs manifest)"
        exit 0
    fi
    echo "[mirror-skills] --check: $drifted drift(s) — run mirror-skills.sh to regenerate" >&2
    exit 1
fi

# ---- Phase 3 (write): drift detection from the pre-copy cache + bounded copy ----
# Drift is computed BEFORE copying (the cache holds pre-copy target hashes), so the
# printed drift count and the manifest are identical to the per-file implementation.
# Fork-free: the target dir is peeled with ${target%/*} (parameter expansion), not a
# per-file $(dirname) fork — one less spawn per mirrored file (MSYS 255-fork relief).
mirrored=0
drifted=0
for line in "${MIRROR_LINES[@]}"; do
    rel="${line%%$'\t'*}"
    canon_file="${line#*$'\t'}"
    target="$ROOT/$rel"
    canon_hash="$(cache_hash "$canon_file")"

    if [ -f "$target" ]; then
        existing_hash="$(cache_hash "$target")"
        [ "$existing_hash" != "$canon_hash" ] && drifted=$((drifted + 1))
    fi
    mkdir -p "${target%/*}"
    cp "$canon_file" "$target"
    mirrored=$((mirrored + 1))
    echo "$rel  $canon_hash" >> "$MANIFEST"
done

echo "[mirror-skills] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); $drifted had pre-existing drift."
echo "[mirror-skills] manifest: $MANIFEST"
