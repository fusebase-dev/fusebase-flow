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

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CANON="$ROOT/agents"
MIRRORS=( ".claude/agents" ".codex/agents" )

if [ ! -d "$CANON" ]; then
    echo "[mirror-agents] canonical dir missing: $CANON" >&2
    exit 1
fi

MANIFEST="$ROOT/audit/agent-mirror-manifest.txt"
mkdir -p "$(dirname "$MANIFEST")"
: > "$MANIFEST"

sha_cmd() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

mirrored=0
drifted=0

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
        echo "$mirror_root/$agent_name.md  $canon_hash" >> "$MANIFEST"
    done
done

echo "[mirror-agents] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); $drifted had pre-existing drift."
echo "[mirror-agents] manifest: $MANIFEST"
