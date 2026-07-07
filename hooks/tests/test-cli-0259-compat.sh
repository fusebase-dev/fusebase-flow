#!/usr/bin/env bash
# Fusebase Flow — FuseBase CLI 0.25.9 compatibility + health-check hardening tests.
# Specs: docs/specs/cli-0.25.9-vendor-refresh/spec.md (AC1..AC3b) and
#        docs/specs/healthcheck-baseline-and-custom-flag-hardening/spec.md (AC-M1..M4, AC-L1).
#
# Load-bearing checks (genuine, loud asserts — no false-green):
#   (a) AC1 receipt-framed health-check: the 0.25.9 wired Stop set + Flow stop.py +
#       receipt is OK; AC-M4 — a dropped baselined CLI hook is an ADVISORY
#       (CLI_STOP_BASELINE_DRIFT), NEVER DRIFT/exit-1 (the v3.30.0 SHARED_MERGE_DRIFT
#       assertion is updated here). RED keeps proving the retired hardcoded set is gone.
#   (b) AC2 merge: settings-json-merge.py on a 0.25.9 settings does NOT re-add
#       run-typecheck-apps.js, preserves the 3 CLI hooks + enabledMcpjsonServers,
#       appends stop.py exactly once, and is idempotent.
#   (c) AC3b flag-gate: app-api-contract-testing absent + flag OFF is a benign
#       INFO, not CLI_LAYER_DRIFT.
#   (d) AC3 freshness: re-stamped vendored sha256 == manifest sha256.
#   (e) AC-M1 receipt written on real-merge AND no-op (durable across a 2nd no-op —
#       RED-then-GREEN vs the v3.30.0 rm -f); AC-M2 receipt+dropped -> advisory exit 0
#       (unwired run-typecheck-apps.js stays benign; re-baseline clears it); AC-M3
#       no-receipt -> CLI_STOP_UNVERIFIED exit 0 (no-stop.py -> no nag); AC-L1 sha-gate.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-0259 <name>" / "FAIL: cli-0259 <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

python_bin="${PYTHON:-python3}"
command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: cli-0259 $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: cli-0259 $1 (${2:-})"; }
finish() { echo "[test-cli-0259-compat] $pass/$((pass + fail)) PASS"; exit $fail; }

TMP_BASE="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/cli0259.$$")"
cleanup() { rm -rf "$TMP_BASE" 2>/dev/null || true; }
trap cleanup EXIT

CONFLICT="$ROOT/hooks/local/check-cli-flow-conflicts.sh"
MERGE="$ROOT/hooks/local/fusebase-flow-overlays/settings-json-merge.py"
STAMP="$ROOT/hooks/local/stamp-cli-provenance.sh"
OWNERSHIP="$ROOT/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"

for f in "$CONFLICT" "$MERGE" "$STAMP" "$OWNERSHIP"; do
  [ -f "$f" ] || { bad "setup-files-present" "missing $f"; finish; }
done
ok "setup-files-present"

