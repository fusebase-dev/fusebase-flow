#!/usr/bin/env bash
# Fusebase Flow — S1: the hook-wiring intent marker + the health engine's PreToolUse
# enforcement arm.
#
# The defect: a tree whose .claude/settings.json was wholesale-rewritten (every Flow
# lifecycle hook stripped) is INDISTINGUISHABLE from a tree that never opted in — the
# engine keyed only on the event-key count and on stop.py, and reported LOCAL_OK either
# way. This phase proves the marker separates "never opted in" from "opted in then
# stripped", and — the part that matters more — proves the six states in which the marker
# can LIE never produce a false DRIFT.
#
# Enforcement presence is the CANONICAL HANDLER, never the event key: the substring
# `hooks/handlers/pre_tool_use.py` (the detection contract .claude/settings.json.example
# and settings-json-merge.py already document). A `"PreToolUse":` key pointing at
# something else is NOT wired.
#
# Output contract (parsed by run-tests.sh): "PASS: hook-wiring-intent <name>" /
# "FAIL: hook-wiring-intent <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/hook-wiring-intent.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: hook-wiring-intent $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: hook-wiring-intent $1 ($2)"; }
finish() { echo "[test-hook-wiring-intent] $pass/$((pass + fail)) PASS"; exit $fail; }

if [ ! -f "$LIB" ]; then
  bad "lib-present" "missing $LIB"; finish
fi
# shellcheck source=../local/lib/hook-wiring-intent.sh
. "$LIB"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

###############################################################################
# Harness — one fixture tree per row; the arm is called exactly as the engine
# calls it, with record_drift stubbed the way the engine defines it.
###############################################################################
mkfixture() {   # -> echoes a fresh fixture root (mktemp, NOT a counter: this runs in a
                # command substitution, so a shell-variable counter would never persist and
                # every row would silently share one tree)
  local d; d="$(mktemp -d "$TMP/fxXXXXXX")"
  mkdir -p "$d/.claude" "$d/state/audit"
  echo "$d"
}

wire_settings() {   # <root> — a settings.json with the canonical Flow PreToolUse handler
  cat > "$1/.claude/settings.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash|Edit|Write",
  "hooks": [ { "type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR\"/hooks/local/run-handler.sh \"$CLAUDE_PROJECT_DIR\"/hooks/handlers/pre_tool_use.py" } ] } ] } }
JSON
}

strip_settings() {   # <root> — CLI-regenerated settings: CLI hooks only, no Flow handler
  cat > "$1/.claude/settings.json" <<'JSON'
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command",
  "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/run-lint-on-stop.sh" } ] } ] } }
JSON
}

wrong_pretooluse() {   # <root> — the EVENT KEY exists but the chain is not Flow's handler
  cat > "$1/.claude/settings.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash",
  "hooks": [ { "type": "command", "command": "bash ./scripts/my-own-guard.sh" } ] } ] } }
JSON
}

# run_arm <root> — resets the engine-scope arrays, runs the arm, exposes the results.
run_arm() {
  LOCAL_OK=(); LOCAL_DRIFT=(); LOCAL_BROKEN=(); LOCAL_UNVERIFIED=(); LOCAL_DEFERRED=()
  DRIFT_IDS=()
  record_drift() { DRIFT_IDS+=("$1"); LOCAL_DRIFT+=("$2"); }
  ffhc_hwi_check "$1"
}

joined() { printf '%s\n' ${1+"$@"}; }

###############################################################################
# Row 1 — ENABLE: a successful --wire-hooks records intent; health reports wired.
###############################################################################
fx="$(mkfixture)"; wire_settings "$fx"
ffhc_hwi_record_wiring "$fx" 0 >/dev/null 2>&1
if [ -f "$fx/state/audit/flow-hook-wiring-intent.json" ]; then
  ok "enable-writes-marker"
else
  bad "enable-writes-marker" "no marker after a successful wire-hooks"
fi
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && [ "${#LOCAL_UNVERIFIED[@]}" -eq 0 ] \
   && joined "${LOCAL_OK[@]}" | grep -q "pre_tool_use.py"; then
  ok "enable-reads-wired"
else
  bad "enable-reads-wired" "drift=${#LOCAL_DRIFT[@]} unver=${#LOCAL_UNVERIFIED[@]} ok=$(joined "${LOCAL_OK[@]}")"
fi

