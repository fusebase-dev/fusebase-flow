#!/usr/bin/env bash
# Fusebase Flow — preflight
# Validates the framework installation: file structure, YAML parse, skill
# frontmatter, mirror consistency, no-orphaned-policy-keys.
#
# Run after install or after editing canonical sources.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1
FF_DIR="$ROOT"

errors=0
warnings=0

note() { echo "[preflight] $*"; }
err()  { echo "[preflight] ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "[preflight] warn:  $*" >&2; warnings=$((warnings + 1)); }

# Canonical skills dir: flow-skills/ (v3.9.0+); legacy root skills/ as fallback.
SKILLS_CANON="flow-skills"
[ -d "$FF_DIR/$SKILLS_CANON" ] || SKILLS_CANON="skills"

# 1. Required top-level files
for f in AGENTS.md CLAUDE.md GEMINI.md FLOW_RULES.md VERSION; do
    [ -f "$f" ] || err "missing required file: $f"
done

# 2. Skills, workflows, templates, policies populated
for d in "$SKILLS_CANON" workflows templates policies hooks/handlers hooks/shared hooks/git hooks/local audit; do
    if [ ! -d "$FF_DIR/$d" ] || [ -z "$(ls -A "$FF_DIR/$d" 2>/dev/null)" ]; then
        warn "empty dir: $d"
    fi
done

# 3. Skill frontmatter structure (requires YAML in each SKILL.md)
if command -v python3 >/dev/null 2>&1; then
    SKILLS_CANON="$SKILLS_CANON" python3 - <<'PY' || true
import os, re, sys
from pathlib import Path
root = Path.cwd()
errs = 0
canon = os.environ.get("SKILLS_CANON", "flow-skills")
for skill in (root / canon).glob("*/SKILL.md"):
    text = skill.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---", text, flags=re.DOTALL)
    if not m:
        print(f"[preflight] ERROR: missing frontmatter: {skill.relative_to(root)}", file=sys.stderr)
        errs += 1
        continue
    fm = m.group(1)
    required = ["name", "description", "source_inspiration", "license_status",
                "fusebase_flow_version", "risk_level", "invocation",
                "expected_outputs", "related_workflows", "hook_dependencies"]
    for k in required:
        if not re.search(rf"^{k}\s*:", fm, flags=re.MULTILINE):
            print(f"[preflight] ERROR: skill {skill.parent.name} missing frontmatter key: {k}", file=sys.stderr)
            errs += 1
sys.exit(errs)
PY
    if [ $? -ne 0 ]; then errors=$((errors + 1)); fi
fi

# 4. YAML parse for every policy file
if command -v python3 >/dev/null 2>&1; then
    for yml in "$FF_DIR"/policies/*.yml; do
        [ -e "$yml" ] || continue
        python3 -c "import yaml,sys; yaml.safe_load(open('$yml'))" 2>/dev/null \
            || err "YAML parse failed: $(basename "$yml")"
    done
fi

# 5. Skill mirrors consistency (canonical = flow-skills/<name>/SKILL.md +
#    references/*.md; approved mirrors = .agents/skills/ (Codex),
#    .claude/skills/ (Claude Code)). references/ carry rule content
#    (role don't-lists, v3.17.0+) — drift-gated like SKILL.md.
for canon in "$FF_DIR/$SKILLS_CANON"/*/SKILL.md "$FF_DIR/$SKILLS_CANON"/*/references/*; do
    [ -f "$canon" ] || continue
    rel="${canon#"$FF_DIR/$SKILLS_CANON/"}"
    canon_hash="$(sha256sum "$canon" 2>/dev/null | awk '{print $1}')"
    [ -z "$canon_hash" ] && canon_hash="$(shasum -a 256 "$canon" | awk '{print $1}')"
    for mirror_root in .agents .claude; do
        mirror_file="$ROOT/$mirror_root/skills/$rel"
        if [ ! -f "$mirror_file" ]; then
            warn "mirror missing: $mirror_root/skills/$rel (run mirror-skills.sh)"
            continue
        fi
        mirror_hash="$(sha256sum "$mirror_file" 2>/dev/null | awk '{print $1}')"
        [ -z "$mirror_hash" ] && mirror_hash="$(shasum -a 256 "$mirror_file" | awk '{print $1}')"
        if [ "$canon_hash" != "$mirror_hash" ]; then
            warn "mirror drift: $mirror_root/skills/$rel != canonical (run mirror-skills.sh)"
        fi
    done
done

# 5b. Agent mirror consistency (canonical = agents/<name>/AGENT.md;
#     approved mirrors = .claude/agents/<name>.md, .codex/agents/<name>.md).
if [ -d "$FF_DIR/agents" ]; then
    for canon in "$FF_DIR"/agents/*/AGENT.md; do
        [ -e "$canon" ] || continue
        agent_name="$(basename "$(dirname "$canon")")"
        canon_hash="$(sha256sum "$canon" 2>/dev/null | awk '{print $1}')"
        [ -z "$canon_hash" ] && canon_hash="$(shasum -a 256 "$canon" | awk '{print $1}')"
        for mirror_root in .claude/agents .codex/agents; do
            mirror_file="$ROOT/$mirror_root/$agent_name.md"
            if [ ! -f "$mirror_file" ]; then
                warn "agent mirror missing: $mirror_root/$agent_name.md (run mirror-agents.sh)"
                continue
            fi
            mirror_hash="$(sha256sum "$mirror_file" 2>/dev/null | awk '{print $1}')"
            [ -z "$mirror_hash" ] && mirror_hash="$(shasum -a 256 "$mirror_file" | awk '{print $1}')"
            if [ "$canon_hash" != "$mirror_hash" ]; then
                warn "agent mirror drift: $mirror_root/$agent_name.md != canonical (run mirror-agents.sh)"
            fi
        done
    done
fi

# 5c. CLI vendor provenance manifest (info/advisory only — never fails).
#     The manifest is a document of record for vendored CLI-owned assets
#     (audit/cli-vendor-manifest.json). If present it must parse; if absent,
#     warn (a fresh edition should ship it, but a downstream may regenerate it
#     with hooks/local/stamp-cli-provenance.sh).
if command -v python3 >/dev/null 2>&1; then
    prov="$FF_DIR/audit/cli-vendor-manifest.json"
    if [ -f "$prov" ]; then
        python3 -c "import json,sys; d=json.load(open('$prov')); sys.exit(0 if d.get('schema_version')==1 and isinstance(d.get('assets'),list) else 1)" 2>/dev/null \
            || warn "cli-vendor-manifest.json present but invalid (schema_version!=1 or no assets); regenerate with hooks/local/stamp-cli-provenance.sh"
    else
        warn "cli-vendor-manifest.json absent; run bash hooks/local/stamp-cli-provenance.sh to stamp CLI vendor provenance"
    fi
fi

# 5d. Overlay recovery-copy drift (warn-level only). The copies under
#     hooks/local/fusebase-flow-overlays/ are recovery sources (health-check
#     skill + slash commands); if canonical moved on without them, recovery
#     would restore stale content.
OVL="$FF_DIR/hooks/local/fusebase-flow-overlays"
if [ -d "$OVL" ]; then
    if [ -f "$OVL/skills/fusebase-flow-health-check/SKILL.md" ] && [ -f "$FF_DIR/$SKILLS_CANON/fusebase-flow-health-check/SKILL.md" ]; then
        cmp -s "$OVL/skills/fusebase-flow-health-check/SKILL.md" "$FF_DIR/$SKILLS_CANON/fusebase-flow-health-check/SKILL.md" \
            || warn "overlay drift: fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md != canonical $SKILLS_CANON copy (refresh the overlay)"
    fi
    for ovl_cmd in "$OVL"/commands/*.md; do
        [ -f "$ovl_cmd" ] || continue
        cmd_name="$(basename "$ovl_cmd")"
        if [ -f "$ROOT/.claude/commands/$cmd_name" ]; then
            cmp -s "$ovl_cmd" "$ROOT/.claude/commands/$cmd_name" \
                || warn "overlay drift: fusebase-flow-overlays/commands/$cmd_name != .claude/commands/$cmd_name (refresh the overlay)"
        else
            warn "overlay command has no live counterpart: .claude/commands/$cmd_name missing"
        fi
    done
fi

# 6. Action-name consistency: command-policy.yml require_approval actions must
#    appear in approval-policy.yml require_approval keys.
if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' || true
import sys, yaml
from pathlib import Path
root = Path.cwd() / "policies"
cmd = yaml.safe_load((root / "command-policy.yml").read_text())
appr = yaml.safe_load((root / "approval-policy.yml").read_text())
appr_keys = set((appr.get("require_approval") or {}).keys())
errs = 0
for entry in (cmd.get("require_approval") or []):
    action = entry.get("action")
    if action and action not in appr_keys:
        print(f"[preflight] ERROR: command-policy require_approval references action '{action}' not in approval-policy.yml require_approval keys", file=sys.stderr)
        errs += 1
sys.exit(errs)
PY
    if [ $? -ne 0 ]; then errors=$((errors + 1)); fi
fi

# 7. Existing Fusebase CLI / MCP overlay sanity check (warning only).
#    If MCP / runtime config is present, ensure Fusebase Flow was installed
#    as an append/merge overlay and not via blind bulk copy.
mcp_present=()
for f in .mcp.json .cursor/mcp.json fusebase.json .claude/settings.json; do
    [ -e "$f" ] && mcp_present+=("$f")
done
if [ "${#mcp_present[@]}" -gt 0 ]; then
    warn "existing Fusebase CLI / MCP configuration detected (${mcp_present[*]}); ensure Fusebase Flow was installed as an append/merge overlay (see docs/install-fusebase-cli-project.md)"
fi

# 8. Command-surface consistency (v3.14.1+; data-driven v3.20.1): every Flow
#    slash command must ship its FULL surface in lockstep — the live command
#    file, the recovery-snapshot copy (the upgrade.sh/post-fusebase-update
#    installer source; a check may only ship in the same release as its
#    installer step), and the CLAUDE.md reference. New command = one array
#    entry + the snapshot copy; preflight fails the release otherwise.
VER_FILE="$(tr -d '\n\r' < VERSION 2>/dev/null)"
FLOW_COMMANDS=(fusebase-health onboard product-owner handoff token-waste-audit)
for c in "${FLOW_COMMANDS[@]}"; do
    [ -f ".claude/commands/$c.md" ] || err "missing .claude/commands/$c.md (/$c slash command)"
    [ -f "$OVL/commands/$c.md" ] || err "command '/$c' missing from recovery snapshot fusebase-flow-overlays/commands/ — a command surface may only ship with its installer step (upgrade would land BROKEN downstream)"
    grep -q "/$c\b" CLAUDE.md || err "CLAUDE.md does not list the /$c slash command"
done
grep -qi 'invoke the `handoff` skill' AGENTS.md || err "AGENTS.md does not explain the portable (non-Claude) handoff invocation"
if [ -f .claude-plugin/plugin.json ] && command -v python3 >/dev/null 2>&1; then
    plugin_ver="$(python3 -c "import json,sys; print(json.load(open('.claude-plugin/plugin.json')).get('version',''))" 2>/dev/null)"
    if [ -n "$plugin_ver" ] && [ -n "$VER_FILE" ] && [ "$plugin_ver" != "$VER_FILE" ]; then
        err ".claude-plugin/plugin.json version ($plugin_ver) != VERSION ($VER_FILE); bump them together"
    fi
fi

note "preflight finished — errors: $errors, warnings: $warnings"
exit $errors
