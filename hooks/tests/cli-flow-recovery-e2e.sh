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
  git -C "$PROJECT" init --quiet
  git -C "$PROJECT" config --local user.name "Fusebase Flow recovery fixture"
  git -C "$PROJECT" config --local user.email "flow-recovery-fixture@example.invalid"
  mkdir -p "$PROJECT/hooks/git"
  cp hooks/local/install-git-hooks.sh "$PROJECT/hooks/local/"
  cp hooks/git/pre-commit hooks/git/commit-msg "$PROJECT/hooks/git/"
  ffcf_root_docs "$PROJECT"
  ffcf_settings_wired "$PROJECT"
}

ffcf_recovery_inventory() {
  "$python_bin" - "$1" "$2" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
paths = [
    root / "AGENTS.md", root / "CLAUDE.md",
    root / "audit/skill-mirror-manifest.txt", root / "audit/agent-mirror-manifest.txt",
    root / ".claude/settings.json", root / ".claude/settings.json.pre-flow-merge",
    root / "state/audit/cli-stop-baseline.json",
    root / "state/audit/flow-hook-wiring-intent.json",
    root / ".git/hooks/pre-commit", root / ".git/hooks/commit-msg",
]
for directory in (".claude/skills", ".agents/skills", ".claude/agents", ".codex/agents", ".claude/commands"):
    paths.extend(path for path in (root / directory).rglob("*") if path.is_file())
doc = {
    str(path.relative_to(root)).replace("\\", "/"): {
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "mtime_ns": path.stat().st_mtime_ns,
    }
    for path in sorted(set(paths)) if path.is_file()
}
out.write_text(json.dumps(doc, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY
}

ffcf_t14_progress_ledger() {
  ffcf_e2e_build
  local status="$PROJECT/state/audit/flow-recovery-status.json" first_plan rc
  set +e
  ( cd "$PROJECT" && FUSEBASE_FLOW_TEST_FAIL_AFTER_SURFACE=skill_mirrors \
      bash hooks/local/post-fusebase-update.sh > "$OUT.t14-interrupt" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] || fail "T14: injected recovery interruption exited $rc instead of 1"
  "$python_bin" - "$status" <<'PY' || fail "T14: interrupted status inventory is inaccurate"
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["schema_version"] == 2 and value["status"] == "partial"
assert value["applied_surfaces"] == ["skill_mirrors"]
assert "skill_mirrors" not in value["pending_surfaces"]
assert len(value["attempts"]) == 1
PY
  first_plan="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1]))["plan_id"])' "$status")"
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh > "$OUT.t14-retry" 2>&1 ) \
    || fail "T14: retry after interruption did not converge"
  "$python_bin" - "$status" "$first_plan" <<'PY' \
    || fail "T14: retry reset plan identity or attempt history"
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["status"] == "complete" and value["exit_code"] == 0
assert value["plan_id"] == sys.argv[2]
assert value["pending_surfaces"] == []
assert len(value["attempts"]) == 2
assert value["attempts"][1]["resumed_applied_surfaces"] == ["skill_mirrors"]
PY
  pass "T14: interrupted progress remains accurate and retry reconciles the same plan history"
}

ffcf_t15_verification() {
  ffcf_e2e_build
  local rc backup status="$PROJECT/state/audit/flow-recovery-status.json"
  cat "$PROJECT/hooks/local/fusebase-flow-overlays/claude-md-overlay.md" >> "$PROJECT/CLAUDE.md"
  backup="$PROJECT/CLAUDE.md.pre-refresh-20260906T000000Z"
  cp "$PROJECT/CLAUDE.md" "$backup"
  "$python_bin" - "$PROJECT" "$backup" <<'PY'
import hashlib, json, pathlib, sys
root, backup = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
path = root / "state/audit/flow-recovery-status.json"
path.parent.mkdir(parents=True, exist_ok=True)
relative = backup.relative_to(root).as_posix()
path.write_text(json.dumps({
    "schema_version": 2, "status": "complete", "backup_paths": [relative],
    "backup_artifacts": [{"path": relative, "sha256": hashlib.sha256(backup.read_bytes()).hexdigest()}],
    "attempts": [],
}), encoding="utf-8")
PY
  rm "$PROJECT/CLAUDE.md"
  set +e
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh > "$OUT.t15-restore" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 0 ] \
    || { cat "$OUT.t15-restore" >&2; fail "T15: ownership-verified provider backup was not restored"; }
  cmp -s "$backup" "$PROJECT/CLAUDE.md" \
    || { sha256sum "$backup" "$PROJECT/CLAUDE.md" >&2; find "$PROJECT" -maxdepth 1 -name 'CLAUDE.md.pre-refresh-*' -print >&2; fail "T15: restored provider bytes do not match the hash-recorded backup"; }

  rm "$PROJECT/CLAUDE.md"
  printf '\nTAMPERED\n' >> "$backup"
  set +e
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && [ ! -e "$PROJECT/CLAUDE.md" ] \
    || fail "T15: tampered provider backup was trusted or reported complete"

  rm "$backup"
  set +e
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && [ ! -e "$PROJECT/CLAUDE.md" ] \
    || fail "T15: missing provider without a verified backup did not remain partial"

  ffcf_e2e_build
  set +e
  ( cd "$PROJECT" && FUSEBASE_FLOW_TEST_TAMPER_AFTER_APPLY=.claude/commands/fusebase-health.md \
      bash hooks/local/post-fusebase-update.sh >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && "$python_bin" - "$status" <<'PY' \
    || fail "T15: post-apply tamper was not reflected in final status"
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["status"] == "partial" and "commands" in value["uncertain_surfaces"]
assert "commands" not in value["verified_surfaces"]
PY
  pass "T15: verified provider backup restores; tampered backup and post-apply mutation stay partial"
}

ffcf_t20_repeated_noop() {
  ffcf_e2e_build
  local evidence="$TMP_BASE/t20-attempts.json" before after out rc attempt
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh >/dev/null 2>&1 ) \
    || fail "T20: convergence recovery failed"
  printf '{"attempts":[' > "$evidence"
  for attempt in 1 2 3; do
    before="$TMP_BASE/t20-before-$attempt.json"
    after="$TMP_BASE/t20-after-$attempt.json"
    out="$TMP_BASE/t20-run-$attempt.log"
    ffcf_recovery_inventory "$PROJECT" "$before"
    set +e
    ( cd "$PROJECT" && timeout 120s bash hooks/local/post-fusebase-update.sh > "$out" 2>&1 )
    rc=$?
    set -e
    ffcf_recovery_inventory "$PROJECT" "$after"
    [ "$attempt" -eq 1 ] || printf ',' >> "$evidence"
    "$python_bin" - "$attempt" "$rc" "$before" "$after" "$out" >> "$evidence" <<'PY'
import datetime, json, pathlib, sys
attempt, rc = int(sys.argv[1]), int(sys.argv[2])
before, after = (json.load(open(path, encoding="utf-8")) for path in sys.argv[3:5])
changed = sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key))
print(json.dumps({"attempt_id": f"write-mode-{attempt}",
 "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(), "exit_code": rc,
 "changed_targets": changed, "write_copy_count": len(changed)}), end="")