# Build a minimal but COMPLETE project so the only drift variable under test is
# the .claude/settings.json Stop chain (a partial fixture would surface unrelated
# MISSING findings and mask the assertion).
make_project() { # make_project <dir>
  local p="$1"
  mkdir -p "$p/.claude/hooks" "$p/hooks/local/fusebase-flow-overlays" \
           "$p/hooks/handlers" "$p/flow-skills" "$p/agents" "$p/audit" "$p/state/audit"
  cp "$OWNERSHIP" "$p/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
  cp "$CONFLICT" "$p/hooks/local/check-cli-flow-conflicts.sh"
  cp "$STAMP"    "$p/hooks/local/stamp-cli-provenance.sh"
  cp "$MERGE"    "$p/hooks/local/fusebase-flow-overlays/settings-json-merge.py"
  # Required Flow paths (presence is all the reporter checks for these globs).
  # The reporter derives expected Flow skill/agent mirrors from the fixture's own
  # flow-skills/ + agents/ dirs, then checks the mirror copies exist — so a
  # canonical skill/agent here MUST have its 4 mirror files or the verdict is
  # FLOW_LAYER_DRIFT (masking the CLI-layer assertion under test).
  printf '# rules\n' > "$p/FLOW_RULES.md"
  mkdir -p "$p/flow-skills/role-discipline"; printf 'x\n' > "$p/flow-skills/role-discipline/SKILL.md"
  mkdir -p "$p/agents/product-owner"; printf 'x\n' > "$p/agents/product-owner/AGENT.md"
  mkdir -p "$p/.claude/skills/role-discipline" "$p/.agents/skills/role-discipline"
  printf 'x\n' > "$p/.claude/skills/role-discipline/SKILL.md"
  printf 'x\n' > "$p/.agents/skills/role-discipline/SKILL.md"
  mkdir -p "$p/.claude/agents" "$p/.codex/agents"
  printf 'x\n' > "$p/.claude/agents/product-owner.md"
  printf 'x\n' > "$p/.codex/agents/product-owner.md"
  printf 'x\n' > "$p/hooks/handlers/stop.py"
  printf '# Fusebase Flow\n' > "$p/AGENTS.md"
  printf '# Fusebase Flow\n' > "$p/CLAUDE.md"
  # 0.25.9 ships 4 hooks on disk; run-typecheck-apps.js is present but UNWIRED.
  for h in run-lint-on-stop.sh run-typecheck-on-stop.sh run-typecheck-apps.js quality-check-apps.js; do
    printf '// %s\n' "$h" > "$p/.claude/hooks/$h"
  done
}

# 0.25.9 CLI-only Stop chain (the merge's pre-merge / CLI-shipped state).
stop_chain_259_clionly() { cat <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 },
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-on-stop.sh", "timeout": 300 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 }
] } ] } }
EOF
}

settings_verdict() { # settings_verdict <project-dir> -> prints the .claude/settings.json finding status
  # A heredoc on `python -` claims stdin, so route the JSON through a temp file.
  local jf="$TMP_BASE/sv.$$.json"
  ( cd "$1" && bash hooks/local/check-cli-flow-conflicts.sh --json 2>/dev/null ) > "$jf"
  "$python_bin" - "$jf" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
s=[f for f in d["findings"] if f["path"]==".claude/settings.json"]
print(s[0]["status"] if s else "NONE", "|", (s[0].get("detail","") if s else ""))
PY
}

reporter_exit() { # reporter_exit <project-dir> -> echoes the reporter exit code
  ( cd "$1" && bash hooks/local/check-cli-flow-conflicts.sh --json >/dev/null 2>&1 ); echo $?
}

overall_verdict() { # overall_verdict <project-dir> -> echoes the verdict string
  ( cd "$1" && bash hooks/local/check-cli-flow-conflicts.sh --json 2>/dev/null ) \
    | "$python_bin" -c 'import json,sys;print(json.load(sys.stdin)["verdict"])'
}

###############################################################################
# (a) AC1 — receipt-framed health-check (v3.30.1 advisory model). The diff source
# is now state/audit/cli-stop-baseline.json (the updater-written receipt), NOT
# .pre-flow-merge. The full 0.25.9 chain + receipt = OK; a dropped CLI hook is an
# ADVISORY (never DRIFT/exit-1) — see AC-M4 below + AC-M2/M3 for the new findings.
###############################################################################
P="$TMP_BASE/ac1"; make_project "$P"
# Receipt = the CLI-shipped 3-hook chain the merge preserved (no run-typecheck-apps.js).
receipt_259() { # receipt_259 <path> [hook ...] — default = the 3 wired 0.25.9 hooks
  local out="$1"; shift
  local hooks=("$@"); [ "${#hooks[@]}" -gt 0 ] || hooks=(run-lint-on-stop.sh run-typecheck-on-stop.sh quality-check-apps.js)
  "$python_bin" - "$out" "${hooks[@]}" <<'PY'
import json,sys
json.dump({"schema":1,"cli_stop_hooks":sys.argv[2:],"written_by":"post-fusebase-update --wire-hooks"}, open(sys.argv[1],"w"), indent=2)
PY
}
receipt_259 "$P/state/audit/cli-stop-baseline.json"
# Current = the real post-merge 0.25.9 state (3 CLI hooks + stop.py appended).
cat > "$P/.claude/settings.json" <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 },
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-on-stop.sh", "timeout": 300 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 },
  { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/stop.py" }
] } ] } }
EOF

