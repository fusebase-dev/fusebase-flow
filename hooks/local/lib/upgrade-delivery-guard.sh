#!/usr/bin/env bash
# Fusebase Flow — "a run that delivered nothing must not claim it did" (decision N3).
#
# PROVENANCE: ticket n5-upgrade-silent-no-op. Lives in a lib because `hooks/local/upgrade.sh`
# sits at the FR-25 ceiling (794/800 before this ticket), and because the reasoning below is
# the load-bearing part — the predicate itself is four lines.
#
# WHY (N5): `upgrade.sh`'s header claims "VERSION as the LAST step — so VERSION can never
# advance ahead of content". That is an ORDERING guarantee, and N5 proved ordering
# insufficient: with every managed path classified `unknown-base` and preserved, VERSION
# advanced ahead of content SEMANTICALLY while the ordering rule was satisfied, the run
# exited 0, and the dry run showed no conflicts. 26 paths kept, 0 refreshed, nothing
# downstream able to notice. The consumer found it by hand-grepping for three known fixes.
#
# TRIPWIRE — this is NOT a per-path abort, and must never become one. K9 is LOCKED:
# `unknown-base` is preserve+report, and only `changed-by-both` stops an unattended run
# (aborting on `unknown-base` is K9's Option A, rejected as "unusable first adoption").
# This is a RUN-LEVEL honesty rule that touches no classification verdict.
#
# TRIPWIRE — the trigger keys on ZERO-REFRESHED, never on synthesis failing. A forked or
# unreleased VERSION cannot resolve an upstream tag, so no base can be synthesized; if that
# consumer still receives files, they proceed exactly as before. Keying on the cause instead
# of the outcome would strand precisely the consumer least able to recover.
#
# THE THIRD CLAUSE IS WHAT MAKES IT CORRECT, not merely strict: a tree that is already
# current, and a release that touches no managed path, both refresh zero files and must NOT
# trip. Only the N5 shape has `unknown-base` present with zero applied.
#
#   VERSION would change  AND  applied == 0 AND removed == 0  AND  >=1 unknown-base
#
# EXIT CODE: 4 — deliberately distinct from 3 (`changed-by-both`: a conflict a human must
# reconcile) and from 0. "Delivered nothing" is a third outcome that had no code of its own,
# which is exactly why it was indistinguishable from success.
#
# CONTRACT (reads from the caller's scope): VERSION_CHANGE, FF_UNKNOWN_BASE, LOCAL_VERSION.
#   ff_n5_nothing_delivered <applied> <removed>   rc 0 = trigger fires
#   ff_n5_report                                  the operator-facing refusal + recovery
#   ff_n5_dry_run_refuses <apply-plan>            rc 0 = a real run would refuse (prints)

# ff_n5_delivery_count <apply-plan> <base-manifest-path> -> files this run actually DELIVERS.
#
# DECISION N4 — the classifier's own base manifest does NOT count. It is the engine's
# reference data, the thing that lets it tell the consumer's edits from upstream's: bookkeeping
# the engine writes FOR ITSELF, not content the consumer's tree exists to receive. Counting it
# lets the engine satisfy its own honesty check with an artifact it authored — the same shape
# as a self-referential provenance stamp, where the check passes because both sides of the
# comparison come from the same place.
#
# TRIPWIRE — this exclusion is why the guard is not a decoration. The base manifest is absent
# EXACTLY in the N5 scenario (its absence is what produces the whole-tree `unknown-base`), so
# upstream is guaranteed to "deliver" it precisely when the guard most needs to fire. With it
# counted, the oracle's refusal rows reported "VERSION advanced" and the guard was INERT.
#
# THE PRINCIPLE, for whoever adds the next such artifact: classifier bookkeeping the engine
# writes for itself does not count toward delivery; anything the consumer's tree exists to
# receive does. Add it HERE rather than re-deriving this.
#
# TRIPWIRE — scope is deliberately narrow: this path only, NOT `audit/*`. A release that
# genuinely ships only manifest changes is real delivery, and excluding them would trade an
# inert guard for a FALSE REFUSAL — the opposite failure, and the worse one, because the
# consumer then cannot upgrade at all.
ff_n5_delivery_count() {
  local plan="${1:-}" base="${2:-audit/managed-content-manifest.json}" n=0 op path
  [ -n "$plan" ] && [ -f "$plan" ] || { printf '0'; return 0; }
  while IFS=$'\t' read -r op path; do
    [ -n "${path:-}" ] || continue
    case "$op" in copy|delete) ;; *) continue ;; esac
    [ "$path" = "$base" ] && continue
    n=$((n + 1))
  done < "$plan"
  printf '%s' "$n"
}

ff_n5_nothing_delivered() {
  [ -n "${VERSION_CHANGE:-}" ] || return 1
  [ "${1:-0}" -eq 0 ] || return 1
  [ "${FF_UNKNOWN_BASE:-0}" -ge 1 ] || return 1
  return 0
}

