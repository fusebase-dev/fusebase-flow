#!/usr/bin/env bash
# Fusebase Flow — rule inventory (AC2 safety instrument; residency schema since T14).
#
# One line per rule statement, 4 tab-separated columns:
#   <ID>  <normalized-text>  <canonical-source-path>  <resident|lazy>
#
# The last two columns are why the schema changed: the T6/T7 compression moved
# prohibitions out of resident carriers into lazy references and the old two-column
# inventory reported a CLEAN diff, because the rule text still existed somewhere. A rule
# that moved resident->lazy, or a don't-list row that moved between roles, is now a
# non-empty diff by construction.
#
# Categories:
#   FR-nn      FLOW_RULES.md rule table            ROLE.*  role authority table
#   BOOT.*     attestation + state announcement    WT.*    FR-24 write-time digest rows
#   PROT.*     shared-protocol prohibition stubs   OD-n    operator expectations
#   FAIL.*     failure / STOP responses            REF.*   exact refusal phrasing
#   PO|IM|AR|DP.n  role don't-lists                Bn      Mode-B principle names
#   QS.*       FR-19 question shapes               FC.*    Mode-B file classification
#   MODE.*     Mode-A / Mode-B normative clauses
#
# Residency is a property of the SOURCE FILE, not of the wording:
#   resident = FLOW_RULES.md operative, the two mandatory SKILL.md files, and the four
#              per-role don't-lists (the attested role must read its own file, and the
#              boot floor budgets one of them).
#   lazy     = everything else under flow-skills/*/references/.
#
# Enforcement columns are dropped by construction, so rewording enforcement can never
# register as rule loss. Compare a compression pass against the committed baseline:
#   diff <(bash hooks/local/rule-inventory.sh) docs/specs/token-floor-remediation/rule-inventory-baseline.txt
# Non-empty diff = a rule statement changed, moved, or vanished. Restore it; never
# re-baseline to make a diff pass.
#
# Usage: rule-inventory.sh [--root DIR]      (DIR default: git toplevel)

set -uo pipefail

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "[rule-inventory] ERROR: unknown arg '$1'" >&2; exit 2 ;;
    esac
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

RULES="$ROOT/FLOW_RULES.md"
ROLE_DIR="$ROOT/flow-skills/role-discipline"
COMM="$ROOT/flow-skills/communication"
ROLE_REFS="$ROLE_DIR/references"

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
function slug(s, max,   t, n, w, i, out) {
    t = norm(s); gsub(/[^a-z0-9 ]/, " ", t); n = split(t, w, " "); out = ""
    for (i = 1; i <= n && i <= max; i++) out = (out == "" ? w[i] : out "-" w[i])
    return out
}
function emit(id, text) {
    if (id == "" || text == "") return
    print id "\t" text "\t" src "\t" res
}
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
    emit(id, name)
}

