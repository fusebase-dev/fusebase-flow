#!/usr/bin/env bash
# Fusebase Flow — missing-base / half-applied detection (decision N6-D2, ticket N6).
#
# PROVENANCE:
#   Extracted to hooks/local/lib/ per FR-25 — fusebase-flow-health-check.sh sits just under
#   the 800-line ceiling. Sourced by the engine; never run standalone in production.
#
# WHAT THIS CAN AND CANNOT KNOW — read this before adding a "smarter" check.
#
# Two trees were driven through the v4.12.0 engine and MEASURED: one poisoned by an upgrade
# that ran without a base, one healthy with a genuine consumer edit. Identical signature:
#
#   signal                          poisoned      healthy+edited
#   base present, self-hash valid    YES            YES
#   managed-content verify           DRIFT/modified DRIFT/modified
#   base == upstream's published     YES            YES     <- K13b installs the SOURCE tree's
#   rc / VERSION advanced            0 / yes        0 / yes     manifest as the new base after
#   backup artifacts                 VERSION.pre-*  VERSION.pre-*  EVERY successful upgrade
#
# So the consumer's own forensic tell — "the base matches a published fingerprint row
# exactly" — is TRUE OF EVERY HEALTHY TREE and discriminates nothing. Neither does "VERSION
# advanced relative to content" (that is what `consumer-only` MEANS), nor backup artifacts
# (audit/managed-content-manifest.json gets no backup twin at all: upgrade.sh twins top-level
# files only, and audit/ is not in `list-managed --dirs`).
#
# The one fact that separates them is HISTORY — did a base exist before the run that wrote
# this one — and no tree written by a pre-N6 engine records it. Hence:
#
#   State 1  base ABSENT       -> KNOWN with certainty. Named, routed to bootstrap-upgrade.sh.
#   State 2  base + DRIFT      -> UNKNOWABLE. A conditional POINTER, never a verdict.
#
# TRIPWIRE — do NOT promote the State-2 pointer to a finding, and do not "improve" it into a
# verdict. A wrong verdict here is actively harmful, not merely unhelpful: the advisory tells
# the poisoned population that deleting the base or bootstrapping blindly RECREATES the
# poison, so sending a healthy consumer down that path makes their tree worse. Half of any
# guessed population is guessed wrong.
#
# TRIPWIRE — READ-ONLY, always. This must never stamp, delete or repair a base. Synthesizing
# one here would key off the LOCAL VERSION (synthesize-base.sh:57-75), which on an
# already-advanced tree reconstructs upstream's current content as the "historical" base —
# rebuilding exactly the poison this ticket exists to stop.
#
# DELIVERY LIMIT — state it, never paper over it: this script is itself among the managed,
# frozen files, so on an already-affected install it is one of the paths the broken upgrade
# will not replace. This check protects the NOT-YET-EXPOSED. The already-affected are reached
# out-of-band, by docs/ADVISORY-2026-08-20-missing-base-upgrade.md and the pinned release
# notes. Any wording that implies broader reach is false.
#
# CONTRACT (the engine relies on these):
#   ffmb_findings -> zero or more lines, each "<CLASS>\t<message>":
#                      DRIFT    a real finding; the engine may move the verdict on it
#                      POINTER  VISIBILITY ONLY — like the M9 approval warnings, it must move
#                               neither the verdict nor the exit code
#   Read-only, tolerant of a missing module/manifest, and silent on a healthy tree.
#   FFMB_MCM overrides the managed-content module path (tests).

