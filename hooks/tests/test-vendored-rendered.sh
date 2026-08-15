#!/usr/bin/env bash
# Fusebase Flow — the `<%=` tripwire (S4).
# Spec: docs/specs/cli-0298-compatibility/spec.md § S4.
#
# WHAT IS BEING PROVEN
#   B2 shipped because nothing asserted that vendored assets are RENDERED: 40 raw ETA
#   interpolations across 12 files, two of them on the sign-in / magic-link surface. The
#   rows below are RED-first — each one reintroduces the defect, watches the check fail
#   NAMING the file, then removes it and watches it pass. A green with no demonstrated
#   red proves only that the check ran.
#
#     T1  live tree is clean AND a non-trivial number of assets was actually scanned
#     T2  reintroduce ONE occurrence => exit 1, names the file:line
#     T3  remove it            => exit 0 again
#     T4  the scope is the MANIFEST, not a directory list: a path added to the manifest
#         is checked from that moment on
#     T5  a file with `<%` (control flow) but no `<%=` is NOT a violation — CLI 0.29.8
#         ships 27 of those itself
#     T6  vacuity guards: an emptied / absent manifest and a missing listed path all exit
#         2, never a silent 0 (the cheapest way to neuter a tripwire is to make it scan
#         nothing)
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-rendered <name>" / "FAIL: cli-rendered <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: cli-rendered $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: cli-rendered $1$w"; }
finish() { echo "[test-vendored-rendered] $pass/$((pass + fail)) PASS"; exit $fail; }

CHECK="$ROOT/hooks/local/check-vendored-rendered.sh"
[ -f "$CHECK" ] || { bad setup "missing $CHECK"; finish; }

python_bin="${PYTHON:-python3}"
command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-rendered.$$"
mkdir -p "$TMP_BASE"
cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-rendered.*|*/tmp/fusebase-flow-rendered.*|*/Temp/fusebase-flow-rendered.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap cleanup EXIT

# The literal needle, assembled so THIS file never contains it — otherwise the tripwire
# would flag its own test the moment someone vendored the tests directory.
NEEDLE='<%''='

run_check() {  # run_check <root> [manifest] -> prints output then EXIT=<rc>
  local r="$1" m="${2:-$1/audit/cli-vendor-manifest.json}" out rc
  out="$(bash "$CHECK" --root "$r" --manifest "$m" 2>&1)"; rc=$?
  printf '%s\nEXIT=%s\n' "$out" "$rc"
}

###############################################################################
# T1 — the live tree, and a vacuity guard on the scan itself
###############################################################################
OUT="$(run_check "$ROOT")"
if echo "$OUT" | grep -q "^EXIT=0$" && echo "$OUT" | grep -qE "OK: [0-9]+ vendored asset\(s\) scanned"; then
  SCANNED="$(echo "$OUT" | sed -n 's/.*OK: \([0-9]*\) vendored asset.*/\1/p')"
  if [ "${SCANNED:-0}" -ge 100 ]; then
    ok "t1-live-tree-clean ($SCANNED vendored assets scanned, 0 occurrences)"
  else
    bad t1-live-tree-clean "only $SCANNED asset(s) scanned — a near-empty scan passes vacuously"
  fi
else
  bad t1-live-tree-clean "$OUT"
fi

###############################################################################
# Scratch root: a real (small) copy of the vendored surface + its own manifest.
###############################################################################
SCRATCH="$TMP_BASE/root"
mkdir -p "$SCRATCH/audit" "$SCRATCH/.claude/skills/app-sidecar" "$SCRATCH/.claude/agents"
cp .claude/skills/app-sidecar/SKILL.md "$SCRATCH/.claude/skills/app-sidecar/SKILL.md"
cp .claude/agents/app-architect.md     "$SCRATCH/.claude/agents/app-architect.md"
cat > "$SCRATCH/audit/cli-vendor-manifest.json" <<'JSON'
{ "schema_version": 2, "source_cli_version": "0.29.8", "asset_count": 2,
  "assets": [ { "path": ".claude/skills/app-sidecar/SKILL.md", "sha256": "x" },
              { "path": ".claude/agents/app-architect.md",     "sha256": "y" } ] }
JSON
VICTIM="$SCRATCH/.claude/skills/app-sidecar/SKILL.md"

OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=0$" || { bad scratch-baseline-clean "$OUT"; finish; }

###############################################################################
# T2 / T3 — RED then GREEN on the same file
###############################################################################
printf 'fusebase secret create --app %s it.flags ? "a" : "b" %%>\n' "$NEEDLE" >> "$VICTIM"
OUT="$(run_check "$SCRATCH")"
f=""
echo "$OUT" | grep -q "^EXIT=1$"  || f="$f [expected exit 1, got: $(echo "$OUT" | grep '^EXIT=')]"
echo "$OUT" | grep -q "FAIL: 1 unrendered" || f="$f [did not report exactly 1 occurrence]"
echo "$OUT" | grep -q "app-sidecar/SKILL.md:" || f="$f [failure does not NAME the offending file:line]"
[ -z "$f" ] && ok "t2-RED-reintroduced-occurrence-fails-naming-the-file" \
            || bad t2-RED-reintroduced-occurrence-fails-naming-the-file "$f"

"$python_bin" - "$VICTIM" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
lines = p.read_bytes().decode("utf-8").split("\n")
p.write_bytes("\n".join(lines[:-2] + [""]).encode("utf-8"))
PY
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=0$" \
  && ok "t3-GREEN-removal-restores-pass (same file, same check)" \
  || bad t3-GREEN-removal-restores-pass "$OUT"

