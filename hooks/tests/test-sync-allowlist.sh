#!/usr/bin/env bash
# Fusebase Flow — AC4: sync-version-strings.sh allowlist UNDER-REACH guard
# (the anti-GEMINI test) + consumer-doc-NOT-synced.
#
# Three failure modes guarded (3 added v4.6.1 after the v4.6.0 red-main):
#   1. UNDER-REACH: a token-bearing FRAMEWORK file omitted from the allowlist
#      would silently never sync (recreates GEMINI-stuck-at-v2.1 in reverse).
#      This test enumerates the allowlist's own reachable set, derives the TRUE
#      set of framework files carrying a LIVE attestation string, and FAILS on
#      any TRUE file the allowlist does not reach. It also self-verifies it would
#      catch an omission (drops a known root and asserts a miss is detected).
#   2. OVER-REACH: a consumer/record doc tree (any docs/<subdir>/**, e.g. this repo's
#      docs/backlog + docs/problem-catalog, or a consumer's docs/product-backlog)
#      with an FR-.. token must NOT be in the reachable set.
#   3. DOCS-SURFACE SYMMETRY: the framework doc surface under docs/ is TOP-LEVEL
#      `docs/*.md` only, so no allowlisted path may live under a docs/ subdirectory.
#      Guards 1 and 2 are then two views of ONE structural rule instead of two
#      hand-maintained name lists that can silently disagree.
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
REACHABLE_LIST="$(printf '%s\n' "${REACHABLE[@]}")"

is_reachable() { local p="$1" x; for x in "${REACHABLE[@]}"; do [ "$x" = "$p" ] && return 0; done; return 1; }

# TRIPWIRE (v4.6.1): exact-line membership is PURE BASH — never `producer | grep -qxF`.
# Under this file's `set -o pipefail`, `grep -q` exits at the first match and every
# further byte the producer writes raises SIGPIPE, so the PIPELINE reports 141 even
# though the line WAS found. That turned the multi-line case into a silent false
# verdict (v4.6.0 red-main: the AC27 self-verification reported "missing_set did NOT
# report FLOW_RULES.md" the moment a second entry existed after it). Pattern-matching
# a quoted "$2" inside `case` is literal, so paths need no escaping.
has_line() { # has_line <newline-separated haystack> <exact line>
  case $'\n'"$1"$'\n' in *$'\n'"$2"$'\n'*) return 0 ;; esac
  return 1
}

# THE production under-reach calculation, factored so the self-verification below runs
# THIS function against a mutated reachable set instead of restating the algorithm.
# TRIPWIRE: never inline a second copy of this loop — the previous self-test filtered
# FLOW_RULES.md out of a stream and then searched that filtered stream for it, so the
# "omission detected" branch was true by construction and never ran the guard.
missing_set() { # missing_set <newline-separated reachable set> -> unreachable TRUE targets
  local reach="$1" t
  for t in "${TRUE_TARGET[@]}"; do
    has_line "$reach" "$t" || printf '%s\n' "$t"
  done
}

# --- TRUE framework target: files with a LIVE string, minus generated mirrors,
#     dated history, local diagnostics, and the record/consumer doc trees. ---
# `-path './docs/*'` (STRUCTURAL, v4.6.1) is the whole docs classification: the
# framework doc surface under docs/ is TOP-LEVEL `docs/*.md` ONLY — exactly what
# SYNC_FILES declares ("top-level docs/*.md only — NOT consumer doc trees") — so every
# `docs/<subdir>/**` is a dated record/consumer tree whose version literals are history.
# TRIPWIRE: do NOT go back to enumerating record trees by name. The v4.6.0 red-main was
# an enumeration that listed the CONSUMER layout `docs/product-backlog` (a path this repo
# has never had) while missing this repo's own `docs/backlog` — so a records tree
# defaulted to FRAMEWORK and broke main the day a backlog note first quoted the
# attestation string. Enumeration fails open for every doc tree nobody remembered.
mapfile -t TRUE_TARGET < <(
  find . \( -type d \( \
        -name '.git' -o -name '.fusebase-flow-source' -o -name 'node_modules' \
        -o -name '.claude' -o -name '.agents' -o -name '.codex' \
        -o -path './internal' -o -path './state' -o -path './docs/*' \
      \) -prune \) -o \
    \( -type f \( -name '*.md' -o -name '*.mdc' \) \
         ! -name 'CHANGELOG.md' ! -name 'FLOW_RULES_HISTORY.md' -print \) \
  | xargs grep -lE "$LIVE_RE" 2>/dev/null | sed 's#^\./##' | sort -u
)
TRUE_TARGET_LIST="$(printf '%s\n' "${TRUE_TARGET[@]}")"

# UNDER-REACH guard: every TRUE framework file must be reachable by the allowlist.
mapfile -t missing < <(missing_set "$REACHABLE_LIST")
if [ "${#missing[@]}" -eq 0 ]; then
  ok "no-under-reach (${#TRUE_TARGET[@]} framework files all reachable)"
else
  bad "no-under-reach" "token-bearing framework file(s) NOT in allowlist: ${missing[*]}"