# RED guard: prove the PRE-FIX hardcoded-marker logic WOULD have phantom-flagged
# run-typecheck-apps.js. We re-run the old algorithm inline; if it does NOT
# produce the phantom the test is meaningless (no RED) -> FAIL loudly.
RED="$( "$python_bin" - "$P" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
cur=json.loads((root/".claude/settings.json").read_text())
cmds=[h["command"] for b in cur["hooks"]["Stop"] for h in b["hooks"]]
expected=["run-typecheck-apps.js","quality-check-apps.js"]  # the retired hardcoded set
hookdir=root/".claude/hooks"
missing=[m for m in expected if (hookdir/m).is_file() and not any(m in c for c in cmds)]
print("PHANTOM" if missing else "NONE")
PY
)"
if [ "$RED" = "PHANTOM" ]; then ok "ac1-red-pre-fix-phantom-confirmed"
else bad "ac1-red-pre-fix-phantom-confirmed" "old hardcoded logic did NOT phantom-flag; RED baseline invalid"; fi

# GREEN: receipt + full chain -> the reporter must NOT flag the settings.json.
V="$(settings_verdict "$P")"
case "$V" in
  OK\ *) ok "ac1-green-0259-set-not-drift" ;;
  *) bad "ac1-green-0259-set-not-drift" "settings.json finding: $V (expected OK)" ;;
esac
# And the overall verdict must be HEALTHY (complete fixture).
VV="$(overall_verdict "$P")"
[ "$VV" = "HEALTHY" ] && ok "ac1-green-verdict-healthy" || bad "ac1-green-verdict-healthy" "verdict=$VV"

# AC-M4 (UPDATED from the v3.30.0 "still-flags-dropped -> SHARED_MERGE_DRIFT"
# assertion): drop run-typecheck-on-stop.sh from the CURRENT chain (it IS in the
# receipt). The advisory model now flags CLI_STOP_BASELINE_DRIFT, NOT DRIFT, and
# the reporter MUST NOT exit 1 from a missing CLI hook anywhere.
cat > "$P/.claude/settings.json" <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 },
  { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/stop.py" }
] } ] } }
EOF
V="$(settings_verdict "$P")"
case "$V" in
  CLI_STOP_BASELINE_DRIFT\ *run-typecheck-on-stop.sh*) ok "ac1-m4-dropped-is-advisory-not-drift" ;;
  *) bad "ac1-m4-dropped-is-advisory-not-drift" "expected CLI_STOP_BASELINE_DRIFT naming run-typecheck-on-stop.sh, got: $V" ;;
esac
RC="$(reporter_exit "$P")"
[ "$RC" -eq 0 ] && ok "ac1-m4-no-exit1-from-missing-cli-hook" || bad "ac1-m4-no-exit1-from-missing-cli-hook" "reporter exited $RC (expected 0; missing CLI hook must never exit-1)"
[ "$(overall_verdict "$P")" = "HEALTHY" ] && ok "ac1-m4-verdict-stays-healthy" || bad "ac1-m4-verdict-stays-healthy" "verdict=$(overall_verdict "$P")"

###############################################################################
# AC-M1 — the receipt is written on the real-merge AND no-op paths, and SURVIVES
# a subsequent no-op run (closes the v3.30.0 rm -f-on-no-op blind spot).
# RED-then-GREEN: the GREEN here is impossible under the v3.30.0 code (which never
# wrote a receipt and rm -f'd the only baseline on the no-op path).
###############################################################################
P="$TMP_BASE/acm1"; make_project "$P"
RCPT="$P/state/audit/cli-stop-baseline.json"
# Real-merge path: a CLI-only 0.25.9 chain (no stop.py yet) -> merge appends stop.py.
stop_chain_259_clionly > "$P/.claude/settings.json"
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json --baseline-out state/audit/cli-stop-baseline.json >/dev/null 2>&1 )
if [ -f "$RCPT" ]; then ok "acm1-receipt-written-on-real-merge"; else bad "acm1-receipt-written-on-real-merge" "no receipt after real merge"; fi
# Receipt content = the 3 preserved CLI hooks, stop.py excluded (it's under hooks/handlers/).
"$python_bin" - "$RCPT" <<'PY' && ok "acm1-receipt-lists-cli-hooks-only" || bad "acm1-receipt-lists-cli-hooks-only" "see assert"
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get("schema")==1, f"bad schema: {r}"
h=r.get("cli_stop_hooks",[])
for m in ("run-lint-on-stop.sh","run-typecheck-on-stop.sh","quality-check-apps.js"):
    assert m in h, f"{m} missing from receipt: {h}"
