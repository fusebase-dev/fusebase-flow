#!/usr/bin/env bash
# Fusebase Flow — cli-flow-recovery: the END-TO-END module (sourced, never run).
# WHY-home: docs/specs/backlog-triage-execution/architecture-review.md § Q2 (step 4).
#
# TRIPWIRE — this is the ONE complete, publisher-shaped tree in the suite, and the only place
# post-fusebase-update.sh actually runs against a full install. Its scenarios are a single
# LIFECYCLE on one tree (recover -> wire -> refresh-current -> refresh-drifted -> refresh-again
# -> preserve-carry), so each step's precondition is deliberately the previous step's product.
# Classification scenarios must NOT be added here: they belong on their own isolated fixtures,
# or the order-dependence the decomposition removed comes straight back.
#
# TRIPWIRE — exactly ONE `cp -R "$PROJECT"` exists in the whole suite and it is taken here, at
# the freshly-recovered-install point, for the U20 migration case. Taking it later would hand
# U20 "whatever the refresh scenarios left behind" instead of a defined base.

ffcf_e2e_build() {
  ffcf_canonical "$PROJECT"
  ffcf_cli_surface "$PROJECT"
  ffcf_engine_scripts "$PROJECT" hooks/local/stamp-cli-provenance.sh
  ffcf_root_docs "$PROJECT"
  ffcf_settings_wired "$PROJECT"
}

