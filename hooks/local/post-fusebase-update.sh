#!/usr/bin/env bash
# Fusebase Flow - post-fusebase-update recovery script.
#
# Lives at hooks/local/, outside the FuseBase CLI refresh manifest in current
# CLI releases. Run after a CLI refresh/update when Flow overlay pieces need to
# be restored.
#
# What this script restores:
#   1. Flow skill mirrors in .claude/skills/ and .agents/skills/
#   2. Flow agent mirrors in .claude/agents/ and .codex/agents/
#   3. AGENTS.md Flow overlay block, wrapped in CLI-preserved CUSTOM:SKILL markers
#   4. CLAUDE.md Flow overlay block
#   5. .claude/settings.json Flow lifecycle events and stop.py hook
#   6. fusebase-flow-health-check skill mirrors
#   7. .claude/commands/*.md (ALL Fusebase Flow slash commands — data-driven
#      from the fusebase-flow-overlays/commands/ snapshot, never a fixed list)
#
# Guardrail:
#   .claude/hooks/** is CLI-owned. Flow recovery does not patch or restore CLI
#   hook helper files. If CLI-owned hook helpers are missing or stale, run the
#   current FuseBase CLI refresh/update first, then run this script.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

OVERLAYS="hooks/local/fusebase-flow-overlays"
ACTIONS_TAKEN=()
ACTIONS_SKIPPED=()
WARNINGS=()

# Flags (F2/F3):
#   --wire-hooks       opt-in: merge Flow lifecycle hooks into .claude/settings.json.
#                      DEFAULT IS OFF — recovery never silently changes settings.json
#                      (matches CLAUDE.md's "hooks are opt-in" contract).
#   --refresh-overlays version-aware: if an AGENTS.md/CLAUDE.md overlay block is
#                      PRESENT but DRIFTED from the template, replace it (with a
#                      backup) instead of skipping. Used by upgrade.sh.
WIRE_HOOKS=0
REFRESH_OVERLAYS=0
for arg in "$@"; do
  case "$arg" in
    --wire-hooks) WIRE_HOOKS=1 ;;
    --refresh-overlays) REFRESH_OVERLAYS=1 ;;
    --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "[post-fusebase-update] Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -d "$OVERLAYS" ]; then
  echo "[post-fusebase-update] FATAL: $OVERLAYS not found. Cannot restore Fusebase Flow overlay." >&2
  exit 1
fi

TS_REFRESH=$(date -u +%Y%m%dT%H%M%SZ)