###############################################################################
# Row 1b — the marker is written ONLY for a wiring the tree ACHIEVED: never after a
# failed/aborted merge, and never after a merge that exited 0 without wiring the handler.
# This is the writer's whole contract. The second half is the v4.14.0 defect: --wire-hooks
# exits 0 having applied every other change, so rc alone recorded intent with enforcement
# absent, and the health arm then prescribed the command that produced the state.
###############################################################################
fx="$(mkfixture)"; wire_settings "$fx"
ffhc_hwi_record_wiring "$fx" 1 >/dev/null 2>&1
if [ ! -f "$fx/state/audit/flow-hook-wiring-intent.json" ]; then
  ok "failed-merge-writes-nothing"
else
  bad "failed-merge-writes-nothing" "marker written after a nonzero merge exit"
fi
fx="$(mkfixture)"; wrong_pretooluse "$fx"
ffhc_hwi_record_wiring "$fx" 0 >/dev/null 2>&1; hwi_rc=$?
if [ ! -f "$fx/state/audit/flow-hook-wiring-intent.json" ] && [ "$hwi_rc" -ne 0 ]; then
  ok "unachieved-wiring-writes-nothing"
else
  bad "unachieved-wiring-writes-nothing" "rc=$hwi_rc, marker=$([ -f "$fx/state/audit/flow-hook-wiring-intent.json" ] && echo written || echo absent)"
fi

###############################################################################
# Row 2 — WHOLESALE STRIP: enabled intent + no Flow handler => DRIFT, stable
# check ID, and a recovery that NAMES --wire-hooks (the default recovery
# explicitly does not modify settings.json, so a bare recommendation is a
# dead end and the ticket would only relocate the forensics).
###############################################################################
fx="$(mkfixture)"; strip_settings "$fx"
# ffhc_hwi_write, not ffhc_hwi_record_wiring: the recorder now refuses to record a wiring it
# did not achieve, and this row's subject is a tree that opted in EARLIER and was stripped
# LATER — a state that arises over time, never in one call.
ffhc_hwi_write "$fx" true >/dev/null 2>&1
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 1 ]; then ok "strip-drifts"; else
  bad "strip-drifts" "expected 1 drift, got ${#LOCAL_DRIFT[@]}"; fi
if [ "${DRIFT_IDS[0]:-}" = "settings_json_flow_enforcement" ]; then ok "strip-check-id"; else
  bad "strip-check-id" "check_id=${DRIFT_IDS[0]:-<none>}"; fi
if joined "${LOCAL_DRIFT[@]}" | grep -q -- "--wire-hooks"; then ok "strip-recovery-names-wire-hooks"; else
  bad "strip-recovery-names-wire-hooks" "$(joined "${LOCAL_DRIFT[@]}")"; fi

###############################################################################
# Row 2b — WRONG PreToolUse: the event key is present, the canonical handler is
# not. Matching `"PreToolUse":` alone would call this wired; it is not.
###############################################################################
fx="$(mkfixture)"; wrong_pretooluse "$fx"
ffhc_hwi_write "$fx" true >/dev/null 2>&1   # opted in earlier, stripped later (see Row 2)
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 1 ]; then ok "wrong-pretooluse-drifts"; else
  bad "wrong-pretooluse-drifts" "expected 1 drift, got ${#LOCAL_DRIFT[@]}"; fi

###############################################################################
# Row 3 — DELIBERATE OPT-OUT: the revocation path clears the intent, so a tree
# that removed the block on purpose does NOT alarm. Intent needs a revocation
# lifecycle, not just a creation event.
###############################################################################
fx="$(mkfixture)"; strip_settings "$fx"
ffhc_hwi_write "$fx" true >/dev/null 2>&1   # opted in earlier, stripped later (see Row 2)
ffhc_hwi_revoke "$fx" >/dev/null 2>&1
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && [ "${#LOCAL_UNVERIFIED[@]}" -eq 0 ]; then
  ok "opt-out-no-drift"
else
  bad "opt-out-no-drift" "drift=$(joined "${LOCAL_DRIFT[@]}") unver=$(joined "${LOCAL_UNVERIFIED[@]}")"
fi

