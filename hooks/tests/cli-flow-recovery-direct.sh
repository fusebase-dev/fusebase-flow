#!/usr/bin/env bash
# Fusebase Flow — cli-flow-recovery: DIRECT + MIGRATION module (sourced, never run).
# WHY-home: docs/specs/backlog-triage-execution/architecture-review.md § Q2 (step 4).
#
# TRIPWIRE — U7 and U9 share ONE tree and ONE --refresh-overlays run because they migrate two
# DIFFERENT files (legacy marker-less CLAUDE.md; pre-FLOW:PRESERVE AGENTS.md) that the recovery
# handles in independent steps. Both predicates keep their own assertions and their own result
# line. Merge nothing else here: every other run in this module changes a different input.
#
# TRIPWIRE — the reduced fixture is only safe while production BREADTH is proven elsewhere.
# ffcf_production_breadth is that proof and must never be deleted alongside a fixture change.

# B3 / final-architecture-review finding 3: predicate 32 used to run ONE read-only
# `mirror-skills.sh --check` over the already-mirrored real tree. Parity on a clean tree cannot
# see a defect in WRITE mode (mirror-skills.sh Phase 3-write: the mkdir/cp loop, the in-memory
# row accumulation, the LC_ALL=C sort, the atomic temp+rename) — and write mode is the half a
# 4-skill fixture would never stress at scale. The predicate now RUNS production write mode over
# the whole canonical corpus and asserts its return code, its output, and that it reproduces the
# COMMITTED manifest byte for byte.
#
# TRIPWIRE (cost, and why the write happens in a copy): the write is ~2 spawns per mirrored file
# (mkdir + cp) x 98 files — the single most expensive thing in this phase on MSYS, measured at
# 6m49s on a loaded host and dominating the phase budget. Do NOT add a second full-corpus write.
# The mutation below deliberately runs on the REDUCED corpus: the full run proves BREADTH, the
# mutation proves the assertions are not vacuous. Running it in a copy (never $ROOT) also keeps
# the phase read-only with respect to the repository.
ffcf_production_breadth() {
  local real=0 sd out rc d files
  for sd in "$ROOT"/flow-skills/*/; do [ -f "$sd/SKILL.md" ] && real=$((real + 1)); done
  [ "$real" -gt "${#FFCF_SKILL_NAMES[@]}" ] \
    || fail "breadth guard is vacuous: production has $real canonical skills, the fixture has ${#FFCF_SKILL_NAMES[@]}"

  # (1) read-only parity over the real tree — the original claim, unchanged.
  out="$( cd "$ROOT" && bash hooks/local/mirror-skills.sh --check 2>&1 )" \
    || { printf '%s\n' "$out" >&2; fail "production breadth: mirror-skills.sh --check reported drift across the full $real-skill tree"; }
  printf '%s' "$out" | grep -qF "0 drift ($real skill(s)" \
    || { printf '%s\n' "$out" >&2; fail "production breadth: --check did not confirm 0 drift over all $real canonical skills"; }
  pass "production breadth: mirror-skills.sh --check is 0-drift over all $real canonical skills (reduced fixture hides nothing)"

  # (2) production RECOVERY/WRITE mode over the full corpus, rc asserted.
  d="$TMP_BASE/production-write"
  mkdir -p "$d/hooks/local"
  cp -R "$ROOT/flow-skills" "$d/flow-skills"
  cp "$ROOT/hooks/local/mirror-skills.sh" "$d/hooks/local/"
  set +e
  ( cd "$d" && bash hooks/local/mirror-skills.sh > "$TMP_BASE/prodwrite.out" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { cat "$TMP_BASE/prodwrite.out" >&2; fail "production write: mirror-skills.sh exited $rc over the full $real-skill corpus (a nonzero recovery rc must never be discarded — MAJOR 5)"; }
  grep -qF "mirroring $real skill(s)" "$TMP_BASE/prodwrite.out" \
    || { cat "$TMP_BASE/prodwrite.out" >&2; fail "production write: the run did not report all $real canonical skills"; }

  # Every mirror file the manifest names must exist on disk in BOTH provider mirrors.
  files="$(wc -l < "$ROOT/audit/skill-mirror-manifest.txt" | tr -d ' ')"
  local rel missing=0
  while IFS= read -r rel; do
    rel="${rel%%  *}"
    [ -n "$rel" ] || continue
    [ -f "$d/$rel" ] || missing=$((missing + 1))
  done < "$ROOT/audit/skill-mirror-manifest.txt"
  [ "$missing" -eq 0 ] || fail "production write: $missing of $files mirrored files were not produced by write mode over the full corpus"

  # (3) the freshly WRITTEN tree must be self-consistent, and (4) byte-identical to what is
  # committed — so write mode over the production corpus reproduces the committed artifact
  # exactly. A locale-dependent sort, a lost row, or a duplicated row fails here and CANNOT
  # be reached by parity on an already-mirrored tree.
  out="$( cd "$d" && bash hooks/local/mirror-skills.sh --check 2>&1 )" \
    || { printf '%s\n' "$out" >&2; fail "production write: --check reported drift in the tree write mode had just produced"; }
  diff -q "$d/audit/skill-mirror-manifest.txt" "$ROOT/audit/skill-mirror-manifest.txt" >/dev/null 2>&1 \
    || fail "production write: the manifest produced over the full corpus is not byte-identical to the committed audit/skill-mirror-manifest.txt"
  pass "production write: mirror-skills.sh write mode over all $real canonical skills exits 0, materializes all $files mirror files, and reproduces the committed manifest byte for byte"

  # (5) RETAINED RED-BEFORE MUTATION — a WRITE-ONLY defect must be caught. The mutation is the
  # recorded incident (concurrent per-row appends producing duplicated manifest rows, which the
  # hash-based --check on a clean tree could not see). Run on the REDUCED corpus on purpose: the
  # full run above owns breadth, this owns "the assertions are not vacuous". If this mutation
  # ever stops being caught, assertions (3)/(4) have gone decorative.
  local m="$TMP_BASE/mutant"
  mkdir -p "$m/hooks/local" "$m/flow-skills"
  local sn
  for sn in "${FFCF_SKILL_NAMES[@]}"; do
    [ -d "$ROOT/flow-skills/$sn" ] && cp -R "$ROOT/flow-skills/$sn" "$m/flow-skills/"
  done
  sed 's#"$manifest_rows" | LC_ALL=C sort#"$manifest_rows$manifest_rows" | LC_ALL=C sort#' \
      "$ROOT/hooks/local/mirror-skills.sh" > "$m/hooks/local/mirror-skills.sh"
  grep -q '"$manifest_rows$manifest_rows"' "$m/hooks/local/mirror-skills.sh" \
    || fail "production write mutation: the manifest-write anchor no longer matches, so the mutation was not applied — an unapplied mutation proves nothing"
  set +e
  ( cd "$m" && bash hooks/local/mirror-skills.sh >/dev/null 2>&1 )
  ( cd "$m" && bash hooks/local/mirror-skills.sh --check > "$TMP_BASE/mutant-check.out" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { cat "$TMP_BASE/mutant-check.out" >&2; fail "production write mutation: a writer that duplicates every manifest row still produced a 0-drift tree — the write-mode assertions cannot see a write-only defect"; }
  pass "production write mutation: a duplicate-row manifest writer is caught (write-only defect class; parity on a clean tree cannot reach it)"
}

# U14 — --wire-hooks must wire stop.py (not a copied CLI command) onto a Stop chain that already
# has CLI hooks, when discovering the Flow config from the upstream example (whose Stop chain
# lists CLI hooks BEFORE stop.py). Regression for the handlers[0] discovery bug.
ffcf_u14_wire_stop() {
  local d="$TMP_BASE/u14-wirestop"
  mkdir -p "$d/.fusebase-flow-source/.claude" "$d/.claude/hooks" "$d/hooks/local/fusebase-flow-overlays"
  cp hooks/local/fusebase-flow-overlays/settings-json-merge.py "$d/hooks/local/fusebase-flow-overlays/"
  cp .claude/settings.json.example "$d/.fusebase-flow-source/.claude/settings.json.example"
  printf '// cli\n' > "$d/.claude/hooks/run-typecheck-apps.js"
  printf '// cli\n' > "$d/.claude/hooks/quality-check-apps.js"
  cat > "$d/.claude/settings.json" <<'EOF'
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/run-typecheck-apps.js", "timeout": 300 },
  { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-check-apps.js", "timeout": 30 }
] } ] } }
EOF
  ( cd "$d" && "$python_bin" hooks/local/fusebase-flow-overlays/settings-json-merge.py .claude/settings.json >/dev/null 2>&1 )
  ffcf_json_assert "$d/.claude/settings.json" "U14: --wire-hooks did not wire stop.py onto an existing CLI Stop chain" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
chain = d["hooks"]["Stop"][0]["hooks"]
flow = [h for h in chain if "Fusebase Flow stop hook" in h.get("statusMessage", "")]
assert flow, "no Flow-labeled Stop entry produced"
assert "hooks/handlers/stop.py" in flow[0]["command"], f"Flow Stop entry has the WRONG command (handlers[0] bug): {flow[0]['command']}"
assert any("hooks/handlers/stop.py" in h.get("command", "") for h in chain), "stop.py missing from Stop chain"
assert sum("run-typecheck-apps.js" in h.get("command", "") for h in chain) == 1, "CLI typecheck duplicated or dropped"
PY
  pass "U14: --wire-hooks wires stop.py (not a CLI command) onto an existing CLI Stop chain (discovery picks the Flow handler)"
}

# U15 — eslint-ignore-flow-paths.sh adds .fusebase-flow-source/** next to .claude/** so the
# staged upstream clone (CommonJS CLI hooks) doesn't fail the downstream's ESLint flat config
# (which doesn't honor .gitignore) -> deploy lint.
ffcf_u15_eslint() {
  local d="$TMP_BASE/u15-eslint"
  mkdir -p "$d/hooks/local"
  cp hooks/local/eslint-ignore-flow-paths.sh "$d/hooks/local/"
  cat > "$d/eslint.config.mjs" <<'EOF'
export default [
  {
    ignores: [
      "node_modules/**",
      "**/dist/**",
      ".claude/**"
    ],
  }
];
EOF
  ( cd "$d" || exit 1; git init -q 2>/dev/null || true; bash hooks/local/eslint-ignore-flow-paths.sh >/dev/null 2>&1 )
  grep -q '"\.fusebase-flow-source/\*\*"' "$d/eslint.config.mjs" || fail "U15: helper did not add .fusebase-flow-source/** to eslint ignores"
  # .claude/** must now carry a trailing comma (it's no longer last)
  grep -qE '"\.claude/\*\*",' "$d/eslint.config.mjs" || fail "U15: .claude/** entry not comma-terminated after insert (broken array)"
  cp "$d/eslint.config.mjs" "$d/eslint.config.mjs.snap"
  ( cd "$d" && bash hooks/local/eslint-ignore-flow-paths.sh >/dev/null 2>&1 )
  diff -q "$d/eslint.config.mjs" "$d/eslint.config.mjs.snap" >/dev/null 2>&1 || fail "U15: helper is not idempotent (second run changed the file)"
  pass "U15: eslint-ignore-flow-paths.sh adds .fusebase-flow-source/** next to .claude/** (idempotent, array stays valid)"
}

# U7 + U9 — the two LEGACY overlay migrations, one tree, one --refresh-overlays run.
#   U7: a pre-3.6.0 marker-LESS CLAUDE.md (bare '---' then the heading) migrates to exactly one
#       wrapped block with no doubled '---' rule.
#   U9: a 3.7.0-era AGENTS.md (CUSTOM:SKILL-wrapped, WITH the ### Project-specific values table
#       but WITHOUT FLOW:PRESERVE markers, and a customized value) must SEED the new preserve
#       region from that legacy table — the first preserve-aware upgrade has to be LOSSLESS.
ffcf_legacy_overlays() {
  local d="$TMP_BASE/legacy-overlays" rules
  ffcf_canonical "$d"
  ffcf_engine_scripts "$d"
  cat > "$d/CLAUDE.md" <<'EOF'
# Legacy CLAUDE

project rules here

---

## Fusebase Flow — additional rules (overlay)

old stale body
EOF
  {
    printf '# pre-upgrade AGENTS\n\nCURRENT CLI AGENTS SENTINEL\n'
    sed -E -e '/<!-- FLOW:PRESERVE:BEGIN/d' -e '/<!-- FLOW:PRESERVE:END -->/d' \
        -e 's/\| Project name \| [^|]*\|/| Project name | SEEDED-FROM-LEGACY |/' \
        "$d/hooks/local/fusebase-flow-overlays/agents-md-overlay.md"
  } > "$d/AGENTS.md"
  # Preconditions: CUSTOM:SKILL present, FLOW:PRESERVE absent, legacy value set.
  [ "$(ffcf_count_marker "$d/AGENTS.md" "$FFCF_MB")" -eq 1 ] || fail "U9 precondition: expected 1 CUSTOM:SKILL:BEGIN"
  grep -q "<!-- FLOW:PRESERVE:BEGIN" "$d/AGENTS.md" && fail "U9 precondition: pre-upgrade block should have NO FLOW:PRESERVE markers" || true
  grep -q "SEEDED-FROM-LEGACY" "$d/AGENTS.md" || fail "U9 setup: could not set the legacy project value"

  set +e
  ( cd "$d" && bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$TMP_BASE/legacy.out" 2>&1 )
  set -e

  [ "$(ffcf_count_marker "$d/CLAUDE.md" "$FFCF_MB")" -eq 1 ] || fail "U7: legacy migration did not produce exactly 1 BEGIN ($(ffcf_count_marker "$d/CLAUDE.md" "$FFCF_MB"))"
  rules="$(awk '/^## Fuse[bB]ase Flow — additional rules/{exit} /^[[:space:]]*---[[:space:]]*$/{c++} END{print c+0}' "$d/CLAUDE.md")"
  [ "$rules" -le 1 ] || fail "U7: $rules '---' rules before the heading (expected <=1; doubled-rule regression)"
  pass "U7: legacy marker-less CLAUDE.md migrates to a single wrapped block (no doubled ---)"

  grep -q "SEEDED-FROM-LEGACY" "$d/AGENTS.md" || fail "U9: first preserve-aware upgrade RESET the legacy project value (lossy transition!)"
  grep -q "<!-- FLOW:PRESERVE:BEGIN" "$d/AGENTS.md" || fail "U9: refresh did not add FLOW:PRESERVE markers (no migration)"
  [ "$(ffcf_count_marker "$d/AGENTS.md" "$FFCF_MB")" -eq 1 ] || fail "U9: BEGIN count not 1 after legacy seed"
  pass "U9: first preserve-aware upgrade seeds the new FLOW:PRESERVE region from the legacy table (lossless)"
}

# Invalid .claude/settings.json under --wire-hooks: warn, restore the original, exit 1, leave no
# backup. The merge path is opt-in, so the invalid-JSON handling is only reachable with the flag.
ffcf_bad_settings() {
  local d="$TMP_BASE/bad-settings" rc
  ffcf_canonical "$d"
  ffcf_engine_scripts "$d"
  printf '# FuseBase CLI project\n' > "$d/AGENTS.md"
  printf '# FuseBase CLI Claude instructions\n' > "$d/CLAUDE.md"
  mkdir -p "$d/.claude"
  printf '{ invalid json\n' > "$d/.claude/settings.json"
  set +e
  ( cd "$d" && bash hooks/local/post-fusebase-update.sh --wire-hooks > "$TMP_BASE/bad-settings.out" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] || fail "invalid settings recovery should return 1, got $rc"
  grep -q "\[post-fusebase-update\] Summary" "$TMP_BASE/bad-settings.out" || fail "invalid settings recovery did not print summary"
  [ ! -f "$d/.claude/settings.json.pre-flow-merge" ] || fail "invalid settings recovery left backup behind"
  grep -q "{ invalid json" "$d/.claude/settings.json" || fail "invalid settings recovery did not restore original settings"
  pass "invalid settings merge (--wire-hooks) reports warning and cleans backup"
}

# U20 (v3.9.0) — the REAL upgrade.sh migration, run on THE single full-tree clone: a pre-3.9.0
# install on root skills/ upgrades against a source shipping flow-skills/. Afterwards the
# canonical must live at flow-skills/, root skills/ must be retired (with a backup), and the
# provider mirrors must be regenerated. Exercises the actual migration code path (step 1b).
ffcf_u20_migration() {
  local d="$FFCF_SNAPSHOT" rc
  mv "$d/flow-skills" "$d/skills"                       # look pre-3.9.0: canonical at root skills/
  cp hooks/local/upgrade.sh "$d/hooks/local/"
  cp hooks/local/sync-version-strings.sh "$d/hooks/local/" 2>/dev/null || true
  mkdir -p "$d/.fusebase-flow-source"
  cp -R "$d/skills" "$d/.fusebase-flow-source/flow-skills"   # upstream ships the NEW layout
  cp VERSION "$d/.fusebase-flow-source/VERSION"
  set +e
  ( cd "$d" && bash hooks/local/upgrade.sh --auto-yes > "$TMP_BASE/u20.out" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { cat "$TMP_BASE/u20.out" >&2; fail "U20: upgrade.sh exited $rc during migration"; }
  local f
  for f in "${FFCF_SKILL_FILES[@]}"; do
    [ -f "$d/flow-skills/$f" ] || fail "U20: canonical flow-skills/$f not present after migration"
  done
  [ ! -d "$d/skills" ] || fail "U20: legacy root skills/ was NOT retired by the migration"
  ls -d "$d"/skills.pre-upgrade-* >/dev/null 2>&1 || fail "U20: migration did not back up the retired skills/ (skills.pre-upgrade-*)"
  ffcf_assert_mirrors "$d" "U20"
  grep -q "retired legacy root skills/" "$TMP_BASE/u20.out" || fail "U20: upgrade.sh did not report the canonical migration"
  # Idempotency: a second run is a no-op for migration (no skills/ to retire).
  set +e
  ( cd "$d" && bash hooks/local/upgrade.sh --auto-yes > "$TMP_BASE/u20b.out" 2>&1 )
  set -e
  [ ! -d "$d/skills" ] || fail "U20: second upgrade run re-created root skills/"
  pass "U20: upgrade.sh migrates root skills/ -> flow-skills/ (retires old dir w/ backup, re-mirrors, idempotent)"
}

ffcf_direct_run() {
  ffcf_production_breadth
  ffcf_u14_wire_stop
  ffcf_u15_eslint
  ffcf_legacy_overlays
  ffcf_bad_settings
  ffcf_u20_migration
}