# F2: version-aware overlay refresh — anchored on the CUSTOM:SKILL markers, NOT
# the heading. Both overlay templates wrap their heading INSIDE
# `<!-- CUSTOM:SKILL:BEGIN -->` … `<!-- CUSTOM:SKILL:END -->`. The previous
# heading-anchored logic compared (heading→EOF) against the full marker-wrapped
# template, so they could never match — every run reported DRIFTED and re-appended
# the wrapper, duplicating the BEGIN marker and unbalancing the block. This helper
# compares the live marker-wrapped block (the BEGIN immediately preceding the
# heading → EOF) against the template's marker-wrapped block and replaces it in
# place (with a .pre-refresh backup) only when they genuinely differ. A legacy
# marker-less block is treated as drifted and migrated to the wrapped form.
refresh_overlay_block() {
  local file="$1" heading="$2" template="$3" label="$4"
  [ -f "$template" ] || { WARNINGS+=("$template missing; cannot refresh $label overlay"); return 0; }

  local heading_line begin_line
  heading_line=$(awk -v h="$heading" 'index($0,h){print NR; exit}' "$file")
  begin_line=$(awk -v hl="$heading_line" '
      index($0,"<!-- CUSTOM:SKILL:BEGIN -->") && (hl=="" || NR<=hl){b=NR}
      END{print b+0}' "$file")
  # Only accept a BEGIN that sits just above the heading (templates put it 4 lines
  # up). A distant BEGIN belongs to a different (e.g. CLI-owned) custom block —
  # treat the Flow block as marker-less so we never truncate that other block.
  if [ "${begin_line:-0}" -gt 0 ] && [ "${heading_line:-0}" -gt 0 ] \
     && [ $((heading_line - begin_line)) -gt 6 ]; then
    begin_line=0
  fi

  # U1: carry the operator's FLOW:PRESERVE sub-region forward. Build an "effective
  # template" = the fresh template with its preserve-region swapped for whatever the
  # existing block currently has, so a refresh updates framework prose WITHOUT
  # clobbering operator-owned values (e.g. AGENTS.md ### Project-specific values).
  # ONLY built when the operator actually customized the region (the regions differ);
  # otherwise the raw template is used unchanged so the rebuild stays byte-identical
  # to a fresh append. If either side lacks the markers, the raw template is used.
  local eff_template="$template"
  local tmp_pres="" tmp_tpres="" tmp_eff="" seed_mode=""
  if grep -q "<!-- FLOW:PRESERVE:BEGIN" "$template" 2>/dev/null && [ "${begin_line:-0}" -gt 0 ]; then
    if grep -q "<!-- FLOW:PRESERVE:BEGIN" "$file" 2>/dev/null; then
      seed_mode="markers"                                  # live block already marked
    elif grep -q "^### Project-specific values" "$file" 2>/dev/null; then
      seed_mode="legacy"                                   # U9: pre-markers block — seed from the legacy table
    fi
  fi
  if [ -n "$seed_mode" ]; then
    tmp_pres="$(mktemp)"; tmp_tpres="$(mktemp)"
    awk 'index($0,"<!-- FLOW:PRESERVE:BEGIN"){p=1} p{print} index($0,"<!-- FLOW:PRESERVE:END -->"){p=0}' "$template" > "$tmp_tpres"
    if [ "$seed_mode" = "markers" ]; then
      awk 'index($0,"<!-- FLOW:PRESERVE:BEGIN"){p=1} p{print} index($0,"<!-- FLOW:PRESERVE:END -->"){p=0}' "$file" > "$tmp_pres"
    else
      # U9 legacy seed: wrap the live block's marker-less `### Project-specific values`
      # table (heading → "…rules win." footer) in the template's preserve markers, so a
      # pre-markers block isn't reset on the FIRST preserve-aware upgrade.
      {
        grep -m1 "<!-- FLOW:PRESERVE:BEGIN" "$template"
        awk '/^### Project-specific values/{p=1} p{print} /project-specific rules win\./{p=0}' "$file"
        echo "<!-- FLOW:PRESERVE:END -->"
      } > "$tmp_pres"
    fi
    # Carry the region forward when it's a legacy seed (the block is migrating anyway)
    # or when the operator actually customized it (markers mode that differs from default).
    if [ "$seed_mode" = "legacy" ] || ! diff -q "$tmp_pres" "$tmp_tpres" >/dev/null 2>&1; then
      tmp_eff="$(mktemp)"
      awk -v pf="$tmp_pres" '
        BEGIN { n=0; while ((getline ln < pf) > 0) pres[++n]=ln }
        index($0,"<!-- FLOW:PRESERVE:BEGIN"){ for (i=1;i<=n;i++) print pres[i]; skip=1; next }
        index($0,"<!-- FLOW:PRESERVE:END -->"){ skip=0; next }
        !skip { print }
      ' "$template" > "$tmp_eff"
      eff_template="$tmp_eff"
    fi
    rm -f "$tmp_pres" "$tmp_tpres"; tmp_pres=""; tmp_tpres=""
  fi

  local file_block tmpl_block
  tmpl_block=$(awk 'index($0,"<!-- CUSTOM:SKILL:BEGIN -->"){f=1} f' "$eff_template")
  if [ "${begin_line:-0}" -gt 0 ]; then
    file_block=$(awk -v s="$begin_line" 'NR>=s' "$file")
  else
    file_block="__LEGACY_MARKERLESS_BLOCK__"   # force migrate to wrapped form
  fi

  if [ "$file_block" = "$tmpl_block" ]; then
    ACTIONS_SKIPPED+=("$label overlay present and current")
    [ -n "$tmp_eff" ] && rm -f "$tmp_eff"
    return 0
  fi

  cp "$file" "$file.pre-refresh-$TS_REFRESH"
  local cut trim_rule=0
  if [ "${begin_line:-0}" -gt 0 ]; then cut="$begin_line"; else cut="$heading_line"; trim_rule=1; fi
  # Preserve everything before the block start; TRIM trailing blank lines (so the
  # template's single leading blank yields exactly one blank before BEGIN — byte-
  # identical to a fresh append). In the legacy marker-less migration (begin_line==0)
  # ALSO trim a trailing `---` rule (U7) so the template's own `---` isn't doubled.
  awk -v c="$cut" -v tr="$trim_rule" '
    NR<c {
      lines[NR]=$0
      is_blank = ($0 ~ /^[[:space:]]*$/)
      is_rule  = (tr && $0 ~ /^[[:space:]]*---[[:space:]]*$/)
      if (!is_blank && !is_rule) last=NR
    }
    END { for (i=1; i<=last; i++) print lines[i] }
  ' "$file.pre-refresh-$TS_REFRESH" > "$file"
  cat "$eff_template" >> "$file"
  [ -n "$tmp_eff" ] && rm -f "$tmp_eff"
  ACTIONS_TAKEN+=("$label: refreshed DRIFTED overlay block (backup: $file.pre-refresh-$TS_REFRESH)")
}

# ff_migrate_marker FILE OLD_HEADING NEW_HEADING: rewrite an exact overlay heading
# line (OLD -> NEW) in place. WS6 marker capitalization migration. Line-anchored on
# the full literal heading so it never rewrites the same words appearing in prose;
# awk (not sed) so the em-dash + parens are matched as literal bytes without ERE
# metacharacter escaping. Idempotent by construction — the caller only invokes this
# when OLD is present and NEW is absent, and it exits 0 only when it actually
# rewrote a line. Never touches file bytes other than the matched heading line(s).
ff_migrate_marker() {
  local file="$1" old="$2" new="$3" tmp
  tmp="$(mktemp)" || return 1
  awk -v o="$old" -v n="$new" '
    $0==o { print n; c++; next }
    { print }
    END { print c+0 > "/dev/stderr" }
  ' "$file" 2>"$tmp.n" >"$tmp"
  local n; n="$(cat "$tmp.n" 2>/dev/null)"; rm -f "$tmp.n"
  if [ "${n:-0}" -gt 0 ]; then
    cat "$tmp" > "$file"; rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"; return 1
}

###############################################################################
# Step 1 - Re-mirror Fusebase Flow skills.
###############################################################################

echo "[post-fusebase-update] Step 1: re-mirror Fusebase Flow skills..."
if [ -x hooks/local/mirror-skills.sh ]; then
  bash hooks/local/mirror-skills.sh >/dev/null 2>&1 || WARNINGS+=("mirror-skills.sh exited non-zero")
  ACTIONS_TAKEN+=("re-mirrored Fusebase Flow skills (.claude/skills/ + .agents/skills/)")
else
  WARNINGS+=("hooks/local/mirror-skills.sh not found or not executable")
fi

###############################################################################
# Step 2 - Re-mirror Fusebase Flow sub-agents.
###############################################################################

echo "[post-fusebase-update] Step 2: re-mirror Fusebase Flow sub-agents..."
if [ -x hooks/local/mirror-agents.sh ]; then
  bash hooks/local/mirror-agents.sh >/dev/null 2>&1 || WARNINGS+=("mirror-agents.sh exited non-zero")
  ACTIONS_TAKEN+=("re-mirrored Fusebase Flow sub-agents (.claude/agents/ + .codex/agents/)")
else
  WARNINGS+=("hooks/local/mirror-agents.sh not found or not executable")
fi

###############################################################################
# Step 3 - Re-append AGENTS.md overlay if missing.
###############################################################################

echo "[post-fusebase-update] Step 3: AGENTS.md overlay check..."
# WS6 marker migration: the heading was recapitalized Fusebase->FuseBase. Migrate
# an existing OLD marker to the NEW one IN PLACE (idempotent: only rewrites the
# legacy spelling, does nothing once already NEW) BEFORE the present/refresh check,
# so an upgraded installed base moves to the new marker without a hand edit and the
# NEW-marker refresh logic below then matches. Dual-accept means either spelling is
# valid; migration just converges the installed base on the canonical NEW form.
AGENTS_MARKER="## FuseBase Flow — workflow lifecycle overlay"
AGENTS_MARKER_OLD="## Fusebase Flow — workflow lifecycle overlay"
if [ -f AGENTS.md ] && grep -qF "$AGENTS_MARKER_OLD" AGENTS.md && ! grep -qF "$AGENTS_MARKER" AGENTS.md; then
  # sed over the exact heading line only (leading `## `), never elsewhere in prose.
  ff_migrate_marker AGENTS.md "$AGENTS_MARKER_OLD" "$AGENTS_MARKER" \
    && ACTIONS_TAKEN+=("AGENTS.md: migrated overlay heading marker Fusebase->FuseBase (WS6)")
fi
if [ ! -f AGENTS.md ]; then
  WARNINGS+=("AGENTS.md not found in repo root; skipping overlay restore")
elif grep -qF "$AGENTS_MARKER" AGENTS.md; then
  # F2: present — refresh if DRIFTED, only under --refresh-overlays (marker-anchored).
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    refresh_overlay_block AGENTS.md "$AGENTS_MARKER" "$OVERLAYS/agents-md-overlay.md" "AGENTS.md"
  else
    ACTIONS_SKIPPED+=("AGENTS.md overlay already present (use --refresh-overlays to update a drifted block)")
  fi
else
  if [ ! -f "$OVERLAYS/agents-md-overlay.md" ]; then
    WARNINGS+=("$OVERLAYS/agents-md-overlay.md missing; cannot restore AGENTS.md")
  else
    cat "$OVERLAYS/agents-md-overlay.md" >> AGENTS.md
    ACTIONS_TAKEN+=("AGENTS.md: appended Fusebase Flow overlay block")
  fi
fi

###############################################################################
# Step 4 - Re-append CLAUDE.md overlay if missing.
###############################################################################

echo "[post-fusebase-update] Step 4: CLAUDE.md overlay check..."
# WS6 marker migration (idempotent) — same as AGENTS.md above.
CLAUDE_MARKER="## FuseBase Flow — additional rules (overlay)"
CLAUDE_MARKER_OLD="## Fusebase Flow — additional rules (overlay)"
if [ -f CLAUDE.md ] && grep -qF "$CLAUDE_MARKER_OLD" CLAUDE.md && ! grep -qF "$CLAUDE_MARKER" CLAUDE.md; then
  ff_migrate_marker CLAUDE.md "$CLAUDE_MARKER_OLD" "$CLAUDE_MARKER" \
    && ACTIONS_TAKEN+=("CLAUDE.md: migrated overlay heading marker Fusebase->FuseBase (WS6)")
fi
if [ ! -f CLAUDE.md ]; then
  ACTIONS_SKIPPED+=("CLAUDE.md not present (Claude Code not configured for this project)")
elif grep -qF "$CLAUDE_MARKER" CLAUDE.md; then
  # F2: present — refresh if DRIFTED, only under --refresh-overlays (marker-anchored).
  if [ "$REFRESH_OVERLAYS" -eq 1 ]; then
    refresh_overlay_block CLAUDE.md "$CLAUDE_MARKER" "$OVERLAYS/claude-md-overlay.md" "CLAUDE.md"
  else
    ACTIONS_SKIPPED+=("CLAUDE.md overlay already present (use --refresh-overlays to update a drifted block)")
  fi
else
  if [ ! -f "$OVERLAYS/claude-md-overlay.md" ]; then
    WARNINGS+=("$OVERLAYS/claude-md-overlay.md missing; cannot restore CLAUDE.md")
  else
    cat "$OVERLAYS/claude-md-overlay.md" >> CLAUDE.md
    ACTIONS_TAKEN+=("CLAUDE.md: appended Fusebase Flow overlay block")
  fi
fi

###############################################################################
# Step 5 - Merge .claude/settings.json with Fusebase Flow lifecycle hooks.
###############################################################################

echo "[post-fusebase-update] Step 5: .claude/settings.json merge check..."
MERGE_SCRIPT="$OVERLAYS/settings-json-merge.py"
if [ "$WIRE_HOOKS" -ne 1 ]; then
  # F3: opt-in. By default recovery does NOT touch settings.json — this matches
  # CLAUDE.md's "hooks are opt-in: nothing runs until you copy settings.json.example."
  if [ -f .claude/settings.json ]; then
    ACTIONS_SKIPPED+=(".claude/settings.json NOT modified (hook wiring is opt-in — re-run with --wire-hooks to merge Flow lifecycle hooks)")
  else
    ACTIONS_SKIPPED+=(".claude/settings.json not present (Claude Code not configured)")
  fi
elif [ ! -f .claude/settings.json ]; then
  ACTIONS_SKIPPED+=(".claude/settings.json not present (Claude Code not configured)")
elif ! command -v python3 >/dev/null 2>&1; then
  WARNINGS+=("python3 not on PATH - cannot merge .claude/settings.json automatically")
elif [ ! -f "$MERGE_SCRIPT" ]; then
  WARNINGS+=("$MERGE_SCRIPT missing; cannot merge settings.json")
else
  cp .claude/settings.json .claude/settings.json.pre-flow-merge
  # D1 receipt: the merge writes state/audit/cli-stop-baseline.json on EVERY
  # wire-hooks run (real merge AND the no-op "already wired" path) so the
  # health-check's diff baseline is durable + self-refreshing. NOT .pre-flow-merge
  # (overwritten at :259 / rm -f'd on no-op).
  CLI_STOP_BASELINE="state/audit/cli-stop-baseline.json"
  set +e
  MERGE_OUTPUT=$(python3 "$MERGE_SCRIPT" .claude/settings.json --baseline-out "$CLI_STOP_BASELINE" 2>&1)
  MERGE_EXIT=$?
  set -e
  if [ "$MERGE_EXIT" -eq 0 ]; then
    ACTIONS_TAKEN+=(".claude/settings.json: wrote CLI Stop baseline receipt ($CLI_STOP_BASELINE)")
    if echo "$MERGE_OUTPUT" | grep -q "already up to date\|byte-identical"; then
      ACTIONS_SKIPPED+=(".claude/settings.json: Fusebase Flow events already wired")
      rm -f .claude/settings.json.pre-flow-merge
    else
      ACTIONS_TAKEN+=(".claude/settings.json: merged Fusebase Flow lifecycle events (backup at .claude/settings.json.pre-flow-merge)")
    fi
  else
    WARNINGS+=("Python merge failed (exit $MERGE_EXIT); .claude/settings.json restored from backup. Output: $MERGE_OUTPUT")
    cp .claude/settings.json.pre-flow-merge .claude/settings.json
    rm -f .claude/settings.json.pre-flow-merge
  fi
fi

###############################################################################
# Step 5b - (Re)install the Flow git fallback hooks (WS1c).
###############################################################################
# Under --wire-hooks, (re)install the git pre-commit/commit-msg so the FIXED
# pre-commit is live after an upgrade (the "upgrade doesn't wire the fixed
# pre-commit" gap). install-git-hooks.sh is SAFE: a custom .git/hooks/pre-commit
# is backed up + preserved, never silently clobbered (needs --force to replace).
echo "[post-fusebase-update] Step 5b: Flow git-hook (re)install check..."
if [ "$WIRE_HOOKS" -eq 1 ] && [ -d .git/hooks ] && [ -x hooks/local/install-git-hooks.sh ]; then
  if bash hooks/local/install-git-hooks.sh 2>&1 | grep -qi 'custom .* detected'; then
    WARNINGS+=("custom .git/hooks preserved (not overwritten); re-run 'bash hooks/local/install-git-hooks.sh --force' to install the Flow hook")
  else
    ACTIONS_TAKEN+=("(re)installed Flow git fallback hooks (.git/hooks/pre-commit, commit-msg)")
  fi
else
  ACTIONS_SKIPPED+=(".git/hooks NOT touched (git-hook (re)install runs under --wire-hooks only)")
fi

###############################################################################
# Step 6 - CLI hook ownership guardrail.
###############################################################################

echo "[post-fusebase-update] Step 6: CLI hook ownership guardrail..."
ACTIONS_SKIPPED+=(".claude/hooks/** is CLI-owned; Flow recovery does not patch CLI hook helpers")

###############################################################################
# Step 7 - Restore fusebase-flow-health-check skill mirror.
###############################################################################

echo "[post-fusebase-update] Step 7: fusebase-flow-health-check skill restore..."
HEALTH_SKILL_TEMPLATE="$OVERLAYS/skills/fusebase-flow-health-check/SKILL.md"
if [ ! -f "$HEALTH_SKILL_TEMPLATE" ]; then
  WARNINGS+=("$HEALTH_SKILL_TEMPLATE missing; cannot restore fusebase-flow-health-check skill")
else
  RESTORED=0
  for target_dir in .claude/skills .agents/skills; do
    target_path="$target_dir/fusebase-flow-health-check/SKILL.md"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$target_path" ] && diff -q "$HEALTH_SKILL_TEMPLATE" "$target_path" >/dev/null 2>&1; then
      :
    else
      cp "$HEALTH_SKILL_TEMPLATE" "$target_path"
      RESTORED=$((RESTORED + 1))
    fi
  done
  if [ "$RESTORED" -gt 0 ]; then
    ACTIONS_TAKEN+=("fusebase-flow-health-check skill: restored to $RESTORED of 2 mirror paths")
  else
    ACTIONS_SKIPPED+=("fusebase-flow-health-check skill already mirrored to both paths")
  fi
fi

###############################################################################
# Step 8 - Restore Fusebase Flow slash commands (data-driven from the
#          recovery snapshot — this is the installer step new commands ship in).
###############################################################################

echo "[post-fusebase-update] Step 8: Fusebase Flow slash commands restore..."
CMD_TEMPLATE_DIR="$OVERLAYS/commands"
CMD_TARGET_DIR=".claude/commands"
if [ ! -d "$CMD_TEMPLATE_DIR" ]; then
  WARNINGS+=("$CMD_TEMPLATE_DIR missing; cannot restore Fusebase Flow slash commands")
else
  CMD_RESTORED=0
  CMD_TOTAL=0
  mkdir -p "$CMD_TARGET_DIR"
  for cmd_template in "$CMD_TEMPLATE_DIR"/*.md; do
    [ -f "$cmd_template" ] || continue
    CMD_TOTAL=$((CMD_TOTAL + 1))
    cmd_name="$(basename "$cmd_template")"
    cmd_target="$CMD_TARGET_DIR/$cmd_name"
    if [ -f "$cmd_target" ] && diff -q "$cmd_template" "$cmd_target" >/dev/null 2>&1; then
      :
    else
      cp "$cmd_template" "$cmd_target"
      CMD_RESTORED=$((CMD_RESTORED + 1))
    fi
  done
  if [ "$CMD_RESTORED" -gt 0 ]; then
    ACTIONS_TAKEN+=("Fusebase Flow slash commands: restored $CMD_RESTORED of $CMD_TOTAL to $CMD_TARGET_DIR")
  else
    ACTIONS_SKIPPED+=("Fusebase Flow slash commands already in place ($CMD_TOTAL command(s))")
  fi
fi

###############################################################################
# Summary
###############################################################################

echo ""
echo "============================================================"
echo "[post-fusebase-update] Summary"
echo "============================================================"
echo ""
if [ "${#ACTIONS_TAKEN[@]}" -gt 0 ]; then
  echo "Actions taken (${#ACTIONS_TAKEN[@]}):"
  for a in "${ACTIONS_TAKEN[@]}"; do echo "  * $a"; done
  echo ""
fi
if [ "${#ACTIONS_SKIPPED[@]}" -gt 0 ]; then
  echo "Already in place (${#ACTIONS_SKIPPED[@]}):"
  for a in "${ACTIONS_SKIPPED[@]}"; do echo "  - $a"; done
  echo ""
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo "Warnings (${#WARNINGS[@]}):"
  for w in "${WARNINGS[@]}"; do echo "  ! $w"; done
  echo ""
fi

echo "Recommended next steps:"
echo "  1. Review changes:   git diff"
echo "  2. Run validation:   bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh"
echo "  3. Stage + commit (through the wired pre-commit — NO --no-verify):"
echo "       git add AGENTS.md CLAUDE.md .claude/settings.json .claude/commands .claude/skills .agents/skills .claude/agents .codex/agents"
echo "       # if the changeset touches Flow-internal protected paths, mint the single-use"
echo "       # bootstrap approval FIRST (digest-bound to exactly this staged changeset):"
echo "       bash hooks/local/write-bootstrap-approval.sh"
echo "       git commit -m 'chore(flow): restore Fusebase Flow overlay after fusebase update'"
echo "       bash hooks/local/write-bootstrap-approval.sh --consume   # single-use: clean up after"

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  exit 1
fi
exit 0
