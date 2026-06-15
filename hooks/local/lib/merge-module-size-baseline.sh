#!/usr/bin/env bash
# Fusebase Flow — module-size baseline merge (U3 / W2 fix, the LOCKED merge rule).
#
# PROVENANCE:
#   Extracted from upgrade.sh per FR-25 so the engine stays small AND so the merge
#   rule is independently unit-testable (hooks/tests/test-baseline-merge.sh / AC3).
#   Lives at hooks/local/lib/ — outside the FuseBase CLI refresh manifest.
#
# WHY (W2): upgrade.sh refreshes policies/ wholesale from upstream, which CLOBBERED
#   policies/module-size-baseline.txt — a file that carries PROJECT state (a
#   consumer's own over-ceiling files frozen at their sizes). After an upgrade
#   `check-module-size.sh --all` then failed because the consumer's project rows
#   vanished. This merge restores the consumer's project rows while taking upstream's
#   line-counts for upstream-owned rows.
#
# THE LOCKED MERGE RULE (ownership = UPSTREAM-BASELINE MEMBERSHIP, not path prefix):
#   flow_owned := the set of paths present in the UPSTREAM baseline.
#   For the merged output:
#     - each UPSTREAM row -> emit with the UPSTREAM line-count (upstream is source
#       of truth for files it owns; a Flow row dropped upstream — file no longer
#       over ceiling — is therefore dropped locally too);
#     - each LOCAL row whose path is NOT in flow_owned (a PROJECT row) -> preserved
#       (the consumer's own frozen monolith);
#     - a LOCAL row whose path IS in flow_owned is superseded by the upstream row
#       (no duplicate; upstream count wins).
#   Output: standard header + deterministic sort ("<lines> <path>", sorted by path).
#   CANONICALIZATION (preservation is by ROW-PER-UNIQUE-PATH, not byte-verbatim):
#   duplicate local paths collapse to the LAST occurrence; malformed local rows are
#   WARNED (stderr) and omitted, never silently dropped. The W2 contract — every
#   PROJECT path keeps its frozen count — holds across both.
#
# USAGE:
#   merge_module_size_baseline <local_baseline> <upstream_baseline> <out_file>
#     local_baseline    path to the consumer's pre-upgrade baseline (may be absent)
#     upstream_baseline  path to the upstream baseline being installed (may be absent)
#     out_file           where to write the merged result
#   Returns 0 on success. Prints a one-line summary to stdout; warnings to stderr.
#
# Standalone (also runnable directly for the test harness):
#   bash hooks/local/lib/merge-module-size-baseline.sh LOCAL UPSTREAM OUT

# A baseline row is "<integer> <path>"; "# ..." and blank lines are comments.
# This parser is the single source of truth for "valid row" (kept in sync with
# hooks/shared/module_size.py:_read_baseline — integer first token, space, path).

merge_module_size_baseline() {
  local local_bl="$1" upstream_bl="$2" out="$3"

  local header='# FR-25 module-size baseline — over-ceiling files frozen at current size.
# Regenerate (operator-run): bash hooks/local/check-module-size.sh --write-baseline
# Re-key ONE file (no global amnesty): ... --write-baseline <path>'

  # upstream rows: path -> lines (flow_owned membership = keys of this map).
  declare -A UP_LINES=()
  declare -a UP_ORDER=()
  if [ -f "$upstream_bl" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      local n="${line%% *}" p="${line#* }"
      if [[ "$n" =~ ^[0-9]+$ ]] && [ "$p" != "$line" ] && [ -n "$p" ]; then
        [ -z "${UP_LINES[$p]:-}" ] && UP_ORDER+=("$p")
        UP_LINES["$p"]="$n"
      else
        echo "[merge-baseline] WARN: skipping malformed UPSTREAM row: $line" >&2
      fi
    done < "$upstream_bl"
  fi

  # local project rows: keep a local row VERBATIM iff its path is NOT flow_owned.
  declare -A OUT_LINES=()
  declare -a OUT_PATHS=()
  local p
  for p in "${UP_ORDER[@]}"; do
    OUT_LINES["$p"]="${UP_LINES[$p]}"
    OUT_PATHS+=("$p")
  done
  if [ -f "$local_bl" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      local n="${line%% *}" lp="${line#* }"
      if ! { [[ "$n" =~ ^[0-9]+$ ]] && [ "$lp" != "$line" ] && [ -n "$lp" ]; }; then
        echo "[merge-baseline] WARN: skipping malformed LOCAL row (kept out of merge): $line" >&2
        continue
      fi
      if [ -n "${UP_LINES[$lp]:-}" ]; then
        continue                              # flow_owned -> upstream count already emitted
      fi
      if [ -z "${OUT_LINES[$lp]:-}" ]; then
        OUT_PATHS+=("$lp")
      fi
      OUT_LINES["$lp"]="$n"                    # PROJECT row kept; dup path -> last wins
    done < "$local_bl"
  fi

  # Deterministic output: sort by path, "<lines> <path>" rows.
  {
    printf '%s\n' "$header"
    local body
    body="$(for p in "${OUT_PATHS[@]}"; do printf '%s %s\n' "${OUT_LINES[$p]}" "$p"; done | sort -k2)"
    [ -n "$body" ] && printf '%s\n' "$body"
  } > "$out"

  echo "[merge-baseline] merged baseline -> $out (${#UP_ORDER[@]} upstream row(s), $(( ${#OUT_PATHS[@]} - ${#UP_ORDER[@]} )) preserved project row(s))"
}

# Standalone invocation (for the test harness / manual use).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  if [ "$#" -ne 3 ]; then
    echo "usage: $0 <local_baseline> <upstream_baseline> <out_file>" >&2
    exit 2
  fi
  merge_module_size_baseline "$1" "$2" "$3"
fi
