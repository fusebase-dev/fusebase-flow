#!/usr/bin/env bash
# Fusebase Flow Local — install.sh
#
# Optional convenience installer. Does NOT install heavy dependencies.
# Does NOT require any external SaaS. Does NOT mutate your project beyond
# the steps you opt into.
#
# Usage:
#   bash install.sh                # interactive
#   bash install.sh --auto-yes     # non-interactive: do everything safe
#
# What this script does (each opt-in):
#   1. install local git hooks  (hooks/git/* into .git/hooks/)
#   2. run preflight            (validate structure + policies + mirrors)
#   3. mirror skills            (skills/ -> .agents/skills/, .claude/skills/)
#   4. show next steps          (provider-specific activation hints)
#
# What this script does NOT do:
#   - install Python or pip
#   - install PyYAML for you (run `pip install -r hooks/requirements.txt`)
#   - rewrite git history
#   - mutate provider settings
#   - call any external service

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

AUTO_YES=0
for arg in "$@"; do
    case "$arg" in
        --auto-yes|-y) AUTO_YES=1 ;;
        --help|-h)
            sed -n '2,28p' "$0"
            exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Run with --help for usage." >&2
            exit 2 ;;
    esac
done

confirm() {
    local prompt="$1"
    if [ "$AUTO_YES" -eq 1 ]; then return 0; fi
    read -r -p "$prompt [y/N] " ans
    case "$ans" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

REPORT="$ROOT/state/audit/install-report.md"
mkdir -p "$(dirname "$REPORT")"

{
    echo "# Fusebase Flow install report"
    echo
    echo "Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Operator: ${USER:-unknown}"
    echo "Repo: $ROOT"
    echo
} > "$REPORT"

echo "[install] Fusebase Flow Local installer"
echo "[install] Repo: $ROOT"
echo "[install] Report will be written to: $REPORT"
echo

# Preflight: PyYAML available?
if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "[install] WARN: PyYAML is not installed. Install before running hooks:"
    echo "[install]   pip install -r hooks/requirements.txt"
    echo "[install] Continuing — preflight will fail until PyYAML is present." >&2
fi

# 1. Install local git hooks
if confirm "(1/3) Install local git fallback hooks (pre-commit, commit-msg)?"; then
    bash hooks/local/install-git-hooks.sh
    echo "- step 1: git hooks installed" >> "$REPORT"
else
    echo "- step 1: git hooks skipped" >> "$REPORT"
fi

# 2. Run preflight
if confirm "(2/3) Run preflight (validate framework structure, policies, mirrors)?"; then
    if bash hooks/local/preflight.sh; then
        echo "- step 2: preflight PASS (errors: 0, warnings: 0)" >> "$REPORT"
    else
        ec=$?
        echo "- step 2: preflight FAIL (exit code $ec) — see stderr above" >> "$REPORT"
        echo "[install] preflight failed; see $REPORT" >&2
    fi
else
    echo "- step 2: preflight skipped" >> "$REPORT"
fi

# 3. Mirror skills
if confirm "(3/3) Mirror skills into provider folders (.agents/skills/, .claude/skills/)?"; then
    bash hooks/local/mirror-skills.sh
    echo "- step 3: skills mirrored to .agents/skills/ and .claude/skills/" >> "$REPORT"
else
    echo "- step 3: skill mirror skipped" >> "$REPORT"
fi

# Next steps hint
{
    echo
    echo "## Next steps"
    echo
    echo "Open this repo in your IDE / agent of choice:"
    echo
    echo "- **Anthropic Claude Code** — reads CLAUDE.md automatically. To enable hooks:"
    echo "  cp .claude/settings.json.example .claude/settings.json"
    echo "  (then customize the python interpreter path inside)"
    echo
    echo "- **OpenAI / ChatGPT Codex** — reads AGENTS.md automatically. To enable hooks:"
    echo "  cp .codex/config.toml.example .codex/config.toml"
    echo "  cp .codex/hooks.json.example .codex/hooks.json"
    echo "  (then accept the project trust prompt in Codex)"
    echo
    echo "- **Cursor** — reads .cursor/rules/ automatically. No further setup needed."
    echo
    echo "- **GitHub Copilot / VS Code** — reads .github/copilot-instructions.md and"
    echo "  .github/instructions/*.instructions.md automatically. No further setup needed."
    echo
    echo "- **Gemini / Antigravity-style IDE agents** — reads AGENTS.md and GEMINI.md."
    echo
    echo "- **Generic local repo workflow** — read AGENTS.md and FLOW_RULES.md"
    echo "  before starting any task. Git hooks are your safety net."
    echo
    echo "## File first ticket"
    echo
    echo "Tell the agent: 'Let's ship <feature description>.'"
    echo "It will invoke the requirements-specification skill and start the eight-phase flow."
    echo "See workflows/eight-phase-flow.md for the full lifecycle."
} >> "$REPORT"

echo
echo "[install] Done. Install report: $REPORT"
echo "[install] Read README.md for the next-steps overview, or open the repo in your IDE."