# Recovery advice, branched on WHY no base could be reconstructed (FFSB_REASON, set by
# lib/synthesize-base.sh).
#
# TRIPWIRE — advice the operator cannot follow is worse than none. The single blanket message
# this replaced said "run bootstrap-upgrade.sh, it synthesizes the base from that tag". On a
# plain-directory source (no-git) that run WAS bootstrap-upgrade.sh and no tag can be recovered
# from a directory; on a forked VERSION (no-tag) the tag does not exist upstream and re-running
# ANY engine re-derives the same `v$(cat VERSION)` and fails identically. Both arms therefore
# sent the operator in a circle — in the release that exists because a consumer had to hand-grep
# to find what an upgrade silently skipped. Keep every arm runnable, or say plainly that no
# automatic recovery exists for that shape. Do NOT collapse these back into one string.
ff_n5_recovery() {
  case "${FFSB_REASON:-}" in
    no-git)
      echo "          Recovery — the source this run read is a PLAIN DIRECTORY with no git" >&2
      echo "          history, so NO upstream tag can be recovered from it. Re-running the same" >&2
      echo "          command against the same source will fail identically." >&2
      echo "            1. docs/release-fingerprints.md identifies the upstream tag matching your" >&2
      echo "               installed VERSION (${LOCAL_VERSION:-?})." >&2
      echo "            2. Point the upgrade at a source that CARRIES that history:" >&2
      echo "               bash hooks/local/bootstrap-upgrade.sh --repo <git-url-or-clone> \\" >&2
      echo "                    --ref <branch-or-tag> -- --auto-yes" >&2
      ;;
    no-tag)
      echo "          Recovery — there is NO AUTOMATIC recovery for this shape, and saying" >&2
      echo "          otherwise would waste your time: your installed VERSION" >&2
      echo "          (${LOCAL_VERSION:-?}) has no upstream tag — it is forked or unreleased —" >&2
      echo "          so no engine can reconstruct a base from history. A human decides:" >&2
      echo "            1. docs/release-fingerprints.md lists each released tree's fingerprint." >&2
      echo "               Match YOUR tree against them to find the release you descend from." >&2
      echo "               Match it by fingerprint, never by guess: seeding from the wrong" >&2
      echo "               release misclassifies every path it disagrees with." >&2
      echo "            2. Set VERSION to that release, then re-run — synthesis resolves the tag" >&2
      echo "               from VERSION, so this is what makes the tag findable." >&2
      echo "            3. Or accept this outcome: NOTHING was lost. Every path was preserved;" >&2
      echo "               little was refreshed. Re-run when you can identify the base." >&2
      ;;
    *)
      echo "          Recovery — seed the base from the tag you are actually on:" >&2
      echo "            1. docs/release-fingerprints.md identifies the upstream tag for your" >&2
      echo "               installed VERSION (${LOCAL_VERSION:-?})." >&2
      echo "            2. bash hooks/local/bootstrap-upgrade.sh -- --auto-yes" >&2
      echo "               (it synthesizes audit/managed-content-manifest.json from that tag," >&2
      echo "                then upgrades; that path already does what this run could not)." >&2
      ;;
  esac
}

ff_n5_report() {
  echo "" >&2
  echo "[upgrade] DELIVERED NOTHING — refusing to bump VERSION." >&2
  echo "          ${FF_UNKNOWN_BASE:-0} managed path(s) classified 'unknown-base' and were preserved," >&2
  echo "          and NOT ONE file was refreshed. Advancing VERSION here would record an" >&2
  echo "          upgrade that did not happen." >&2
  echo "" >&2
  echo "          This is NOT a conflict needing a human decision (that is 'changed-by-both'," >&2
  echo "          exit 3). It means no classifier base could be reconstructed, so the engine" >&2
  echo "          could not tell YOUR edits from upstream's and safely kept everything." >&2
  echo "" >&2
  ff_n5_recovery
  echo "" >&2
  echo "          Do NOT stamp a base from your current tree: that records your local edits" >&2
  echo "          as 'upstream base', and the next upstream change then overwrites them (K13b)." >&2
}

# AC5: the preview must surface the same condition. The consumer's report specifically noted
# that the dry run showed no conflicts — a preview that hides this is the same silence one
# step earlier, and it is where an operator decides whether to run the real thing.
ff_n5_dry_run_refuses() {
  # Same definition of "delivery" as the real run — one function, so the preview and the
  # outcome can never disagree about what would have happened.
  ff_n5_nothing_delivered "$(ff_n5_delivery_count "${1:-}" "${2:-audit/managed-content-manifest.json}")" || return 1
  ff_n5_report
  echo "[upgrade] (dry-run; nothing written) — and a real run would REFUSE, per above." >&2
  return 0
}
