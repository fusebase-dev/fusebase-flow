#!/usr/bin/env bash
# Fusebase Flow — rule inventory (AC2 safety instrument for the S5 compression phase).
#
# Emits one normalized line per rule statement, "<ID>\t<normalized-text>", sorted:
#   (a) FLOW_RULES.md FR table       -> "FR-07\t<rule name> :: <rule statement>"
#   (b) role don't-lists             -> "IM.4\t<don't text>"   (PO/IM/AR/DP)
#   (c) Mode-B principle names       -> "B1\t<principle name>"
#
# The Enforcement column is dropped by construction, so rewording enforcement can never
# register as rule loss. Compare a compression pass against the committed baseline:
#   diff <(bash hooks/local/rule-inventory.sh) docs/specs/token-floor-remediation/rule-inventory-baseline.txt
# Non-empty diff = a rule statement changed or vanished. Restore it; never re-baseline.
#
# Usage: rule-inventory.sh [--root DIR]      (DIR default: git toplevel)

set -uo pipefail

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "[rule-inventory] ERROR: unknown arg '$1'" >&2; exit 2 ;;
    esac
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

RULES="$ROOT/FLOW_RULES.md"
ROLE_REFS="$ROOT/flow-skills/role-discipline/references"
COMM="$ROOT/flow-skills/communication"

for p in "$RULES" "$ROLE_REFS" "$COMM"; do
    [ -e "$p" ] || { echo "[rule-inventory] ERROR: missing source $p" >&2; exit 1; }
done

# TRIPWIRE: cells are split on a bare "|", which assumes no escaped "\|" inside a rule
# cell (verified zero across all sources). Introducing one shifts that row's columns.
AWK_PROG='
function norm(s) {
    gsub(/`/, "", s); gsub(/\*/, "", s)
    gsub(/[[:space:]]+/, " ", s); sub(/^ +/, "", s); sub(/ +$/, "", s)
    return tolower(s)
}
function nid(s) { gsub(/[^A-Za-z0-9.-]/, "", s); return s }
# Format-agnostic: heading, table row, and bullet forms of a principle id must all
# normalize to the same "<id>\t<name>" so a layout change is not a rule change.
function emitname(raw,   id, name) {
    if (match(raw, /^B[0-9]+/) == 0) return
    id = substr(raw, 1, RLENGTH); name = substr(raw, RLENGTH + 1)
    sub(/^[ ]*[.:)][ ]*/, "", name)
    sub(/^[ ]*(—|–|-)[ ]*/, "", name)
    sub(/[ ]+(—|–)[ ]+.*$/, "", name)
    sub(/[ ]+-[ ]+.*$/, "", name)
    sub(/[ ]+\(.*$/, "", name)
    sub(/:[ ].*$/, "", name)
    name = norm(name); sub(/[.,;:]+$/, "", name)
    if (name != "") print id "\t" name
}
mode == "fr" && $0 ~ /^\|[ ]*FR-[0-9]+[ ]*\|/ {
    n = split($0, c, "|"); if (n < 4) next
    print nid(c[2]) "\t" norm(c[3]) " :: " norm(c[4]); next
}
mode == "dont" && $0 ~ /^\|[ ]*(PO|IM|AR|DP)\.[0-9]+[ ]*\|/ {
    n = split($0, c, "|"); if (n < 3) next
    print nid(c[2]) "\t" norm(c[3]); next
}
mode == "principle" {
    line = $0
    if (line ~ /^\|[ ]*B[0-9]+[ ]*\|/) {
        n = split(line, c, "|"); if (n < 3) next
        emitname(nid(c[2]) ". " c[3]); next
    }
    sub(/^[ ]*[-*+][ ]+/, "", line); sub(/^#+[ ]*/, "", line)
    gsub(/\*\*/, "", line); gsub(/`/, "", line)
    if (line ~ /^B[0-9]+([ .:)]|-|—|–|$)/) emitname(line)
}
'

extract() { # extract <mode> <file>...
    local mode="$1"; shift
    awk -v mode="$mode" "$AWK_PROG" "$@"
}

# Globs are expanded through a -f test: an unmatched glob passed to awk aborts the pass
# mid-stream and would silently truncate a category.
role_files=(); for f in "$ROLE_REFS"/*.md; do [ -f "$f" ] && role_files+=("$f"); done
comm_files=("$COMM/SKILL.md"); for f in "$COMM"/references/*.md; do [ -f "$f" ] && comm_files+=("$f"); done

fr="$(extract fr "$RULES")"
dont=""; [ ${#role_files[@]} -gt 0 ] && dont="$(extract dont "${role_files[@]}")"
principles="$(extract principle "${comm_files[@]}")"

# Fail closed: an empty category means the parser lost its grip on a source file, and a
# silently empty inventory would read as "nothing to compare" instead of "rules lost".
for pair in "FR:$fr" "dont-list:$dont" "principle:$principles"; do
    [ -n "${pair#*:}" ] || { echo "[rule-inventory] ERROR: zero ${pair%%:*} rows extracted" >&2; exit 1; }
done

printf '%s\n%s\n%s\n' "$fr" "$dont" "$principles" | LC_ALL=C sort -u
