#!/usr/bin/env bash
# Simulate a FuseBase CLI agent-asset refresh followed by Fusebase Flow recovery.
# The test proves ownership behavior, not exact CLI wording.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-cli-sim.$$"
PROJECT="$TMP_BASE/project"
OUT="$TMP_BASE/recovery.out"

cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-cli-sim.*|*/tmp/fusebase-flow-cli-sim.*|*/Temp/fusebase-flow-cli-sim.*)
      rm -rf "$TMP_BASE"
      ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "[test-cli-flow-recovery] FAIL: $*" >&2
  exit 1
}

pass() {
  echo "[test-cli-flow-recovery] PASS: $*"
}

sha_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  python_bin="python"
fi

mkdir -p "$PROJECT"

cp -R flow-skills "$PROJECT/flow-skills"   # v3.9.0: canonical is flow-skills/ (was root skills/)
cp -R agents "$PROJECT/agents"
mkdir -p "$PROJECT/hooks/local"
cp hooks/local/mirror-skills.sh "$PROJECT/hooks/local/"
cp hooks/local/mirror-agents.sh "$PROJECT/hooks/local/"
cp hooks/local/post-fusebase-update.sh "$PROJECT/hooks/local/"
cp hooks/local/check-cli-flow-conflicts.sh "$PROJECT/hooks/local/"
cp hooks/local/stamp-cli-provenance.sh "$PROJECT/hooks/local/"
cp -R hooks/local/lib "$PROJECT/hooks/local/lib"   # health engine sources lib/run-with-timeout.sh
cp -R hooks/local/fusebase-flow-overlays "$PROJECT/hooks/local/fusebase-flow-overlays"
cp -R hooks/handlers "$PROJECT/hooks/handlers"
cp FLOW_RULES.md "$PROJECT/FLOW_RULES.md"

mkdir -p "$PROJECT/.claude/hooks" "$PROJECT/.claude/skills" "$PROJECT/.claude/agents" "$PROJECT/.claude/commands"
mkdir -p "$PROJECT/.agents/skills" "$PROJECT/.codex/agents" "$PROJECT/.codex"

cat > "$PROJECT/AGENTS.md" <<'EOF'
# FuseBase CLI project

CURRENT CLI AGENTS SENTINEL 0.25.5

## Fusebase Flow V2 - stale previous overlay heading
EOF

cat > "$PROJECT/CLAUDE.md" <<'EOF'
# FuseBase CLI Claude instructions

CURRENT CLI CLAUDE SENTINEL 0.25.5

## Fusebase Flow V2 - stale previous overlay heading
EOF

cat > "$PROJECT/.claude/settings.json" <<'EOF'
{
  "enabledMcpjsonServers": [
    "fusebase-dashboards",
    "fusebase-gate"
  ],
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-apps.js",
            "timeout": 300
          },
          {
            "type": "command",
            "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
EOF

cat > "$PROJECT/.codex/config.toml" <<'EOF'
codex_hooks = true
hooks_file = ".codex/hooks.json"
skills_dir = ".agents/skills"

[mcp_servers.fusebase-dashboards]
command = "fusebase"
args = ["mcp", "dashboards"]
EOF

cat > "$PROJECT/.claude/hooks/run-lint-on-stop.sh" <<'EOF'
#!/usr/bin/env bash
echo "CURRENT CLI LINT HOOK SENTINEL"
EOF

cat > "$PROJECT/.claude/hooks/run-typecheck-on-stop.sh" <<'EOF'
#!/usr/bin/env bash
echo "CURRENT CLI TYPECHECK HOOK SENTINEL"
EOF

cat > "$PROJECT/.claude/hooks/quality-check-apps.js" <<'EOF'
console.log("CURRENT CLI QUALITY HOOK SENTINEL");
EOF

cat > "$PROJECT/.claude/hooks/run-typecheck-apps.js" <<'EOF'
console.log("CURRENT CLI HOOK SENTINEL run-typecheck-apps");
EOF

providers=(
  api-exploration
  app-backend
  app-business-docs
  app-dev-practices
  app-routing
  app-secrets
  app-sidecar
  app-ui-design
  dev-debug-logs
  file-upload
  fusebase-cli
  fusebase-dashboards
  fusebase-gate
  fusebase-portal-specific-apps
  git-workflow
  handling-authentication-errors
  managed-integrations
  mcp-gate-debug
  remote-logs
)

for name in "${providers[@]}"; do
  mkdir -p "$PROJECT/.claude/skills/$name" "$PROJECT/.agents/skills/$name"
  printf '# %s\n\nCURRENT CLI SKILL SENTINEL %s\n' "$name" "$name" > "$PROJECT/.claude/skills/$name/SKILL.md"
  printf '# %s\n\nCURRENT CLI SKILL SENTINEL %s\n' "$name" "$name" > "$PROJECT/.agents/skills/$name/SKILL.md"
done

cat > "$PROJECT/.claude/agents/app-architect.md" <<'EOF'
CURRENT CLI AGENT SENTINEL app-architect
EOF

cat > "$PROJECT/.claude/agents/app-create-checker.md" <<'EOF'
CURRENT CLI AGENT SENTINEL app-create-checker
EOF

cat > "$PROJECT/.codex/agents/app-architect.md" <<'EOF'
CURRENT CLI AGENT SENTINEL app-architect
EOF

cat > "$PROJECT/.codex/agents/app-create-checker.md" <<'EOF'
CURRENT CLI AGENT SENTINEL app-create-checker
EOF

CODEX_BEFORE="$(sha_cmd "$PROJECT/.codex/config.toml")"
HOOK_BEFORE="$(sha_cmd "$PROJECT/.claude/hooks/run-typecheck-apps.js")"
CLI_SKILL_BEFORE="$(sha_cmd "$PROJECT/.claude/skills/fusebase-cli/SKILL.md")"
SETTINGS_BEFORE="$(sha_cmd "$PROJECT/.claude/settings.json")"

(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh > "$OUT"
)

grep -q "CURRENT CLI AGENTS SENTINEL" "$PROJECT/AGENTS.md" || fail "CLI AGENTS baseline was lost"
grep -q "## Fusebase Flow — workflow lifecycle overlay" "$PROJECT/AGENTS.md" || fail "current Flow AGENTS overlay was not restored"
grep -q "CURRENT CLI CLAUDE SENTINEL" "$PROJECT/CLAUDE.md" || fail "CLI CLAUDE baseline was lost"
grep -q "## Fusebase Flow — additional rules (overlay)" "$PROJECT/CLAUDE.md" || fail "current Flow CLAUDE overlay was not restored"

[ "$CODEX_BEFORE" = "$(sha_cmd "$PROJECT/.codex/config.toml")" ] || fail ".codex/config.toml changed"
[ "$HOOK_BEFORE" = "$(sha_cmd "$PROJECT/.claude/hooks/run-typecheck-apps.js")" ] || fail "CLI hook helper changed"
[ "$CLI_SKILL_BEFORE" = "$(sha_cmd "$PROJECT/.claude/skills/fusebase-cli/SKILL.md")" ] || fail "CLI provider skill changed"

# F3: DEFAULT recovery is opt-in for hook wiring — it must NOT touch settings.json.
[ "$SETTINGS_BEFORE" = "$(sha_cmd "$PROJECT/.claude/settings.json")" ] || fail "F3: default recovery modified settings.json without --wire-hooks"
grep -q "hooks/handlers/stop.py" "$PROJECT/.claude/settings.json" && fail "F3: stop.py merged without --wire-hooks" || true
[ ! -f "$PROJECT/.claude/settings.json.pre-flow-merge" ] || fail "F3: default recovery left a settings.json backup behind"
grep -q "NOT modified (hook wiring is opt-in" "$OUT" || fail "F3: default recovery did not print the opt-in notice"
pass "F3: default recovery leaves settings.json untouched and prints the opt-in notice"

# F3: explicit --wire-hooks performs the merge, preserving the CLI Stop hooks.
(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh --wire-hooks > "$OUT.wire"
)
grep -q "hooks/handlers/stop.py" "$PROJECT/.claude/settings.json" || fail "Flow stop.py was not merged under --wire-hooks"
grep -q "run-typecheck-apps.js" "$PROJECT/.claude/settings.json" || fail "CLI node typecheck Stop hook not preserved"
grep -q "quality-check-apps.js" "$PROJECT/.claude/settings.json" || fail "CLI quality Stop hook not preserved"
# B5: the deprecated jq/bash Stop hooks are present on disk but were not wired
# in the simulated CLI settings; Flow merge must NOT re-inject them.
grep -q "run-lint-on-stop.sh" "$PROJECT/.claude/settings.json" && fail "deprecated run-lint-on-stop.sh was re-injected into settings" || true
grep -q "run-typecheck-on-stop.sh" "$PROJECT/.claude/settings.json" && fail "deprecated run-typecheck-on-stop.sh was re-injected into settings" || true
pass "F3: --wire-hooks merges Flow lifecycle hooks and preserves the CLI Stop hooks"

test -f "$PROJECT/.claude/skills/role-discipline/SKILL.md" || fail "Flow Claude skill mirror missing"
test -f "$PROJECT/.agents/skills/role-discipline/SKILL.md" || fail "Flow Codex skill mirror missing"
test -f "$PROJECT/.claude/agents/product-owner.md" || fail "Flow Claude agent mirror missing"
test -f "$PROJECT/.codex/agents/product-owner.md" || fail "Flow Codex agent mirror missing"
test -f "$PROJECT/.claude/commands/fusebase-health.md" || fail "Flow health slash command missing"

CONFLICT_OUTPUT="$(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh
)"
echo "$CONFLICT_OUTPUT" | grep -q "Verdict: HEALTHY" || {
  echo "$CONFLICT_OUTPUT" >&2
  fail "conflict reporter did not return HEALTHY after recovery"
}

