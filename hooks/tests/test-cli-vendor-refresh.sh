#!/usr/bin/env bash
# Fusebase Flow — guarded CLI re-vendor oracle (S2).
# Spec: docs/specs/cli-0298-compatibility/spec.md § S2.
#
# WHAT IS BEING PROVEN — by deletion, not by assertion.
#   The claim "the refresh preserves CUSTOM:SKILL blocks" is worthless unless something
#   shows (a) the block would otherwise have been destroyed, and (b) the preservation is
#   sourced from the local file rather than faked. Every row here is paired:
#
#     R1 guarded refresh keeps a Flow-only CUSTOM block, byte-for-byte
#     R1c CONTROL — `--blind` (naive copy) on the SAME fixture DESTROYS it
#     R2  delete the block from the local input => it is absent afterwards
#         (proves R1's block came from the local file; a hardcoded/faked block passes R1)
#     R3  upstream content actually lands (the whole point of a re-vendor)
#     R4  supersession: when UPSTREAM ships a block with the SAME title, the local copy is
#         dropped instead of duplicated, and the drop is recorded with both sha256s
#     R4c CONTROL — a DIFFERENT title is preserved, not superseded (the rule is narrow)
#     R5  idempotence: a second run changes nothing
#     R6  a file with no CUSTOM block is byte-identical to upstream
#
#   Fixtures are synthetic CLI trees built here, never the operator's real CLI tree — the
#   oracle must not depend on a directory outside the repo.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-vendor <name>" / "FAIL: cli-vendor <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: cli-vendor $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: cli-vendor $1$w"; }
finish() { echo "[test-cli-vendor-refresh] $pass/$((pass + fail)) PASS"; exit $fail; }

python_bin="${PYTHON:-python3}"
command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-cli-vendor.$$"
mkdir -p "$TMP_BASE"
cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-cli-vendor.*|*/tmp/fusebase-flow-cli-vendor.*|*/Temp/fusebase-flow-cli-vendor.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap cleanup EXIT

REFRESH="$ROOT/hooks/local/refresh-cli-vendor.sh"
OWNERSHIP="$ROOT/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
for f in "$REFRESH" "$OWNERSHIP"; do
  [ -f "$f" ] || { bad setup-files-present "missing $f"; finish; }
done
ok setup-files-present

FLOW_BLOCK='<!-- CUSTOM:SKILL:BEGIN -->
## Consuming Another Fusebase App API

Flow-authored guidance that upstream does not ship.
<!-- CUSTOM:SKILL:END -->'
OTHER_BLOCK='<!-- CUSTOM:SKILL:BEGIN -->
## Flow Only Section

Never shipped by any CLI.
<!-- CUSTOM:SKILL:END -->'

# make_src <dir> [upstream-block]: a synthetic CLI tree carrying one skill Flow vendors
# (app-sidecar, from the ownership map) plus one CLI agent.
make_src() {
  local d="$1" upblock="${2:-}"
  mkdir -p "$d/project-template/.claude/skills/app-sidecar" "$d/project-template/.claude/agents"
  {
    printf -- '# app-sidecar (upstream 9.9.9)\n\n'
    printf -- 'fusebase sidecar list --app <appPath>\n\n'
    [ -z "$upblock" ] || { printf '%s\n\n' "$upblock"; }
    printf -- '## Authentication\n\nupstream auth text\n'
  } > "$d/project-template/.claude/skills/app-sidecar/SKILL.md"
  printf -- '# app-architect (upstream 9.9.9)\nFBS_FEATURE_TOKEN brokering.\n' \
    > "$d/project-template/.claude/agents/app-architect.md"
  printf -- '# app-create-checker (upstream 9.9.9)\n' \
    > "$d/project-template/.claude/agents/app-create-checker.md"
}

# make_dest <dir> [local-block]: a repo-shaped destination with a STALE local copy that
# carries the given Flow-authored block in front of '## Authentication'.
make_dest() {
  local d="$1" block="${2:-}"
  mkdir -p "$d/hooks/local/fusebase-flow-overlays" "$d/audit" \
           "$d/.claude/skills/app-sidecar" "$d/.agents/skills/app-sidecar" \
           "$d/.claude/agents" "$d/.codex/agents"
  cp "$OWNERSHIP" "$d/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
  local m
  for m in .claude/skills .agents/skills; do
    {
      printf -- '# app-sidecar (STALE 0.25.16)\n\n'
      printf -- 'fusebase sidecar list --app <appId>\n'
      printf -- 'fusebase secret create --app <%%= it.flags ? "a" : "b" %%>\n\n'
      [ -z "$block" ] || { printf '%s\n\n' "$block"; }
      printf -- '## Authentication\n\nstale auth text\n'
    } > "$d/$m/app-sidecar/SKILL.md"
  done
  for m in .claude/agents .codex/agents; do
    printf -- '# app-architect (STALE)\n' > "$d/$m/app-architect.md"
    printf -- '# app-create-checker (STALE)\n' > "$d/$m/app-create-checker.md"
  done
}

