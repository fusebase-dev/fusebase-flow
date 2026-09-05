#!/usr/bin/env bash
# Fusebase Flow — reduced fixture builders for the cli-flow-recovery suite (sourced, never run).
# WHY-home: docs/specs/backlog-triage-execution/architecture-review.md § Q2 + § Q5 (step 4).
#
# TRIPWIRE — the canonical skill set below is SYNTHETIC and picked for LAYOUT coverage
# (SKILL.md-only, plus a nested references/ carrying a .md AND a non-.md asset). It is NOT a
# subset chosen from what the assertions happen to name: that reasoning is circular and this
# repo shipped it once already. Production BREADTH is guarded by a separate full-tree
# `mirror-skills.sh --check` scenario, never by this fixture.
#
# TRIPWIRE — `communication` + `role-discipline` are here ONLY because
# hooks/local/check-cli-flow-conflicts.sh:497 hard-codes those two names as the "Flow mirrors
# still present" marker. Rename them and U12 silently stops exercising FLOW_LAYER_DRIFT.
# Their CONTENT is synthetic; nothing reads it.
#
# TRIPWIRE — every builder writes a FRESH, isolated tree from shell builtins plus a handful of
# BATCHED cp/mkdir calls. On MSYS one process spawn costs ~0.6s, so per-file forks (not bytes)
# are what made the old monolith a 26-minute phase: mirror-skills alone cost ~125s per recovery
# run at 34 canonical skills. Never reintroduce a per-file cp/mkdir loop, and never let one
# scenario mutate another scenario's tree.

# Canonical Flow skill files, relative to <tree>/flow-skills/.
FFCF_SKILL_FILES=(
  communication/SKILL.md
  role-discipline/SKILL.md
  zz-fixture-flat/SKILL.md
  zz-fixture-nested/SKILL.md
  zz-fixture-nested/references/one.md
  zz-fixture-nested/references/two.txt
)
# Canonical skill DIRECTORY names (what the conflict reporter + health engine enumerate).
FFCF_SKILL_NAMES=(communication role-discipline zz-fixture-flat zz-fixture-nested)
FFCF_AGENTS=(zz-fixture-agent-a zz-fixture-agent-b)
# The CLI provider surface — DERIVED from the ownership map, never handwritten.
#
# WHY (cli-0298-compatibility): this was a hardcoded list. T4 added app-e2e-tests +
# invite-with-password to the ownership map, the list did not follow, the reporter called
# them MISSING => CLI_LAYER_DRIFT => exit 1, and the `CONFLICT_OUTPUT="$( … )"` capture in
# cli-flow-recovery-e2e.sh aborted the whole phase under `set -e` with NO stderr and no FAIL
# row — run-tests could only report "crashed before reporting scenarios". Re-typing the list
# with the two new names would have left the same trap armed for the next addition; deriving
# it disarms the trap instead.
#
# app-api-contract-testing is deliberately EXCLUDED: it is flag-gated, so its absence is the
# benign default the U10/AC3b rows assert. The other flag-gated names stay present — being
# gated makes absence benign, it does not make presence wrong.
FFCF_PROVIDER_EXCLUDE="app-api-contract-testing"
ffcf_derive_providers() {
  local ownership="$ROOT/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
  [ -f "$ownership" ] || { echo "[cli-flow-recovery] ownership map not found: $ownership" >&2; return 1; }
  local names
  names="$("$python_bin" - "$ownership" "$FFCF_PROVIDER_EXCLUDE" <<'PY'
import json, sys
own = json.load(open(sys.argv[1], encoding="utf-8"))
skip = set(sys.argv[2].split())
names: set[str] = set()
for e in own.get("paths", []):
    if "<cli-provider-skill>" in e.get("path", ""):
        names.update(e.get("known_names") or [])
names -= skip
if not names:
    raise SystemExit(1)          # deriving an EMPTY provider set would silently pass every row
print(" ".join(sorted(names)))
PY
)" || return 1
  [ -n "$names" ] || return 1
  # shellcheck disable=SC2206
  FFCF_PROVIDERS=($names)
}
if ! ffcf_derive_providers; then
  echo "[cli-flow-recovery] FATAL: could not derive the CLI provider set from the ownership map" >&2
  exit 1
