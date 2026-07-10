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
trap 'rm -f "$manifest_tmp"' EXIT

sha_cmd() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

mirrored=0
drifted=0
manifest_rows=""

for agent_dir in "$CANON"/*/; do
    agent_name="$(basename "$agent_dir")"
    canon_file="$agent_dir/AGENT.md"
    [ -f "$canon_file" ] || { echo "[mirror-agents] skip $agent_name (no AGENT.md)"; continue; }
    canon_hash="$(sha_cmd "$canon_file")"

    for mirror_root in "${MIRRORS[@]}"; do
        target_dir="$ROOT/$mirror_root"
        target_file="$target_dir/$agent_name.md"
        mkdir -p "$target_dir"
        if [ -f "$target_file" ]; then
            existing_hash="$(sha_cmd "$target_file")"
            if [ "$existing_hash" != "$canon_hash" ]; then
                drifted=$((drifted + 1))
            fi
        fi
        cp "$canon_file" "$target_file"
        mirrored=$((mirrored + 1))
        manifest_rows+="$mirror_root/$agent_name.md  $canon_hash"$'\n'
    done
done

# Atomic, byte-deterministic manifest write (cross-platform AND concurrency-safe) — see
# mirror-skills.sh for the full rationale. Rows are collected in-memory above, then
# written ONCE to a temp file and renamed into place — never appended per-row, so two
# overlapping runs can never interleave into a duplicated manifest. LC_ALL=C sort pins
# byte order everywhere (LC_COLLATE-independent). Header-less file; drift check is
# hash-map-based, so order does not affect it.
manifest_tmp="$MANIFEST.tmp.$$"
printf '%s' "$manifest_rows" | LC_ALL=C sort > "$manifest_tmp"
mv -f "$manifest_tmp" "$MANIFEST"

echo "[mirror-agents] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); $drifted had pre-existing drift."
echo "[mirror-agents] manifest: $MANIFEST"