run_refresh() {  # run_refresh <src> <dest> [extra args...]
  local s="$1" d="$2"; shift 2
  bash "$REFRESH" --source "$s" --dest "$d" --cli-version 9.9.9 "$@" 2>&1
}

# block_sha <file> <index> -> sha256 of the Nth CUSTOM block, or "NONE"
block_sha() {
  "$python_bin" - "$1" "$2" <<'PY'
import hashlib, re, sys, pathlib
BEGIN="<!-- CUSTOM:SKILL:BEGIN -->"; END="<!-- CUSTOM:SKILL:END -->"
RE=re.compile(r"^"+re.escape(BEGIN)+r"\n.*?^"+re.escape(END)+r"$", re.DOTALL|re.MULTILINE)
p=pathlib.Path(sys.argv[1]); i=int(sys.argv[2])
if not p.exists(): print("NOFILE"); raise SystemExit
ms=RE.findall(p.read_bytes().decode("utf-8"))
print(hashlib.sha256(ms[i].encode()).hexdigest() if i < len(ms) else "NONE")
PY
}
block_count() {
  "$python_bin" - "$1" <<'PY'
import re, sys, pathlib
BEGIN="<!-- CUSTOM:SKILL:BEGIN -->"; END="<!-- CUSTOM:SKILL:END -->"
RE=re.compile(r"^"+re.escape(BEGIN)+r"\n.*?^"+re.escape(END)+r"$", re.DOTALL|re.MULTILINE)
p=pathlib.Path(sys.argv[1])
print(len(RE.findall(p.read_bytes().decode("utf-8"))) if p.exists() else -1)
PY
}

TARGET=".claude/skills/app-sidecar/SKILL.md"
MIRROR=".agents/skills/app-sidecar/SKILL.md"

###############################################################################
# R1 + R1c — preservation, and the blind copy that destroys it
###############################################################################
S="$TMP_BASE/s1"; D="$TMP_BASE/d1"; DB="$TMP_BASE/d1blind"
make_src "$S"                       # upstream ships NO custom block
make_dest "$D"  "$FLOW_BLOCK"
make_dest "$DB" "$FLOW_BLOCK"
BEFORE_SHA="$(block_sha "$D/$TARGET" 0)"
run_refresh "$S" "$D"  >/dev/null
run_refresh "$S" "$DB" --blind >/dev/null
AFTER_SHA="$(block_sha "$D/$TARGET" 0)"
BLIND_SHA="$(block_sha "$DB/$TARGET" 0)"
if [ "$AFTER_SHA" = "$BEFORE_SHA" ] && [ "$BEFORE_SHA" != "NONE" ]; then
  ok "r1-guarded-preserves-block-byte-for-byte (sha ${BEFORE_SHA:0:12} before and after)"
else
  bad r1-guarded-preserves-block "before=$BEFORE_SHA after=$AFTER_SHA"
fi
if [ "$BLIND_SHA" = "NONE" ]; then
  ok "r1c-CONTROL-blind-copy-destroys-the-block (same fixture, --blind => 0 blocks; R1 is therefore not vacuous)"
else
  bad r1c-CONTROL-blind-copy-destroys-the-block "blind run still has a block: $BLIND_SHA"
fi
# The block must be preserved on BOTH provider surfaces, not just .claude.
[ "$(block_sha "$D/$MIRROR" 0)" = "$BEFORE_SHA" ] \
  && ok "r1b-preserved-on-both-mirrors (.claude/skills and .agents/skills)" \
  || bad r1b-preserved-on-both-mirrors "mirror sha=$(block_sha "$D/$MIRROR" 0)"

###############################################################################
# R2 — DELETION: no block in the local input => none in the output.
# This is what makes R1 mean something: a hardcoded or fabricated block would still
# satisfy R1, but it would also survive here, and this row would fail.
###############################################################################
S2D="$TMP_BASE/s2"; D2="$TMP_BASE/d2"
make_src "$S2D"
make_dest "$D2" ""                  # local copy with the CUSTOM block DELETED
run_refresh "$S2D" "$D2" >/dev/null
if [ "$(block_count "$D2/$TARGET")" = "0" ]; then
  ok "r2-deletion-oracle (block removed from the local input => absent after refresh; the preserved bytes really come from the local file)"
