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
# TRIPWIRE: test the heredoc python's rc DIRECTLY (if ! ...). A `|| true` here
# resets $? to 0 before the test, so the check can never fail preflight (false-clean).
if command -v python3 >/dev/null 2>&1; then
    if ! SKILLS_CANON="$SKILLS_CANON" python3 - <<'PY'
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
    then errors=$((errors + 1)); fi
fi

# 4. YAML parse for every policy file
if command -v python3 >/dev/null 2>&1; then
    for yml in "$FF_DIR"/policies/*.yml; do
        [ -e "$yml" ] || continue
        python3 -c "import yaml,sys; yaml.safe_load(open('$yml'))" 2>/dev/null \
            || err "YAML parse failed: $(basename "$yml")"
    done
fi

# _pf_hash_batch OUTFILE FILE...: write "<sha256>  <abs-path>" for each EXISTING file
# to OUTFILE in ONE pass. Batched sha256sum (one spawn per root, not per file) is the
# MSYS speedup; falls back to a per-file `shasum -a 256` loop only when sha256sum is
# absent (same policy as the prior per-file path). Output goes to a FILE REDIRECT, never
# a pipe (MSYS pipe hygiene). Missing files are simply absent from OUTFILE — the caller
# reads that absence as "mirror missing", preserving the missing-vs-drift distinction.
_pf_hash_batch() {
    local out="$1"; shift
    local -a existing=()
    local f
    for f in "$@"; do [ -f "$f" ] && existing+=("$f"); done
    : > "$out"
    [ "${#existing[@]}" -eq 0 ] && return 0
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${existing[@]}" > "$out" 2>/dev/null
    else
        for f in "${existing[@]}"; do shasum -a 256 "$f"; done > "$out" 2>/dev/null
    fi
}

# 5. Skill mirrors consistency (canonical = flow-skills/<name>/SKILL.md +
#    references/*.md; approved mirrors = .agents/skills/ (Codex),
#    .claude/skills/ (Claude Code)). references/ carry rule content
#    (role don't-lists, v3.17.0+) — drift-gated like SKILL.md.
#    Batched: ONE sha256sum per root (canonical + each mirror) instead of ~270
#    per-file spawns; same file set, same comparison, same warn/err text in
#    canonical-list order (F4 — MSYS spawn-cost cut, coverage identical).
skill_canon_list=()
for canon in "$FF_DIR/$SKILLS_CANON"/*/SKILL.md "$FF_DIR/$SKILLS_CANON"/*/references/*; do
    [ -f "$canon" ] && skill_canon_list+=("$canon")
done
if [ "${#skill_canon_list[@]}" -gt 0 ]; then
    _pf_skill_canon_tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-pf-skillcanon.XXXXXX")"
    _pf_skill_agents_tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-pf-skillagents.XXXXXX")"
    _pf_skill_claude_tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-pf-skillclaude.XXXXXX")"
    # Mirror path lists, index-aligned to skill_canon_list (rel path preserved).
    _pf_agents_files=(); _pf_claude_files=()
    for canon in "${skill_canon_list[@]}"; do
        rel="${canon#"$FF_DIR/$SKILLS_CANON/"}"
        _pf_agents_files+=("$ROOT/.agents/skills/$rel")
        _pf_claude_files+=("$ROOT/.claude/skills/$rel")
    done
    _pf_hash_batch "$_pf_skill_canon_tf"  "${skill_canon_list[@]}"
    _pf_hash_batch "$_pf_skill_agents_tf" "${_pf_agents_files[@]}"
    _pf_hash_batch "$_pf_skill_claude_tf" "${_pf_claude_files[@]}"
    # Build abs-path -> hash maps; the shell loop then warns in canonical order. Strip a
    # leading '*' (sha256sum binary-mode path marker on MSYS) so the key matches the shell
    # path; a no-op for text-mode / shasum output.
    declare -A _pf_canon_h=() _pf_agents_h=() _pf_claude_h=()
    while read -r h p; do p="${p#\*}"; _pf_canon_h["$p"]="$h";  done < "$_pf_skill_canon_tf"
    while read -r h p; do p="${p#\*}"; _pf_agents_h["$p"]="$h"; done < "$_pf_skill_agents_tf"
    while read -r h p; do p="${p#\*}"; _pf_claude_h["$p"]="$h"; done < "$_pf_skill_claude_tf"
    rm -f "$_pf_skill_canon_tf" "$_pf_skill_agents_tf" "$_pf_skill_claude_tf"
    for i in "${!skill_canon_list[@]}"; do
        canon="${skill_canon_list[$i]}"
        rel="${canon#"$FF_DIR/$SKILLS_CANON/"}"
        canon_hash="${_pf_canon_h[$canon]:-}"
        agents_file="${_pf_agents_files[$i]}"; claude_file="${_pf_claude_files[$i]}"
        # .agents mirror
        if [ ! -f "$agents_file" ]; then
            warn "mirror missing: .agents/skills/$rel (run mirror-skills.sh)"
        elif [ "$canon_hash" != "${_pf_agents_h[$agents_file]:-}" ]; then
            warn "mirror drift: .agents/skills/$rel != canonical (run mirror-skills.sh)"
        fi
        # .claude mirror
        if [ ! -f "$claude_file" ]; then
            warn "mirror missing: .claude/skills/$rel (run mirror-skills.sh)"
        elif [ "$canon_hash" != "${_pf_claude_h[$claude_file]:-}" ]; then
            warn "mirror drift: .claude/skills/$rel != canonical (run mirror-skills.sh)"
        fi
    done
fi

# 5b. Agent mirror consistency (canonical = agents/<name>/AGENT.md;
#     approved mirrors = .claude/agents/<name>.md, .codex/agents/<name>.md).
#     Batched like §5: ONE sha256sum per root, same warn text in canonical order.
if [ -d "$FF_DIR/agents" ]; then
    agent_canon_list=()
    for canon in "$FF_DIR"/agents/*/AGENT.md; do
        [ -e "$canon" ] && agent_canon_list+=("$canon")
    done
    if [ "${#agent_canon_list[@]}" -gt 0 ]; then
        _pf_ag_canon_tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-pf-agcanon.XXXXXX")"
        _pf_ag_claude_tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-pf-agclaude.XXXXXX")"
        _pf_ag_codex_tf="$(mktemp "${TMPDIR:-/tmp}/ffhc-pf-agcodex.XXXXXX")"
        _pf_ag_names=(); _pf_ag_claude_files=(); _pf_ag_codex_files=()
        for canon in "${agent_canon_list[@]}"; do
            agent_name="$(basename "$(dirname "$canon")")"
            _pf_ag_names+=("$agent_name")
            _pf_ag_claude_files+=("$ROOT/.claude/agents/$agent_name.md")
            _pf_ag_codex_files+=("$ROOT/.codex/agents/$agent_name.md")
        done
        _pf_hash_batch "$_pf_ag_canon_tf"  "${agent_canon_list[@]}"
        _pf_hash_batch "$_pf_ag_claude_tf" "${_pf_ag_claude_files[@]}"
        _pf_hash_batch "$_pf_ag_codex_tf"  "${_pf_ag_codex_files[@]}"
        declare -A _pf_agc_h=() _pf_agcl_h=() _pf_agcx_h=()
        while read -r h p; do p="${p#\*}"; _pf_agc_h["$p"]="$h";  done < "$_pf_ag_canon_tf"
        while read -r h p; do p="${p#\*}"; _pf_agcl_h["$p"]="$h"; done < "$_pf_ag_claude_tf"
        while read -r h p; do p="${p#\*}"; _pf_agcx_h["$p"]="$h"; done < "$_pf_ag_codex_tf"
        rm -f "$_pf_ag_canon_tf" "$_pf_ag_claude_tf" "$_pf_ag_codex_tf"
        for i in "${!agent_canon_list[@]}"; do
            canon="${agent_canon_list[$i]}"; agent_name="${_pf_ag_names[$i]}"
            canon_hash="${_pf_agc_h[$canon]:-}"
            claude_file="${_pf_ag_claude_files[$i]}"; codex_file="${_pf_ag_codex_files[$i]}"
            # .claude/agents mirror
            if [ ! -f "$claude_file" ]; then
                warn "agent mirror missing: .claude/agents/$agent_name.md (run mirror-agents.sh)"
            elif [ "$canon_hash" != "${_pf_agcl_h[$claude_file]:-}" ]; then
                warn "agent mirror drift: .claude/agents/$agent_name.md != canonical (run mirror-agents.sh)"
            fi
            # .codex/agents mirror
            if [ ! -f "$codex_file" ]; then
                warn "agent mirror missing: .codex/agents/$agent_name.md (run mirror-agents.sh)"
            elif [ "$canon_hash" != "${_pf_agcx_h[$codex_file]:-}" ]; then
                warn "agent mirror drift: .codex/agents/$agent_name.md != canonical (run mirror-agents.sh)"
            fi
        done
    fi
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