ffcf_e2e_run() {
  ffcf_e2e_build

  local CODEX_BEFORE HOOK_BEFORE CLI_SKILL_BEFORE SETTINGS_BEFORE AGENTS_GOOD m ov c
  CODEX_BEFORE="$(sha_cmd "$PROJECT/.codex/config.toml")"
  HOOK_BEFORE="$(sha_cmd "$PROJECT/.claude/hooks/run-typecheck-apps.js")"
  CLI_SKILL_BEFORE="$(sha_cmd "$PROJECT/.claude/skills/fusebase-cli/SKILL.md")"
  SETTINGS_BEFORE="$(sha_cmd "$PROJECT/.claude/settings.json")"

  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh > "$OUT" )

  grep -q "CURRENT CLI AGENTS SENTINEL" "$PROJECT/AGENTS.md" || fail "CLI AGENTS baseline was lost"
  # WS6 dual-accept: recovery emits the NEW marker; a legacy tree may carry either.
  grep -qE "^## Fuse[bB]ase Flow — workflow lifecycle overlay" "$PROJECT/AGENTS.md" && grep -qF -- "bootstrap-upgrade.sh -- --auto-yes" "$PROJECT/AGENTS.md" || fail "current Flow AGENTS overlay was not restored (heading, or T6/M7 supported-upgrade-route guidance — the latter is CANONICAL-overlay content, so a root-AGENTS.md-only edit is discarded here)"
  grep -q "CURRENT CLI CLAUDE SENTINEL" "$PROJECT/CLAUDE.md" || fail "CLI CLAUDE baseline was lost"
  grep -qE "^## Fuse[bB]ase Flow — additional rules \(overlay\)" "$PROJECT/CLAUDE.md" || fail "current Flow CLAUDE overlay was not restored"

  [ "$CODEX_BEFORE" = "$(sha_cmd "$PROJECT/.codex/config.toml")" ] || fail ".codex/config.toml changed"
  [ "$HOOK_BEFORE" = "$(sha_cmd "$PROJECT/.claude/hooks/run-typecheck-apps.js")" ] || fail "CLI hook helper changed"
  [ "$CLI_SKILL_BEFORE" = "$(sha_cmd "$PROJECT/.claude/skills/fusebase-cli/SKILL.md")" ] || fail "CLI provider skill changed"

  # F3: DEFAULT recovery is opt-in for hook wiring — it must NOT touch settings.json.
  [ "$SETTINGS_BEFORE" = "$(sha_cmd "$PROJECT/.claude/settings.json")" ] || fail "F3: default recovery modified settings.json without --wire-hooks"
  grep -q "hooks/handlers/stop.py" "$PROJECT/.claude/settings.json" && fail "F3: stop.py merged without --wire-hooks" || true
  [ ! -f "$PROJECT/.claude/settings.json.pre-flow-merge" ] || fail "F3: default recovery left a settings.json backup behind"
  grep -q "NOT modified (hook wiring is opt-in" "$OUT" || fail "F3: default recovery did not print the opt-in notice"
  pass "F3: default recovery leaves settings.json untouched and prints the opt-in notice"

  # F3: explicit --wire-hooks performs the merge, preserving the CLI Stop hooks.
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --wire-hooks > "$OUT.wire" )
  grep -q "hooks/handlers/stop.py" "$PROJECT/.claude/settings.json" || fail "Flow stop.py was not merged under --wire-hooks"
  # 0.25.9-era model (D1 preserve-only; unchanged through 0.25.16): the merge keeps every wired
  # CLI Stop hook + appends stop.py, and must NOT static-inject the unwired run-typecheck-apps.js
  # (that would run typecheck twice alongside run-typecheck-on-stop.sh).
  for m in run-lint-on-stop.sh run-typecheck-on-stop.sh quality-check-apps.js; do
    grep -q "$m" "$PROJECT/.claude/settings.json" || fail "0.25.9-era CLI Stop hook not preserved (unchanged through 0.25.16): $m"
  done
  grep -q "run-typecheck-apps.js" "$PROJECT/.claude/settings.json" && fail "unwired run-typecheck-apps.js re-injected (double typecheck)" || true
  pass "F3: --wire-hooks appends stop.py and preserves the 0.25.9-era CLI Stop set (unchanged through 0.25.16; no run-typecheck-apps.js re-inject)"

  # THE one full-tree clone (see the header tripwire). Handed to U20 as a defined base.
  cp -R "$PROJECT" "$FFCF_SNAPSHOT"

  ffcf_assert_mirrors "$PROJECT" "recovery"
  for c in "${FFCF_COMMANDS[@]}"; do
    [ -f "$PROJECT/.claude/commands/$c" ] || fail "Flow slash command not restored: $c"
  done

  local CONFLICT_OUTPUT
  CONFLICT_OUTPUT="$( cd "$PROJECT" && bash hooks/local/check-cli-flow-conflicts.sh )"
  echo "$CONFLICT_OUTPUT" | grep -q "Verdict: HEALTHY" || {
    echo "$CONFLICT_OUTPUT" >&2
    fail "conflict reporter did not return HEALTHY after recovery"
  }

  pass "CLI-owned AGENTS/CLAUDE baselines preserved"
  pass "CLI provider skills and hook helpers untouched"
  pass "Flow skills, agents, overlays, and health command restored"
  pass "conflict reporter returned HEALTHY"

  # F2 — --refresh-overlays is marker-anchored + idempotent: (1) refreshing a CURRENT block is a
  # no-op with one balanced BEGIN/END; (2) a drifted block is restored to one balanced block;
  # (3) re-running is idempotent. (Guards the bug where heading-anchored drift re-appended the
  # CUSTOM:SKILL wrapper each run.)
  for ov in AGENTS.md CLAUDE.md; do
    [ "$(ffcf_count_marker "$PROJECT/$ov" "$FFCF_MB")" -eq 1 ] \
      || fail "F2 precondition: $ov should have exactly 1 BEGIN after recovery, got $(ffcf_count_marker "$PROJECT/$ov" "$FFCF_MB")"
  done

  # Byte-exactness baseline: the clean, freshly-appended AGENTS.md block. A no-op refresh must
  # leave it identical; a drift refresh must converge back to it byte-for-byte (locks the
  # trailing-blank-before-BEGIN nit so it can't regress).
  AGENTS_GOOD="$(sha_cmd "$PROJECT/AGENTS.md")"

  # (1) refresh a CURRENT block -> no-op (no backup, reported "present and current").
  rm -f "$PROJECT"/AGENTS.md.pre-refresh-* "$PROJECT"/CLAUDE.md.pre-refresh-*
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.refresh1" )
  for ov in AGENTS.md CLAUDE.md; do
    [ "$(ffcf_count_marker "$PROJECT/$ov" "$FFCF_MB")" -eq 1 ] \
      || fail "F2: refreshing a CURRENT $ov changed BEGIN count to $(ffcf_count_marker "$PROJECT/$ov" "$FFCF_MB") (duplication bug)"
    [ "$(ffcf_count_marker "$PROJECT/$ov" "$FFCF_ME")" -eq 1 ] \
      || fail "F2: $ov has $(ffcf_count_marker "$PROJECT/$ov" "$FFCF_ME") END markers (expected 1 — unbalanced)"
    grep -q "$ov overlay present and current" "$OUT.refresh1" \
      || fail "F2: refresh of a current $ov was not reported as 'present and current'"
  done
  ls "$PROJECT"/AGENTS.md.pre-refresh-* >/dev/null 2>&1 && fail "F2: no-op refresh wrote an AGENTS.md backup" || true
  ls "$PROJECT"/CLAUDE.md.pre-refresh-* >/dev/null 2>&1 && fail "F2: no-op refresh wrote a CLAUDE.md backup" || true
  [ "$(sha_cmd "$PROJECT/AGENTS.md")" = "$AGENTS_GOOD" ] \
    || fail "F2: no-op refresh changed AGENTS.md bytes (should be byte-identical to the clean block)"
  pass "F2: --refresh-overlays on a current block is a no-op (byte-identical; BEGIN/END balanced at 1)"

  # (2) drift AGENTS.md, refresh -> restored to one balanced block, drift removed.
  printf '\nDRIFTED-FLOW-BLOCK-EXTRA-LINE\n' >> "$PROJECT/AGENTS.md"
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.refresh2" )
  [ "$(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_MB")" -eq 1 ] \
    || fail "F2: after refreshing a DRIFTED AGENTS.md, BEGIN count is $(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_MB") (expected 1)"
  [ "$(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_ME")" -eq 1 ] \
    || fail "F2: after refreshing a DRIFTED AGENTS.md, END count is $(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_ME") (expected 1)"
  grep -q "DRIFTED-FLOW-BLOCK-EXTRA-LINE" "$PROJECT/AGENTS.md" && fail "F2: drift survived the refresh (block not replaced)" || true
  ls "$PROJECT"/AGENTS.md.pre-refresh-* >/dev/null 2>&1 || fail "F2: refresh of a drifted block wrote no backup"
  grep -q "CURRENT CLI AGENTS SENTINEL" "$PROJECT/AGENTS.md" && grep -qF -- "bootstrap-upgrade.sh -- --auto-yes" "$PROJECT/AGENTS.md" || fail "F2: refresh dropped the CLI-owned AGENTS baseline or the T6/M7 supported-upgrade-route guidance"
  [ "$(sha_cmd "$PROJECT/AGENTS.md")" = "$AGENTS_GOOD" ] \
    || fail "F2: drift refresh did not converge byte-exactly to the clean block (trailing-blank-before-BEGIN regression?)"
  pass "F2: --refresh-overlays restores a drifted block byte-exactly (== clean block; single balanced BEGIN/END; CLI baseline kept)"

  # (3) refresh again -> idempotent no-op.
  rm -f "$PROJECT"/AGENTS.md.pre-refresh-*
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.refresh3" )
  [ "$(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_MB")" -eq 1 ] \
    || fail "F2: second refresh changed BEGIN count (not idempotent)"
  ls "$PROJECT"/AGENTS.md.pre-refresh-* >/dev/null 2>&1 && fail "F2: second refresh of a now-current block wrote a backup (not idempotent)" || true
  pass "F2: --refresh-overlays is idempotent (re-run on a current block does nothing)"

  # U1 — overlay refresh PRESERVES the operator-customized FLOW:PRESERVE region. Customize the
  # project value (operator data), drift the framework prose OUTSIDE that region, then refresh:
  # the operator's value must survive AND the framework prose must update. (Data-loss guard.)
  grep -q "<!-- FLOW:PRESERVE:BEGIN" "$PROJECT/AGENTS.md" || fail "U1 precondition: AGENTS.md block lacks FLOW:PRESERVE markers"
  sed -i -E 's/\| Project name \| [^|]*\|/| Project name | WORKHUB-MANAGED |/' "$PROJECT/AGENTS.md"
  grep -q "WORKHUB-MANAGED" "$PROJECT/AGENTS.md" || fail "U1 setup: could not set the operator project value"
  sed -i 's/workflow lifecycle overlay/workflow lifecycle overlay (DRIFTED-FRAMEWORK-PROSE)/' "$PROJECT/AGENTS.md"
  rm -f "$PROJECT"/AGENTS.md.pre-refresh-*
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.u1" )
  grep -q "WORKHUB-MANAGED" "$PROJECT/AGENTS.md" || fail "U1: refresh WIPED the operator's project value (data loss!)"
  grep -q "DRIFTED-FRAMEWORK-PROSE" "$PROJECT/AGENTS.md" && fail "U1: framework prose drift survived the refresh (block not refreshed)" || true
  [ "$(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_MB")" -eq 1 ] || fail "U1: BEGIN count not 1 after preserve-carry refresh"
  pass "U1: refresh preserves operator FLOW:PRESERVE values while refreshing framework prose"
}