pass "CLI-owned AGENTS/CLAUDE baselines preserved"
pass "CLI provider skills and hook helpers untouched"
pass "Flow skills, agents, overlays, and health command restored"
pass "conflict reporter returned HEALTHY"

###############################################################################
# U10 — an absent FLAG-GATED CLI provider skill is benign, not CLI_LAYER_DRIFT.
# The CLI deletes flag-gated skills when their flag is off, so absence is by
# design. Removing one from an otherwise-complete install must NOT flip the
# verdict, and the remediation must name `set-flag` (not `fusebase update`).
# Run on a copy so $PROJECT stays clean for the overlay tests below.
###############################################################################
U10P="$TMP_BASE/u10-flaggated"
cp -R "$PROJECT" "$U10P"
rm -rf "$U10P/.claude/skills/managed-integrations" "$U10P/.agents/skills/managed-integrations"
set +e
(
  cd "$U10P"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/u10.json"
)
U10_RC=$?
set -e
[ "$U10_RC" -ne 1 ] || { cat "$TMP_BASE/u10.json" >&2; fail "U10: absent flag-gated skill wrongly escalated to CLI_LAYER_DRIFT (exit 1)"; }
"$python_bin" - "$TMP_BASE/u10.json" <<'PY' || fail "U10: absent flag-gated skill should be benign INFO, not drift"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "CLI_LAYER_DRIFT", f"flag-gated absence must not be CLI_LAYER_DRIFT, got {d['verdict']}"
bad = [f for f in d["findings"] if f["status"] == "MISSING" and "managed-integrations" in f["path"]]
assert not bad, f"flag-gated skill reported MISSING: {bad}"
info = [f for f in d["findings"] if f["status"] == "INFO" and "managed-integrations" in f["path"]]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and "flag" in txt and "set-flag" in txt, f"expected flag-aware benign INFO, got {info}"
PY
pass "U10: absent flag-gated CLI skill is benign INFO (not CLI_LAYER_DRIFT); remediation names set-flag"

###############################################################################
# U11 — Flow hooks NOT wired (opt-in default) is benign, not SHARED_MERGE_DRIFT.
# settings.json exists with CLI hooks but no Flow stop.py → deliberate hooks-off
# (F3) must read as a benign INFO, not drift.
###############################################################################
U11P="$TMP_BASE/u11-hooksoff"
cp -R "$PROJECT" "$U11P"
# Reset settings.json to CLI-only (CLI Stop hooks present, NO Flow stop.py).
cat > "$U11P/.claude/settings.json" <<'EOF'
{
  "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": {
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-apps.js", "timeout": 300 },
        { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 }
      ] }
    ]
  }
}
EOF
set +e
(
  cd "$U11P"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/u11.json"
)
set -e
"$python_bin" - "$TMP_BASE/u11.json" <<'PY' || fail "U11: hooks-off should be benign INFO, not SHARED_MERGE_DRIFT"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "SHARED_MERGE_DRIFT", f"deliberate hooks-off must not be SHARED_MERGE_DRIFT, got {d['verdict']}"
drift = [f for f in d["findings"] if f["path"] == ".claude/settings.json" and f["status"] in ("DRIFT", "MISSING")]
assert not drift, f"settings.json wrongly reported drift: {drift}"
info = [f for f in d["findings"] if f["path"] == ".claude/settings.json" and f["status"] == "INFO"]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and ("not wired" in txt or "opt-in" in txt), f"expected an opt-in INFO for unwired hooks, got {info}"
PY
pass "U11: Flow hooks-off (opt-in) is benign INFO, not SHARED_MERGE_DRIFT"

