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

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CANON="$ROOT/flow-skills"
[ -d "$CANON" ] || CANON="$ROOT/skills"   # legacy fallback (pre-3.9.0 layout)
MIRRORS=( ".agents/skills" ".claude/skills" )

if [ ! -d "$CANON" ]; then
    echo "[mirror-skills] canonical dir missing: $ROOT/flow-skills (or legacy $ROOT/skills)" >&2
    exit 1
fi

MANIFEST="$ROOT/audit/skill-mirror-manifest.txt"
mkdir -p "$(dirname "$MANIFEST")"
: > "$MANIFEST"

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
{
    for f in "${CANON_FILES[@]}"; do printf '%s\0' "$f"; done
    for line in "${MIRROR_LINES[@]}"; do
        target="$ROOT/${line%%$'\t'*}"
        [ -f "$target" ] && printf '%s\0' "$target"
    done
} | sha_batch | {
    # sha256sum prints "<hash>  <path>"; slice fixed offsets (space-safe: the repo
    # path can contain a space). 64 hex + 2 spaces => path starts at offset 66.
    while IFS= read -r line; do
        printf '%s\t%s\n' "${line:66}" "${line:0:64}"
    done
} > "$ROOT/.mirror-hash-cache.$$"
while IFS=$'\t' read -r path hash; do
    [ -n "$path" ] && HASHCACHE["$path"]="$hash"
done < "$ROOT/.mirror-hash-cache.$$"
rm -f "$ROOT/.mirror-hash-cache.$$"

cache_hash() { # cache_hash <path> -> hash (cache hit, else single-file fallback)
    local p="$1"
    if [ -n "${HASHCACHE[$p]:-}" ]; then printf '%s' "${HASHCACHE[$p]}"
    else sha_one "$p"; fi
}

# ---- Phase 3: drift detection from the pre-copy cache + bounded copy ----
# Drift is computed BEFORE copying (the cache holds pre-copy target hashes), so the
# printed drift count and the manifest are identical to the per-file implementation.
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
    mkdir -p "$(dirname "$target")"
    cp "$canon_file" "$target"
    mirrored=$((mirrored + 1))
    echo "$rel  $canon_hash" >> "$MANIFEST"
done

echo "[mirror-skills] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); $drifted had pre-existing drift."
echo "[mirror-skills] manifest: $MANIFEST"
