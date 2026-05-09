#!/usr/bin/env bash
# Fusebase Flow — mirror-skills
# Copies canonical skills from skills/ into the approved provider
# mirror dirs (.agents/skills/ for OpenAI/ChatGPT Codex; .claude/skills/ for
# Anthropic Claude Code) and writes a checksum manifest for drift detection.
#
# We copy (not symlink) for cross-platform GitHub-template reliability.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CANON="$ROOT/skills"
MIRRORS=( ".agents/skills" ".claude/skills" )

if [ ! -d "$CANON" ]; then
    echo "[mirror-skills] canonical dir missing: $CANON" >&2
    exit 1
fi

MANIFEST="$ROOT/audit/skill-mirror-manifest.txt"
mkdir -p "$(dirname "$MANIFEST")"
: > "$MANIFEST"

sha_cmd() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

mirrored=0
drifted=0

for skill_dir in "$CANON"/*/; do
    skill_name="$(basename "$skill_dir")"
    canon_file="$skill_dir/SKILL.md"
    [ -f "$canon_file" ] || { echo "[mirror-skills] skip $skill_name (no SKILL.md)"; continue; }
    canon_hash="$(sha_cmd "$canon_file")"

    for mirror_root in "${MIRRORS[@]}"; do
        target_dir="$ROOT/$mirror_root/$skill_name"
        target_file="$target_dir/SKILL.md"
        mkdir -p "$target_dir"
        if [ -f "$target_file" ]; then
            existing_hash="$(sha_cmd "$target_file")"
            if [ "$existing_hash" != "$canon_hash" ]; then
                drifted=$((drifted + 1))
            fi
        fi
        cp "$canon_file" "$target_file"
        mirrored=$((mirrored + 1))
        # Also surface any references/ subdir if the skill has one.
        if [ -d "$skill_dir/references" ]; then
            mkdir -p "$target_dir/references"
            cp -R "$skill_dir/references/." "$target_dir/references/"
        fi
        echo "$mirror_root/$skill_name/SKILL.md  $canon_hash" >> "$MANIFEST"
    done
done

echo "[mirror-skills] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); $drifted had pre-existing drift."
echo "[mirror-skills] manifest: $MANIFEST"