###############################################################################
# U12 (v3.9.0) — deleting the canonical source (now flow-skills/) is flagged
# loudly. Canonical flow-skills/ gone while mirrors remain → a clear, recoverable
# FLOW_LAYER_DRIFT finding naming the restore path.
###############################################################################
U12P="$TMP_BASE/u12-skillsdeleted"
cp -R "$PROJECT" "$U12P"
rm -rf "$U12P/flow-skills"   # canonical source removed
set +e
(
  cd "$U12P"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/u12.json"
)
set -e
"$python_bin" - "$TMP_BASE/u12.json" <<'PY' || fail "U12: deleted canonical flow-skills/ should be flagged loudly with restore guidance"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
hits = [f for f in d["findings"] if f["path"] == "flow-skills/" and f["status"] == "MISSING"]
assert hits, "expected a loud MISSING finding for deleted canonical flow-skills/"
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in hits).lower()
assert "canonical" in txt, f"finding should name it canonical: {hits}"
assert "upgrade.sh" in txt or "git checkout" in txt, f"finding should name a restore path: {hits}"
assert d["verdict"] == "FLOW_LAYER_DRIFT", f"deleted canonical source should be FLOW_LAYER_DRIFT, got {d['verdict']}"
PY
pass "U12: deleted canonical flow-skills/ is flagged FLOW_LAYER_DRIFT with restore guidance"

###############################################################################
# U19 (v3.9.0) — a legacy root skills/ left ALONGSIDE the new flow-skills/ is
# benign (the CLI's "delete ./skills" warning is finally correct for Flow too):
# a one-line INFO advising the idempotent migration, never drift.
###############################################################################
U19P="$TMP_BASE/u19-legacy-leftover"
cp -R "$PROJECT" "$U19P"
cp -R "$U19P/flow-skills" "$U19P/skills"   # stale legacy copy still present
set +e
(
  cd "$U19P"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/u19.json"
)
U19_RC=$?
set -e
[ "$U19_RC" -ne 1 ] || { cat "$TMP_BASE/u19.json" >&2; fail "U19: legacy skills/ leftover wrongly escalated to drift (exit 1)"; }
"$python_bin" - "$TMP_BASE/u19.json" <<'PY' || fail "U19: legacy skills/ leftover should be a benign INFO, not drift"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", f"legacy leftover must stay HEALTHY, got {d['verdict']}"
info = [f for f in d["findings"] if f["path"] == "skills/" and f["status"] == "INFO"]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and "flow-skills/" in txt and ("safe to delete" in txt or "upgrade.sh" in txt), f"expected benign migration INFO, got {info}"
# It must NOT be a MISSING/drift finding.
bad = [f for f in d["findings"] if f["path"] == "skills/" and f["status"] == "MISSING"]
assert not bad, f"legacy leftover must not be MISSING: {bad}"
PY
pass "U19: legacy root skills/ alongside flow-skills/ is a benign migration INFO (not drift)"

###############################################################################
# U13 (Issue 2) — CLI provider skills absent from the NON-authoritative .agents/
# mirror is benign, not CLI_LAYER_DRIFT. The CLI maintains provider skills in
# .claude/skills only; Flow never writes CLI provider skill text. So a partial
# .agents/ mirror (present in .claude, missing in .agents) must NOT drift, and the
# recommendation must not be the dead-end "run fusebase update".
###############################################################################
U13P="$TMP_BASE/u13-agentsgap"
cp -R "$PROJECT" "$U13P"
for s in app-backend app-routing app-secrets app-sidecar app-ui-design; do
  rm -rf "$U13P/.agents/skills/$s"   # present in .claude, removed from .agents only
done
set +e
(
  cd "$U13P"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/u13.json"
)
U13_RC=$?
set -e
[ "$U13_RC" -ne 1 ] || { cat "$TMP_BASE/u13.json" >&2; fail "U13: .agents CLI-provider gap wrongly escalated to CLI_LAYER_DRIFT (exit 1)"; }
"$python_bin" - "$TMP_BASE/u13.json" <<'PY' || fail "U13: .agents CLI-provider gap should be benign, not drift"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "CLI_LAYER_DRIFT", f".agents CLI-provider gap must not be CLI_LAYER_DRIFT, got {d['verdict']}"
# No MISSING finding for any .agents/skills CLI provider skill.
bad = [f for f in d["findings"] if f["status"] == "MISSING" and f["path"].startswith(".agents/skills/")]
assert not bad, f".agents CLI-provider skills wrongly reported MISSING: {bad}"
# A benign INFO for the .agents mirror that explains it (and does NOT dead-end on `fusebase update`).
info = [f for f in d["findings"] if f["status"] == "INFO" and f["path"] == ".agents/skills"]
txt = " ".join((f.get("action","") + " " + f.get("detail","")) for f in info).lower()
assert info and ".claude/skills" in txt and "expected" in txt, f"expected a benign explanatory INFO for .agents mirror, got {info}"
PY
pass "U13 (Issue 2): .agents CLI-provider mirror gap is benign INFO (not CLI_LAYER_DRIFT); points at .claude/skills, not fusebase update"

###############################################################################
# U14 — --wire-hooks must wire stop.py (not a copied CLI command) onto a Stop
# chain that already has CLI hooks, when discovering the Flow config from the
# upstream example (whose Stop chain lists CLI hooks BEFORE stop.py). Regression
# for the handlers[0] discovery bug. Exercised via the merge script with an
# upstream example present (the existing F3 test runs without one).
###############################################################################
U14P="$TMP_BASE/u14-wirestop"
mkdir -p "$U14P/.fusebase-flow-source/.claude" "$U14P/.claude/hooks" "$U14P/hooks/local/fusebase-flow-overlays"
cp hooks/local/fusebase-flow-overlays/settings-json-merge.py "$U14P/hooks/local/fusebase-flow-overlays/"
cp .claude/settings.json.example "$U14P/.fusebase-flow-source/.claude/settings.json.example"
echo "// cli" > "$U14P/.claude/hooks/run-typecheck-apps.js"
echo "// cli" > "$U14P/.claude/hooks/quality-check-apps.js"
cat > "$U14P/.claude/settings.json" <<'EOF'
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-apps.js", "timeout": 300 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 }
] } ] } }
EOF
(
  cd "$U14P"
  "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1
)
"$python_bin" - "$U14P/.claude/settings.json" <<'PY' || fail "U14: --wire-hooks did not wire stop.py onto an existing CLI Stop chain"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
chain = d["hooks"]["Stop"][0]["hooks"]
flow = [h for h in chain if "Fusebase Flow stop hook" in h.get("statusMessage", "")]
assert flow, "no Flow-labeled Stop entry produced"
assert "hooks/handlers/stop.py" in flow[0]["command"], f"Flow Stop entry has the WRONG command (handlers[0] bug): {flow[0]['command']}"
assert any("hooks/handlers/stop.py" in h.get("command", "") for h in chain), "stop.py missing from Stop chain"
assert sum("run-typecheck-apps.js" in h.get("command", "") for h in chain) == 1, "CLI typecheck duplicated or dropped"
PY
pass "U14: --wire-hooks wires stop.py (not a CLI command) onto an existing CLI Stop chain (discovery picks the Flow handler)"

