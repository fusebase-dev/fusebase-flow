#!/usr/bin/env bash
# Fusebase Flow — hook-install call-site rc handling (T24). Drives the SHIPPED T24
# branch (extracted verbatim from hooks/local/{upgrade,post-fusebase-update}.sh) so a
# regression in the real files changes the extract and trips the test.
#
# The BUG (v3.30.4): `install-git-hooks.sh 2>&1 | grep -qi 'custom .* detected'` keyed
# the branch off `$?` of GREP, not the installer — a nonzero install that didn't print
# the custom-preserve line fell into the "installed" branch (a silent false success).
# T24 captures OUTPUT + RC SEPARATELY (set -e-safe) and reports:
#   rc≠0 -> WARN/FAIL explicitly (no "installed" claim);
#   rc0 + custom-preserve signal -> preserved;
#   rc0 clean -> installed.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: hook-install-rc <name>" / "FAIL: hook-install-rc <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
UPGRADE="$ROOT/hooks/local/upgrade.sh"
POSTUP="$ROOT/hooks/local/post-fusebase-update.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: hook-install-rc $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: hook-install-rc $1 (${2:-})"; }
finish() { echo "[test-hook-install-rc] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$UPGRADE" ] || { bad "setup-upgrade-present" "missing $UPGRADE"; finish; }
[ -f "$POSTUP" ]  || { bad "setup-postup-present" "missing $POSTUP"; finish; }

# Extract the region between the T24 tripwire comment and the branch-closing `fi` from
# a shipped file, so the assertions run the REAL code. The block opens at the line
# carrying `TRIPWIRE (T24)` and closes at the FIRST subsequent line that is exactly
# `  fi` (2-space indent — the call-site's own closing fi).
extract_t24() { awk '/TRIPWIRE \(T24\)/{p=1} p{print} p&&/^  fi$/{exit}' "$1"; }

# stub_installer DIR RC EXTRA: write a fake hooks/local/install-git-hooks.sh in DIR that
# prints EXTRA (to stdout+stderr as the real one splits) and exits RC.
stub_installer() {
  local d="$1" rc="$2" extra="$3"
  mkdir -p "$d/hooks/local" "$d/.git/hooks"
  cat > "$d/hooks/local/install-git-hooks.sh" <<STUB
#!/usr/bin/env bash
[ -n "$extra" ] && echo "$extra" >&2
echo "[fusebase-flow] git hooks install complete."
exit $rc
STUB
  chmod +x "$d/hooks/local/install-git-hooks.sh"
}