###############################################################################
# T4 — manifest-driven, not directory-hardcoded
###############################################################################
mkdir -p "$SCRATCH/.codex/agents"
printf 'a %s it.x %%> b\n' "$NEEDLE" > "$SCRATCH/.codex/agents/newly-vendored.md"
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=0$" \
  || { bad t4-manifest-driven "a file NOT in the manifest was already being scanned: $OUT"; }
cat > "$SCRATCH/audit/cli-vendor-manifest.json" <<'JSON'
{ "schema_version": 2, "source_cli_version": "0.29.8", "asset_count": 3,
  "assets": [ { "path": ".claude/skills/app-sidecar/SKILL.md", "sha256": "x" },
              { "path": ".claude/agents/app-architect.md",     "sha256": "y" },
              { "path": ".codex/agents/newly-vendored.md",     "sha256": "z" } ] }
JSON
OUT="$(run_check "$SCRATCH")"
if echo "$OUT" | grep -q "^EXIT=1$" && echo "$OUT" | grep -q "newly-vendored.md"; then
  ok "t4-manifest-driven (invisible before the manifest listed it; caught the moment it did — the scope follows the manifest, not a hardcoded dir list)"
else
  bad t4-manifest-driven "$OUT"
fi
rm -f "$SCRATCH/.codex/agents/newly-vendored.md"

###############################################################################
# T5 — `<%` control flow is NOT a violation (0.29.8 ships 27 of them)
###############################################################################
cat > "$SCRATCH/audit/cli-vendor-manifest.json" <<'JSON'
{ "schema_version": 2, "source_cli_version": "0.29.8", "asset_count": 2,
  "assets": [ { "path": ".claude/skills/app-sidecar/SKILL.md", "sha256": "x" },
              { "path": ".claude/agents/app-architect.md",     "sha256": "y" } ] }
JSON
printf '<%% if (it.flags?.includes("portal-specific-apps")) { %%>\ntext\n<%% } %%>\n' >> "$VICTIM"
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=0$" \
  && ok "t5-control-flow-tags-are-not-violations (upstream ships them; only the output interpolation is banned)" \
  || bad t5-control-flow-tags-are-not-violations "$OUT"

###############################################################################
# T6 — vacuity guards: neutering the manifest must not produce a green
###############################################################################
f=""
printf '{ "schema_version": 2, "assets": [] }\n' > "$SCRATCH/audit/cli-vendor-manifest.json"
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=2$" || f="$f [emptied manifest did not exit 2: $(echo "$OUT" | grep '^EXIT=')]"
OUT="$(run_check "$SCRATCH" "$SCRATCH/audit/does-not-exist.json")"
echo "$OUT" | grep -q "^EXIT=2$" || f="$f [absent manifest did not exit 2]"
cat > "$SCRATCH/audit/cli-vendor-manifest.json" <<'JSON'
{ "schema_version": 2, "asset_count": 1,
  "assets": [ { "path": ".claude/skills/gone/SKILL.md", "sha256": "x" } ] }
JSON
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=2$" || f="$f [a manifest path missing from the tree did not exit 2]"
[ -z "$f" ] && ok "t6-vacuity-guards (empty manifest / absent manifest / missing listed path all exit 2, never a silent 0)" \
            || bad t6-vacuity-guards "$f"

###############################################################################
# T7 — vacuity, second and third forms (added after review; each one PASSED
# with `OK: 0 vendored asset(s) scanned` before the fix)
###############################################################################
f=""
# [WAS-VACUOUS] a NON-EMPTY array of pathless entries: the emptiness guard above sees a
# non-empty list, every entry is then skipped, and the check reports success on 0 files.
printf '{ "schema_version": 2, "assets": [{}] }\n' > "$SCRATCH/audit/cli-vendor-manifest.json"
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=2$"   || f="$f [pathless entry did not exit 2: $(echo "$OUT" | grep '^EXIT=')]"
echo "$OUT" | grep -q "MALFORMED"  || f="$f [pathless entry did not name the malformed entry]"
printf '{ "schema_version": 2, "assets": ["nope"] }\n' > "$SCRATCH/audit/cli-vendor-manifest.json"
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=2$"   || f="$f [non-object entry did not exit 2]"
printf '{ "schema_version": 2, "assets": [{"path": "   "}] }\n' > "$SCRATCH/audit/cli-vendor-manifest.json"
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=2$"   || f="$f [whitespace-only path did not exit 2]"
# The manifest must not disagree with itself about its own size.
cat > "$SCRATCH/audit/cli-vendor-manifest.json" <<'JSON'
{ "schema_version": 2, "asset_count": 99,
  "assets": [ { "path": ".claude/agents/app-architect.md", "sha256": "y" } ] }
JSON
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=2$"        || f="$f [asset_count/list-length mismatch did not exit 2]"
echo "$OUT" | grep -q "disagrees with itself" || f="$f [count mismatch did not explain itself]"
# Control: the SAME shape with an honest count must still pass, or the guard above is
# just rejecting everything.
cat > "$SCRATCH/audit/cli-vendor-manifest.json" <<'JSON'
{ "schema_version": 2, "asset_count": 1,
  "assets": [ { "path": ".claude/agents/app-architect.md", "sha256": "y" } ] }
JSON
OUT="$(run_check "$SCRATCH")"
echo "$OUT" | grep -q "^EXIT=0$" || f="$f [CONTROL: an honest 1-asset manifest was rejected — the guards reject everything]"
echo "$OUT" | grep -q "1 vendored asset(s) scanned" || f="$f [CONTROL: honest manifest did not report 1 scanned]"
[ -z "$f" ] && ok "t7-malformed-entry-and-count-guards (pathless / non-object / blank-path entries and an asset_count that disagrees with the list all exit 2; an honest 1-asset manifest still passes)" \
            || bad t7-malformed-entry-and-count-guards "$f"

finish