###############################################################################
# U15 — eslint-ignore-flow-paths.sh adds .fusebase-flow-source/** next to
# .claude/** so the staged upstream clone (CommonJS CLI hooks) doesn't fail the
# downstream's ESLint flat config (which doesn't honor .gitignore) → deploy lint.
###############################################################################
U15P="$TMP_BASE/u15-eslint"
mkdir -p "$U15P/hooks/local"
cp hooks/local/eslint-ignore-flow-paths.sh "$U15P/hooks/local/"
cat > "$U15P/eslint.config.mjs" <<'EOF'
export default [
  {
    ignores: [
      "node_modules/**",
      "**/dist/**",
      ".claude/**"
    ],
  }
];
EOF
(
  cd "$U15P"
  git init -q 2>/dev/null || true
  bash hooks/local/eslint-ignore-flow-paths.sh >/dev/null 2>&1
)
grep -q '"\.fusebase-flow-source/\*\*"' "$U15P/eslint.config.mjs" || fail "U15: helper did not add .fusebase-flow-source/** to eslint ignores"
# .claude/** must now carry a trailing comma (it's no longer last)
grep -qE '"\.claude/\*\*",' "$U15P/eslint.config.mjs" || fail "U15: .claude/** entry not comma-terminated after insert (broken array)"
# idempotent: second run makes no change
cp "$U15P/eslint.config.mjs" "$U15P/eslint.config.mjs.snap"
( cd "$U15P"; bash hooks/local/eslint-ignore-flow-paths.sh >/dev/null 2>&1 )
diff -q "$U15P/eslint.config.mjs" "$U15P/eslint.config.mjs.snap" >/dev/null 2>&1 || fail "U15: helper is not idempotent (second run changed the file)"
pass "U15: eslint-ignore-flow-paths.sh adds .fusebase-flow-source/** next to .claude/** (idempotent, array stays valid)"

###############################################################################
# F2 (U16) — the MAIN health engine (fusebase-flow-health-check.sh), not just the
# conflict checker, must read deliberate hooks-off as benign (U11 consistency).
# An overlay-only install (CLI hooks present, no Flow stop.py, no clobber) must
# NOT verdict SHARED_MERGE_DRIFT.
###############################################################################
F2P="$TMP_BASE/f2-engine-hooksoff"
cp -R "$PROJECT" "$F2P"
cp hooks/local/fusebase-flow-health-check.sh "$F2P/hooks/local/"
cp VERSION "$F2P/VERSION"   # main engine checks VERSION at repo root (fixture lacks it)
cat > "$F2P/.claude/settings.json" <<'EOF'
{
  "enabledMcpjsonServers": ["fusebase-dashboards", "fusebase-gate"],
  "hooks": {
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-apps.js", "timeout": 300 },
        { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 }
      ] }
    ]
  }
}
EOF
(
  cd "$F2P"
  FFHC_PREFLIGHT_TIMEOUT=600 FFHC_TESTS_TIMEOUT=600 FFHC_CONFLICT_TIMEOUT=600 FFHC_FETCH_TIMEOUT=30 bash hooks/local/fusebase-flow-health-check.sh > "$TMP_BASE/f2.out" 2>&1 || true
)
grep -q "Verdict: SHARED_MERGE_DRIFT" "$TMP_BASE/f2.out" && { sed -n '/Verdict/,$p' "$TMP_BASE/f2.out" >&2; fail "F2: main health engine verdict SHARED_MERGE_DRIFT for deliberate hooks-off (should be benign)"; } || true
grep -qE "lifecycle events wired \(stop.py present|stop.py missing from Stop chain" "$TMP_BASE/f2.out" && fail "F2: main engine recorded a settings.json drift for the opt-in-off state" || true
grep -q "Flow lifecycle hooks not wired (opt-in" "$TMP_BASE/f2.out" || fail "F2: main engine did not emit the benign opt-in note for hooks-off"
pass "F2 (U16): main health engine reads deliberate hooks-off as benign (no SHARED_MERGE_DRIFT)"

###############################################################################
# U17/U18 — "two engines agree": the MAIN engine folds the conflict checker but
# only its MISSING/DRIFT, so INFO classifications must NOT surface as drift.
# U17 = flag-gated absence (U10 class); U18 = .agents/.codex gap (U13 class).
###############################################################################
run_main_engine_verdict() {  # $1=project dir → Verdict line; `|| true`+budgets => exit 4 won't abort the suite
  local out
  out="$(cd "$1" 2>/dev/null && FFHC_PREFLIGHT_TIMEOUT=600 FFHC_TESTS_TIMEOUT=600 FFHC_CONFLICT_TIMEOUT=600 FFHC_FETCH_TIMEOUT=30 bash hooks/local/fusebase-flow-health-check.sh 2>/dev/null)" || true
  printf '%s\n' "$out" | grep -m1 "^Verdict:" || echo "Verdict: (none captured)"
}

U17P="$TMP_BASE/u17-engine-flaggated"
cp -R "$PROJECT" "$U17P"
cp hooks/local/fusebase-flow-health-check.sh "$U17P/hooks/local/"
cp VERSION "$U17P/VERSION"
rm -rf "$U17P/.claude/skills/managed-integrations" "$U17P/.agents/skills/managed-integrations"
V17="$(run_main_engine_verdict "$U17P")"
case "$V17" in
  *CLI_LAYER_DRIFT*) fail "U17: main engine $V17 for a flag-gated absence (should be benign)";;
  *HEALTHY*) : ;;
  *) fail "U17: unexpected main-engine '$V17' (expected HEALTHY)";;
esac
pass "U17: main health engine reads a flag-gated CLI skill absence as benign (HEALTHY)"

U18P="$TMP_BASE/u18-engine-agentsgap"
cp -R "$PROJECT" "$U18P"
cp hooks/local/fusebase-flow-health-check.sh "$U18P/hooks/local/"
cp VERSION "$U18P/VERSION"
for s in app-backend app-routing app-secrets app-sidecar app-ui-design; do rm -rf "$U18P/.agents/skills/$s"; done
V18="$(run_main_engine_verdict "$U18P")"
case "$V18" in
  *CLI_LAYER_DRIFT*) fail "U18: main engine $V18 for a .agents CLI-provider gap (should be benign)";;
  *HEALTHY*) : ;;
  *) fail "U18: unexpected main-engine '$V18' (expected HEALTHY)";;
esac
pass "U18: main health engine reads a non-authoritative .agents CLI-provider gap as benign (HEALTHY)"