fi
FFCF_CLI_AGENTS=(app-architect app-create-checker)
# 2 of the 7 shipped command templates. Step 8 of the recovery is data-driven, so the
# assertion is "every template in the snapshot landed" — copying all 7 only buys forks.
FFCF_COMMANDS=(fusebase-health.md product-owner.md)

# Single source of truth for fixture bytes: canonical and mirror writers both call these, so a
# hand-built mirror can never silently differ from its canonical source.
ffcf_skill_body() { printf '# fixture skill file %s\n\nFIXTURE FLOW SKILL CONTENT %s\n' "$1" "$1"; }
ffcf_agent_body() { printf '# fixture agent %s\n\nFIXTURE FLOW AGENT CONTENT %s\n' "$1" "$1"; }

# ffcf_canonical <tree>: the Flow-owned canonical sources (flow-skills/ + agents/).
ffcf_canonical() {
  local d="$1" f n
  mkdir -p "$d/flow-skills/communication" "$d/flow-skills/role-discipline" \
           "$d/flow-skills/zz-fixture-flat" "$d/flow-skills/zz-fixture-nested/references" \
           "$d/agents/${FFCF_AGENTS[0]}" "$d/agents/${FFCF_AGENTS[1]}"
  for f in "${FFCF_SKILL_FILES[@]}"; do ffcf_skill_body "$f" > "$d/flow-skills/$f"; done
  for n in "${FFCF_AGENTS[@]}"; do ffcf_agent_body "$n" > "$d/agents/$n/AGENT.md"; done
}

# ffcf_flow_mirrors <tree>: the provider mirrors a completed recovery would have produced.
# Used by trees that assert CLASSIFICATION of a given state; the E2E tree earns them by
# actually running post-fusebase-update.sh instead.
ffcf_flow_mirrors() {
  local d="$1" m f n c
  mkdir -p \
    "$d/.claude/skills/communication" "$d/.claude/skills/role-discipline" \
    "$d/.claude/skills/zz-fixture-flat" "$d/.claude/skills/zz-fixture-nested/references" \
    "$d/.claude/skills/fusebase-flow-health-check" \
    "$d/.agents/skills/communication" "$d/.agents/skills/role-discipline" \
    "$d/.agents/skills/zz-fixture-flat" "$d/.agents/skills/zz-fixture-nested/references" \
    "$d/.agents/skills/fusebase-flow-health-check" \
    "$d/.claude/agents" "$d/.codex/agents" "$d/.claude/commands"
  for m in .claude/skills .agents/skills; do
    for f in "${FFCF_SKILL_FILES[@]}"; do ffcf_skill_body "$f" > "$d/$m/$f"; done
    printf '# fusebase-flow-health-check\n\nFIXTURE HEALTH SKILL\n' > "$d/$m/fusebase-flow-health-check/SKILL.md"
  done
  for m in .claude/agents .codex/agents; do
    for n in "${FFCF_AGENTS[@]}"; do ffcf_agent_body "$n" > "$d/$m/$n.md"; done
  done
  for c in "${FFCF_COMMANDS[@]}"; do printf '# %s\n\nFIXTURE FLOW COMMAND\n' "$c" > "$d/.claude/commands/$c"; done
}

