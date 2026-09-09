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
#   ffhc_partial_upgrade_findings      -> echoes one "<surface>: <detail>" line per
#                                         stale-derived-fact mismatch (empty == none).
#   ffhc_publisher_packaging_collect   -> records plugin-manifest parity findings in the
#                                         PUBLISHER repo only, as a SEPARATE class.
#   ffhc_preflight_is_packaging_only   -> rc 0 iff every preflight error line is one of those
#                                         findings (the engine's BROKEN-vs-packaging decision).
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

# Plugin-manifest parity, PUBLISHER-ONLY — the SAME helper preflight uses (lib/plugin-parity.sh),
# never a second copy. Health previously carried only predicate 1 (ownership by `name`), so a
# consumer whose three manifests are named fusebase-flow BECAUSE they were generated from Flow's
# was told their tree was a partial upgrade; they hand-copied our manifest bytes twice to clear
# it — the consumer-ownership risk the exclusion exists to prevent. Predicate 2 (the release
# ledger exists) is exactly what plugin-parity.sh added; reuse it instead of re-deriving it.
#
# DECISION — marketplace.json IS in scope here, deliberately, not by inheritance. It is not
# written by sync-version-strings.sh and silently drifted ~20 minor versions before any parity
# check existed (plugin-parity.sh § TRIPWIRE); the arm is publisher-only, so no consumer tree is
# affected; and giving health narrower coverage than preflight would recreate the two-copies
# divergence this reuse removes.
#
# TRIPWIRE: a publisher manifest mismatch is packaging drift, NOT evidence of an interrupted
# upgrade. It gets its own PACKAGING_DRIFT class and its own remediation — never PARTIAL_UPGRADE.
# TRIPWIRE: this arm must never suppress the adapter checks above. They are independent; a stale
# consumer adapter still fails whether or not any plugin diagnostic is available. Read-only.
ffhc_publisher_packaging_collect() {
  local lib e
  lib="$(dirname "${BASH_SOURCE[0]}")/plugin-parity.sh"
  if ! command -v ffpp_errors >/dev/null 2>&1; then
    [ -f "$lib" ] || return 0
    # shellcheck source=plugin-parity.sh
    . "$lib"
  fi
  command -v ffpp_errors >/dev/null 2>&1 || return 0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    PUBLISHER_PACKAGING_FINDINGS+=("$e")
    command -v record_drift >/dev/null 2>&1 && record_drift "publisher_packaging" "PACKAGING_DRIFT — $e"
  done < <(ffpp_errors 2>/dev/null)
  return 0
}

# ffhc_preflight_is_packaging_only <preflight-combined-output>
# rc 0 iff preflight reported at least one error line and EVERY one of them is also a packaging
# finding THIS run collected. The engine uses it to decide whether a failed preflight is the
# packaging arm's finding restated (verdict falls through to PUBLISHER_PACKAGING_DRIFT) or a
# genuine breakage (BROKEN). Read-only: preflight is never re-run.
# TRIPWIRE: match on the error line TEXT, never on counts — equal counts of different findings
# would hide a real breakage behind the packaging class. preflight's err() prefix is
# "[preflight] ERROR: " (preflight.sh:23); a prefix change must be reflected here.
ffhc_preflight_is_packaging_only() {
  local line stripped e seen=0 hit
  declare -p PUBLISHER_PACKAGING_FINDINGS >/dev/null 2>&1 || return 1
  [ "${#PUBLISHER_PACKAGING_FINDINGS[@]}" -gt 0 ] || return 1
  while IFS= read -r line; do
    case "$line" in "[preflight] ERROR: "*) : ;; *) continue ;; esac
    stripped="${line#\[preflight\] ERROR: }"; stripped="${stripped%$'\r'}"
    seen=$((seen + 1)); hit=0
    for e in "${PUBLISHER_PACKAGING_FINDINGS[@]}"; do
      [ "$e" = "$stripped" ] && { hit=1; break; }
    done
    [ "$hit" -eq 1 ] || return 1
  done < <(printf '%s\n' "$1")
  [ "$seen" -gt 0 ]
}