###############################################################################
# F2 — version-aware overlay refresh is marker-anchored and idempotent.
# The reported bug: --refresh-overlays anchored on the heading, but the
# templates wrap the heading inside CUSTOM:SKILL markers, so the drift check was
# always true and each run re-appended the wrapper (BEGIN count grew, END went
# unbalanced). These assertions pin: (1) refreshing a CURRENT block is a no-op
# with exactly one balanced BEGIN/END; (2) a drifted block is restored to one
# balanced block; (3) re-running is idempotent.
###############################################################################
count_marker() { awk -v m="$2" 'index($0,m){n++} END{print n+0}' "$1"; }
MB="<!-- CUSTOM:SKILL:BEGIN -->"
ME="<!-- CUSTOM:SKILL:END -->"

for ov in AGENTS.md CLAUDE.md; do
  [ "$(count_marker "$PROJECT/$ov" "$MB")" -eq 1 ] \
    || fail "F2 precondition: $ov should have exactly 1 BEGIN after recovery, got $(count_marker "$PROJECT/$ov" "$MB")"
done

# Byte-exactness baseline: the clean, freshly-appended AGENTS.md block. A no-op
# refresh must leave it identical; a drift refresh must converge back to it
# byte-for-byte (locks the trailing-blank-before-BEGIN nit so it can't regress).
AGENTS_GOOD="$(sha_cmd "$PROJECT/AGENTS.md")"

# (1) refresh a CURRENT block -> no-op (no backup, reported "present and current").
rm -f "$PROJECT"/AGENTS.md.pre-refresh-* "$PROJECT"/CLAUDE.md.pre-refresh-*
(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.refresh1"
)
for ov in AGENTS.md CLAUDE.md; do
  [ "$(count_marker "$PROJECT/$ov" "$MB")" -eq 1 ] \
    || fail "F2: refreshing a CURRENT $ov changed BEGIN count to $(count_marker "$PROJECT/$ov" "$MB") (duplication bug)"
  [ "$(count_marker "$PROJECT/$ov" "$ME")" -eq 1 ] \
    || fail "F2: $ov has $(count_marker "$PROJECT/$ov" "$ME") END markers (expected 1 — unbalanced)"
  grep -q "$ov overlay present and current" "$OUT.refresh1" \
    || fail "F2: refresh of a current $ov was not reported as 'present and current'"
done
ls "$PROJECT"/AGENTS.md.pre-refresh-* >/dev/null 2>&1 && fail "F2: no-op refresh wrote an AGENTS.md backup" || true
ls "$PROJECT"/CLAUDE.md.pre-refresh-* >/dev/null 2>&1 && fail "F2: no-op refresh wrote a CLAUDE.md backup" || true
[ "$(sha_cmd "$PROJECT/AGENTS.md")" = "$AGENTS_GOOD" ] \
  || fail "F2: no-op refresh changed AGENTS.md bytes (should be byte-identical to the clean block)"
pass "F2: --refresh-overlays on a current block is a no-op (byte-identical; BEGIN/END balanced at 1)"

# (2) drift AGENTS.md, refresh -> restored to one balanced block, drift removed.
printf '\nDRIFTED-FLOW-BLOCK-EXTRA-LINE\n' >> "$PROJECT/AGENTS.md"
(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.refresh2"
)
[ "$(count_marker "$PROJECT/AGENTS.md" "$MB")" -eq 1 ] \
  || fail "F2: after refreshing a DRIFTED AGENTS.md, BEGIN count is $(count_marker "$PROJECT/AGENTS.md" "$MB") (expected 1)"
[ "$(count_marker "$PROJECT/AGENTS.md" "$ME")" -eq 1 ] \
  || fail "F2: after refreshing a DRIFTED AGENTS.md, END count is $(count_marker "$PROJECT/AGENTS.md" "$ME") (expected 1)"
grep -q "DRIFTED-FLOW-BLOCK-EXTRA-LINE" "$PROJECT/AGENTS.md" && fail "F2: drift survived the refresh (block not replaced)" || true
ls "$PROJECT"/AGENTS.md.pre-refresh-* >/dev/null 2>&1 || fail "F2: refresh of a drifted block wrote no backup"
grep -q "CURRENT CLI AGENTS SENTINEL" "$PROJECT/AGENTS.md" || fail "F2: refresh dropped the CLI-owned AGENTS baseline"
[ "$(sha_cmd "$PROJECT/AGENTS.md")" = "$AGENTS_GOOD" ] \
  || fail "F2: drift refresh did not converge byte-exactly to the clean block (trailing-blank-before-BEGIN regression?)"
pass "F2: --refresh-overlays restores a drifted block byte-exactly (== clean block; single balanced BEGIN/END; CLI baseline kept)"

# (3) refresh again -> idempotent no-op.
rm -f "$PROJECT"/AGENTS.md.pre-refresh-*
(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.refresh3"
)
[ "$(count_marker "$PROJECT/AGENTS.md" "$MB")" -eq 1 ] \
  || fail "F2: second refresh changed BEGIN count (not idempotent)"
ls "$PROJECT"/AGENTS.md.pre-refresh-* >/dev/null 2>&1 && fail "F2: second refresh of a now-current block wrote a backup (not idempotent)" || true
pass "F2: --refresh-overlays is idempotent (re-run on a current block does nothing)"

###############################################################################
# U1 — overlay refresh PRESERVES operator-customized FLOW:PRESERVE region.
# Customize the project-values (operator data), then drift the framework prose
# inside the block, then refresh. The operator's value must survive AND the
# framework prose must update. (Regression guard for the data-loss bug.)
###############################################################################
grep -q "<!-- FLOW:PRESERVE:BEGIN" "$PROJECT/AGENTS.md" || fail "U1 precondition: AGENTS.md block lacks FLOW:PRESERVE markers"
# operator fills a project value inside the preserve region (robust to placeholder wording)
sed -i -E 's/\| Project name \| [^|]*\|/| Project name | WORKHUB-MANAGED |/' "$PROJECT/AGENTS.md"
grep -q "WORKHUB-MANAGED" "$PROJECT/AGENTS.md" || fail "U1 setup: could not set the operator project value"
# drift the framework prose inside the block (a line OUTSIDE the preserve region)
sed -i 's/workflow lifecycle overlay/workflow lifecycle overlay (DRIFTED-FRAMEWORK-PROSE)/' "$PROJECT/AGENTS.md"
rm -f "$PROJECT"/AGENTS.md.pre-refresh-*
(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.u1"
)
grep -q "WORKHUB-MANAGED" "$PROJECT/AGENTS.md" || fail "U1: refresh WIPED the operator's project value (data loss!)"
grep -q "DRIFTED-FRAMEWORK-PROSE" "$PROJECT/AGENTS.md" && fail "U1: framework prose drift survived the refresh (block not refreshed)" || true
[ "$(count_marker "$PROJECT/AGENTS.md" "$MB")" -eq 1 ] || fail "U1: BEGIN count not 1 after preserve-carry refresh"
pass "U1: refresh preserves operator FLOW:PRESERVE values while refreshing framework prose"