assert not any("stop.py" in x for x in h), f"stop.py wrongly in receipt: {h}"
PY
# No-op path: a SECOND run (settings already wired) must STILL (re)write the receipt.
rm -f "$RCPT"
NOOP_OUT="$( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json --baseline-out state/audit/cli-stop-baseline.json 2>&1 )"
echo "$NOOP_OUT" | grep -q "already up to date\|byte-identical" || bad "acm1-second-run-is-noop" "2nd run was not a no-op: $NOOP_OUT"
if [ -f "$RCPT" ]; then ok "acm1-receipt-durable-across-noop"; else bad "acm1-receipt-durable-across-noop" "receipt NOT rewritten on the no-op path (v3.30.0 rm -f blind spot)"; fi

###############################################################################
# AC-M2 — receipt present + a baselined CLI hook dropped -> CLI_STOP_BASELINE_DRIFT,
# verdict HEALTHY, exit 0 (NOT SHARED_MERGE_DRIFT/exit-1). The 0.25.9
# run-typecheck-apps.js-on-disk-but-unwired case stays benign (never baselined,
# so never flagged). Re-running the updater clears the advisory.
###############################################################################
P="$TMP_BASE/acm2"; make_project "$P"
receipt_259 "$P/state/audit/cli-stop-baseline.json"
# Dropped run-typecheck-on-stop.sh (baselined) AND run-typecheck-apps.js still on
# disk but never wired/baselined.
cat > "$P/.claude/settings.json" <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 },
  { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/stop.py" }
] } ] } }
EOF
V="$(settings_verdict "$P")"
case "$V" in
  CLI_STOP_BASELINE_DRIFT\ *) ok "acm2-receipt-dropped-hook-is-baseline-drift" ;;
  *) bad "acm2-receipt-dropped-hook-is-baseline-drift" "expected CLI_STOP_BASELINE_DRIFT, got: $V" ;;
esac
case "$V" in
  *run-typecheck-apps.js*) bad "acm2-unwired-typecheck-apps-stays-benign" "unwired run-typecheck-apps.js wrongly flagged: $V" ;;
  *) ok "acm2-unwired-typecheck-apps-stays-benign" ;;
esac
[ "$(overall_verdict "$P")" = "HEALTHY" ] && ok "acm2-verdict-healthy" || bad "acm2-verdict-healthy" "verdict=$(overall_verdict "$P")"
[ "$(reporter_exit "$P")" -eq 0 ] && ok "acm2-exit-0" || bad "acm2-exit-0" "reporter exited $(reporter_exit "$P")"
# Re-baseline escape hatch: re-run the updater -> receipt drops the gone hook -> OK.
receipt_259 "$P/state/audit/cli-stop-baseline.json" run-lint-on-stop.sh quality-check-apps.js
V="$(settings_verdict "$P")"
case "$V" in
  OK\ *) ok "acm2-rebaseline-clears-advisory" ;;
  *) bad "acm2-rebaseline-clears-advisory" "expected OK after re-baseline, got: $V" ;;
esac

###############################################################################
# AC-M3 — has_flow_stop true + NO receipt -> CLI_STOP_UNVERIFIED (never silent),
# verdict HEALTHY, exit 0. A no-stop.py / never-wired project -> NO finding (no nag).
###############################################################################
P="$TMP_BASE/acm3"; make_project "$P"
# stop.py wired, but no receipt on disk.
cat > "$P/.claude/settings.json" <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 },
  { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/stop.py" }
] } ] } }
EOF
rm -f "$P/state/audit/cli-stop-baseline.json"
V="$(settings_verdict "$P")"
case "$V" in
  CLI_STOP_UNVERIFIED\ *) ok "acm3-no-receipt-is-unverified" ;;
  *) bad "acm3-no-receipt-is-unverified" "expected CLI_STOP_UNVERIFIED, got: $V" ;;