###############################################################################
# Row 4 — MALFORMED MARKER: presence alone must NOT imply opt-in. Every broken
# shape reads UNVERIFIED, never enforcement drift.
###############################################################################
for shape in empty garbage truncated wrong-schema no-enabled; do
  fx="$(mkfixture)"; strip_settings "$fx"
  case "$shape" in
    empty)       : > "$fx/state/audit/flow-hook-wiring-intent.json" ;;
    garbage)     printf 'not json at all\n' > "$fx/state/audit/flow-hook-wiring-intent.json" ;;
    truncated)   printf '{"schema_version": 1, "enabled": tru' > "$fx/state/audit/flow-hook-wiring-intent.json" ;;
    wrong-schema) printf '{"schema_version": 99, "enabled": true}\n' > "$fx/state/audit/flow-hook-wiring-intent.json" ;;
    no-enabled)  printf '{"schema_version": 1}\n' > "$fx/state/audit/flow-hook-wiring-intent.json" ;;
  esac
  run_arm "$fx"
  if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && [ "${#LOCAL_UNVERIFIED[@]}" -eq 1 ]; then
    ok "malformed-$shape-unverified-not-drift"
  else
    bad "malformed-$shape-unverified-not-drift" "drift=${#LOCAL_DRIFT[@]} unver=${#LOCAL_UNVERIFIED[@]}"
  fi
done

###############################################################################
# Row 5 — MISSING settings.json entirely + enabled intent => DRIFT. The engine's
# old arm had no `else` outside the file-exists condition, so this path did not
# exist at all.
###############################################################################
fx="$(mkfixture)"
ffhc_hwi_write "$fx" true >/dev/null 2>&1   # opted in earlier, settings.json deleted later
rm -f "$fx/.claude/settings.json"
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 1 ] && [ "${DRIFT_IDS[0]:-}" = "settings_json_flow_enforcement" ]; then
  ok "missing-settings-drifts"
else
  bad "missing-settings-drifts" "drift=${#LOCAL_DRIFT[@]} id=${DRIFT_IDS[0]:-<none>}"
fi

###############################################################################
# Row 6 — MANUAL WIRING, NO MARKER: `cp .claude/settings.json.example` on a host
# without python3 wires hooks but records no intent. Marker-absence means "not
# known to have opted in", never "definitely never opted in" — so this is
# today's line, unchanged, and NEVER drift. (The recorded false negative.)
###############################################################################
fx="$(mkfixture)"; wire_settings "$fx"
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && [ "${#LOCAL_UNVERIFIED[@]}" -eq 0 ] && [ "${#LOCAL_OK[@]}" -eq 0 ]; then
  ok "manual-wiring-unchanged"
else
  bad "manual-wiring-unchanged" "drift=${#LOCAL_DRIFT[@]} unver=${#LOCAL_UNVERIFIED[@]} ok=${#LOCAL_OK[@]}"
fi

###############################################################################
# Row 7 — LEGACY NO-MARKER TREES: any settings state, no marker => the arm is
# silent. A pre-marker checkout must not start alarming after an upgrade.
###############################################################################
for state in stripped absent wired-wrong; do
  fx="$(mkfixture)"
  case "$state" in
    stripped)    strip_settings "$fx" ;;
    absent)      rm -f "$fx/.claude/settings.json" ;;
    wired-wrong) wrong_pretooluse "$fx" ;;
  esac
  run_arm "$fx"
  if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && [ "${#LOCAL_UNVERIFIED[@]}" -eq 0 ]; then
    ok "legacy-$state-silent"
  else
    bad "legacy-$state-silent" "drift=${#LOCAL_DRIFT[@]} unver=${#LOCAL_UNVERIFIED[@]}"
  fi
done

###############################################################################
# Row 8 — COPIED STATE: state/audit is gitignored but an archive carries it, so
# a copied tree can inherit ANOTHER checkout's intent. That inherited intent must
# never fire as drift here — it is UNVERIFIED with a named reset.
###############################################################################
fx="$(mkfixture)"; strip_settings "$fx"
other="$(mkfixture)"
ffhc_hwi_write "$other" true >/dev/null 2>&1   # the OTHER checkout's intent, inherited by copy
cp "$other/state/audit/flow-hook-wiring-intent.json" "$fx/state/audit/"
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && [ "${#LOCAL_UNVERIFIED[@]}" -eq 1 ]; then
  ok "copied-state-unverified-not-drift"
else
  bad "copied-state-unverified-not-drift" "drift=$(joined "${LOCAL_DRIFT[@]}") unver=${#LOCAL_UNVERIFIED[@]}"
fi

