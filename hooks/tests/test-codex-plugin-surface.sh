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
  && grep -qF 'INHERITS the count' "$CR_CANON" \
  && grep -qF 'does not reset it' "$CR_CANON" \
  && grep -qF 'never implicitly accepted' "$CR_CANON"; then
  ok "step-out-round-cap-exhaustion-owned"
else
  bad "step-out-round-cap-exhaustion-owned" "code-review lacks the round bound / successor-inheritance / exhaustion semantics"
fi

# A bound that is only asserted is not enforceable: the owner must require a DURABLE
# count in an artifact the work already owns, read BEFORE each dispatch, extendable
# only by explicit operator authorization. Without these the cap is chat-only.
cap_missing=""
for phrase in "checked BEFORE dispatch" "Never a new file" "Read it before launching any review round" \
              "rounds dispatched" "explicit operator authorization" "raises the limit"; do
  grep -qF "$phrase" "$CR_CANON" || cap_missing="$cap_missing|$phrase"
done
[ -z "$cap_missing" ] \
  && ok "step-out-round-cap-durably-recorded" \
  || bad "step-out-round-cap-durably-recorded" "code-review round accounting missing:$cap_missing"

# The shipped policy names NO model: every tier row must be null in the ACTIVE YAML.
# TRIPWIRE: never exit 0 on a missing dependency. An absent PyYAML must fall back to the
# stdlib parse below, and an unparseable file must report UNAVAILABLE — a check that
# reports PASS when it did not run is worse than an absent check.
# rc 0 = validated all-null · 1 = validation FAILED · 3 = could not validate.
if [ -f "$ROUTING_YML" ] && command -v "$py_bin" >/dev/null 2>&1; then
  ROUTING_YML="$ROUTING_YML" "$py_bin" - <<'PY'
import os, re, sys

text = open(os.environ["ROUTING_YML"], encoding="utf-8").read()
EXPECTED = {"planning", "adversarial_review", "sensitive_implementation",
            "routine_implementation", "execution"}

def check(tiers):
    return set(tiers) == EXPECTED and all(
        (row or {}).get("model") is None and (row or {}).get("family") is None
        for row in tiers.values()
    )

try:
    import yaml
except ImportError:
    yaml = None

if yaml is not None:
    try:
        doc = yaml.safe_load(text)
    except Exception as exc:                       # malformed YAML is a real failure
        print(f"unparseable: {exc}", file=sys.stderr)
        sys.exit(1)
    sys.exit(0 if check((doc or {}).get("tiers") or {}) else 1)

# Stdlib fallback — no PyYAML on this host. Parse the `tiers:` block line by line and
# accept ONLY the shipped shape; anything else (block style, a filled-in selector, an
# extra or missing tier) is reported rather than waved through.
block = re.search(r"^tiers:\s*$(.*?)(?=^\S|\Z)", text, re.M | re.S)
if not block:
    print("no `tiers:` block found", file=sys.stderr)
    sys.exit(3)
row_re = re.compile(r"^  ([A-Za-z_][A-Za-z0-9_]*):\s*\{\s*model:\s*null\s*,\s*family:\s*null\s*\}\s*$")
found, stray = {}, []
for line in block.group(1).splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    m = row_re.match(line)
    if m:
        found[m.group(1)] = {"model": None, "family": None}
    else:
        stray.append(line.rstrip())
if stray:
    print(f"non-null or unrecognized tier line(s): {stray}", file=sys.stderr)
    sys.exit(1)
sys.exit(0 if check(found) else 1)
PY
  ROUTING_RC=$?
  case "$ROUTING_RC" in
    0) ok "step-out-model-routing-ships-all-null" ;;
    3) bad "step-out-model-routing-ships-all-null" "UNAVAILABLE — could not validate policies/model-routing.yml (not a PASS)" ;;
    *) bad "step-out-model-routing-ships-all-null" "policies/model-routing.yml must ship exactly 5 tiers with null model/family (rc=$ROUTING_RC)" ;;
  esac
else
  bad "step-out-model-routing-ships-all-null" "missing policies/model-routing.yml or python"
fi

###############################################################################
# Discovery metadata (Astra F1). The routing pointer at task-delegation:31 is in the
# skill BODY; a host only loads that body if the always-loaded DESCRIPTION matches.
# The description must therefore carry the absence trigger itself, or "I'll be away,
# finish this one ordinary change" never reaches the bridge — and the placement
# assertion above would still pass. Assert canonical AND both mirrors.
###############################################################################
td_desc="$(grep -m1 '^description:' "$TD_CANON")"
desc_missing=""
for phrase in "stepping out" "unattended" "I'll be away" "/step-out" "planning-only/read-only"; do
  printf '%s' "$td_desc" | grep -qF "$phrase" || desc_missing="$desc_missing|$phrase"
done
[ -z "$desc_missing" ] \
  && ok "step-out-absence-trigger-in-discovery-description" \
  || bad "step-out-absence-trigger-in-discovery-description" "task-delegation description missing:$desc_missing"

for m in "$ROOT/.agents/skills/task-delegation/SKILL.md" "$ROOT/.claude/skills/task-delegation/SKILL.md"; do
  if [ -f "$m" ] && cmp -s "$TD_CANON" "$m"; then
    ok "task-delegation-mirror-identical-$(basename "$(dirname "$(dirname "$(dirname "$m")")")")"
  else
    bad "task-delegation-mirror-identical-$(basename "$(dirname "$(dirname "$(dirname "$m")")")")" "mirror missing or drifted — run mirror-skills.sh"
  fi
done

finish