###############################################################################
# U7 — legacy marker-less CLAUDE.md migrates to ONE '---' before the heading.
###############################################################################
LEGACY="$TMP_BASE/legacy-claude"
mkdir -p "$LEGACY/hooks/local" "$LEGACY/.claude/skills" "$LEGACY/.agents/skills" "$LEGACY/.claude/agents" "$LEGACY/.codex/agents" "$LEGACY/.claude/commands"
cp -R flow-skills "$LEGACY/flow-skills"; cp -R agents "$LEGACY/agents"
cp hooks/local/mirror-skills.sh hooks/local/mirror-agents.sh hooks/local/post-fusebase-update.sh "$LEGACY/hooks/local/"
cp -R hooks/local/fusebase-flow-overlays "$LEGACY/hooks/local/fusebase-flow-overlays"
cat > "$LEGACY/AGENTS.md" <<'EOF'
# Legacy project
EOF
# A pre-3.6.0 marker-LESS CLAUDE.md overlay block: a bare '---' then the heading,
# no CUSTOM:SKILL markers (the old append format).
cat > "$LEGACY/CLAUDE.md" <<'EOF'
# Legacy CLAUDE

project rules here

---

## Fusebase Flow — additional rules (overlay)

old stale body
EOF
set +e
(
  cd "$LEGACY"
  bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$TMP_BASE/u7.out" 2>&1
)
set -e
# After migration: exactly one CUSTOM:SKILL:BEGIN, and exactly one '---' on the
# lines between the project content and the heading (the template's own rule).
[ "$(count_marker "$LEGACY/CLAUDE.md" "$MB")" -eq 1 ] || fail "U7: legacy migration did not produce exactly 1 BEGIN ($(count_marker "$LEGACY/CLAUDE.md" "$MB"))"
RULES_BEFORE_HEADING="$(awk '/^## Fusebase Flow — additional rules/{exit} /^[[:space:]]*---[[:space:]]*$/{c++} END{print c+0}' "$LEGACY/CLAUDE.md")"
[ "$RULES_BEFORE_HEADING" -le 1 ] || fail "U7: $RULES_BEFORE_HEADING '---' rules before the heading (expected <=1; doubled-rule regression)"
pass "U7: legacy marker-less CLAUDE.md migrates to a single wrapped block (no doubled ---)"

###############################################################################
# U9 — first preserve-aware upgrade is LOSSLESS for a pre-markers block.
# Simulate a 3.7.0-era AGENTS.md: a CUSTOM:SKILL-wrapped block WITH the
# ### Project-specific values table but WITHOUT FLOW:PRESERVE markers, and a
# customized value. A refresh against the 3.8.0 template must SEED the new
# preserve region from that legacy table (value survives) AND add the markers.
###############################################################################
U9P="$TMP_BASE/u9-preupgrade"
mkdir -p "$U9P/hooks/local" "$U9P/.claude/skills" "$U9P/.agents/skills" "$U9P/.claude/agents" "$U9P/.codex/agents" "$U9P/.claude/commands"
cp -R flow-skills "$U9P/flow-skills"; cp -R agents "$U9P/agents"
cp hooks/local/mirror-skills.sh hooks/local/mirror-agents.sh hooks/local/post-fusebase-update.sh "$U9P/hooks/local/"
cp -R hooks/local/fusebase-flow-overlays "$U9P/hooks/local/fusebase-flow-overlays"
cat > "$U9P/CLAUDE.md" <<'EOF'
# pre-upgrade CLAUDE
EOF
# Build a marker-less (pre-3.8.0) block from the current AGENTS overlay template:
# strip the FLOW:PRESERVE marker lines and customize a project value.
{
  printf '# pre-upgrade AGENTS\n\nCURRENT CLI AGENTS SENTINEL\n'
  sed -E -e '/<!-- FLOW:PRESERVE:BEGIN/d' -e '/<!-- FLOW:PRESERVE:END -->/d' \
      -e 's/\| Project name \| [^|]*\|/| Project name | SEEDED-FROM-LEGACY |/' \
      hooks/local/fusebase-flow-overlays/agents-md-overlay.md
} > "$U9P/AGENTS.md"
# Precondition: CUSTOM:SKILL present, FLOW:PRESERVE absent, value set.
[ "$(count_marker "$U9P/AGENTS.md" "$MB")" -eq 1 ] || fail "U9 precondition: expected 1 CUSTOM:SKILL:BEGIN"
grep -q "<!-- FLOW:PRESERVE:BEGIN" "$U9P/AGENTS.md" && fail "U9 precondition: pre-upgrade block should have NO FLOW:PRESERVE markers" || true
grep -q "SEEDED-FROM-LEGACY" "$U9P/AGENTS.md" || fail "U9 setup: could not set the legacy project value"
(
  cd "$U9P"
  bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$TMP_BASE/u9.out" 2>&1
)
grep -q "SEEDED-FROM-LEGACY" "$U9P/AGENTS.md" || fail "U9: first preserve-aware upgrade RESET the legacy project value (lossy transition!)"
grep -q "<!-- FLOW:PRESERVE:BEGIN" "$U9P/AGENTS.md" || fail "U9: refresh did not add FLOW:PRESERVE markers (no migration)"
[ "$(count_marker "$U9P/AGENTS.md" "$MB")" -eq 1 ] || fail "U9: BEGIN count not 1 after legacy seed"
pass "U9: first preserve-aware upgrade seeds the new FLOW:PRESERVE region from the legacy table (lossless)"

# --- AC4: explicit known_names, no app-*.md glob ---
# The two known CLI app-agents must be attributed cli-owned by name on the
# AUTHORITATIVE surface (.claude/agents). (.codex/agents is a non-authoritative
# mirror as of Issue 2 — reported as a benign summary, not per-agent.)
(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/conflict.json"
)
"$python_bin" - "$TMP_BASE/conflict.json" <<'PY' || fail "known_names CLI app-agents not attributed cli-owned"
import json, sys
data = json.loads(open(sys.argv[1], encoding="utf-8").read())
findings = data["findings"]
def owned(path):
    return [f for f in findings if f["path"] == path and f["layer"] == "cli"]
for name in ("app-architect", "app-create-checker"):
    p = f".claude/agents/{name}.md"
    if not owned(p):
        print(f"missing cli-owned finding for {p}", file=sys.stderr)
        sys.exit(1)
PY
pass "CLI app-agents attributed cli-owned by explicit known_names (authoritative .claude/agents)"

# A non-listed app-*.md agent must NOT be scooped up as cli-owned (no glob).
# Drop a synthetic app-foo.md into the CLI agent dirs that is absent from
# known_names; the reporter must not attribute it to the CLI layer.
echo "SYNTHETIC FLOW-NAMED AGENT app-foo" > "$PROJECT/.claude/agents/app-foo.md"
echo "SYNTHETIC FLOW-NAMED AGENT app-foo" > "$PROJECT/.codex/agents/app-foo.md"
(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/conflict2.json"
)
"$python_bin" - "$TMP_BASE/conflict2.json" <<'PY' || fail "synthetic app-foo.md was misattributed cli-owned (glob still active)"
import json, sys
data = json.loads(open(sys.argv[1], encoding="utf-8").read())
findings = data["findings"]
bad = [
    f for f in findings
    if f["layer"] == "cli" and f["path"].endswith("app-foo.md")
]
if bad:
    print(f"app-foo.md wrongly attributed cli-owned: {bad}", file=sys.stderr)
    sys.exit(1)
