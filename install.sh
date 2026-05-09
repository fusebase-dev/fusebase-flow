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
# What this script does:
#   0. detect existing agent / MCP / Fusebase CLI config and require explicit
#      APPEND-ONLY confirmation if any is found (or --auto-yes acknowledgement)
#   1. install local git hooks  (hooks/git/* into .git/hooks/)              [opt-in]
#   2. run preflight            (validate structure + policies + mirrors)   [opt-in]
#   3. mirror skills            (skills/ -> .agents/skills/, .claude/skills/) [opt-in]
#   4. mirror sub-agents        (agents/ -> .claude/agents/, .codex/agents/) [opt-in]
#   5. show next steps          (provider-specific activation hints)
#
# Exit codes:
#   0  success
#   2  unknown argument
#   3  protected files detected and operator did not type APPEND-ONLY
#
# What this script does NOT do:
#   - install Python or pip
#   - install PyYAML for you (run `pip install -r hooks/requirements.txt`)
#   - rewrite git history
#   - mutate provider settings
#   - call any external service
#   - merge or replace existing AGENTS.md, CLAUDE.md, MCP config, or
#     `.claude/settings.json`. See docs/install-fusebase-cli-project.md
#     for the manual append/merge procedure.

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

# 0. Existing Fusebase CLI / MCP / agent configuration detection.
#
# Fusebase Flow must be installed as an append/merge overlay on top of any
# existing Fusebase CLI, MCP, or agent configuration. This guard surfaces
# protected files and requires explicit APPEND-ONLY acknowledgement before
# proceeding. See docs/install-fusebase-cli-project.md.
PROTECTED_DETECTED=()
for f in AGENTS.md CLAUDE.md .gitignore .claude/settings.json .codex/config.toml \
         .cursor/mcp.json .mcp.json fusebase.json skills-lock.json; do
    if [ -e "$f" ]; then PROTECTED_DETECTED+=("$f"); fi
done
for d in .agents/skills .claude/skills .claude/hooks .claude/agents; do
    if [ -d "$d" ]; then PROTECTED_DETECTED+=("$d/"); fi
done

if [ "${#PROTECTED_DETECTED[@]}" -gt 0 ]; then
    echo "[install] WARNING: existing agent / MCP / Fusebase CLI configuration detected:"
    for path in "${PROTECTED_DETECTED[@]}"; do
        echo "[install]   - $path"
    done
    echo
    echo "[install] Fusebase Flow must be installed as an append/merge overlay."
    echo "[install] Do not overwrite existing AGENTS.md, CLAUDE.md, .gitignore,"
    echo "[install] MCP config, Claude settings, or existing skill folders."
    echo
    echo "[install] Review docs/install-fusebase-cli-project.md before continuing."
    echo
    {
        echo
        echo "## Step 0 — protected file detection"
        echo
        echo "Detected:"
        for path in "${PROTECTED_DETECTED[@]}"; do echo "- $path"; done
    } >> "$REPORT"

    if [ "$AUTO_YES" -eq 1 ]; then
        echo "[install] --auto-yes set: continuing (assumes operator has reviewed merge safety)."
        echo "- step 0: --auto-yes acknowledged, continuing" >> "$REPORT"
    else
        ack=""
        read -r -p "Type APPEND-ONLY to continue: " ack || true
        if [ "$ack" != "APPEND-ONLY" ]; then
            echo "[install] aborted: no APPEND-ONLY confirmation." >&2
            echo "- step 0: aborted (no APPEND-ONLY confirmation)" >> "$REPORT"
            exit 3
        fi
        echo "- step 0: APPEND-ONLY confirmed by operator" >> "$REPORT"
    fi
    echo
else
    echo "- step 0: no existing agent / MCP / Fusebase CLI files detected" >> "$REPORT"
fi

# Preflight: PyYAML available?
if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "[install] WARN: PyYAML is not installed. Install before running hooks:"
    echo "[install]   pip install -r hooks/requirements.txt"
    echo "[install] Continuing — preflight will fail until PyYAML is present." >&2
fi

# 1. Install local git hooks
if confirm "(1/4) Install local git fallback hooks (pre-commit, commit-msg)?"; then
    bash hooks/local/install-git-hooks.sh
    echo "- step 1: git hooks installed" >> "$REPORT"
else
    echo "- step 1: git hooks skipped" >> "$REPORT"
fi

# 2. Run preflight
if confirm "(2/4) Run preflight (validate framework structure, policies, mirrors)?"; then
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
if confirm "(3/4) Mirror skills into provider folders (.agents/skills/, .claude/skills/)?"; then
    bash hooks/local/mirror-skills.sh
    echo "- step 3: skills mirrored to .agents/skills/ and .claude/skills/" >> "$REPORT"
else
    echo "- step 3: skill mirror skipped" >> "$REPORT"
fi

# 4. Mirror sub-agents (canonical agents/<name>/AGENT.md -> .claude/agents/, .codex/agents/)
if [ -d "$ROOT/agents" ]; then
    if confirm "(4/4) Mirror sub-agents into provider folders (.claude/agents/, .codex/agents/)?"; then
        bash hooks/local/mirror-agents.sh
        echo "- step 4: agents mirrored to .claude/agents/ and .codex/agents/" >> "$REPORT"
    else
        echo "- step 4: agent mirror skipped" >> "$REPORT"
    fi
else
    echo "- step 4: agents/ canonical dir not present — skipped" >> "$REPORT"
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