else
  bad r2-deletion-oracle "expected 0 blocks, got $(block_count "$D2/$TARGET")"
fi

###############################################################################
# R3 — the refresh actually re-vendors (otherwise preservation is trivially true)
###############################################################################
f=""
grep -q 'upstream 9.9.9' "$D/$TARGET" || f="$f [upstream content did not land]"
grep -q 'app <appPath>' "$D/$TARGET" || f="$f [upstream --app <appPath> missing]"
grep -q 'app <appId>'   "$D/$TARGET" && f="$f [stale --app <appId> survived]"
grep -q '<%=' "$D/$TARGET"           && f="$f [stale <%= template syntax survived]"
grep -q 'FBS_FEATURE_TOKEN' "$D/.codex/agents/app-architect.md" \
  || f="$f [.codex/agents not re-vendored — mirror-skills.sh does not carry it, so the refresh must]"
[ -z "$f" ] && ok "r3-upstream-content-lands (incl. .codex/agents, which mirror-skills.sh never touches)" \
            || bad r3-upstream-content-lands "$f"

###############################################################################
# R4 + R4c — supersession is narrow: same TITLE only
###############################################################################
S4="$TMP_BASE/s4"; D4="$TMP_BASE/d4"; D4C="$TMP_BASE/d4c"
UPSTREAM_ADOPTED='<!-- CUSTOM:SKILL:BEGIN -->
## Consuming Another Fusebase App API

Upstream superset that CORRECTS the Flow copy.
<!-- CUSTOM:SKILL:END -->'
make_src "$S4" "$UPSTREAM_ADOPTED"
make_dest "$D4"  "$FLOW_BLOCK"      # same title as upstream's => superseded
make_dest "$D4C" "$OTHER_BLOCK"     # different title       => preserved
OUT4="$(run_refresh "$S4" "$D4")"
OUT4C="$(run_refresh "$S4" "$D4C")"
f=""
[ "$(block_count "$D4/$TARGET")" = "1" ] || f="$f [expected exactly 1 block (upstream's), got $(block_count "$D4/$TARGET") — a duplicated heading is the failure mode]"
printf '%s' "$OUT4" | grep -q "SUPERSEDED" || f="$f [supersession not reported on stdout]"
"$python_bin" - "$D4/audit/cli-upstream-manifest.json" <<'PY' || f="$f [manifest did not record the superseded block with both sha256s]"
import json,sys
d=json.load(open(sys.argv[1]))
s=d.get("superseded_custom_blocks") or []
raise SystemExit(0 if s and all(k in s[0] for k in ("path","title","local_sha256","upstream_sha256")) else 1)
PY
[ -z "$f" ] && ok "r4-upstream-adoption-supersedes (same title => local dropped, not duplicated; recorded with both sha256s)" \
            || bad r4-upstream-adoption-supersedes "$f"
if [ "$(block_count "$D4C/$TARGET")" = "2" ] && ! printf '%s' "$OUT4C" | grep -q "SUPERSEDED"; then
  ok "r4c-CONTROL-different-title-is-preserved (supersession fires on an exact title match only)"
else
  bad r4c-CONTROL-different-title-is-preserved "blocks=$(block_count "$D4C/$TARGET") out=$OUT4C"
fi

###############################################################################
# R5 — idempotence; R6 — a no-block file is byte-identical to upstream
###############################################################################
H1="$("$python_bin" -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$D/$TARGET")"
run_refresh "$S" "$D" >/dev/null
H2="$("$python_bin" -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$D/$TARGET")"
[ "$H1" = "$H2" ] && ok "r5-idempotent (a second guarded refresh changes nothing)" \
                  || bad r5-idempotent "run1=$H1 run2=$H2"

SRC_AGENT="$S/project-template/.claude/agents/app-architect.md"
for m in .claude/agents .codex/agents; do
  cmp -s "$SRC_AGENT" "$D/$m/app-architect.md" || { bad r6-noblock-file-matches-upstream "$m/app-architect.md differs from source"; break; }
done
cmp -s "$SRC_AGENT" "$D/.codex/agents/app-architect.md" \
  && ok "r6-noblock-file-matches-upstream (agent files byte-identical to the source tree on both surfaces)"

finish