esac
[ "$(overall_verdict "$P")" = "HEALTHY" ] && ok "acm3-verdict-healthy" || bad "acm3-verdict-healthy" "verdict=$(overall_verdict "$P")"
[ "$(reporter_exit "$P")" -eq 0 ] && ok "acm3-exit-0" || bad "acm3-exit-0" "reporter exited $(reporter_exit "$P")"
# No-stop.py project (hooks off) + no receipt -> benign INFO, NOT CLI_STOP_UNVERIFIED.
cat > "$P/.claude/settings.json" <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 }
] } ] } }
EOF
V="$(settings_verdict "$P")"
case "$V" in
  CLI_STOP_UNVERIFIED\ *) bad "acm3-no-stop-py-no-nag" "no-stop.py project wrongly nagged: $V" ;;
  INFO\ *) ok "acm3-no-stop-py-no-nag" ;;
  *) bad "acm3-no-stop-py-no-nag" "expected INFO, got: $V" ;;
esac

###############################################################################
# AC-L1 — sha-gate CLI_CUSTOM_AT_RISK: pristine (sha==provenance)+CUSTOM -> NOT
# flagged; drifted (sha!=provenance)+CUSTOM -> flagged; provenance-absent ->
# conservative flag. Advisory-only throughout.
###############################################################################
custom_at_risk_count() {
  ( cd "$1" && bash hooks/local/check-cli-flow-conflicts.sh --json 2>/dev/null ) \
    | "$python_bin" -c 'import json,sys;print(json.load(sys.stdin)["summary"]["cli_custom_at_risk"])'
}
# Vendor the full CLI provider surface so the verdict isn't masked by other drift.
vendor_full_cli_surface() { # vendor_full_cli_surface <dir>
  "$python_bin" - "$1" "$OWNERSHIP" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); own=json.loads(Path(sys.argv[2]).read_text())
names=set()
for e in own["paths"]:
    if "<cli-provider-skill>" in e.get("path",""):
        names.update(e.get("known_names",[]))
for mirror in (".claude/skills",".agents/skills"):
    for n in sorted(names):
        d=p/mirror/n; d.mkdir(parents=True,exist_ok=True); (d/"SKILL.md").write_text(f"# {n}\nbody\n")
for mirror in (".claude/agents",".codex/agents"):
    (p/mirror).mkdir(parents=True,exist_ok=True)
    for a in ("app-architect","app-create-checker"):
        (p/mirror/f"{a}.md").write_text(f"{a}\n")
PY
}
SKILL_REL="fusebase-cli"
P="$TMP_BASE/acl1"; make_project "$P"
receipt_259 "$P/state/audit/cli-stop-baseline.json"
cat > "$P/.claude/settings.json" <<'EOF'
{ "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh", "timeout": 120 },
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-on-stop.sh", "timeout": 300 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 },
  { "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/stop.py" }
] } ] } }
EOF
vendor_full_cli_surface "$P"
# Put a CUSTOM:SKILL block in a CLI-owned skill, then stamp provenance over it.
CB='# fusebase-cli\n<!-- CUSTOM:SKILL:BEGIN -->\noperator note\n<!-- CUSTOM:SKILL:END -->\n'
printf "$CB" > "$P/.claude/skills/$SKILL_REL/SKILL.md"
printf "$CB" > "$P/.agents/skills/$SKILL_REL/SKILL.md"
( cd "$P" && bash hooks/local/stamp-cli-provenance.sh >/dev/null 2>&1 )
# Pristine: sha == provenance -> CUSTOM block NOT flagged.
[ "$(custom_at_risk_count "$P")" -eq 0 ] && ok "acl1-pristine-sha-eq-provenance-not-flagged" || bad "acl1-pristine-sha-eq-provenance-not-flagged" "count=$(custom_at_risk_count "$P") (expected 0)"
# Drift the file content (sha != provenance) -> CUSTOM block flagged.
printf '# fusebase-cli\n<!-- CUSTOM:SKILL:BEGIN -->\nDRIFTED operator content that a refresh would clobber\n<!-- CUSTOM:SKILL:END -->\n' > "$P/.claude/skills/$SKILL_REL/SKILL.md"
[ "$(custom_at_risk_count "$P")" -ge 1 ] && ok "acl1-drifted-sha-ne-provenance-flagged" || bad "acl1-drifted-sha-ne-provenance-flagged" "count=$(custom_at_risk_count "$P") (expected >=1)"
[ "$(overall_verdict "$P")" = "HEALTHY" ] && ok "acl1-advisory-only-stays-healthy" || bad "acl1-advisory-only-stays-healthy" "verdict=$(overall_verdict "$P")"
# Provenance absent for the file (no manifest) -> conservative flag preserved.
P="$TMP_BASE/acl1b"; make_project "$P"
receipt_259 "$P/state/audit/cli-stop-baseline.json"
stop_chain_259_clionly > "$P/.claude/settings.json"
vendor_full_cli_surface "$P"
printf "$CB" > "$P/.claude/skills/$SKILL_REL/SKILL.md"
printf "$CB" > "$P/.agents/skills/$SKILL_REL/SKILL.md"
# no stamp -> no audit/cli-vendor-manifest.json -> PROVENANCE_AVAILABLE False.
[ "$(custom_at_risk_count "$P")" -ge 1 ] && ok "acl1-provenance-absent-conservative-flag" || bad "acl1-provenance-absent-conservative-flag" "count=$(custom_at_risk_count "$P") (expected >=1)"