# ffcf_cli_surface <tree>: everything the FuseBase CLI owns. Every file carries a SENTINEL
# string — an ownership test can only prove "untouched" against bytes it can name.
ffcf_cli_surface() {
  local d="$1" n dirs=()
  for n in "${FFCF_PROVIDERS[@]}"; do dirs+=("$d/.claude/skills/$n" "$d/.agents/skills/$n"); done
  mkdir -p "${dirs[@]}" "$d/.claude/agents" "$d/.codex/agents" "$d/.claude/hooks" "$d/.codex"
  for n in "${FFCF_PROVIDERS[@]}"; do
    printf '# %s\n\nCURRENT CLI SKILL SENTINEL %s\n' "$n" "$n" > "$d/.claude/skills/$n/SKILL.md"
    printf '# %s\n\nCURRENT CLI SKILL SENTINEL %s\n' "$n" "$n" > "$d/.agents/skills/$n/SKILL.md"
  done
  for n in "${FFCF_CLI_AGENTS[@]}"; do
    printf 'CURRENT CLI AGENT SENTINEL %s\n' "$n" > "$d/.claude/agents/$n.md"
    printf 'CURRENT CLI AGENT SENTINEL %s\n' "$n" > "$d/.codex/agents/$n.md"
  done
  printf '#!/usr/bin/env bash\necho "CURRENT CLI LINT HOOK SENTINEL"\n' > "$d/.claude/hooks/run-lint-on-stop.sh"
  printf '#!/usr/bin/env bash\necho "CURRENT CLI TYPECHECK HOOK SENTINEL"\n' > "$d/.claude/hooks/run-typecheck-on-stop.sh"
  printf 'console.log("CURRENT CLI QUALITY HOOK SENTINEL");\n' > "$d/.claude/hooks/quality-check-apps.js"
  # Ships on disk but stays UNWIRED — re-injecting it would run typecheck twice (F3/U14).
  printf 'console.log("CURRENT CLI HOOK SENTINEL run-typecheck-apps");\n' > "$d/.claude/hooks/run-typecheck-apps.js"
  cat > "$d/.codex/config.toml" <<'EOF'
codex_hooks = true
hooks_file = ".codex/hooks.json"
skills_dir = ".agents/skills"

[mcp_servers.fusebase-dashboards]
command = "fusebase"
args = ["mcp", "dashboards"]
EOF
}

# ffcf_settings_wired <tree>: the FuseBase CLI 0.25.9-era wired Stop set (unchanged through
# 0.25.16). run-typecheck-apps.js is deliberately NOT in it.
ffcf_settings_wired() {
  mkdir -p "$1/.claude"
  cat > "$1/.claude/settings.json" <<'EOF'
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
}

# ffcf_settings_hooksoff <tree>: CLI Stop hooks present, Flow stop.py absent — the deliberate
# opt-in-off default (F3). Both benign-classification engines must read it as INFO, not drift.
ffcf_settings_hooksoff() {
  mkdir -p "$1/.claude"
  cat > "$1/.claude/settings.json" <<'EOF'
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
}

# ffcf_engine_scripts <tree> [extra hooks/local script ...]: the Flow-owned engine. One batched
# cp per group — a per-script cp loop is ~0.6s each on MSYS.
ffcf_engine_scripts() {
  local d="$1"; shift
  mkdir -p "$d/hooks/local"
  cp hooks/local/mirror-skills.sh hooks/local/mirror-agents.sh \
     hooks/local/post-fusebase-update.sh hooks/local/check-cli-flow-conflicts.sh \
     "$@" "$d/hooks/local/"
  [ -d "$d/hooks/handlers" ] || cp -R hooks/handlers "$d/hooks/handlers"
  # TRIPWIRE: not optional. upgrade.sh exits FATAL without lib/materialize-managed-source.sh,
  # and the health engine sources lib/run-with-timeout.sh + lib/hook-integrity-check.sh.
  [ -d "$d/hooks/local/lib" ] || cp -R hooks/local/lib "$d/hooks/local/lib"
  mkdir -p "$d/hooks/local/fusebase-flow-overlays/commands" \
           "$d/hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check"
  cp hooks/local/fusebase-flow-overlays/agent-surface-ownership.json \
     hooks/local/fusebase-flow-overlays/agents-md-overlay.md \
     hooks/local/fusebase-flow-overlays/claude-md-overlay.md \
     hooks/local/fusebase-flow-overlays/overlay-block-replace.py \
     hooks/local/fusebase-flow-overlays/settings-json-merge.py \
     "$d/hooks/local/fusebase-flow-overlays/"
  cp "hooks/local/fusebase-flow-overlays/commands/${FFCF_COMMANDS[0]}" \
     "hooks/local/fusebase-flow-overlays/commands/${FFCF_COMMANDS[1]}" \
     "$d/hooks/local/fusebase-flow-overlays/commands/"
  cp hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md \
     "$d/hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/"
  # flow-owned + required by the ownership manifest; only presence is ever asserted.
  printf '# FLOW_RULES (fixture stub)\n\nFusebase Flow rule surface placeholder.\n' > "$d/FLOW_RULES.md"
}

