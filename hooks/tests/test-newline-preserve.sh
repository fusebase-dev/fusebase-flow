#!/usr/bin/env bash
# Fusebase Flow — AC2: sync-version-strings.sh preserves each file's EOF-newline
# state (both trailing-newline and no-trailing-newline fixtures). The previous
# `printf '%s' > "$f"` stripped the trailing newline and churned consumer docs.
#
# Output contract (parsed by run-tests.sh): "PASS: newline-preserve <name>" /
# "FAIL: newline-preserve <name>"; exit code = number of failures.
#
# Self-contained: builds a temp git repo with the real sync script + a minimal
# framework surface, runs sync, and checks the EOF byte of each fixture.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
GIT=(git -C "$TMP" -c user.name=flow-test -c user.email=flow-test@local)

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS: newline-preserve $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: newline-preserve $1 ($2)"; }

ends_with_newline() { # 0 (yes) / 1 (no)
  [ -s "$1" ] || return 1
  [ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" = "0a" ]
}

# Minimal framework surface the allowlist + derivations need.
git init -q "$TMP"
mkdir -p "$TMP/hooks/local" "$TMP/flow-skills/dummy" "$TMP/agents"
cp "$ROOT/hooks/local/sync-version-strings.sh" "$TMP/hooks/local/"
echo "3.24.0" > "$TMP/VERSION"
# FLOW_RULES with an FR max so the FR-range sub is active; a "## Amendment log"
# anchor so the range-limited program is valid.
printf '# rules\nFR-01\nFR-26\n## Amendment log\n' > "$TMP/FLOW_RULES.md"
printf -- '---\nname: dummy\n---\n# dummy\n' > "$TMP/flow-skills/dummy/SKILL.md"

# Fixture A — a STALE token-bearing adapter WITH a trailing newline (must stay).
printf 'Operating as PO under Fusebase Flow v3.20.0 today.\nFR-01 through FR-25 apply.\n' > "$TMP/AGENTS.md"
# Fixture B — a STALE token-bearing adapter with NO trailing newline (must stay none).
printf 'Operating as PO under Fusebase Flow v3.20.0 today.\nFR-01 through FR-25 apply.' > "$TMP/CLAUDE.md"

# Sanity: the fixtures start in the expected EOF states.
ends_with_newline "$TMP/AGENTS.md"  || bad "fixture-A-precondition" "AGENTS.md should start WITH a trailing newline"
ends_with_newline "$TMP/CLAUDE.md"  && bad "fixture-B-precondition" "CLAUDE.md should start WITHOUT a trailing newline"

( cd "$TMP" && bash hooks/local/sync-version-strings.sh >/dev/null 2>&1 )

# The substitution MUST have happened (proves the file was actually rewritten, so
# the EOF check is meaningful — not a no-op pass).
grep -q 'Fusebase Flow v3.24.0' "$TMP/AGENTS.md" && grep -q 'FR-01 through FR-26' "$TMP/AGENTS.md" \
  && ok "trailing-newline-file-was-synced" \
  || bad "trailing-newline-file-was-synced" "AGENTS.md not rewritten to v3.24.0/FR-26"
grep -q 'Fusebase Flow v3.24.0' "$TMP/CLAUDE.md" \
  && ok "no-newline-file-was-synced" \
  || bad "no-newline-file-was-synced" "CLAUDE.md not rewritten to v3.24.0"

# AC2 core: EOF state preserved on BOTH.
ends_with_newline "$TMP/AGENTS.md" \
  && ok "trailing-newline-preserved" \
  || bad "trailing-newline-preserved" "AGENTS.md lost its trailing newline (the churn bug)"
ends_with_newline "$TMP/CLAUDE.md" \
  && bad "no-trailing-newline-preserved" "CLAUDE.md gained a spurious trailing newline" \
  || ok "no-trailing-newline-preserved"

echo "[test-newline-preserve] $pass/$((pass + fail)) PASS"
exit $fail