###############################################################################
# (b) AC2 — merge is preserve-only.
###############################################################################
P="$TMP_BASE/ac2"; make_project "$P"
stop_chain_259_clionly > "$P/.claude/settings.json"
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
"$python_bin" - "$P/.claude/settings.json" <<'PY' && ok "ac2-merge-preserve-only" || bad "ac2-merge-preserve-only" "see assert"
import json,sys
d=json.load(open(sys.argv[1]))
chain=[h.get("command","") for h in d["hooks"]["Stop"][0]["hooks"]]
assert sum("run-typecheck-apps.js" in c for c in chain)==0, f"run-typecheck-apps.js re-injected: {chain}"
for m in ("run-lint-on-stop.sh","run-typecheck-on-stop.sh","quality-check-apps.js"):
    assert sum(m in c for c in chain)==1, f"{m} not preserved exactly once: {chain}"
assert sum("hooks/handlers/stop.py" in c for c in chain)==1, f"stop.py not appended exactly once: {chain}"
assert d.get("enabledMcpjsonServers")==["fusebase-dashboards","fusebase-gate"], f"MCP servers not preserved: {d.get('enabledMcpjsonServers')}"
PY
# Idempotency: a second run is byte-identical.
cp "$P/.claude/settings.json" "$P/snap.json"
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
if diff -q "$P/.claude/settings.json" "$P/snap.json" >/dev/null 2>&1; then ok "ac2-merge-idempotent"
else bad "ac2-merge-idempotent" "second run changed the file"; fi

# Older-CLI guard (D4): a project that DOES wire run-typecheck-apps.js keeps it.
P="$TMP_BASE/ac2-old"; make_project "$P"
cat > "$P/.claude/settings.json" <<'EOF'
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-apps.js", "timeout": 300 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 }
] } ] } }
EOF
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
"$python_bin" - "$P/.claude/settings.json" <<'PY' && ok "ac2-older-cli-typecheck-preserved" || bad "ac2-older-cli-typecheck-preserved" "see assert"
import json,sys
d=json.load(open(sys.argv[1]))
chain=[h.get("command","") for h in d["hooks"]["Stop"][0]["hooks"]]
assert sum("run-typecheck-apps.js" in c for c in chain)==1, f"older-CLI hook removed: {chain}"
assert sum("hooks/handlers/stop.py" in c for c in chain)==1, f"stop.py not appended: {chain}"
PY