###############################################################################
# Row 8b — REGRESSION (measured on Git-Bash): `pwd` says /c/Users/… and
# `git rev-parse --show-toplevel` says C:/Users/… for the SAME tree. Before the
# drive fold, that read FOREIGN and the arm went permanently inert — the blind
# spot back, now with a marker file to make it look covered.
###############################################################################
if [ "$(ffhc_hwi_norm '/c/Users/x/repo')" = "$(ffhc_hwi_norm 'C:/Users/x/repo')" ] \
   && [ "$(ffhc_hwi_norm 'C:\Users\x\repo\')" = "$(ffhc_hwi_norm '/c/Users/x/repo')" ] \
   && [ "$(ffhc_hwi_norm '/c/Users/x/repo')" != "$(ffhc_hwi_norm '/d/Users/x/repo')" ]; then
  ok "msys-drive-form-folds"
else
  bad "msys-drive-form-folds" "$(ffhc_hwi_norm '/c/Users/x/repo') vs $(ffhc_hwi_norm 'C:/Users/x/repo')"
fi

###############################################################################
# Row 9 — the engine actually CALLS the arm, and post-fusebase-update.sh actually
# records + revokes. A perfect lib nobody wired in is the same blind spot.
###############################################################################
ENGINE="$ROOT/hooks/local/fusebase-flow-health-check.sh"
if grep -q "ffhc_hwi_check" "$ENGINE"; then ok "engine-calls-arm"; else
  bad "engine-calls-arm" "no ffhc_hwi_check in fusebase-flow-health-check.sh"; fi
RECOVERY="$ROOT/hooks/local/post-fusebase-update.sh"
if grep -q "ffhc_hwi_record_wiring" "$RECOVERY"; then ok "recovery-records-intent"; else
  bad "recovery-records-intent" "no ffhc_hwi_record_wiring in post-fusebase-update.sh"; fi
if grep -q -- "--forget-hook-wiring" "$RECOVERY"; then ok "recovery-offers-opt-out"; else
  bad "recovery-offers-opt-out" "no --forget-hook-wiring flag in post-fusebase-update.sh"; fi

t3_fixture() {
  local d="$1"
  mkdir -p "$d/hooks/local/lib" "$d/hooks/local/fusebase-flow-overlays/commands" \
    "$d/hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check" \
    "$d/flow-skills/fixture" "$d/agents/fixture" "$d/.claude"
  cp "$ROOT/hooks/local/post-fusebase-update.sh" "$d/hooks/local/"
  cp "$ROOT/hooks/local/lib/hook-wiring-intent.sh" "$ROOT/hooks/local/lib/flow-recovery-plan.sh" "$d/hooks/local/lib/"
  cp "$ROOT/hooks/local/fusebase-flow-overlays/agents-md-overlay.md" \
    "$ROOT/hooks/local/fusebase-flow-overlays/claude-md-overlay.md" \
    "$ROOT/hooks/local/fusebase-flow-overlays/overlay-block-replace.py" \
    "$ROOT/hooks/local/fusebase-flow-overlays/settings-json-merge.py" \
    "$d/hooks/local/fusebase-flow-overlays/"
  printf '# fixture\n' > "$d/flow-skills/fixture/SKILL.md"
  printf '# fixture\n' > "$d/agents/fixture/AGENT.md"
  printf '# command\n' > "$d/hooks/local/fusebase-flow-overlays/commands/fusebase-health.md"
  printf '# health\n' > "$d/hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/local/mirror-skills.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/local/mirror-agents.sh"
  printf '#!/usr/bin/env bash\nprintf installed\nprintf wired > .git/hooks/pre-commit\n' > "$d/hooks/local/install-git-hooks.sh"
  chmod +x "$d/hooks/local/"*.sh
  printf '# CLI AGENTS\n' > "$d/AGENTS.md"
  cat "$d/hooks/local/fusebase-flow-overlays/agents-md-overlay.md" >> "$d/AGENTS.md"
  printf '# CLI CLAUDE\n' > "$d/CLAUDE.md"
  cat "$d/hooks/local/fusebase-flow-overlays/claude-md-overlay.md" >> "$d/CLAUDE.md"
  ( cd "$d" && git init -q )
}

fx="$TMP/t3-missing-settings"; t3_fixture "$fx"
( cd "$fx" && ffhc_hwi_write "$(git rev-parse --show-toplevel)" true "claude_settings" ) >/dev/null
set +e
( cd "$fx" && bash hooks/local/post-fusebase-update.sh > recovery.log 2>&1 )
t3_rc=$?
set -e
if [ "$t3_rc" -eq 1 ] && python3 - "$fx" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
settings = json.loads((root / ".claude/settings.json").read_text(encoding="utf-8"))
commands = [h.get("command", "") for blocks in settings["hooks"].values()
            for block in blocks for h in block.get("hooks", [])]
