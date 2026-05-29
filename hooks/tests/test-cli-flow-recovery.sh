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

mkdir -p "$PROJECT"

cp -R skills "$PROJECT/skills"
cp -R agents "$PROJECT/agents"
mkdir -p "$PROJECT/hooks/local"
cp hooks/local/mirror-skills.sh "$PROJECT/hooks/local/"
cp hooks/local/mirror-agents.sh "$PROJECT/hooks/local/"
cp hooks/local/post-fusebase-update.sh "$PROJECT/hooks/local/"
cp hooks/local/check-cli-flow-conflicts.sh "$PROJECT/hooks/local/"
cp -R hooks/local/fusebase-flow-overlays "$PROJECT/hooks/local/fusebase-flow-overlays"
cp -R hooks/handlers "$PROJECT/hooks/handlers"
cp FLOW_RULES.md "$PROJECT/FLOW_RULES.md"

mkdir -p "$PROJECT/.claude/hooks" "$PROJECT/.claude/skills" "$PROJECT/.claude/agents" "$PROJECT/.claude/commands"
mkdir -p "$PROJECT/.agents/skills" "$PROJECT/.codex/agents" "$PROJECT/.codex"

cat > "$PROJECT/AGENTS.md" <<'EOF'
# FuseBase CLI project

CURRENT CLI AGENTS SENTINEL 0.25.5
EOF

cat > "$PROJECT/CLAUDE.md" <<'EOF'
# FuseBase CLI Claude instructions

CURRENT CLI CLAUDE SENTINEL 0.25.5
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
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-lint-on-stop.sh",
            "timeout": 120
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-on-stop.sh",
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

(
  cd "$PROJECT"
  bash hooks/local/post-fusebase-update.sh > "$OUT"
)

grep -q "CURRENT CLI AGENTS SENTINEL" "$PROJECT/AGENTS.md" || fail "CLI AGENTS baseline was lost"
grep -q "Fusebase Flow" "$PROJECT/AGENTS.md" || fail "Flow AGENTS overlay was not restored"
grep -q "CURRENT CLI CLAUDE SENTINEL" "$PROJECT/CLAUDE.md" || fail "CLI CLAUDE baseline was lost"
grep -q "Fusebase Flow" "$PROJECT/CLAUDE.md" || fail "Flow CLAUDE overlay was not restored"

[ "$CODEX_BEFORE" = "$(sha_cmd "$PROJECT/.codex/config.toml")" ] || fail ".codex/config.toml changed"
[ "$HOOK_BEFORE" = "$(sha_cmd "$PROJECT/.claude/hooks/run-typecheck-apps.js")" ] || fail "CLI hook helper changed"
[ "$CLI_SKILL_BEFORE" = "$(sha_cmd "$PROJECT/.claude/skills/fusebase-cli/SKILL.md")" ] || fail "CLI provider skill changed"

grep -q "hooks/handlers/stop.py" "$PROJECT/.claude/settings.json" || fail "Flow stop.py was not merged"
grep -q "run-lint-on-stop.sh" "$PROJECT/.claude/settings.json" || fail "CLI lint Stop hook not preserved"
grep -q "run-typecheck-on-stop.sh" "$PROJECT/.claude/settings.json" || fail "CLI typecheck Stop hook not preserved"
grep -q "quality-check-apps.js" "$PROJECT/.claude/settings.json" || fail "CLI quality Stop hook not preserved"

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
pass "shared settings merge preserved CLI Stop hooks"
pass "Flow skills, agents, overlays, and health command restored"
pass "conflict reporter returned HEALTHY"
