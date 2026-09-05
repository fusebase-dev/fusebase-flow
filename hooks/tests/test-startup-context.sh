#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
EXPECTED_ROWS=170
EXPECTED_SHA="d681165a93385fc4d104636c335edc8c437d505c837a0f20261a8fa41aafb505"
BASELINE_BYTES=145388
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "PASS: startup-context $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: startup-context $1 ($2)"; }
finish() { echo "[test-startup-context] $pass/$((pass + fail)) PASS"; exit "$fail"; }

inventory="$("$ROOT/hooks/local/rule-inventory.sh" --root "$ROOT")"
rows="$(printf '%s\n' "$inventory" | wc -l | tr -d ' ')"
sha="$(printf '%s\n' "$inventory" | sha256sum | awk '{print $1}')"
[ "$rows" = "$EXPECTED_ROWS" ] && [ "$sha" = "$EXPECTED_SHA" ] \
  && ok "semantic-inventory-preserved" \
  || bad "semantic-inventory-preserved" "rows=$rows sha=$sha"

providers=(
  "AGENTS.md"
  "CLAUDE.md"
  "GEMINI.md"
  ".github/copilot-instructions.md"
  ".github/instructions/fusebase-flow.instructions.md"
  ".cursor/rules/fusebase-flow-always.mdc"
  "agents/ai-developer/AGENT.md"
  "agents/product-owner/AGENT.md"
)
required=(
  "AGENTS.md"
  "FLOW_RULES.md"
  "flow-skills/communication/SKILL.md"
  "flow-skills/role-discipline/SKILL.md"
  "references/"
)

for rel in "${providers[@]}"; do
  file="$ROOT/$rel"
  missing=""
  for needle in "${required[@]}"; do
    grep -qF "$needle" "$file" || missing="$missing $needle"
  done
  [ -z "$missing" ] \
    && ok "bootstrap-$rel" \
    || bad "bootstrap-$rel" "missing:$missing"
done

duplicates=0
for rel in "${providers[@]}"; do
  case "$rel" in AGENTS.md) continue ;; esac
  grep -Eq '^## (Operator Relay|Chat-Text Questions|Operator Gate|Forward Momentum) Protocol' "$ROOT/$rel" \
    && duplicates=$((duplicates + 1))
done
[ "$duplicates" -eq 0 ] \
  && ok "provider-protocol-bodies-pointer-only" \
  || bad "provider-protocol-bodies-pointer-only" "$duplicates adapters duplicate resident protocols"

carriers=(
  "AGENTS.md"
  "CLAUDE.md"
  "FLOW_RULES.md"
  "flow-skills/communication/SKILL.md"
  "flow-skills/role-discipline/SKILL.md"
  "flow-skills/role-discipline/references/ai-developer.md"
  "flow-skills/role-discipline/references/product-owner.md"
  "flow-skills/role-discipline/references/architect.md"
  "flow-skills/role-discipline/references/deploy.md"
  "agents/ai-developer/AGENT.md"
  "agents/product-owner/AGENT.md"
  "GEMINI.md"
  ".github/copilot-instructions.md"
  ".github/instructions/fusebase-flow.instructions.md"
  ".cursor/rules/fusebase-flow-always.mdc"
)
current=0
for rel in "${carriers[@]}"; do current=$((current + $(wc -c < "$ROOT/$rel"))); done
[ "$current" -lt "$BASELINE_BYTES" ] \
  && ok "static-carrier-estimate-decreased" \
  || bad "static-carrier-estimate-decreased" "$current >= $BASELINE_BYTES"
echo "INFO: startup-context static-carrier-estimate before=$BASELINE_BYTES after=$current"

for host in Codex Claude Cursor Copilot Gemini; do
  echo "COVERAGE: startup-context host=$host status=UNVERIFIED reason=paired-fresh-session-telemetry-unavailable"
done

finish
