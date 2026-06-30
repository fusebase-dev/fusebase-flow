#!/usr/bin/env bash
# Fusebase Flow — FuseBase CLI 0.25.9 compatibility tests.
# Spec: docs/specs/cli-0.25.9-vendor-refresh/spec.md (AC1, AC2, AC3, AC3b).
#
# Load-bearing checks (genuine, loud asserts — no false-green):
#   (a) AC1 diff-framed health-check: the 0.25.9 wired Stop set + Flow stop.py
#       is NOT SHARED_MERGE_DRIFT, and a genuinely-DROPPED CLI hook IS still
#       flagged. RED-then-GREEN: the pre-fix hardcoded-marker code phantom-
#       flagged run-typecheck-apps.js (unwired in 0.25.9); see the RED assert.
#   (b) AC2 merge: settings-json-merge.py on a 0.25.9 settings does NOT re-add
#       run-typecheck-apps.js, preserves the 3 CLI hooks + enabledMcpjsonServers,
#       appends stop.py exactly once, and is idempotent.
#   (c) AC3b flag-gate: app-api-contract-testing absent + flag OFF is a benign
#       INFO, not CLI_LAYER_DRIFT.
#   (d) AC3 freshness: re-stamped vendored sha256 == manifest sha256.
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
           "$p/hooks/handlers" "$p/flow-skills" "$p/agents" "$p/audit"
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

###############################################################################
# (a) AC1 — diff-framed health-check.
###############################################################################
P="$TMP_BASE/ac1"; make_project "$P"
# Pre-merge backup = the CLI-shipped 3-hook chain (no run-typecheck-apps.js wired).
stop_chain_259_clionly > "$P/.claude/settings.json.pre-flow-merge"
# Current = pre-merge + stop.py appended (the real post-merge 0.25.9 state).
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

# GREEN: the CURRENT (fixed) reporter must NOT flag the settings.json.
V="$(settings_verdict "$P")"
case "$V" in
  OK\ *) ok "ac1-green-0259-set-not-drift" ;;
  *) bad "ac1-green-0259-set-not-drift" "settings.json finding: $V (expected OK)" ;;
esac
# And the overall verdict must be HEALTHY (complete fixture).
VV="$( ( cd "$P" && bash hooks/local/check-cli-flow-conflicts.sh --json 2>/dev/null ) | "$python_bin" -c 'import json,sys;print(json.load(sys.stdin)["verdict"])')"
[ "$VV" = "HEALTHY" ] && ok "ac1-green-verdict-healthy" || bad "ac1-green-verdict-healthy" "verdict=$VV"

# GREEN (still-flags-dropped): drop run-typecheck-on-stop.sh from the CURRENT
# chain (it WAS in the pre-merge backup) -> must be flagged.
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
  DRIFT\ *run-typecheck-on-stop.sh*) ok "ac1-still-flags-dropped-cli-hook" ;;
  *) bad "ac1-still-flags-dropped-cli-hook" "expected DRIFT naming run-typecheck-on-stop.sh, got: $V" ;;
esac

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