mode == "fr" && $0 ~ /^\|[ ]*FR-[0-9]+[ ]*\|/ {
    n = split($0, c, "|"); if (n < 4) next
    emit(nid(c[2]), norm(c[3]) " :: " norm(c[4])); next
}
# Role authority: who may write code / specs / handoffs / deploy.
mode == "role" && $0 ~ /^\|[ ]*(Product Owner|AI Developer|Architect|Deploy phase)[^|]*\|/ {
    n = split($0, c, "|"); if (n < 6) next
    emit("ROLE." slug(c[2], 3), norm(c[3]) " :: " norm(c[4]) " :: " norm(c[5]) " :: " norm(c[6])); next
}
mode == "boot" && $0 ~ /Self-attestation \(mandatory/ { emit("BOOT.attestation", norm($0)); next }
mode == "boot" && $0 ~ /State announcement \(mandatory/ { bcap = 1; bbuf = norm($0); next }
mode == "boot" && bcap {
    if ($0 ~ /^```/) { if (++bfence == 2) { emit("BOOT.state-announcement", bbuf); bcap = 0 }; next }
    if ($0 != "") bbuf = bbuf " " norm($0)
    next
}
mode == "dont" && $0 ~ /^\|[ ]*(PO|IM|AR|DP)\.[0-9]+[ ]*\|/ {
    n = split($0, c, "|"); if (n < 3) next
    emit(nid(c[2]), norm(c[3])); next
}
# FR-24 write-time digest: one row per rule the writing agent must apply at write time.
mode == "digest" && $0 ~ /^\|[ ]*FR-[0-9]+[ ]*\|/ {
    n = split($0, c, "|"); if (n < 4) next
    emit("WT." nid(c[2]), norm(c[3])); next
}
# Shared-protocol stubs: heading + the prohibition sentence that follows it.
mode == "protocol" {
    if ($0 ~ /^##+[ ]*[A-Z].*(Protocol|Convention)[ ]*\(/) {
        h = $0; sub(/^##+[ ]*/, "", h); sub(/[ ]*\(.*$/, "", h)
        pending = "PROT." slug(h, 4); next
    }
    if (pending != "" && $0 ~ /[A-Za-z]/) { emit(pending, norm($0)); pending = "" }
    next
}
mode == "od" && $0 ~ /^\|[ ]*OD-[0-9]+[ ]*\|/ {
    n = split($0, c, "|"); if (n < 3) next
    emit(nid(c[2]), norm(c[3])); next
}
# Failure / STOP responses: "| <failure> | <response> |" under a failure-response table.
mode == "failure" {
    if ($0 ~ /^##+.*(Failure|failure)/) { infail = 1; next }
    if ($0 ~ /^##+/) { infail = 0 }
    if (!infail || $0 !~ /^\|/) next
    n = split($0, c, "|"); if (n < 3) next
    if (norm(c[2]) ~ /^-+$/ || norm(c[2]) == "failure mode" || norm(c[2]) == "failure") next
    if (norm(c[3]) == "") next
    emit("FAIL." slug(c[2], 4), norm(c[2]) " :: " norm(c[n - 1])); next
}
# Exact refusal phrasing: the blockquote that follows a "phrasing"/"self-correction" cue.
mode == "refusal" {
    if (tolower($0) ~ /(refusal|deflection|self-correction).*(phrasing|:)/) { armed = 3; next }
    if (armed > 0 && $0 ~ /^>[ ]*[^ ]/) { emit("REF." slug($0, 5), norm($0)); armed = 0; next }
    if (armed > 0) armed--
    next
}
mode == "principle" {
    line = $0
    if (line ~ /^\|[ ]*B[0-9]+[ ]*\|/) {
        n = split(line, c, "|"); if (n < 3) next
        emitname(nid(c[2]) ". " c[3]); next
    }
    sub(/^[ ]*[-*+][ ]+/, "", line); sub(/^#+[ ]*/, "", line)
    gsub(/\*\*/, "", line); gsub(/`/, "", line)
    # TRIPWIRE: the id must be followed by whitespace or a "." / ":" / ")" — never a bare
    # dash. "B1–B12 worked examples" is a RANGE, not a principle definition; accepting a
    # dash separator here mints a phantom principle and a permanently non-empty diff.
    if (line ~ /^B[0-9]+([ .:)]|$)/) emitname(line)
    next
}
# FR-19 question shapes: "| <question type> | <required shape> |".
mode == "qshape" {
    if ($0 ~ /^##+/) { inq = ($0 ~ /questions are chat text/) ? 1 : 0; next }
    if (!inq || $0 !~ /^\|/) next
    n = split($0, c, "|"); if (n < 3) next
    if (norm(c[2]) ~ /^-+$/ || norm(c[2]) == "question type") next
    emit("QS." slug(c[2], 3), norm(c[3])); next
}
# Mode-B file classification: which files are Mode B, Mode B-lite, human-readable.
mode == "fclass" {
    if ($0 ~ /Mode B applies/)   { tier = "FC.mode-b";      buf = ""; next }
    if ($0 ~ /Mode B-lite/)      { emit(tier, buf); tier = "FC.mode-b-lite"; buf = norm($0); next }
    if ($0 ~ /^\*\*Not Mode B/)  { emit(tier, buf); tier = "FC.not-mode-b"; buf = norm($0); next }
    if (tier == "") next
    if ($0 ~ /^##/) { emit(tier, buf); tier = ""; buf = ""; next }
    if ($0 ~ /^```/ || $0 == "") next
    buf = (buf == "" ? norm($0) : buf " " norm($0))
}
END { if (mode == "fclass" && tier != "") emit(tier, buf) }
# Mode-A / Mode-B normative clauses, anchored on their subject (not on layout).
mode == "modeclause" {
    if ($0 ~ /^\*\*Mode A — operator chat/)        { emit("MODE.a", norm($0)); next }
    if ($0 ~ /^\*\*Mode B — internal artifacts/)   { emit("MODE.b", norm($0)); next }
    if ($0 ~ /^Both apply in every session/)       { emit("MODE.both-mandatory", norm($0)); next }
    if ($0 ~ /^\*\*Prohibition — visuals/)         { emit("MODE.no-visuals-in-mode-b", norm($0)); next }
    if ($0 ~ /^\*\*Width \+ decoration/)           { emit("MODE.width-decoration", norm($0)); next }
    if ($0 ~ /^Use one when:/)                     { emit("MODE.visual-triggers", norm($0)); next }
    if ($0 ~ /^Don.t when:/)                       { emit("MODE.visual-suppressors", norm($0)); next }
    next
}
'

# rel PATH -> repo-relative path (the inventory must not leak an absolute checkout path).
rel() { printf '%s' "${1#"$ROOT"/}"; }

# residency PATH: source-file property, never a property of the wording.
residency() {
    case "$(rel "$1")" in
        FLOW_RULES.md|flow-skills/communication/SKILL.md|flow-skills/role-discipline/SKILL.md) echo resident ;;
        flow-skills/role-discipline/references/product-owner.md|\
        flow-skills/role-discipline/references/ai-developer.md|\
        flow-skills/role-discipline/references/architect.md|\
        flow-skills/role-discipline/references/deploy.md) echo resident ;;
        *) echo lazy ;;
    esac
}

extract() { # extract <mode> <file>...
    local mode="$1" f; shift
    for f in "$@"; do
        [ -f "$f" ] || continue
        awk -v mode="$mode" -v src="$(rel "$f")" -v res="$(residency "$f")" "$AWK_PROG" "$f"
    done
}

# Globs are expanded through a -f test: an unmatched glob passed to awk aborts the pass
# mid-stream and would silently truncate a category.
role_files=(); for f in "$ROLE_REFS"/*.md; do [ -f "$f" ] && role_files+=("$f"); done
comm_files=("$COMM/SKILL.md"); for f in "$COMM"/references/*.md; do [ -f "$f" ] && comm_files+=("$f"); done
# Protocol / operator / failure / refusal statements are scanned in BOTH the resident
# SKILL.md and the lazy reference: that is what makes a resident->lazy move visible as a
# path+residency change instead of a clean diff.
proto_files=("$ROLE_DIR/SKILL.md"); [ -f "$ROLE_REFS/shared-protocols.md" ] && proto_files+=("$ROLE_REFS/shared-protocols.md")

fr="$(extract fr "$RULES")"
role="$(extract role "$RULES")"
boot="$(extract boot "$RULES")"
dont=""; [ ${#role_files[@]} -gt 0 ] && dont="$(extract dont "${role_files[@]}")"
digest="$(extract digest "$ROLE_DIR/SKILL.md")"
protocol="$(extract protocol "${proto_files[@]}")"
od="$(extract od "${proto_files[@]}")"
failure="$(extract failure "${proto_files[@]}")"
refusal="$(extract refusal "${proto_files[@]}")"
principles="$(extract principle "${comm_files[@]}")"
qshape="$(extract qshape "$COMM/SKILL.md")"
fclass="$(extract fclass "$COMM/SKILL.md")"
modeclause="$(extract modeclause "$COMM/SKILL.md")"

# Fail closed: an empty category means the parser lost its grip on a source file, and a
# silently empty inventory would read as "nothing to compare" instead of "rules lost".
for pair in "FR:$fr" "role-authority:$role" "boot:$boot" "dont-list:$dont" \
            "write-time-digest:$digest" "protocol:$protocol" "operator:$od" \
            "failure:$failure" "refusal:$refusal" "principle:$principles" \
            "question-shape:$qshape" "file-class:$fclass" "mode-clause:$modeclause"; do
    [ -n "${pair#*:}" ] || { echo "[rule-inventory] ERROR: zero ${pair%%:*} rows extracted" >&2; exit 1; }
done

printf '%s\n' "$fr" "$role" "$boot" "$dont" "$digest" "$protocol" "$od" "$failure" \
              "$refusal" "$principles" "$qshape" "$fclass" "$modeclause" \
  | grep -v '^$' | LC_ALL=C sort -u
