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
ffcf_tree_inventory() {
  "$python_bin" - "$@" <<'PY'
import hashlib, json, pathlib, sys
root, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
paths = []
for rel in sys.argv[3:]:
    path = root / rel
    paths.extend(item for item in path.rglob("*") if item.is_file()) if path.is_dir() else paths.append(path)
doc = {str(path.relative_to(root)).replace("\\", "/"): [
    hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns]
    for path in sorted(set(paths)) if path.is_file()}
out.write_text(json.dumps(doc, sort_keys=True), encoding="utf-8")
PY
}

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
  mkdir -p "$d/hooks/local/lib"
  cp -R "$ROOT/flow-skills" "$d/flow-skills"
  cp "$ROOT/hooks/local/mirror-skills.sh" "$d/hooks/local/"
  cp "$ROOT/hooks/local/lib/recovery-owned-write.py" "$d/hooks/local/lib/"
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

  ffcf_tree_inventory "$d" "$TMP_BASE/skills-before.json" audit/skill-mirror-manifest.txt .agents/skills .claude/skills
  ( cd "$d" && bash hooks/local/mirror-skills.sh > "$TMP_BASE/skills-noop.out" 2>&1 )
  ffcf_tree_inventory "$d" "$TMP_BASE/skills-after.json" audit/skill-mirror-manifest.txt .agents/skills .claude/skills
  diff -q "$TMP_BASE/skills-before.json" "$TMP_BASE/skills-after.json" >/dev/null 2>&1 \
    || fail "T4: full-corpus skill no-op changed mirror or manifest bytes/mtimes"
  grep -qF "copied 0;" "$TMP_BASE/skills-noop.out" \
    || fail "T4: full-corpus skill no-op did not report zero copies"
  printf '\nT13 OWNED UPDATE\n' >> "$d/flow-skills/communication/SKILL.md"
  ( cd "$d" && bash hooks/local/mirror-skills.sh > "$TMP_BASE/skills-repair.out" 2>&1 )
  grep -qF "copied 2;" "$TMP_BASE/skills-repair.out" \
    || fail "T13: one canonical skill update did not repair both owned mirrors"
  for target in .agents/skills .claude/skills; do
    diff -q "$d/flow-skills/communication/SKILL.md" "$d/$target/communication/SKILL.md" >/dev/null 2>&1 \
      || fail "T13: canonical skill update did not repair $target"
  done
  pass "T13: full-corpus skill mirrors are zero-write on no-op; one canonical update repairs both owned targets"

  local a="$TMP_BASE/agent-write"
  mkdir -p "$a/hooks/local/lib"
  cp -R "$ROOT/agents" "$a/agents"
  cp "$ROOT/hooks/local/mirror-agents.sh" "$a/hooks/local/"
  cp "$ROOT/hooks/local/lib/recovery-owned-write.py" "$a/hooks/local/lib/"
  ( cd "$a" && bash hooks/local/mirror-agents.sh > "$TMP_BASE/agents-first.out" 2>&1 )
  ffcf_tree_inventory "$a" "$TMP_BASE/agents-before.json" audit/agent-mirror-manifest.txt .claude/agents .codex/agents
  ( cd "$a" && bash hooks/local/mirror-agents.sh > "$TMP_BASE/agents-noop.out" 2>&1 )
  ffcf_tree_inventory "$a" "$TMP_BASE/agents-after.json" audit/agent-mirror-manifest.txt .claude/agents .codex/agents
  diff -q "$TMP_BASE/agents-before.json" "$TMP_BASE/agents-after.json" >/dev/null 2>&1 \
    || fail "T4: agent no-op changed mirror or manifest bytes/mtimes"
  grep -qF "copied 0;" "$TMP_BASE/agents-noop.out" \
    || fail "T4: agent no-op did not report zero copies"
  printf '\nT13 OWNED UPDATE\n' >> "$a/agents/ai-developer/AGENT.md"
  ( cd "$a" && bash hooks/local/mirror-agents.sh > "$TMP_BASE/agents-repair.out" 2>&1 )
  grep -qF "copied 2;" "$TMP_BASE/agents-repair.out" \
    || fail "T13: one canonical agent update did not repair both owned mirrors"
  for target in .claude/agents .codex/agents; do
    diff -q "$a/agents/ai-developer/AGENT.md" "$a/$target/ai-developer.md" >/dev/null 2>&1 \
      || fail "T13: canonical agent update did not repair $target"
  done
  pass "T13: agent mirrors are zero-write on no-op; one canonical update repairs both owned targets"

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
  mkdir -p "$m/hooks/local/lib"
  cp "$ROOT/hooks/local/lib/recovery-owned-write.py" "$m/hooks/local/lib/"
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