PY
rm -f "$PROJECT/.claude/agents/app-foo.md" "$PROJECT/.codex/agents/app-foo.md"
pass "non-listed app-foo.md agent not misattributed cli-owned (glob retired)"

# --- B3 / AC2 + AC3: provenance drift advisory + CUSTOM:SKILL scan ---
# Stamp provenance over the simulated CLI assets, then prove:
#   (1) clean state -> 0 advisories, verdict HEALTHY;
#   (2) a mutated present CLI skill -> CLI_SNAPSHOT_STALE advisory, still
#       HEALTHY + exit 0 (advisory must NOT flip the verdict/exit code);
#   (3) a CUSTOM:SKILL block in a CLI skill -> CLI_CUSTOM_AT_RISK advisory.
(
  cd "$PROJECT"
  bash hooks/local/stamp-cli-provenance.sh > "$TMP_BASE/stamp.out"
)
test -f "$PROJECT/audit/cli-vendor-manifest.json" || fail "provenance manifest not generated"

# (1) clean: 0 advisories, HEALTHY, exit 0.
set +e
(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/prov-clean.json"
)
PROV_CLEAN_RC=$?
set -e
[ "$PROV_CLEAN_RC" -eq 0 ] || fail "clean provenance reporter should exit 0, got $PROV_CLEAN_RC"
"$python_bin" - "$TMP_BASE/prov-clean.json" <<'PY' || fail "clean provenance state should report 0 advisories and HEALTHY"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", d["verdict"]
assert d["summary"]["cli_snapshot_stale"] == 0, d["summary"]
assert d["summary"]["cli_custom_at_risk"] == 0, d["summary"]
PY
pass "provenance stamped; clean state has 0 advisories and HEALTHY verdict"

# (2) mutate a present CLI skill -> CLI_SNAPSHOT_STALE, still HEALTHY + exit 0.
printf '\nLOCAL EDIT THAT DIFFERS FROM BUNDLED SNAPSHOT\n' >> "$PROJECT/.claude/skills/fusebase-cli/SKILL.md"
set +e
(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/prov-stale.json"
)
PROV_STALE_RC=$?
set -e
[ "$PROV_STALE_RC" -eq 0 ] || fail "CLI_SNAPSHOT_STALE is advisory; reporter must still exit 0, got $PROV_STALE_RC"
"$python_bin" - "$TMP_BASE/prov-stale.json" <<'PY' || fail "mutated CLI skill should produce CLI_SNAPSHOT_STALE advisory while staying HEALTHY"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", f"advisory stale must not flip verdict: {d['verdict']}"
assert d["summary"]["cli_snapshot_stale"] >= 1, d["summary"]
stale = [f for f in d["findings"] if f["status"] == "CLI_SNAPSHOT_STALE" and f["path"].endswith("fusebase-cli/SKILL.md")]
assert stale, "expected CLI_SNAPSHOT_STALE for the mutated skill"
PY
pass "mutated CLI skill -> CLI_SNAPSHOT_STALE advisory (non-failing, verdict stays HEALTHY)"

# (3) inject a CUSTOM:SKILL block -> CLI_CUSTOM_AT_RISK advisory. Inject on the
# AUTHORITATIVE surface (.claude/skills) — that's the one the CLI refreshes, so it's
# where a CUSTOM block is genuinely at risk (Issue 2: .agents is not CLI-touched).
printf '\n<!-- CUSTOM:SKILL:BEGIN -->\nuser customization\n<!-- CUSTOM:SKILL:END -->\n' >> "$PROJECT/.claude/skills/app-backend/SKILL.md"
set +e
(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/prov-custom.json"
)
PROV_CUSTOM_RC=$?
set -e
[ "$PROV_CUSTOM_RC" -eq 0 ] || fail "CLI_CUSTOM_AT_RISK is advisory; reporter must still exit 0, got $PROV_CUSTOM_RC"
"$python_bin" - "$TMP_BASE/prov-custom.json" <<'PY' || fail "CUSTOM:SKILL block should be reported at-risk"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "HEALTHY", f"advisory custom must not flip verdict: {d['verdict']}"
assert d["summary"]["cli_custom_at_risk"] >= 1, d["summary"]
risk = [f for f in d["findings"] if f["status"] == "CLI_CUSTOM_AT_RISK" and f["path"].endswith("app-backend/SKILL.md")]
assert risk, "expected CLI_CUSTOM_AT_RISK for the skill carrying a CUSTOM:SKILL block"
PY
pass "CUSTOM:SKILL block -> CLI_CUSTOM_AT_RISK advisory (at-risk on next refresh)"

# (4) a MISSING CLI skill still escalates to CLI_LAYER_DRIFT (exit 1) — the
#     advisory work must not weaken the missing-asset semantics.
rm -f "$PROJECT/.claude/skills/fusebase-cli/SKILL.md"
set +e
(
  cd "$PROJECT"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/prov-missing.json"
)
PROV_MISSING_RC=$?
set -e
[ "$PROV_MISSING_RC" -eq 1 ] || fail "MISSING CLI skill must still exit 1 (CLI_LAYER_DRIFT), got $PROV_MISSING_RC"
"$python_bin" - "$TMP_BASE/prov-missing.json" <<'PY' || fail "MISSING CLI skill should still be CLI_LAYER_DRIFT"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] == "CLI_LAYER_DRIFT", d["verdict"]
PY
pass "MISSING CLI skill still escalates to CLI_LAYER_DRIFT (missing-vs-stale semantics intact)"

BAD_PROJECT="$TMP_BASE/bad-settings"
mkdir -p "$BAD_PROJECT/hooks/local" "$BAD_PROJECT/.claude" "$BAD_PROJECT/.claude/skills" "$BAD_PROJECT/.agents/skills" "$BAD_PROJECT/.claude/agents" "$BAD_PROJECT/.codex/agents" "$BAD_PROJECT/.claude/commands"
cp -R flow-skills "$BAD_PROJECT/flow-skills"
cp -R agents "$BAD_PROJECT/agents"
cp hooks/local/mirror-skills.sh "$BAD_PROJECT/hooks/local/"
cp hooks/local/mirror-agents.sh "$BAD_PROJECT/hooks/local/"
cp hooks/local/post-fusebase-update.sh "$BAD_PROJECT/hooks/local/"
cp -R hooks/local/fusebase-flow-overlays "$BAD_PROJECT/hooks/local/fusebase-flow-overlays"