# AC2 migration (v3.30.8+): an EXISTING install wired with bare `python3 …handler.py` is
# migrated to the run-handler.sh wrapper on merge (so the python-less self-degrade reaches
# upgraded projects, not only fresh `cp settings.json.example` ones). CLI Stop hooks and the
# stop.py substring are preserved; the migration is idempotent.
P="$TMP_BASE/ac2-migrate"; make_project "$P"
cat > "$P/.claude/settings.json" <<'EOF'
{ "hooks": {
  "SessionStart": [ { "hooks": [ { "type":"command", "command":"python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/session_start.py" } ] } ],
  "Stop": [ { "hooks": [
    { "type":"command", "command":"node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout":30 },
    { "type":"command", "command":"python3 \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/stop.py" }
  ] } ]
} }
EOF
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
"$python_bin" - "$P/.claude/settings.json" <<'PY' && ok "ac2-migrate-python3-to-wrapper" || bad "ac2-migrate-python3-to-wrapper" "see assert"
import json,sys
d=json.load(open(sys.argv[1]))
def cmds(ev): return [h.get("command","") for b in d["hooks"][ev] for h in b.get("hooks",[])]
ss=cmds("SessionStart"); stop=cmds("Stop")
assert ss and all("run-handler.sh" in c for c in ss), f"SessionStart not migrated: {ss}"
assert not any(c.strip().startswith("python3 ") for c in ss+stop), f"bare python3 remains: {ss+stop}"
assert sum("hooks/handlers/stop.py" in c for c in stop)==1, f"stop.py not exactly once: {stop}"
assert any("run-handler.sh" in c and "stop.py" in c for c in stop), f"Stop not migrated: {stop}"
assert sum("quality-check-apps.js" in c for c in stop)==1, f"CLI hook not preserved: {stop}"
PY
cp "$P/.claude/settings.json" "$P/snap2.json"
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
if diff -q "$P/.claude/settings.json" "$P/snap2.json" >/dev/null 2>&1; then ok "ac2-migrate-idempotent"
else bad "ac2-migrate-idempotent" "second migration run changed the file"; fi

# Migration must EXACT-match the canonical legacy form — never clobber an operator
# customization: an added interpreter flag (`python3 -I …`) or a DIFFERENT file whose path
# merely contains hooks/handlers/<x>.py (…/custom/hooks/handlers/<x>.py) must be left as-is.
P="$TMP_BASE/ac2-noclobber"; make_project "$P"
cat > "$P/.claude/settings.json" <<'EOF'
{ "hooks": {
  "SessionStart": [ { "hooks": [ { "type":"command", "command":"python3 -I \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/session_start.py" } ] } ],
  "PreToolUse": [ { "matcher":"Bash", "hooks": [ { "type":"command", "command":"python3 \"$CLAUDE_PROJECT_DIR\"/custom/hooks/handlers/pre_tool_use.py" } ] } ]
} }
EOF
( cd "$P" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
"$python_bin" - "$P/.claude/settings.json" <<'PY' && ok "ac2-migrate-no-clobber-customizations" || bad "ac2-migrate-no-clobber-customizations" "see assert"
import json,sys
d=json.load(open(sys.argv[1]))
def cmds(ev): return [h.get("command","") for b in d["hooks"][ev] for h in b.get("hooks",[])]
ss=cmds("SessionStart"); pt=cmds("PreToolUse")
assert any("python3 -I " in c and "run-handler.sh" not in c for c in ss), f"'-I' customization was clobbered: {ss}"
assert any("/custom/hooks/handlers/pre_tool_use.py" in c and "run-handler.sh" not in c for c in pt), f"custom-path hook was clobbered: {pt}"
PY

###############################################################################
# (c) AC3b — app-api-contract-testing flag-OFF + absent is a benign INFO.
###############################################################################
P="$TMP_BASE/ac3b"; make_project "$P"
stop_chain_259_clionly > "$P/.claude/settings.json"
# Vendor every KNOWN CLI provider skill EXCEPT app-api-contract-testing (which is
# flag-gated; absent + flag-off must be benign, not CLI_LAYER_DRIFT). No
# fusebase.json -> flags undeterminable -> flag-gated absence treated as benign.
"$python_bin" - "$P" "$OWNERSHIP" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); own=json.loads(Path(sys.argv[2]).read_text())
names=set()
for e in own["paths"]:
    if "<cli-provider-skill>" in e.get("path",""):
        names.update(e.get("known_names",[]))
for mirror in (".claude/skills",".agents/skills"):
    for n in sorted(names):
        if n=="app-api-contract-testing":  # leave the flag-gated one absent
            continue
        d=p/mirror/n; d.mkdir(parents=True,exist_ok=True)
        (d/"SKILL.md").write_text(f"# {n}\n")