ffmb_findings() {
  local mcm="${FFMB_MCM:-hooks/local/lib/managed_content_manifest.py}"
  local base="audit/managed-content-manifest.json" verdict=""
  [ -f "$mcm" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  if [ ! -f "$base" ]; then
    # STATE 1 — the pre-exposure state, and the only one knowable for certain.
    # bootstrap-upgrade.sh works from here BECAUSE it stages the new engine first and
    # reconstructs the base from the upstream tag equal to the installed VERSION
    # (bootstrap-upgrade.sh:683-708,714-750). The ordinary upgrade does not: it would
    # classify every differing path `unknown-base`, preserve them, and — before N6-D1 —
    # record upstream's bytes as their history.
    printf 'DRIFT\t%s\n' \
      "managed-content base manifest ABSENT ($base) — an ORDINARY upgrade from here cannot tell your edits from upstream's. Adopt through the staged-engine path instead: bash hooks/local/bootstrap-upgrade.sh -- --auto-yes . Do NOT stamp a base from this tree (that records your edits as 'upstream base' — K13b) and do NOT hand-edit the manifest. This check runs BEFORE the problem: it cannot reach an install already affected, because this script is itself one of the frozen files — see docs/ADVISORY-2026-08-20-missing-base-upgrade.md, which is how already-affected installs are reached."
    return 0
  fi

  verdict="$(python3 "$mcm" verify --root . 2>/dev/null | sed -n 's/.*verify: \([A-Z]*\).*/\1/p' | head -1)"
  [ "$verdict" = "DRIFT" ] || return 0

  # STATE 2 — CONDITIONAL. Everything above is equally true of a healthy tree whose owner
  # edited a managed file on purpose, which is the ordinary case. So this asks the operator
  # the one question only they can answer, and asserts nothing.
  printf 'POINTER\t%s\n' \
    "if your last upgrade ran against a tree that had NO audit/managed-content-manifest.json, the drift reported above may be an upgrade that half-applied rather than your own edits — this check CANNOT tell the two apart (they are byte-identical locally). Confirm from your own history, then follow docs/ADVISORY-2026-08-20-missing-base-upgrade.md. Until then change nothing: do NOT re-run upgrade blind, do NOT delete or re-stamp the base, and preserve *.pre-upgrade-*, VERSION backups and the source clone."
  return 0
}

# MBASE_POINTERS lives HERE, not in the engine's declaration block: the lib is sourced into
# the engine's scope (FR-25 — the engine has 3 lines of headroom under the 800 ceiling and
# this wiring must cost none of them).
MBASE_POINTERS=()

# ffmb_collect: route findings to the engine's buckets.
#   DRIFT   -> record_drift (a real, repairable finding the verdict may move on)
#   POINTER -> MBASE_POINTERS (VISIBILITY ONLY — the M9 approval-warning pattern)
#
# TRIPWIRE — never send a POINTER to record_drift. It would give a HEALTHY tree with an
# ordinary consumer edit a drift finding it cannot act on, and it would let a guess move an
# exit code. The class prefix is the whole contract; see this file's header for the
# measurement that says the two states are locally indistinguishable.
ffmb_collect() {
  command -v ffmb_findings >/dev/null 2>&1 || return 0
  local cls msg
  while IFS=$'\t' read -r cls msg; do
    [ -n "${msg:-}" ] || continue
    case "$cls" in
      DRIFT)   command -v record_drift >/dev/null 2>&1 && record_drift "missing_base" "$msg" ;;
      POINTER) MBASE_POINTERS+=("$msg") ;;
    esac
  done < <(ffmb_findings 2>/dev/null)
  return 0
}

ffmb_print_pointers() {
  [ "${#MBASE_POINTERS[@]}" -gt 0 ] || return 0
  echo "Half-applied-upgrade pointer (${#MBASE_POINTERS[@]} — visibility only; NOT part of the verdict, counts, or exit code):"
  local x
  for x in "${MBASE_POINTERS[@]}"; do echo "  ? $x"; done
  echo "  This asks rather than asserts on purpose: a half-applied tree and a tree you edited"
  echo "  yourself are byte-identical locally, so a verdict here would be a guess, and acting"
  echo "  on a wrong one makes the tree worse."
  echo ""
  return 0
}