PY
  done
  printf ']}' >> "$evidence"
  "$python_bin" - "$evidence" <<'PY' || fail "T20: repeated write-mode attempts were not no-ops"
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))["attempts"]
assert len(rows) == 3 and len({row["attempt_id"] for row in rows}) == 3
assert all(row["timestamp"] and row["exit_code"] == 0 and not row["changed_targets"]
           and row["write_copy_count"] == 0 for row in rows)
PY
  ffcf_recovery_inventory "$PROJECT" "$TMP_BASE/t20-mutation-before.json"
  printf '\ninjected mutation\n' >> "$PROJECT/.claude/commands/fusebase-health.md"
  ffcf_recovery_inventory "$PROJECT" "$TMP_BASE/t20-mutation-after.json"
  cmp -s "$TMP_BASE/t20-mutation-before.json" "$TMP_BASE/t20-mutation-after.json" \
    && fail "T20: injected write was not detected"
  pass "T20: three independent write-mode recoveries preserve hashes/mtimes and injected writes are detected"
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
  grep -qE "^## FuseBase Flow — Claude Code adapter$" "$PROJECT/CLAUDE.md" || fail "current Flow CLAUDE overlay was not restored"

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

  ffcf_recovery_inventory "$PROJECT" "$TMP_BASE/t4-before.json"
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --wire-hooks > "$OUT.noop" )
  ffcf_recovery_inventory "$PROJECT" "$TMP_BASE/t4-after.json"
  diff -q "$TMP_BASE/t4-before.json" "$TMP_BASE/t4-after.json" >/dev/null 2>&1 \
    || fail "T4: second recovery changed a target hash or mtime"
  [ -f "$PROJECT/.claude/settings.json.pre-flow-merge" ] \
    || fail "T4: second recovery removed retained settings recovery material"
  grep -q "skill mirrors already current" "$OUT.noop" \
    || fail "T4: clean skill mirrors were not reported as current"
  grep -q "agent mirrors already current" "$OUT.noop" \
    || fail "T4: clean agent mirrors were not reported as current"
  for m in .claude/skills .agents/skills; do
    diff -q "$PROJECT/flow-skills/fusebase-flow-health-check/SKILL.md" \
      "$PROJECT/$m/fusebase-flow-health-check/SKILL.md" >/dev/null 2>&1 \
      || fail "T4: $m health skill did not retain canonical bytes"
  done
  pass "T4: second recovery retains every target hash/mtime and canonical health bytes"

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
  sed -i '0,/Provider adapters point here/s//DRIFTED-FLOW-BLOCK-EXTRA-LINE/' "$PROJECT/AGENTS.md"
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
  sed -i '0,/Provider adapters point here/s//DRIFTED-FRAMEWORK-PROSE/' "$PROJECT/AGENTS.md"
  rm -f "$PROJECT"/AGENTS.md.pre-refresh-*
  ( cd "$PROJECT" && bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$OUT.u1" )
  grep -q "WORKHUB-MANAGED" "$PROJECT/AGENTS.md" || fail "U1: refresh WIPED the operator's project value (data loss!)"
  grep -q "DRIFTED-FRAMEWORK-PROSE" "$PROJECT/AGENTS.md" && fail "U1: framework prose drift survived the refresh (block not refreshed)" || true
  [ "$(ffcf_count_marker "$PROJECT/AGENTS.md" "$FFCF_MB")" -eq 1 ] || fail "U1: BEGIN count not 1 after preserve-carry refresh"
  pass "U1: refresh preserves operator FLOW:PRESERVE values while refreshing framework prose"
}