assert len([c for c in commands if "hooks/handlers/" in c]) == 6
status = json.loads((root / "state/audit/flow-recovery-status.json").read_text())
assert status["status"] == "partial" and status["exit_code"] == 1
assert "external settings bytes were unavailable" in status["note"]
assert not (root / ".git/hooks/pre-commit").exists()
PY
then ok "recovery-valid-intent-restores-missing-settings-as-partial"; else
  bad "recovery-valid-intent-restores-missing-settings-as-partial" "rc=$t3_rc"; fi

fx="$TMP/t3-schema1"; t3_fixture "$fx"
strip_settings "$fx"
( cd "$fx" && ffhc_hwi_write "$(git rev-parse --show-toplevel)" true "claude_settings" ) >/dev/null
python3 - "$fx/state/audit/flow-hook-wiring-intent.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["schema_version"] = 1
doc.pop("surfaces")
path.write_text(json.dumps(doc), encoding="utf-8")
PY
( cd "$fx" && bash hooks/local/post-fusebase-update.sh > recovery.log 2>&1 )
if grep -q "hooks/handlers/pre_tool_use.py" "$fx/.claude/settings.json" \
   && [ ! -f "$fx/.git/hooks/pre-commit" ]; then
  ok "recovery-schema1-restores-settings-without-git-authorization"
else
  bad "recovery-schema1-restores-settings-without-git-authorization" "legacy intent widened its surface"
fi

fx="$TMP/t3-git-surface"; t3_fixture "$fx"
strip_settings "$fx"
( cd "$fx" && ffhc_hwi_write "$(git rev-parse --show-toplevel)" true "claude_settings,git_hooks" ) >/dev/null
( cd "$fx" && bash hooks/local/post-fusebase-update.sh > recovery.log 2>&1 )
if grep -q "hooks/handlers/pre_tool_use.py" "$fx/.claude/settings.json" \
   && grep -q "wired" "$fx/.git/hooks/pre-commit"; then
  ok "recovery-schema2-restores-recorded-git-surface"
else
  bad "recovery-schema2-restores-recorded-git-surface" "recorded Git surface was not restored: $(tr '\n' ' ' < "$fx/recovery.log")"
fi

fx="$TMP/t3-prevalidation"; t3_fixture "$fx"
printf '{ invalid\n' > "$fx/.claude/settings.json"
( cd "$fx" && ffhc_hwi_write "$(git rev-parse --show-toplevel)" true "claude_settings" ) >/dev/null
before="$(sha256sum "$fx/AGENTS.md" | awk '{print $1}')"
set +e
( cd "$fx" && bash hooks/local/post-fusebase-update.sh > recovery.log 2>&1 )
t3_rc=$?
set -e
after="$(sha256sum "$fx/AGENTS.md" | awk '{print $1}')"
if [ "$t3_rc" -eq 2 ] && [ "$before" = "$after" ] && python3 - "$fx/state/audit/flow-recovery-status.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc["status"] == "failed" and doc["exit_code"] == 2
assert doc["applied_surfaces"] == []
PY
then ok "recovery-prevalidation-fails-before-target-writes"; else
  bad "recovery-prevalidation-fails-before-target-writes" "rc=$t3_rc"; fi

fx="$TMP/t3-interrupted"; t3_fixture "$fx"
strip_settings "$fx"
( cd "$fx" && ffhc_hwi_write "$(git rev-parse --show-toplevel)" true "claude_settings" ) >/dev/null
set +e
( cd "$fx" && FUSEBASE_FLOW_TEST_FAIL_AFTER_SURFACE=agents_overlay \
  bash hooks/local/post-fusebase-update.sh > first.log 2>&1 )
t3_rc=$?
set -e
if [ "$t3_rc" -ne 0 ] && python3 - "$fx/state/audit/flow-recovery-status.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc["status"] == "partial"
assert "agents_overlay" in doc["applied_surfaces"]
assert "claude_settings" in doc["pending_surfaces"]
PY
then ok "recovery-mid-apply-persists-partial-inventory"; else
  bad "recovery-mid-apply-persists-partial-inventory" "rc=$t3_rc"; fi
( cd "$fx" && bash hooks/local/post-fusebase-update.sh > retry.log 2>&1 )
if python3 - "$fx/state/audit/flow-recovery-status.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc["status"] == "complete" and doc["exit_code"] == 0
assert doc["pending_surfaces"] == []
PY
then ok "recovery-retry-converges-to-complete"; else
  bad "recovery-retry-converges-to-complete" "status did not converge"; fi

finish
