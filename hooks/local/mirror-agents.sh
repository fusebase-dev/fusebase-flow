#!/usr/bin/env bash
# Fusebase Flow — mirror-agents
# Copies canonical sub-agent definitions from agents/<name>/AGENT.md into the
# approved provider mirror dirs:
#   .claude/agents/<name>.md   (Anthropic Claude Code — auto-discovered)
#   .codex/agents/<name>.md    (OpenAI / ChatGPT Codex — operator-referenced)
# and writes a checksum manifest for drift detection (parallel to the
# skill-mirror manifest).
#
# Note: canonical layout is folder-per-agent (agents/<name>/AGENT.md), but
# providers expect file-per-agent (.claude/agents/<name>.md, etc.). The mirror
# script renames AGENT.md -> <name>.md during copy.
#
# We copy (not symlink) for cross-platform GitHub-template reliability.

set -euo pipefail

# No supported flags — this script only performs the write mirror. Reject any argument
# (notably --check) so it can't be silently misread as a read-only run. Agent-mirror drift
# is detected by preflight.sh (against audit/agent-mirror-manifest.txt); the `--check` flag
# exists only on mirror-skills.sh.
if [ "$#" -gt 0 ]; then
    echo "[mirror-agents] unknown argument: $* (this script takes no flags; it writes the agent mirror)" >&2
    exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CANON="$ROOT/agents"
MIRRORS=( ".claude/agents" ".codex/agents" )

if [ ! -d "$CANON" ]; then
    echo "[mirror-agents] canonical dir missing: $CANON" >&2
    exit 1
fi

MANIFEST="$ROOT/audit/agent-mirror-manifest.txt"
mkdir -p "$(dirname "$MANIFEST")"
# Manifest is rebuilt via a single atomic temp-write + rename at the end (NOT per-row
# appends — see the write below), so no early truncate here. manifest_tmp is set just
# before that write; pre-declared + trapped so a sort/mv failure mid-write can't leave a
# half-written temp behind (set -u safe; rm -f "" is a no-op until it is set).
manifest_tmp=""
hash_raw="$(mktemp "${TMPDIR:-/tmp}/agent-mirror-hash-cache.XXXXXX")"
write_plan=""
write_result=""
trap 'rm -f "$hash_raw" "$manifest_tmp" "$write_plan" "$write_result"' EXIT

sha_batch() {
    if command -v sha256sum >/dev/null 2>&1; then xargs -0 -n 256 sha256sum --
    else xargs -0 -n 256 shasum -a 256 --; fi
}

declare -a AGENT_LINES=()
for agent_dir in "$CANON"/*/; do
    agent_dir="${agent_dir%/}"
    agent_name="${agent_dir##*/}"
    canon_file="$agent_dir/AGENT.md"
    [ -f "$canon_file" ] || { echo "[mirror-agents] skip $agent_name (no AGENT.md)"; continue; }
    for mirror_root in "${MIRRORS[@]}"; do
        AGENT_LINES+=("$mirror_root/$agent_name.md"$'\t'"$canon_file")
    done
done

{
    for line in "${AGENT_LINES[@]}"; do
        canon_file="${line#*$'\t'}"
        printf '%s\0' "$canon_file"
        target_file="$ROOT/${line%%$'\t'*}"
        [ -f "$target_file" ] && printf '%s\0' "$target_file"
    done
    true
} | sha_batch > "$hash_raw"

declare -A HASHCACHE=()
while IFS= read -r line; do
    [ -n "$line" ] || continue
    HASHCACHE["${line:66}"]="${line:0:64}"
done < "$hash_raw"
rm -f "$hash_raw"

cache_hash_into() {
    local path="$1"
    if [ -n "${HASHCACHE[$path]:-}" ]; then HASH_VALUE="${HASHCACHE[$path]}"
    elif command -v sha256sum >/dev/null 2>&1; then read -r HASH_VALUE _ < <(sha256sum -- "$path")
    else read -r HASH_VALUE _ < <(shasum -a 256 -- "$path"); fi
}

mirrored=0
copied=0
drifted=0
manifest_rows=""
write_plan="$(mktemp "${TMPDIR:-/tmp}/agent-write-plan.XXXXXX")"
write_result="$(mktemp "${TMPDIR:-/tmp}/agent-write-result.XXXXXX")"
declare -A CANON_HASH_BY_REL=()
for line in "${AGENT_LINES[@]}"; do
    rel="${line%%$'\t'*}"
    canon_file="${line#*$'\t'}"
    cache_hash_into "$canon_file"; canon_hash="$HASH_VALUE"
    CANON_HASH_BY_REL["$rel"]="$canon_hash"
    printf '%s\t%s\n' "$canon_file" "$rel" >> "$write_plan"
done
set +e
python3 "$ROOT/hooks/local/lib/recovery-owned-write.py" --root "$ROOT" \
  --surface agent --plan "$write_plan" --result "$write_result"
write_rc=$?
set -e
while IFS=$'\t' read -r status rel detail backup; do
    case "$status" in
        current) mirrored=$((mirrored + 1)) ;;
        missing-and-authorized|owned-repair)
            mirrored=$((mirrored + 1)); copied=$((copied + 1)); drifted=$((drifted + 1)) ;;
        *)
            drifted=$((drifted + 1))
            echo "[mirror-agents] preserved $rel ($status: $detail)" >&2
            continue ;;
    esac
    manifest_rows+="$rel  ${CANON_HASH_BY_REL[$rel]}"$'\n'
done < "$write_result"

# Atomic, byte-deterministic manifest write (cross-platform AND concurrency-safe) — see
# mirror-skills.sh for the full rationale. Rows are collected in-memory above, then
# written ONCE to a temp file and renamed into place — never appended per-row, so two
# overlapping runs can never interleave into a duplicated manifest. LC_ALL=C sort pins
# byte order everywhere (LC_COLLATE-independent). Header-less file; drift check is
# hash-map-based, so order does not affect it.
manifest_tmp="$MANIFEST.tmp.$$"
printf '%s' "$manifest_rows" | LC_ALL=C sort > "$manifest_tmp"
if [ -f "$MANIFEST" ] && cmp -s "$manifest_tmp" "$MANIFEST"; then
    rm -f "$manifest_tmp"
else
    mv -f "$manifest_tmp" "$MANIFEST"
fi

echo "[mirror-agents] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); copied $copied; $drifted had pre-existing drift."
echo "[mirror-agents] manifest: $MANIFEST"
exit "$write_rc"