ffcf_t13_owned_write_matrix() {
  local d="$TMP_BASE/t13-owned-write" plan result target before rc surface
  ffcf_path_fingerprint() {
    "$python_bin" -c 'import hashlib,pathlib,sys; p=pathlib.Path(sys.argv[1]); print(f"{hashlib.sha256(p.read_bytes()).hexdigest()}:{p.stat().st_mtime_ns}")' "$1"
  }
  mkdir -p "$d/hooks/local/lib" "$d/sources"
  cp "$ROOT/hooks/local/lib/recovery-owned-write.py" "$d/hooks/local/lib/"
  for surface in skill agent command health-skill; do
    printf '%s\n' "$surface-v1" > "$d/sources/$surface.txt"
    target="targets/$surface.txt"
    plan="$d/$surface.plan"
    result="$d/$surface.result"
    printf '%s\t%s\n' "$d/sources/$surface.txt" "$target" > "$plan"
    "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
      --surface "$surface" --plan "$plan" --result "$result"
    grep -q $'^missing-and-authorized\t'"$target" "$result" \
      || fail "T13: $surface missing target was not authorized"
    before="$(ffcf_path_fingerprint "$d/$target")"
    "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
      --surface "$surface" --plan "$plan" --result "$result"
    [ "$before" = "$(ffcf_path_fingerprint "$d/$target")" ] || fail "T13: $surface current target changed mtime"
    printf '%s\n' "$surface-v2" > "$d/sources/$surface.txt"
    "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
      --surface "$surface" --plan "$plan" --result "$result"
    grep -q $'^owned-repair\t'"$target" "$result" \
      || fail "T13: $surface prior ownership did not permit repair"
    [ -f "$d/$target.pre-flow-repair" ] || fail "T13: $surface repair retained no original"
  done

  printf 'unowned\n' > "$d/targets/unowned.txt"
  printf 'source\n' > "$d/sources/unowned.txt"
  printf '%s\t%s\n' "$d/sources/unowned.txt" targets/unowned.txt > "$d/unowned.plan"
  before="$(ffcf_path_fingerprint "$d/targets/unowned.txt")"
  set +e
  "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
    --surface skill --plan "$d/unowned.plan" --result "$d/unowned.result"
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && [ "$before" = "$(ffcf_path_fingerprint "$d/targets/unowned.txt")" ] \
    || fail "T13: unowned collision was modified or returned rc=$rc"

  mkdir -p "$d/targets/type-mismatch"
  printf '%s\t%s\n' "$d/sources/unowned.txt" targets/type-mismatch > "$d/type.plan"
  set +e
  "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
    --surface agent --plan "$d/type.plan" --result "$d/type.result"
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && [ -d "$d/targets/type-mismatch" ] \
    || fail "T13: target type mismatch was overwritten or returned rc=$rc"

  printf 'link-target\n' > "$d/targets/link-target.txt"
  if ln -s link-target.txt "$d/targets/link.txt" 2>/dev/null && [ -L "$d/targets/link.txt" ]; then
    printf '%s\t%s\n' "$d/sources/unowned.txt" targets/link.txt > "$d/link.plan"
    before="$(ffcf_path_fingerprint "$d/targets/link-target.txt")"
    set +e
    "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
      --surface command --plan "$d/link.plan" --result "$d/link.result"
    rc=$?
    set -e
    [ "$rc" -eq 1 ] && [ "$before" = "$(ffcf_path_fingerprint "$d/targets/link-target.txt")" ] \
      || fail "T13: symlink destination or target was modified"
  fi

  printf '%s\t%s\n' "$d/sources/unowned.txt" targets/interrupted.txt > "$d/interrupted.plan"
  set +e
  FF_RECOVERY_WRITE_INTERRUPT='before-replace:targets/interrupted.txt' \
    "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
      --surface skill --plan "$d/interrupted.plan" --result "$d/interrupted.result"
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && [ ! -e "$d/targets/interrupted.txt" ] \
    || fail "T13: before-replace interruption changed target"
  "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
    --surface skill --plan "$d/interrupted.plan" --result "$d/interrupted.result"
  printf 'source-v2\n' > "$d/sources/unowned.txt"
  set +e
  FF_RECOVERY_WRITE_INTERRUPT='after-retain:targets/interrupted.txt' \
    "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
      --surface skill --plan "$d/interrupted.plan" --result "$d/interrupted.result"
  rc=$?
  set -e
  [ "$rc" -eq 1 ] && grep -q '^source$' "$d/targets/interrupted.txt" \
    && [ -f "$d/targets/interrupted.txt.pre-flow-repair" ] \
    || fail "T13: after-retain interruption did not preserve original target"
  "$python_bin" "$d/hooks/local/lib/recovery-owned-write.py" --root "$d" \
    --surface skill --plan "$d/interrupted.plan" --result "$d/interrupted.result"
  grep -q '^source-v2$' "$d/targets/interrupted.txt" || fail "T13: retry did not converge"
  pass "T13: skill/agent/command/health ownership, atomic repair, collisions, symlink, interruption, and retry"
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
  [ "$rc" -eq 2 ] || fail "invalid settings recovery should return 2, got $rc"
  grep -q "recovery plan validation failed" "$TMP_BASE/bad-settings.out" || fail "invalid settings recovery did not report prevalidation failure"
  [ ! -f "$d/.claude/settings.json.pre-flow-merge" ] || fail "invalid settings recovery left backup behind"
  grep -q "{ invalid json" "$d/.claude/settings.json" || fail "invalid settings recovery did not restore original settings"
  pass "invalid settings merge (--wire-hooks) fails prevalidation without target writes"
}