cat > "$BAD_PROJECT/AGENTS.md" <<'EOF'
# FuseBase CLI project
EOF
cat > "$BAD_PROJECT/CLAUDE.md" <<'EOF'
# FuseBase CLI Claude instructions
EOF
cat > "$BAD_PROJECT/.claude/settings.json" <<'EOF'
{ invalid json
EOF

# F3: the merge path is opt-in — exercise it with --wire-hooks so the invalid-JSON
# handling (warn, restore, exit 1, no backup left) is actually tested.
set +e
(
  cd "$BAD_PROJECT"
  bash hooks/local/post-fusebase-update.sh --wire-hooks > "$TMP_BASE/bad-settings.out" 2>&1
)
BAD_RC=$?
set -e

[ "$BAD_RC" -eq 1 ] || fail "invalid settings recovery should return 1, got $BAD_RC"
grep -q "\[post-fusebase-update\] Summary" "$TMP_BASE/bad-settings.out" || fail "invalid settings recovery did not print summary"
[ ! -f "$BAD_PROJECT/.claude/settings.json.pre-flow-merge" ] || fail "invalid settings recovery left backup behind"
grep -q "{ invalid json" "$BAD_PROJECT/.claude/settings.json" || fail "invalid settings recovery did not restore original settings"

pass "invalid settings merge (--wire-hooks) reports warning and cleans backup"

###############################################################################
# F4 — single-provider benign absence.
# A Claude-only / Flow-only project that NEVER installed the CLI provider skills
# (0 of N present) must NOT be flagged CLI_LAYER_DRIFT. The reporter emits one
# benign INFO instead of per-skill MISSING. Partial install stays drift (already
# covered by case (4) above, which removes one of 19 and expects CLI_LAYER_DRIFT).
#
# Built from a clean copy of the recovered HEALTHY project, then the entire CLI
# provider surface is removed — so only the absent-CLI-surface variable changes;
# every required Flow path stays present.
###############################################################################

CLAUDE_ONLY="$TMP_BASE/claude-only"
cp -R "$PROJECT" "$CLAUDE_ONLY"
# Remove ALL known CLI provider skills + app-agents (simulate never-installed).
for name in "${providers[@]}"; do
  rm -rf "$CLAUDE_ONLY/.claude/skills/$name" "$CLAUDE_ONLY/.agents/skills/$name"
done
rm -f "$CLAUDE_ONLY/.claude/agents/app-architect.md" "$CLAUDE_ONLY/.claude/agents/app-create-checker.md" \
      "$CLAUDE_ONLY/.codex/agents/app-architect.md" "$CLAUDE_ONLY/.codex/agents/app-create-checker.md"
# .claude/skills + .claude/agents dirs still exist (Flow mirrors remain), but
# contain 0 of the known CLI provider skills/agents.
set +e
(
  cd "$CLAUDE_ONLY"
  bash hooks/local/check-cli-flow-conflicts.sh --json > "$TMP_BASE/claude-only.json"
)
CLAUDE_ONLY_RC=$?
set -e
[ "$CLAUDE_ONLY_RC" -ne 1 ] || {
  cat "$TMP_BASE/claude-only.json" >&2
  fail "F4: 0-present CLI provider surface wrongly escalated to CLI_LAYER_DRIFT (exit 1)"
}
"$python_bin" - "$TMP_BASE/claude-only.json" <<'PY' || fail "F4: 0-present provider surface should be benign (INFO, not CLI_LAYER_DRIFT)"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert d["verdict"] != "CLI_LAYER_DRIFT", f"0-present must not be CLI_LAYER_DRIFT, got {d['verdict']}"
# No per-skill MISSING for the never-installed provider surface.
missing = [f for f in d["findings"] if f["status"] == "MISSING" and f["layer"] == "cli"]
assert not missing, f"0-present provider surface produced per-item MISSING: {missing}"
# A benign INFO names the not-installed case (message lives in action/detail).
def text(f): return (f.get("action", "") + " " + f.get("detail", "")).lower()
info = [f for f in d["findings"] if f["status"] == "INFO" and "not installed" in text(f)]
assert info, "expected a benign INFO about provider skills not being installed"
PY
pass "F4: 0-present CLI provider surface is benign (single INFO, never CLI_LAYER_DRIFT)"

###############################################################################
# U20 (v3.9.0) — REAL upgrade.sh migration: a pre-3.9.0 install on root skills/
# upgrades against a source shipping flow-skills/. After the run the canonical
# must live at flow-skills/, root skills/ must be retired (with a backup), and
# the provider mirrors must be regenerated. This exercises the actual migration
# code path (step 1b), not a re-implementation.
###############################################################################
U20P="$TMP_BASE/u20-migration"
cp -R "$PROJECT" "$U20P"
# Make it look pre-3.9.0: canonical at root skills/, no flow-skills/ yet.
mv "$U20P/flow-skills" "$U20P/skills"
# The engine scripts the migration needs (PROJECT fixture lacks upgrade.sh).
cp hooks/local/upgrade.sh "$U20P/hooks/local/"
cp hooks/local/sync-version-strings.sh "$U20P/hooks/local/" 2>/dev/null || true
# Stage a minimal upstream source shipping the NEW layout (flow-skills/ + VERSION).
mkdir -p "$U20P/.fusebase-flow-source"
cp -R flow-skills "$U20P/.fusebase-flow-source/flow-skills"
cp VERSION "$U20P/.fusebase-flow-source/VERSION"
set +e
(
  cd "$U20P"
  bash hooks/local/upgrade.sh --auto-yes > "$TMP_BASE/u20.out" 2>&1
)
U20_RC=$?
set -e
[ "$U20_RC" -eq 0 ] || { cat "$TMP_BASE/u20.out" >&2; fail "U20: upgrade.sh exited $U20_RC during migration"; }
[ -f "$U20P/flow-skills/communication/SKILL.md" ] || fail "U20: canonical flow-skills/ not present after migration"
[ ! -d "$U20P/skills" ] || fail "U20: legacy root skills/ was NOT retired by the migration"
ls -d "$U20P"/skills.pre-upgrade-* >/dev/null 2>&1 || fail "U20: migration did not back up the retired skills/ (skills.pre-upgrade-*)"
[ -f "$U20P/.claude/skills/communication/SKILL.md" ] || fail "U20: provider mirror not regenerated from flow-skills/ after migration"
grep -q "retired legacy root skills/" "$TMP_BASE/u20.out" || fail "U20: upgrade.sh did not report the canonical migration"
# Idempotency: a second run is a no-op for migration (no skills/ to retire).
set +e
( cd "$U20P"; bash hooks/local/upgrade.sh --auto-yes > "$TMP_BASE/u20b.out" 2>&1 )
set -e
[ ! -d "$U20P/skills" ] || fail "U20: second upgrade run re-created root skills/"
pass "U20: upgrade.sh migrates root skills/ -> flow-skills/ (retires old dir w/ backup, re-mirrors, idempotent)"