fi

# Self-verification (AC27): mutate the reachable set by dropping TWO framework files,
# then run the PRODUCTION missing_set against it and require BOTH to be REPORTED missing.
# TRIPWIRE: drop TWO, never one. A single-entry expectation is satisfied by a producer
# that stops after the first line, which is precisely how the v4.6.0 SIGPIPE defect hid —
# the control only exercises multi-entry output when more than one entry is missing.
DROP_A="AGENTS.md"; DROP_B="FLOW_RULES.md"
if ! has_line "$TRUE_TARGET_LIST" "$DROP_A" || ! has_line "$TRUE_TARGET_LIST" "$DROP_B"; then
  bad "guard-detects-omission" "$DROP_A/$DROP_B not both in TRUE target — can't self-verify"
else
  MUTATED_REACHABLE="$(printf '%s\n' "$REACHABLE_LIST" | grep -vxF "$DROP_A" | grep -vxF "$DROP_B")"
  MUT_MISSING="$(missing_set "$MUTATED_REACHABLE")"
  UNMUT_MISSING="$(missing_set "$REACHABLE_LIST")"
  if has_line "$MUTATED_REACHABLE" "$DROP_A" || has_line "$MUTATED_REACHABLE" "$DROP_B"; then
    bad "guard-detects-omission" "mutation did not take effect — dropped file still reachable"
  elif ! has_line "$MUT_MISSING" "$DROP_A" || ! has_line "$MUT_MISSING" "$DROP_B"; then
    bad "guard-detects-omission" "production missing_set did NOT report both omitted files (got: ${MUT_MISSING//$'\n'/, })"
  elif has_line "$UNMUT_MISSING" "$DROP_A" || has_line "$UNMUT_MISSING" "$DROP_B"; then
    bad "guard-detects-omission" "missing_set reports a dropped file missing on the UNMUTATED set too"
  else
    ok "guard-detects-omission (2-entry mutation: $DROP_A + $DROP_B)"
  fi
fi

# --- DOCS-SURFACE guard (v4.6.1): the two halves of the structural docs rule must agree.
#     TRUE_TARGET prunes every `docs/<subdir>/**` as a record tree; this asserts the
#     allowlist does not REACH one either. Without it the classification is one-sided:
#     an allowlist edit adding a docs subtree to SYNC_ROOTS would start rewriting dated
#     records while the pruned TRUE_TARGET stayed silent about it. ---
mapfile -t DOCS_SUBTREE_REACHED < <(printf '%s\n' "$REACHABLE_LIST" | grep -E '^docs/[^/]+/' || true)
if [ "${#DOCS_SUBTREE_REACHED[@]}" -eq 0 ]; then
  ok "docs-surface-is-top-level-only"
else
  bad "docs-surface-is-top-level-only" \
      "allowlist reaches docs/<subdir>/ record tree(s): ${DOCS_SUBTREE_REACHED[*]}"
fi

# --- DATED-HISTORY guard: FLOW_RULES_HISTORY.md carries live-LOOKING strings (old
#     banners, "(N canonical", FR ranges) but is history — syncing it falsifies the
#     record. It is excluded from TRUE_TARGET above, so this asserts the other half:
#     the allowlist must not reach it. ---
if [ -f FLOW_RULES_HISTORY.md ]; then
  if is_reachable "FLOW_RULES_HISTORY.md"; then
    bad "history-not-in-allowlist" "FLOW_RULES_HISTORY.md is reachable by the sync allowlist"
  elif grep -qE "$LIVE_RE" FLOW_RULES_HISTORY.md; then
    ok "history-not-in-allowlist (carries live-looking tokens; excluded as dated history)"
  else
    ok "history-not-in-allowlist"
  fi
else
  bad "history-not-in-allowlist" "FLOW_RULES_HISTORY.md missing (extracted amendment log)"
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
# Dated history carrying ALL THREE syncable token shapes: if it were ever reachable,
# the sed would rewrite every one of them and falsify the record.
printf 'Shipped under Fusebase Flow v2.0.0 with FR-01 through FR-12 and (9 canonical skills).\n' \
  > "$TMP/repo/FLOW_RULES_HISTORY.md"
history_before="$(cat "$TMP/repo/FLOW_RULES_HISTORY.md")"
( cd "$TMP/repo" && bash hooks/local/sync-version-strings.sh >/dev/null 2>&1 )
consumer_after="$(cat "$TMP/repo/docs/product-backlog/old-plan.md")"
history_after="$(cat "$TMP/repo/FLOW_RULES_HISTORY.md")"
[ "$history_before" = "$history_after" ] \
  && ok "history-never-synced" \
  || bad "history-never-synced" "FLOW_RULES_HISTORY.md WAS rewritten by sync"
[ "$consumer_before" = "$consumer_after" ] \
  && ok "consumer-doc-not-synced" \
  || bad "consumer-doc-not-synced" "a docs/product-backlog/ file with FR tokens WAS rewritten by sync"

echo "[test-sync-allowlist] $pass/$((pass + fail)) PASS"
exit $fail
