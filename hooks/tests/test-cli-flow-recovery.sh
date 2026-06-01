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

cp -R skills "$PROJECT/skills"
cp -R agents "$PROJECT/agents"
mkdir -p "$PROJECT/hooks/local"
cp hooks/local/mirror-skills.sh "$PROJECT/hooks/local/"
cp hooks/local/mirror-agents.sh "$PROJECT/hooks/local/"
cp hooks/local/post-fusebase-update.sh "$PROJECT/hooks/local/"
cp hooks/local/check-cli-flow-conflicts.sh "$PROJECT/hooks/local/"
cp hooks/local/stamp-cli-provenance.sh "$PROJECT/hooks/local/"
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

# --- AC4: explicit known_names, no app-*.md glob ---
# The two known CLI app-agents must be attributed cli-owned by name.
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
    for root in (".claude/agents", ".codex/agents"):
        p = f"{root}/{name}.md"
        if not owned(p):
            print(f"missing cli-owned finding for {p}", file=sys.stderr)
            sys.exit(1)
PY
pass "CLI app-agents attributed cli-owned by explicit known_names"

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

# (3) inject a CUSTOM:SKILL block -> CLI_CUSTOM_AT_RISK advisory.
printf '\n<!-- CUSTOM:SKILL:BEGIN -->\nuser customization\n<!-- CUSTOM:SKILL:END -->\n' >> "$PROJECT/.agents/skills/app-backend/SKILL.md"
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
cp -R skills "$BAD_PROJECT/skills"
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
