#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLUGIN="$ROOT/.codex-plugin/plugin.json"
CANON="$ROOT/flow-skills/product-owner/SKILL.md"
AGENTS_MIRROR="$ROOT/.agents/skills/product-owner/SKILL.md"
CLAUDE_MIRROR="$ROOT/.claude/skills/product-owner/SKILL.md"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: codex-plugin $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: codex-plugin $1 ($2)"; }
finish() { echo "[test-codex-plugin-surface] $pass/$((pass + fail)) PASS"; exit "$fail"; }

py_bin="${PYTHON:-python3}"
command -v "$py_bin" >/dev/null 2>&1 || py_bin="python"

[ -f "$PLUGIN" ] && ok "manifest-present" || { bad "manifest-present" "missing .codex-plugin/plugin.json"; finish; }
[ -f "$CANON" ] && ok "product-owner-canonical-skill-present" || { bad "product-owner-canonical-skill-present" "missing flow-skills/product-owner/SKILL.md"; finish; }

if command -v "$py_bin" >/dev/null 2>&1; then
  if PLUGIN="$PLUGIN" VERSION_FILE="$ROOT/VERSION" "$py_bin" - <<'PY'
import json
import os
import sys

plugin = json.load(open(os.environ["PLUGIN"], encoding="utf-8"))
version = open(os.environ["VERSION_FILE"], encoding="utf-8").read().strip()
checks = [
    plugin.get("name") == "fusebase-flow",
    plugin.get("version") == version,
    plugin.get("skills") == "./.agents/skills/",
    plugin.get("interface", {}).get("displayName") == "Flow",
    "commands" not in plugin,
    "agents" not in plugin,
    "apps" not in plugin,
    "mcpServers" not in plugin,
]
sys.exit(0 if all(checks) else 1)
PY
  then
    ok "manifest-shape"
  else
    bad "manifest-shape" "expected name/version/skills/interface fields not found or unsupported fields present"
  fi
else
  bad "manifest-shape" "python not found"
fi

for skill in product-owner product-docs-first product-apps-decomposition; do
  [ -f "$ROOT/flow-skills/$skill/SKILL.md" ] \
    && ok "canonical-$skill-present" \
    || bad "canonical-$skill-present" "missing flow-skills/$skill/SKILL.md"
done

[ -f "$AGENTS_MIRROR" ] \
  && ok "agents-product-owner-mirror-present" \
  || bad "agents-product-owner-mirror-present" "run mirror-skills.sh"
[ -f "$CLAUDE_MIRROR" ] \
  && ok "claude-product-owner-mirror-present" \
  || bad "claude-product-owner-mirror-present" "run mirror-skills.sh"

if grep -qF 'name: product-owner' "$CANON" \
  && grep -qF '/product-owner' "$CANON" \
  && grep -qi 'Product Owner' "$CANON" \
  && grep -qi 'activate' "$CANON" \
  && grep -qF '.codex/agents/product-owner.md' "$CANON"; then
  ok "product-owner-trigger-rich"
else
  bad "product-owner-trigger-rich" "frontmatter/body missing Product Owner activation keywords or Codex agent pointer"
fi

if [ -f "$AGENTS_MIRROR" ] && cmp -s "$CANON" "$AGENTS_MIRROR" \
  && [ -f "$CLAUDE_MIRROR" ] && cmp -s "$CANON" "$CLAUDE_MIRROR"; then
  ok "product-owner-mirrors-byte-identical"
else
  bad "product-owner-mirrors-byte-identical" "mirrors are missing or drift from canonical"
fi

finish
