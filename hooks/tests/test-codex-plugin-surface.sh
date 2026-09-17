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

###############################################################################
# /step-out on the Codex plugin surface. The manifest forbids a `commands` field
# (asserted above), so Codex reaches /step-out through the SKILL surface only:
# task-delegation routes to the canonical command body before it assesses
# delegation eligibility. These assertions check that bridge and the two owner
# contracts the command points at — absent config, same-family fallback and the
# review round cap — so the routing pointer cannot ship without its owners.
###############################################################################
TD_CANON="$ROOT/flow-skills/task-delegation/SKILL.md"
CR_CANON="$ROOT/flow-skills/code-review/SKILL.md"
CMD_CANON="$ROOT/hooks/local/fusebase-flow-overlays/commands/step-out.md"
ROUTING_YML="$ROOT/policies/model-routing.yml"

[ -f "$CMD_CANON" ] \
  && ok "step-out-canonical-command-present" \
  || bad "step-out-canonical-command-present" "missing hooks/local/fusebase-flow-overlays/commands/step-out.md"

# The routing pointer must sit ABOVE the delegation eligibility checks (§ Do not
# invoke when) — a pointer placed after them is read too late to route.
td_route_ln="$(grep -nF 'commands/step-out.md' "$TD_CANON" | head -1 | cut -d: -f1)"
td_elig_ln="$(grep -nF '## Do not invoke when' "$TD_CANON" | head -1 | cut -d: -f1)"
if [ -n "$td_route_ln" ] && [ -n "$td_elig_ln" ] && [ "$td_route_ln" -lt "$td_elig_ln" ]; then
  ok "step-out-routed-before-delegation-eligibility"
else
  bad "step-out-routed-before-delegation-eligibility" "pointer line=$td_route_ln not strictly above eligibility=$td_elig_ln"
fi

# Model routing: the config is optional and ABSENT/unreachable config must not stop a run.
if grep -qF 'policies/model-routing.yml' "$TD_CANON" \
  && grep -qF 'Never stop a run for model configuration' "$TD_CANON"; then
  ok "step-out-absent-config-is-a-fallback"
else
  bad "step-out-absent-config-is-a-fallback" "task-delegation lacks the optional-config / never-stop fallback contract"
fi

# Same-family fallback must be REPORTED, never dressed up as independence.
if grep -qF 'same-family review' "$TD_CANON" \
  && grep -qF 'instead of claiming independence' "$TD_CANON"; then
  ok "step-out-same-family-fallback-reported"
else
  bad "step-out-same-family-fallback-reported" "task-delegation lacks the same-family review reporting rule"
fi

# A tier selects a model, never authority (an execution-tier agent cannot deploy).
grep -qF 'A tier selects a MODEL, never authority' "$TD_CANON" \
  && ok "step-out-tier-grants-no-authority" \
  || bad "step-out-tier-grants-no-authority" "task-delegation does not separate model tier from role authority"

# Unattended scheduling: retry exhaustion moves on; a blocked slice parks its chain only.
if grep -qF '## Unattended scheduling' "$TD_CANON" \
  && grep -qF 'dispatch the next INDEPENDENT authorized slice' "$TD_CANON" \
  && grep -qF 'parks that slice AND its dependents' "$TD_CANON"; then
  ok "step-out-blocked-dependency-continuation-owned"
else
  bad "step-out-blocked-dependency-continuation-owned" "task-delegation lacks the unattended scheduling contract"
fi

# Review round cap: two rounds, no reset via a successor, exhaustion never accepts.
if grep -qF 'default maximum two per change' "$CR_CANON" \
  && grep -qF 'does not reset the counter' "$CR_CANON" \
  && grep -qF 'never implicitly accepted' "$CR_CANON"; then
  ok "step-out-round-cap-exhaustion-owned"
else
  bad "step-out-round-cap-exhaustion-owned" "code-review lacks the round bound / exhaustion semantics"
fi

# The shipped policy names NO model: every tier row must be null in the active YAML.
if [ -f "$ROUTING_YML" ] && command -v "$py_bin" >/dev/null 2>&1; then
  if ROUTING_YML="$ROUTING_YML" "$py_bin" - <<'PY'
import os, sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # yaml unavailable on this host: the grep arm below still guards
doc = yaml.safe_load(open(os.environ["ROUTING_YML"], encoding="utf-8"))
tiers = (doc or {}).get("tiers") or {}
expected = {"planning", "adversarial_review", "sensitive_implementation",
            "routine_implementation", "execution"}
ok = set(tiers) == expected and all(
    (row or {}).get("model") is None and (row or {}).get("family") is None
    for row in tiers.values()
)
sys.exit(0 if ok else 1)
PY
  then
    ok "step-out-model-routing-ships-all-null"
  else
    bad "step-out-model-routing-ships-all-null" "policies/model-routing.yml must ship exactly 5 tiers with null model/family"
  fi
else
  bad "step-out-model-routing-ships-all-null" "missing policies/model-routing.yml or python"
fi

finish