# 5e. Overlay heading-marker assert (WS6) — dual-accept, mirrors the health-check
#     engine so preflight ⟷ health-check agree on what a valid overlay looks like.
#     Accept the legacy `## Fusebase Flow — …` OR the new `## FuseBase Flow — …`
#     marker; if neither, accept the source-template baseline title (edition mode).
#     A file with NEITHER a marker NOR the baseline title is real drift => ERROR.
if [ -f AGENTS.md ]; then
    if grep -qE "^## Fuse[bB]ase Flow — workflow lifecycle overlay" AGENTS.md; then
        : # overlay marker present (old or new) — OK
    elif grep -qF "Fusebase Flow always-on baseline" AGENTS.md; then
        : # source-template baseline (edition mode) — OK
    else
        err "AGENTS.md missing the FuseBase Flow overlay heading marker (## FuseBase Flow — workflow lifecycle overlay) and baseline title"
    fi
fi
if [ -f CLAUDE.md ]; then
    if grep -qE "^## Fuse[bB]ase Flow — additional rules \(overlay\)" CLAUDE.md; then
        :
    elif grep -qF "Claude Code adapter for Fusebase Flow" CLAUDE.md; then
        :
    else
        err "CLAUDE.md missing the FuseBase Flow overlay heading marker (## FuseBase Flow — additional rules (overlay)) and baseline title"
    fi