# Also vendor the 2 CLI app-agents so the agent surface is complete.
for mirror in (".claude/agents",".codex/agents"):
    (p/mirror).mkdir(parents=True,exist_ok=True)
    for a in ("app-architect","app-create-checker"):
        (p/mirror/f"{a}.md").write_text(f"{a}\n")
PY
( cd "$P" && bash hooks/local/check-cli-flow-conflicts.sh --json 2>/dev/null > "$TMP_BASE/ac3b.json" )
AC3B_RC=$?
"$python_bin" - "$TMP_BASE/ac3b.json" <<'PY' && ok "ac3b-flag-gated-benign" || bad "ac3b-flag-gated-benign" "see assert"
import json,sys
d=json.loads(open(sys.argv[1]).read())
assert d["verdict"]!="CLI_LAYER_DRIFT", f"flag-gated absence escalated: {d['verdict']}"
missing=[f for f in d["findings"] if f["status"]=="MISSING" and "app-api-contract-testing" in f["path"]]
assert not missing, f"app-api-contract-testing wrongly MISSING: {missing}"
info=[f for f in d["findings"] if f["status"]=="INFO" and "app-api-contract-testing" in f["path"]]
txt=" ".join((f.get("action","")+" "+f.get("detail","")).lower() for f in info)
assert info and "flag" in txt and "cross-app-api-calls-analysis" in txt, f"expected flag-aware benign INFO, got {info}"
PY
[ "$AC3B_RC" -ne 1 ] && ok "ac3b-flag-gated-exit-not-drift" || bad "ac3b-flag-gated-exit-not-drift" "reporter exited 1 (CLI_LAYER_DRIFT) on flag-gated absence"

###############################################################################
# (d) AC3 — re-vendor freshness: stamped sha256 == manifest, no CLI_SNAPSHOT_STALE.
###############################################################################
P="$TMP_BASE/ac3"; make_project "$P"
stop_chain_259_clionly > "$P/.claude/settings.json"
# Vendor a couple of CLI skills + the agents so the manifest has assets to hash.
"$python_bin" - "$P" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
for mirror in (".claude/skills",".agents/skills"):
    for n in ("fusebase-cli","app-api-contract-testing"):
        d=p/mirror/n; d.mkdir(parents=True,exist_ok=True)
        (d/"SKILL.md").write_text(f"# {n}\nbody\n")
        r=d/"references"; r.mkdir(exist_ok=True); (r/"x.md").write_text("ref\n")
for mirror in (".claude/agents",".codex/agents"):
    (p/mirror).mkdir(parents=True,exist_ok=True)
    for a in ("app-architect","app-create-checker"):
        (p/mirror/f"{a}.md").write_text(f"{a}\n")
PY
( cd "$P" && bash hooks/local/stamp-cli-provenance.sh >/dev/null 2>&1 )
test -f "$P/audit/cli-vendor-manifest.json" || bad "ac3-manifest-generated" "no manifest"
"$python_bin" - "$P" <<'PY' && ok "ac3-freshness-sha-matches-manifest" || bad "ac3-freshness-sha-matches-manifest" "see assert"
import json,hashlib,sys
from pathlib import Path
root=Path(sys.argv[1])
man=json.loads((root/"audit/cli-vendor-manifest.json").read_text())
assert man["assets"], "manifest has no assets"
def sha(p):
    h=hashlib.sha256()
    h.update(p.read_bytes()); return h.hexdigest()
for a in man["assets"]:
    fp=root/a["path"]
    assert fp.is_file(), f"manifest names a missing asset: {a['path']}"
    assert sha(fp)==a["sha256"], f"stale sha for {a['path']}"
PY
# And the reporter sees 0 CLI_SNAPSHOT_STALE on the freshly-stamped snapshot.
( cd "$P" && bash hooks/local/check-cli-flow-conflicts.sh --json 2>/dev/null > "$TMP_BASE/ac3.json" )
"$python_bin" - "$TMP_BASE/ac3.json" <<'PY' && ok "ac3-no-snapshot-stale" || bad "ac3-no-snapshot-stale" "see assert"
import json,sys
d=json.loads(open(sys.argv[1]).read())
assert d["summary"]["cli_snapshot_stale"]==0, f"unexpected stale: {d['summary']}"
PY

finish
