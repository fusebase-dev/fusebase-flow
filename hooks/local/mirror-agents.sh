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

mirrored=0
copied=0
drifted=0
write_plan="$(mktemp "${TMPDIR:-/tmp}/agent-write-plan.XXXXXX")"
write_result="$(mktemp "${TMPDIR:-/tmp}/agent-write-result.XXXXXX")"
trap 'rm -f "$write_plan" "$write_result"' EXIT
for line in "${AGENT_LINES[@]}"; do
    rel="${line%%$'\t'*}"
    canon_file="${line#*$'\t'}"
    printf '%s\t%s\n' "$canon_file" "$rel" >> "$write_plan"
done
set +e
python3 "$ROOT/hooks/local/lib/recovery-owned-write.py" --root "$ROOT" \
  --surface agent --plan "$write_plan" --result "$write_result" --manifest "$MANIFEST"
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
done < "$write_result"

echo "[mirror-agents] mirrored $mirrored files (across ${#MIRRORS[@]} mirrors); copied $copied; $drifted had pre-existing drift."
echo "[mirror-agents] manifest: $MANIFEST"
exit "$write_rc"
