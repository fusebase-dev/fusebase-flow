#!/usr/bin/env bash

ffpf_claude_overlay_present() {
    local path="$1"
    LC_ALL=C awk '
        BEGIN { cr = sprintf("%c", 13) }
        {
            line = $0
            sub(cr "$", "", line)
            if (line == "## FuseBase Flow — Claude Code adapter" ||
                line == "## FuseBase Flow — additional rules (overlay)" ||
                line == "## Fusebase Flow — additional rules (overlay)" ||
                line == "# CLAUDE.md — Claude Code adapter for Fusebase Flow") {
                found = 1
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$path"
}
