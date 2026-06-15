#!/usr/bin/env bash
# Fusebase Flow — PARTIAL_UPGRADE derived-facts check (U7, v3.24.x).
#
# PROVENANCE:
#   Extracted from fusebase-flow-health-check.sh per FR-25 (the engine sat at the
#   800-line ceiling). Lives at hooks/local/lib/ — outside the FuseBase CLI refresh
#   manifest. Sourced by the engine; never run standalone in production.
#
# WHY (W1/W3): upgrade.sh refreshes content, bumps VERSION, then syncs the derived
#   attestation strings (version + FR-range + skill count) into the adapters. If
#   that run is INTERRUPTED (the Windows mid-mirror stall) or an adapter has no
#   overlay-refresh path (e.g. GEMINI.md before U5/U6), the tree ends up with a new
#   VERSION but STALE live strings — a "partial upgrade" the old health-check could
#   not name. This check compares the DERIVED facts against the LIVE strings and
#   reports each mismatch.
#
# CONTRACT (the engine relies on these):
#   ffhc_partial_upgrade_findings  -> echoes one "<surface>: <detail>" line per
#                                     stale-derived-fact mismatch (empty == none).
#   Verdict mapping is the ENGINE's call: a non-empty result is genuine DRIFT
#   (a concrete stale-fact finding), mapped to the PARTIAL_UPGRADE signature /
#   exit 1 (the drift class). It is NOT exit 4 — exit 4 (PARTIAL_UNVERIFIED) is
#   reserved for a CRITICAL check that could not RUN; here the check ran and FOUND
#   drift. The v3.24.0 0/1/2/3/4 contract is unchanged; PARTIAL_UPGRADE is a named
#   sub-class of the existing drift exit (1).
#
# Derived facts (single source of truth = the repo's own files):
#   VERSION                          -> the canonical version
#   FLOW_RULES.md FR-NN max          -> the canonical FR-range high bound
#   flow-skills/ dir count           -> the canonical skill count
# Live strings checked against them, per surface:
#   .claude-plugin/plugin.json version   == VERSION
#   GEMINI.md / AGENTS.md / CLAUDE.md / .github/copilot-instructions.md /
#     .cursor/rules/*.mdc live "Fusebase Flow v<semver>" banner/attestation == VERSION
#   any adapter "FR-01 through FR-NN" / "FR-01..FR-NN" == derived FR high bound

# ffhc_partial_upgrade_findings: print stale-derived-fact mismatches, one per line.
# Read-only; tolerant of missing files (a missing adapter is the existing mirror/
# overlay-count checks' job, not this one).
ffhc_partial_upgrade_findings() {
  local ver fr_max fr_hi skill_count
  [ -f VERSION ] || return 0
  ver="$(tr -d '\n\r' < VERSION 2>/dev/null)"
  [ -n "$ver" ] || return 0
  fr_max="$(grep -oE 'FR-[0-9]+' FLOW_RULES.md 2>/dev/null | sed 's/FR-//' | sort -n | tail -1)"
  [ -n "$fr_max" ] && fr_hi="$(printf 'FR-%02d' "$fr_max")" || fr_hi=""
  local scan="flow-skills"; [ -d "$scan" ] || scan="skills"
  skill_count="$(find "$scan" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

  # plugin.json version parity (preflight §8 also checks this; surfaced here as a
  # partial-upgrade signal so the operator gets a repair command, not just an error).
  if [ -f .claude-plugin/plugin.json ] && command -v python3 >/dev/null 2>&1; then
    local pv
    pv="$(python3 -c "import json,sys; print(json.load(open('.claude-plugin/plugin.json')).get('version',''))" 2>/dev/null)"
    [ -n "$pv" ] && [ "$pv" != "$ver" ] && echo ".claude-plugin/plugin.json: version $pv != VERSION $ver"
  fi

  # Live "Fusebase Flow v<semver>" banner/attestation strings per adapter must read
  # the current VERSION. The U5 regex form (optional Local / 2-or-3-part) is matched
  # so a stuck `Local v2.1` header is reported (not silently passed).
  local f live
  # The two live anchors (matching sync-version-strings.sh exactly): "under Fusebase
  # Flow " (space) and "runs **Fusebase Flow " (the ** abuts Fusebase, no space).
  local banner_re='(under Fusebase Flow |runs \*\*Fusebase Flow )(Local )?v[0-9]+(\.[0-9]+){1,2}'
  for f in GEMINI.md AGENTS.md CLAUDE.md .github/copilot-instructions.md \
           .cursor/rules/fusebase-flow-always.mdc .github/instructions/fusebase-flow.instructions.md; do
    [ -f "$f" ] || continue
    # Any live banner/attestation version token that is NOT the current VERSION.
    live="$(grep -oE "$banner_re" "$f" 2>/dev/null \
            | grep -oE 'v[0-9]+(\.[0-9]+){1,2}' | grep -vxF "v$ver" | sort -u | head -1)"
    [ -n "$live" ] && echo "$f: live 'Fusebase Flow $live' != VERSION v$ver"
  done

  # FR-range high bound: any adapter naming "FR-01 through FR-NN" / "FR-01..FR-NN"
  # with NN != the derived high bound is stale (the GEMINI-stuck-FR class).
  if [ -n "$fr_hi" ]; then
    local fr_num="${fr_hi#FR-}"; fr_num="${fr_num#0}"
    for f in GEMINI.md AGENTS.md CLAUDE.md .github/copilot-instructions.md \
             .cursor/rules/fusebase-flow-always.mdc .github/instructions/fusebase-flow.instructions.md; do
      [ -f "$f" ] || continue
      local stale_fr
      stale_fr="$(grep -oE 'FR-01 (through FR-|\.\.FR-)[0-9]+' "$f" 2>/dev/null \
                  | grep -oE 'FR-[0-9]+$' | grep -oE '[0-9]+$' | sed 's/^0*//' \
                  | grep -vxF "$fr_num" | sort -u | head -1)"
      [ -n "$stale_fr" ] && echo "$f: live FR-range high bound FR-$stale_fr != derived $fr_hi"
    done
  fi
  return 0
}