ffcf_t4_health_fallback() {
  local d="$TMP_BASE/t4-health-fallback" snapshot hash rc health_target command_target health_before command_before
  ffcf_collision_fingerprint() {
    "$python_bin" -c 'import hashlib,pathlib,sys; p=pathlib.Path(sys.argv[1]); print(f"{hashlib.sha256(p.read_bytes()).hexdigest()}:{p.stat().st_mtime_ns}")' "$1"
  }
  ffcf_canonical "$d"
  rm -rf "$d/flow-skills/fusebase-flow-health-check"
  ffcf_engine_scripts "$d"
  ffcf_root_docs "$d"
  ffcf_apply_overlays "$d"
  ffcf_settings_hooksoff "$d"
  snapshot="hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md"
  hash="$(sha_cmd "$d/$snapshot")"
  mkdir -p "$d/audit"
  printf '{"assets":[{"path":"%s","sha256":"%s"}]}\n' "$snapshot" "$hash" \
    > "$d/audit/managed-content-manifest.json"
  ( cd "$d" && bash hooks/local/post-fusebase-update.sh > "$TMP_BASE/t4-fallback.out" 2>&1 )
  for m in .claude/skills .agents/skills; do
    diff -q "$d/$snapshot" "$d/$m/fusebase-flow-health-check/SKILL.md" >/dev/null 2>&1 \
      || fail "T4: ownership-verified health snapshot did not restore $m fallback"
  done
  grep -q "ownership-verified recovery snapshot" "$TMP_BASE/t4-fallback.out" \
    || fail "T4: verified health fallback was not reported"

  health_target="$d/.claude/skills/fusebase-flow-health-check/SKILL.md"
  command_target="$d/.claude/commands/${FFCF_COMMANDS[0]}"
  printf 'UNOWNED HEALTH COLLISION\n' > "$health_target"
  printf 'UNOWNED COMMAND COLLISION\n' > "$command_target"
  health_before="$(ffcf_collision_fingerprint "$health_target")"
  command_before="$(ffcf_collision_fingerprint "$command_target")"
  set +e
  ( cd "$d" && bash hooks/local/post-fusebase-update.sh > "$TMP_BASE/t13-target-collisions.out" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] \
    && [ "$health_before" = "$(ffcf_collision_fingerprint "$health_target")" ] \
    && [ "$command_before" = "$(ffcf_collision_fingerprint "$command_target")" ] \
    || fail "T13: post-update changed an unowned health/command collision or returned rc=$rc"
  grep -q 'health-skill target preserved' "$TMP_BASE/t13-target-collisions.out" \
    && grep -q 'command target preserved' "$TMP_BASE/t13-target-collisions.out" \
    || fail "T13: post-update did not report both preserved target collisions"
  pass "T13: post-update preserves unowned health and command collisions byte/mtime-exactly and returns partial"

  printf '\nUNOWNED DRIFT\n' >> "$d/$snapshot"
  rm -f "$d/.claude/skills/fusebase-flow-health-check/SKILL.md"
  set +e
  ( cd "$d" && bash hooks/local/post-fusebase-update.sh > "$TMP_BASE/t4-unowned.out" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 1 ] || fail "T4: unowned health snapshot should return partial rc=1, got $rc"
  [ ! -f "$d/.claude/skills/fusebase-flow-health-check/SKILL.md" ] \
    || fail "T4: unowned health snapshot superseded the missing canonical source"
  pass "T4: health snapshot is fallback-only and requires manifest-verified ownership"
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

ffcf_t1_overlay_spans() {
  "$python_bin" - "$ROOT/hooks/local/fusebase-flow-overlays/overlay-block-replace.py" "$TMP_BASE/t1-overlay" <<'PY'
import importlib.util
from pathlib import Path
import sys

helper = Path(sys.argv[1])
work = Path(sys.argv[2])
work.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location("overlay_replace", helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

heading = "## FuseBase Flow — workflow lifecycle overlay"
legacy = ("## Fusebase Flow — workflow lifecycle overlay",)
template = Path("hooks/local/fusebase-flow-overlays/agents-md-overlay.md").resolve()
template_bytes = template.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
customized = template_bytes.replace(
    b"| Project name | (run `/onboard` or edit) |",
    "| Project name | München-東京 |".encode(),
)
customized = customized.replace(b"Provider adapters point here", b"STALE Flow adapter pointer")
prefix = b"CLI-PREFIX-\xc3\xa9\r\n<!-- CUSTOM:SKILL:BEGIN -->\r\nUNRELATED-A\r\n<!-- CUSTOM:SKILL:END -->\r\n"
suffix = b"\r\nCLI-SUFFIX-\xe6\x9d\xb1\xe4\xba\xac\r\n<!-- CUSTOM:SKILL:BEGIN -->\r\nUNRELATED-B\r\n<!-- CUSTOM:SKILL:END -->\r\n"
target = work / "AGENTS.md"
backup = work / "AGENTS.backup"
target.write_bytes(prefix + customized + suffix)
preserve_start = customized.index(module.PRESERVE_BEGIN)
preserve_end = customized.index(module.PRESERVE_END) + len(module.PRESERVE_END)
preserve = customized[preserve_start:preserve_end]

assert module.replace_overlay(target, template, heading, legacy, backup) == "refreshed"
updated = target.read_bytes()
assert updated.startswith(prefix)
assert updated.endswith(suffix)
assert preserve in updated
assert b"STALE Flow adapter pointer" not in updated
assert b"\n" not in updated.replace(b"\r\n", b"")
mtime = target.stat().st_mtime_ns
backup_mtime = backup.stat().st_mtime_ns
assert module.replace_overlay(target, template, heading, legacy, backup) == "current"
assert target.stat().st_mtime_ns == mtime
assert backup.stat().st_mtime_ns == backup_mtime

def refused(name, data):
    candidate = work / name
    candidate.write_bytes(data)
    before = candidate.read_bytes()
    try:
        module.replace_overlay(candidate, template, heading, legacy, work / f"{name}.backup")
    except module.OverlayError:
        pass
    else:
        raise AssertionError(f"{name}: ambiguous input was accepted")
    assert candidate.read_bytes() == before
    assert not (work / f"{name}.backup").exists()

flow = template_bytes
refused("duplicate-heading.md", flow + suffix + flow)
refused("nested.md", flow.replace(module.BEGIN, module.BEGIN + b"\r\n" + module.BEGIN, 1))
refused("unbalanced.md", flow.replace(module.END, b"", 1))
refused(
    "duplicate-preserve.md",
    flow.replace(module.PRESERVE_END, module.PRESERVE_END + b"\r\n" + module.PRESERVE_END, 1),
)

atomic = work / "atomic.md"
atomic.write_bytes(customized)
atomic_before = atomic.read_bytes()
atomic_backup = work / "atomic.backup"
def fail_replace(_source, _target):
    raise OSError("injected replace failure")
try:
    module.replace_overlay(
        atomic, template, heading, legacy, atomic_backup, replace_fn=fail_replace
    )
except OSError:
    pass
else:
    raise AssertionError("atomic failure injection did not fail")
assert atomic.read_bytes() == atomic_before
assert atomic_backup.read_bytes() == atomic_before
PY
  pass "T1: exact overlay span preserves prefix/suffix/CRLF/Unicode/FLOW:PRESERVE, rejects ambiguity, and is atomic/idempotent"
}

ffcf_direct_run() {
  ffcf_t1_overlay_spans
  ffcf_t13_owned_write_matrix
  ffcf_production_breadth
  ffcf_u14_wire_stop
  ffcf_u15_eslint
  ffcf_legacy_overlays
  ffcf_bad_settings
  ffcf_t4_health_fallback
  ffcf_u20_migration
}
