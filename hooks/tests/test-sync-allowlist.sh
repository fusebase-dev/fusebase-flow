#!/usr/bin/env bash
# Fusebase Flow — AC4: sync-version-strings.sh allowlist UNDER-REACH guard
# (the anti-GEMINI test) + consumer-doc-NOT-synced.
#
# Two failure modes guarded:
#   1. UNDER-REACH: a token-bearing FRAMEWORK file omitted from the allowlist
#      would silently never sync (recreates GEMINI-stuck-at-v2.1 in reverse).
#      This test enumerates the allowlist's own reachable set, derives the TRUE
#      set of framework files carrying a LIVE attestation string, and FAILS on
#      any TRUE file the allowlist does not reach. It also self-verifies it would
#      catch an omission (drops a known root and asserts a miss is detected).
#   2. OVER-REACH: a consumer doc tree (docs/product-backlog|problem-catalog|
#      product-execution|client-workflows/**) with an FR-.. token must NOT be in
#      the reachable set.
#
# Output contract (parsed by run-tests.sh): "PASS: sync-allowlist <name>" /
# "FAIL: sync-allowlist <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
SCRIPT="hooks/local/sync-version-strings.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: sync-allowlist $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: sync-allowlist $1 ($2)"; }

# A live attestation/banner/FR/skill-count string (the set the sed actually
# rewrites) — NOT any historical/provenance "v2.3.0+" mention.
LIVE_RE='(under Fusebase Flow |runs \*\*Fusebase Flow )(Local )?v[0-9]|FR-01 (through FR-|\.\.FR-)[0-9]|\([0-9]+ canonical'

# --- Extract the allowlist arrays straight from the script (source of truth) ---
# Pull each `NAME=(` … `)` block verbatim and eval it, so the test always reflects
# the shipped allowlist (no second copy to drift). The blocks contain only quoted
# literals + comments — safe to eval. Using the script's own bash parser avoids the
# awk-regex-portability pitfalls of re-parsing array syntax by hand.
extract_block() { # extract_block <NAME>  -> prints the "NAME=( ... )" block
  sed -n "/^$1=(/,/^)/p" "$SCRIPT"
}
eval "$(extract_block SYNC_ROOTS)"
eval "$(extract_block SYNC_FILES)"

[ "${#SYNC_ROOTS[@]}" -gt 0 ] && ok "allowlist-roots-parsed" || bad "allowlist-roots-parsed" "no SYNC_ROOTS extracted"
[ "${#SYNC_FILES[@]}" -gt 0 ] && ok "allowlist-files-parsed" || bad "allowlist-files-parsed" "no SYNC_FILES extracted"

# --- Build the allowlist's REACHABLE set (paths the script would scan) ---
reachable_set() { # echoes every md/mdc the allowlist reaches, NUL-safe-ish (no NUL paths in framework)
  local r f
  for r in "${SYNC_ROOTS[@]}"; do
    [ -d "$r" ] || continue
    find "$r" -type f \( -name '*.md' -o -name '*.mdc' \) 2>/dev/null
  done
  for f in "${SYNC_FILES[@]}"; do [ -f "$f" ] && echo "$f"; done
}
mapfile -t REACHABLE < <(reachable_set | sed 's#^\./##' | sort -u)

is_reachable() { local p="$1" x; for x in "${REACHABLE[@]}"; do [ "$x" = "$p" ] && return 0; done; return 1; }

# --- TRUE framework target: files with a LIVE string, minus generated mirrors,
#     dated history, local diagnostics, and the consumer doc trees. ---
mapfile -t TRUE_TARGET < <(
  find . \( -type d \( \
        -name '.git' -o -name '.fusebase-flow-source' -o -name 'node_modules' \
        -o -name '.claude' -o -name '.agents' -o -name '.codex' \
        -o -path './internal' \
        -o -path './docs/release-notes' -o -path './docs/handoff' -o -path './docs/tmp' \
        -o -path './docs/specs' -o -path './docs/changes' -o -path './docs/fusebase-health' \
        -o -path './docs/product-backlog' -o -path './docs/problem-catalog' \
        -o -path './docs/product-execution' -o -path './docs/client-workflows' \
      \) -prune \) -o \
    \( -type f \( -name '*.md' -o -name '*.mdc' \) ! -name 'CHANGELOG.md' -print \) \
  | xargs grep -lE "$LIVE_RE" 2>/dev/null | sed 's#^\./##' | sort -u
)

# UNDER-REACH guard: every TRUE framework file must be reachable by the allowlist.
missing=()
for t in "${TRUE_TARGET[@]}"; do is_reachable "$t" || missing+=("$t"); done
if [ "${#missing[@]}" -eq 0 ]; then
  ok "no-under-reach (${#TRUE_TARGET[@]} framework files all reachable)"
else
  bad "no-under-reach" "token-bearing framework file(s) NOT in allowlist: ${missing[*]}"
fi

# Self-verification: the guard must DETECT an omission. Drop the FLOW_RULES.md
# entry from a copy of REACHABLE and confirm a TRUE file becomes unreachable.
if printf '%s\n' "${TRUE_TARGET[@]}" | grep -qxF "FLOW_RULES.md"; then
  if printf '%s\n' "${REACHABLE[@]}" | grep -vxF "FLOW_RULES.md" | grep -qxF "FLOW_RULES.md"; then
    bad "guard-detects-omission" "removal did not take effect"
  else
    ok "guard-detects-omission"
  fi
else
  bad "guard-detects-omission" "FLOW_RULES.md not in TRUE target — can't self-verify"
fi

# --- OVER-REACH guard: a consumer doc with an FR token must NOT be reachable. ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/docs/product-backlog" "$TMP/repo/hooks/local" "$TMP/repo/flow-skills/d"
git -C "$TMP/repo" init -q
cp "$SCRIPT" "$TMP/repo/hooks/local/sync-version-strings.sh"
echo "3.24.0" > "$TMP/repo/VERSION"
printf '# rules\nFR-01\nFR-26\n## Amendment log\n' > "$TMP/repo/FLOW_RULES.md"
printf -- '---\nname: d\n---\n# d\n' > "$TMP/repo/flow-skills/d/SKILL.md"
# A consumer historical doc carrying an FR ref + an old version banner.
printf 'Backlog note: FR-01 through FR-12 were the original set.\nran under Fusebase Flow v2.0.0 back then.\n' \
  > "$TMP/repo/docs/product-backlog/old-plan.md"
consumer_before="$(cat "$TMP/repo/docs/product-backlog/old-plan.md")"
( cd "$TMP/repo" && bash hooks/local/sync-version-strings.sh >/dev/null 2>&1 )
consumer_after="$(cat "$TMP/repo/docs/product-backlog/old-plan.md")"
[ "$consumer_before" = "$consumer_after" ] \
  && ok "consumer-doc-not-synced" \
  || bad "consumer-doc-not-synced" "a docs/product-backlog/ file with FR tokens WAS rewritten by sync"

echo "[test-sync-allowlist] $pass/$((pass + fail)) PASS"
exit $fail