# ffcf_root_docs <tree>: CLI-owned AGENTS.md/CLAUDE.md carrying a stale previous overlay
# heading — the exact shape a CLI refresh leaves behind for recovery to repair.
ffcf_root_docs() {
  local d="$1"
  cat > "$d/AGENTS.md" <<'EOF'
# FuseBase CLI project

CURRENT CLI AGENTS SENTINEL 0.25.5

## Fusebase Flow V2 - stale previous overlay heading
EOF
  cat > "$d/CLAUDE.md" <<'EOF'
# FuseBase CLI Claude instructions

CURRENT CLI CLAUDE SENTINEL 0.25.5

## Fusebase Flow V2 - stale previous overlay heading
EOF
}

# ffcf_apply_overlays <tree>: append the REAL overlay templates, i.e. the post-recovery state.
# Classification/engine trees need the genuine block (the engine counts its heading and reads
# the attestation strings inside it); only the E2E tree earns it by running recovery.
ffcf_apply_overlays() {
  local d="$1"
  cat "$d/hooks/local/fusebase-flow-overlays/agents-md-overlay.md" >> "$d/AGENTS.md"
  cat "$d/hooks/local/fusebase-flow-overlays/claude-md-overlay.md" >> "$d/CLAUDE.md"
}

# ffcf_conflict_tree <tree>: a complete, already-recovered install shaped for the read-only
# conflict reporter. No recovery run: these scenarios assert how a STATE is classified, so
# earning the state through a ~40s recovery would only re-test the E2E module.
ffcf_conflict_tree() {
  local d="$1"
  ffcf_canonical "$d"
  ffcf_cli_surface "$d"
  ffcf_flow_mirrors "$d"
  ffcf_engine_scripts "$d" hooks/local/stamp-cli-provenance.sh
  ffcf_root_docs "$d"
  ffcf_apply_overlays "$d"
  ffcf_settings_wired "$d"
}

# ffcf_assert_mirrors <tree> <label>: EVERY canonical fixture member present in BOTH provider
# mirrors. Replaces the old "one named skill exists" spot check — a reduced fixture is only
# safe if the assertion walks the whole fixture, not a name someone remembered to list.
ffcf_assert_mirrors() {
  local d="$1" label="$2" m f n
  for m in .claude/skills .agents/skills; do
    for f in "${FFCF_SKILL_FILES[@]}"; do
      [ -f "$d/$m/$f" ] || fail "$label: Flow skill mirror missing: $m/$f"
    done
  done
  for m in .claude/agents .codex/agents; do
    for n in "${FFCF_AGENTS[@]}"; do
      [ -f "$d/$m/$n.md" ] || fail "$label: Flow agent mirror missing: $m/$n.md"
    done
  done
}

# ffcf_json_assert <json-file> <fail-message> <<'PY' ... PY
# One python spawn per classification assertion; the heredoc arrives on stdin of the caller.
ffcf_json_assert() { "$python_bin" - "$1" || fail "$2"; }

# ffcf_conflicts <tree> <out-json>: run the read-only reporter, capture its exit code in
# FFCF_RC. Never aborts the caller — several scenarios assert on a NON-zero code.
ffcf_conflicts() {
  set +e
  ( cd "$1" && bash hooks/local/check-cli-flow-conflicts.sh --json > "$2" )
  FFCF_RC=$?
  set -e
}

# ffcf_count_marker <file> <marker>: occurrences, fork-free per call is impossible (awk), but
# one spawn beats grep|wc.
ffcf_count_marker() { awk -v m="$2" 'index($0,m){n++} END{print n+0}' "$1"; }

FFCF_MB="<!-- CUSTOM:SKILL:BEGIN -->"
FFCF_ME="<!-- CUSTOM:SKILL:END -->"
