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

# 1. Required top-level files
for f in AGENTS.md CLAUDE.md GEMINI.md FLOW_RULES.md VERSION; do
    [ -f "$f" ] || err "missing required file: $f"
done

# 2. Skills, workflows, templates, policies populated
for d in skills workflows templates policies hooks/handlers hooks/shared hooks/git hooks/local audit; do
    if [ ! -d "$FF_DIR/$d" ] || [ -z "$(ls -A "$FF_DIR/$d" 2>/dev/null)" ]; then
        warn "empty dir: $d"
    fi
done

# 3. Skill frontmatter structure (requires YAML in each SKILL.md)
if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' || true
import os, re, sys
from pathlib import Path
root = Path.cwd()
errs = 0
for skill in (root / "skills").glob("*/SKILL.md"):
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

# 5. Skill mirrors consistency (canonical = skills/<name>/SKILL.md;
#    approved mirrors = .agents/skills/ (Codex), .claude/skills/ (Claude Code))
for canon in "$FF_DIR"/skills/*/SKILL.md; do
    [ -e "$canon" ] || continue
    skill_name="$(basename "$(dirname "$canon")")"
    canon_hash="$(sha256sum "$canon" 2>/dev/null | awk '{print $1}')"
    [ -z "$canon_hash" ] && canon_hash="$(shasum -a 256 "$canon" | awk '{print $1}')"
    for mirror_root in .agents .claude; do
        mirror_file="$ROOT/$mirror_root/skills/$skill_name/SKILL.md"
        if [ ! -f "$mirror_file" ]; then
            warn "mirror missing: $mirror_root/skills/$skill_name/SKILL.md (run mirror-skills.sh)"
            continue
        fi
        mirror_hash="$(sha256sum "$mirror_file" 2>/dev/null | awk '{print $1}')"
        [ -z "$mirror_hash" ] && mirror_hash="$(shasum -a 256 "$mirror_file" | awk '{print $1}')"
        if [ "$canon_hash" != "$mirror_hash" ]; then
            warn "mirror drift: $mirror_root/skills/$skill_name/SKILL.md != canonical (run mirror-skills.sh)"
        fi
    done
done

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

note "preflight finished — errors: $errors, warnings: $warnings"
exit $errors