fi

# 6. Action-name consistency: command-policy.yml require_approval actions must
#    appear in approval-policy.yml require_approval keys.
# TRIPWIRE: test the heredoc python's rc DIRECTLY (if ! ...); a `|| true` here
# resets $? to 0 before the test, so an orphaned action can never fail preflight.
if command -v python3 >/dev/null 2>&1; then
    if ! python3 - <<'PY'
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
    then errors=$((errors + 1)); fi
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
FLOW_COMMANDS=(fusebase-health onboard product-owner handoff token-waste-audit find-wasted-effort find-wasted-code)
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
if [ -f .codex-plugin/plugin.json ] && command -v python3 >/dev/null 2>&1; then
    codex_plugin_ver="$(python3 -c "import json,sys; print(json.load(open('.codex-plugin/plugin.json')).get('version',''))" 2>/dev/null)"
    if [ -n "$codex_plugin_ver" ] && [ -n "$VER_FILE" ] && [ "$codex_plugin_ver" != "$VER_FILE" ]; then
        err ".codex-plugin/plugin.json version ($codex_plugin_ver) != VERSION ($VER_FILE); bump them together"
    fi
fi
# marketplace.json is NOT written by sync-version-strings.sh — same manual-bump
# parity as plugin.json, or it silently drifts (it lagged ~20 minor versions).
if [ -f .claude-plugin/marketplace.json ] && command -v python3 >/dev/null 2>&1; then
    mkt_ver="$(python3 -c "import json,sys; print((json.load(open('.claude-plugin/marketplace.json')).get('plugins') or [{}])[0].get('version',''))" 2>/dev/null)"
    if [ -n "$mkt_ver" ] && [ -n "$VER_FILE" ] && [ "$mkt_ver" != "$VER_FILE" ]; then
        err ".claude-plugin/marketplace.json plugins[0].version ($mkt_ver) != VERSION ($VER_FILE); bump them together"
    fi
fi

note "preflight finished — errors: $errors, warnings: $warnings"
exit $errors
