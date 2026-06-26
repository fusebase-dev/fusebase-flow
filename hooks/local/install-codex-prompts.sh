#!/usr/bin/env bash
# Fusebase Flow — install-codex-prompts.sh (OPT-IN, per-machine).
#
# Generates native Codex custom prompts from the 6 canonical Flow command bodies
# and installs them to $CODEX_HOME/prompts/ (default ~/.codex/prompts/), where
# Codex surfaces them as /prompts:<name>. Single-sourced from
# hooks/local/fusebase-flow-overlays/commands/*.md (the same bodies that become
# the Claude .claude/commands/ — see docs/specs/codex-slash-command-parity/spec.md
# D3 for the no-hand-maintained-copy rationale).
#
# OPT-IN ONLY — NEVER call this from post-fusebase-update.sh or any default path:
# it writes USER-GLOBAL files outside the repo (D2/D5). Codex custom prompts are
# user-global, namespaced (/prompts:<name>), and Codex-DEPRECATED in favor of
# skills — B (the AGENTS.md command-equivalents table) is the real repo-portable
# parity; this native layer is per-machine polish.
#
# Usage:
#   bash hooks/local/install-codex-prompts.sh            # install (refuses to clobber UNMARKED files)
#   bash hooks/local/install-codex-prompts.sh --force    # overwrite even UNMARKED collisions
#   bash hooks/local/install-codex-prompts.sh --dry-run  # show what would be written, write nothing
#   CODEX_HOME=/path bash hooks/local/install-codex-prompts.sh   # override target root
#
# Exit: 0 success / nothing to do; 1 error (incl. unmarked collision without --force); 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SRC_DIR="hooks/local/fusebase-flow-overlays/commands"

# Tripwire: this exact sentinel is the marked-by-Flow contract — the collision
# guard, idempotency check, and the AC3 test all match this literal line. Changing
# it silently breaks unmarked-collision refusal. Kept stable on purpose.
MARKER="<!-- FUSEBASE-FLOW-GENERATED: codex prompt; source hooks/local/fusebase-flow-overlays/commands/<name>.md; regenerate via install-codex-prompts.sh — do not hand-edit -->"
MARKER_PREFIX="<!-- FUSEBASE-FLOW-GENERATED: codex prompt;"

DRY_RUN=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "[install-codex-prompts] Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -d "$SRC_DIR" ]; then
  echo "[install-codex-prompts] FATAL: canonical command source $SRC_DIR not found." >&2
  exit 1
fi

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PROMPTS_DIR="$CODEX_HOME/prompts"

# Transform one canonical Claude command body into a Codex prompt body on stdout.
# Single-source contract (D3): keep the YAML frontmatter description; repoint
# .claude/agents -> .codex/agents; insert the Flow marker just after the closing
# frontmatter fence so the YAML stays valid and the PO-boot block + its markers
# pass through untouched.
transform_body() { # transform_body <canonical-file> <basename>
  local file="$1" name="$2" marker
  marker="${MARKER/<name>/$name}"
  awk -v marker="$marker" '
    BEGIN { fm=0; inserted=0 }
    NR==1 && $0=="---" { fm=1; print; next }
    fm==1 && $0=="---" { print; print ""; print marker; fm=2; inserted=1; next }
    { print }
    END {
      # No frontmatter fence (unexpected) -> still mark the file at the very top.
      if (!inserted) { print marker > "/dev/stderr" }
    }
  ' "$file" | sed 's|\.claude/agents/|.codex/agents/|g'
}

# Returns 0 if an existing file carries the Flow marker (safe to overwrite).
is_marked() { # is_marked <file>
  [ -f "$1" ] && grep -qF "$MARKER_PREFIX" "$1"
}

mapfile -t SRC_FILES < <(find "$SRC_DIR" -maxdepth 1 -type f -name '*.md' | sort)
if [ "${#SRC_FILES[@]}" -eq 0 ]; then
  echo "[install-codex-prompts] FATAL: no command bodies found under $SRC_DIR." >&2
  exit 1
fi

# Pass 1 — collision check BEFORE writing anything (fail closed; no partial writes
# when an unmarked file would be clobbered without --force).
COLLISIONS=()
for src in "${SRC_FILES[@]}"; do
  name="$(basename "$src" .md)"
  target="$PROMPTS_DIR/$name.md"
  if [ -f "$target" ] && ! is_marked "$target" && [ "$FORCE" -ne 1 ]; then
    COLLISIONS+=("$target")
  fi
done
if [ "${#COLLISIONS[@]}" -gt 0 ]; then
  echo "[install-codex-prompts] REFUSING to overwrite UNMARKED existing prompt file(s):" >&2
  for c in "${COLLISIONS[@]}"; do echo "  ! $c (not Flow-generated)" >&2; done
  echo "  Re-run with --force to overwrite, or move these files aside." >&2
  exit 1
fi

if [ "$DRY_RUN" -ne 1 ]; then
  mkdir -p "$PROMPTS_DIR"
fi

WRITTEN=0
SKIPPED=0
for src in "${SRC_FILES[@]}"; do
  name="$(basename "$src" .md)"
  target="$PROMPTS_DIR/$name.md"
  generated="$(transform_body "$src" "$name")"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[install-codex-prompts] (dry-run) would write $target  (/prompts:$name)"
    continue
  fi
  # Idempotent: byte-identical generated output -> no write.
  if [ -f "$target" ] && printf '%s\n' "$generated" | cmp -s - "$target"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  printf '%s\n' "$generated" > "$target"
  WRITTEN=$((WRITTEN + 1))
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[install-codex-prompts] (dry-run) ${#SRC_FILES[@]} prompt(s) would be installed to $PROMPTS_DIR"
  exit 0
fi

echo "[install-codex-prompts] installed to $PROMPTS_DIR — written: $WRITTEN, unchanged: $SKIPPED"
echo ""
echo "Invoke in Codex's interactive UI as:"
for src in "${SRC_FILES[@]}"; do
  echo "  /prompts:$(basename "$src" .md)"
done
echo ""
echo "Note (honest): Codex custom prompts are PER-MACHINE (user-global under \$CODEX_HOME),"
echo "namespaced as /prompts:<name>, and DEPRECATED by Codex in favor of skills. The repo-"
echo "portable parity is the AGENTS.md command-equivalents table (B); this is optional polish."
echo "Re-run anytime — it is idempotent and only rewrites Flow-marked files."
exit 0