# ---- upgrade.sh block: run the extracted T24 branch under the ENGINE environment
# (`set -euo pipefail`) against a stub installer, capture stdout, assert the message. ----
run_upgrade_block() { # DIR -> prints the block's stdout
  local d="$1" body; body="$(extract_t24 "$UPGRADE")"
  [ -n "$body" ] || { echo "__EXTRACT_FAILED__"; return; }
  ( cd "$d" && bash -c "set -euo pipefail
$body
" ) 2>/dev/null
}

# 1. rc≠0 (installer FAILS, no custom line): must WARN, NOT claim "installed".
D="$(mktemp -d)"; stub_installer "$D" 3 ""
OUT="$(run_upgrade_block "$D")"
if echo "$OUT" | grep -qi 'FAILED (exit 3)' && ! echo "$OUT" | grep -qi '(re)installed'; then
  ok "upgrade-rc-nonzero-no-silent-installed"
else bad "upgrade-rc-nonzero-no-silent-installed" "rc≠0 not surfaced as failure / claimed installed: [$OUT]"; fi
rm -rf "$D"

# 2. rc0 + custom-preserve signal: must report PRESERVED (not installed).
D="$(mktemp -d)"; stub_installer "$D" 0 "[fusebase-flow] WARNING: custom pre-commit detected at .git/hooks/pre-commit — NOT overwritten."
OUT="$(run_upgrade_block "$D")"
if echo "$OUT" | grep -qi 'preserved' && ! echo "$OUT" | grep -qi '(re)installed'; then
  ok "upgrade-rc0-custom-preserved"
else bad "upgrade-rc0-custom-preserved" "rc0+custom not reported preserved: [$OUT]"; fi
rm -rf "$D"

# 3. rc0 clean: must report INSTALLED.
D="$(mktemp -d)"; stub_installer "$D" 0 "[fusebase-flow] installed pre-commit"
OUT="$(run_upgrade_block "$D")"
if echo "$OUT" | grep -qi '(re)installed'; then ok "upgrade-rc0-clean-installed"
else bad "upgrade-rc0-clean-installed" "rc0 clean not reported installed: [$OUT]"; fi
rm -rf "$D"

# 4. set -e-safety: the rc≠0 branch must NOT abort the script — a marker AFTER the block
#    must still print (proves the capture neutralized -e).
D="$(mktemp -d)"; stub_installer "$D" 5 ""
BODY="$(extract_t24 "$UPGRADE")"
OUT="$( ( cd "$D" && bash -c "set -euo pipefail
$BODY
echo REACHED-AFTER-BLOCK
" ) 2>/dev/null )"
if echo "$OUT" | grep -q 'REACHED-AFTER-BLOCK'; then ok "upgrade-rc-nonzero-set-e-safe"
else bad "upgrade-rc-nonzero-set-e-safe" "set -e aborted on installer rc≠0 (marker missing): [$OUT]"; fi
rm -rf "$D"

# ---- post-fusebase-update.sh block: same three cases. The block appends to WARNINGS[]
# / ACTIONS_TAKEN[] arrays; seed them + WIRE_HOOKS=1 + echo the arrays after. ----
run_postup_block() { # DIR -> prints WARNINGS + ACTIONS after running the block
  local d="$1" body; body="$(extract_t24 "$POSTUP")"
  [ -n "$body" ] || { echo "__EXTRACT_FAILED__"; return; }
  ( cd "$d" && bash -c "set -euo pipefail
WARNINGS=(); ACTIONS_TAKEN=(); ACTIONS_SKIPPED=(); WIRE_HOOKS=1
$body
printf 'WARN:%s\n' \"\${WARNINGS[@]:-}\"
printf 'ACTION:%s\n' \"\${ACTIONS_TAKEN[@]:-}\"
" ) 2>/dev/null
}

# 5. rc≠0: appends a WARNING (FAILED), does NOT append the "installed" action.
D="$(mktemp -d)"; stub_installer "$D" 4 ""
OUT="$(run_postup_block "$D")"
if echo "$OUT" | grep -qi 'WARN:.*FAILED (exit 4)' && ! echo "$OUT" | grep -qi 'ACTION:.*(re)installed'; then
  ok "postup-rc-nonzero-no-silent-installed"
else bad "postup-rc-nonzero-no-silent-installed" "rc≠0 not warned / claimed installed: [$OUT]"; fi
rm -rf "$D"

# 6. rc0 + custom: WARNING (preserved), not the installed action.
D="$(mktemp -d)"; stub_installer "$D" 0 "[fusebase-flow] WARNING: custom pre-commit detected — NOT overwritten."
OUT="$(run_postup_block "$D")"
if echo "$OUT" | grep -qi 'WARN:.*custom .* preserved' && ! echo "$OUT" | grep -qi 'ACTION:.*(re)installed'; then
  ok "postup-rc0-custom-preserved"
else bad "postup-rc0-custom-preserved" "rc0+custom not reported preserved: [$OUT]"; fi
rm -rf "$D"

# 7. rc0 clean: the installed ACTION is appended.
D="$(mktemp -d)"; stub_installer "$D" 0 "[fusebase-flow] installed pre-commit"
OUT="$(run_postup_block "$D")"
if echo "$OUT" | grep -qi 'ACTION:.*(re)installed'; then ok "postup-rc0-clean-installed"
else bad "postup-rc0-clean-installed" "rc0 clean not reported installed: [$OUT]"; fi
rm -rf "$D"

finish
