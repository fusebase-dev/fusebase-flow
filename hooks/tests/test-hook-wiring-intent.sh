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
# Row 1b — the marker is written ONLY after a SUCCESSFUL merge (never on a
# failed/aborted one). This is the writer's whole contract.
###############################################################################
fx="$(mkfixture)"; wire_settings "$fx"
ffhc_hwi_record_wiring "$fx" 1 >/dev/null 2>&1
if [ ! -f "$fx/state/audit/flow-hook-wiring-intent.json" ]; then
  ok "failed-merge-writes-nothing"
else
  bad "failed-merge-writes-nothing" "marker written after a nonzero merge exit"
fi

###############################################################################
# Row 2 — WHOLESALE STRIP: enabled intent + no Flow handler => DRIFT, stable
# check ID, and a recovery that NAMES --wire-hooks (the default recovery
# explicitly does not modify settings.json, so a bare recommendation is a
# dead end and the ticket would only relocate the forensics).
###############################################################################
fx="$(mkfixture)"; strip_settings "$fx"
ffhc_hwi_record_wiring "$fx" 0 >/dev/null 2>&1
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
ffhc_hwi_record_wiring "$fx" 0 >/dev/null 2>&1
run_arm "$fx"
if [ "${#LOCAL_DRIFT[@]}" -eq 1 ]; then ok "wrong-pretooluse-drifts"; else
  bad "wrong-pretooluse-drifts" "expected 1 drift, got ${#LOCAL_DRIFT[@]}"; fi

###############################################################################
# Row 3 — DELIBERATE OPT-OUT: the revocation path clears the intent, so a tree
# that removed the block on purpose does NOT alarm. Intent needs a revocation
# lifecycle, not just a creation event.
###############################################################################
fx="$(mkfixture)"; strip_settings "$fx"
ffhc_hwi_record_wiring "$fx" 0 >/dev/null 2>&1
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
ffhc_hwi_record_wiring "$fx" 0 >/dev/null 2>&1
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
ffhc_hwi_record_wiring "$other" 0 >/dev/null 2>&1
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

finish
