#!/usr/bin/env bash
# Fusebase Flow — "the base must not record entries the run did not earn" (decision N6-D1).
#
# PROVENANCE: ticket half-apply-self-seals (N6). Lives in a lib because hooks/local/upgrade.sh
# is pinned at its FR-25 module-size baseline (821) and must not grow, and because the
# reasoning is the load-bearing part — the call itself is one line.
#
# WHY (N6): build_plan appends the base refresh as a WHOLESALE copy of the source tree's
# manifest (K13b: "what upstream shipped you this time"). That is true only of paths the run
# actually applied. A consumer with no base classifies every differing pre-existing path
# `unknown-base`; K9 PRESERVES them; the run then records UPSTREAM's bytes as those paths'
# history. The next run reads L != B, U == B and reports `consumer-only` — "YOU changed
# these" — for files the consumer never touched, and the release after that reports
# `changed-by-both` and ABORTS. Measured end-to-end against the v4.12.0 engine:
#
#   run 1  rc 0 · applied 2 · preserved 9 · VERSION 9.9.9-fork -> 4.11.0
#          hooks/local/control.sh   base==upstream:True  base==local:False
#   run 2  changed-by-both hooks/local/control.sh  ->  ABORTED rc 3
#
# TRIPWIRE — this is NOT a refusal, and must never become one. Refusing the run when no
# trustworthy base could be built keys on CAUSE (synthesis failed), which is decision N3's
# explicitly rejected alternative: "trigger on synthesis failure — rejected: strands the
# forked consumer who still received files. The refusal must key on outcome, not on cause."
# N2 protects the same population, and the shipped oracle
# `test-upgrade-delivers-or-refuses.sh :: n2-forked-still-proceeds` asserts rc 0 + VERSION
# advanced + no refusal on this exact shape. N6-D1 keys on OUTCOME instead: what the run
# delivered decides what the base may claim. The forked consumer still receives files and
# still advances VERSION — only the unearned base entries are dropped.
#
# WHY OMITTING BEATS RECORDING: a path missing from the base re-classifies `unknown-base`,
# which is preserve AND REPORT, every run — K9's designed safe residue, visible and
# recoverable. A path recorded with bytes the run never delivered is silent and permanent.
#
# TRIPWIRE (write window) — the prune runs immediately AFTER the apply loop wrote the base,
# because the base copy is the plan's last entry (K13b ordering, which must not be
# reordered). A crash between those two points leaves today's unpruned base — no worse than
# the current engine, and the run's ERR trap prints the recovery hint. Do NOT "fix" this by
# moving the base refresh earlier in the plan: a mid-run failure would then leave a base
# claiming content that was never written, which is the failure K13b ordered against.
#
# CONTRACT
#   fftb_prune_base <base-manifest> <omit-list> <mcm-module> <py-fn>
#     base-manifest  the base this run just wrote (repo-relative)
#     omit-list      <plan-file>.unclassified, written by managed_content_manifest.py plan
#     mcm-module     managed_content_manifest.py to run (the SOURCE tree's — upgrade.sh:312)
#     py-fn          the caller's ISOLATED python runner (ff_up_py), never a bare python3:
#                    this rewrites the classifier's own reference data, so a startup-file
#                    injection here would decide what counts as a consumer edit later.
#   rc 0 always — a missing sidecar, a missing manifest or an older module is a NO-OP, never
#   a failed upgrade. The engine that could not prune behaves exactly as it does today.

fftb_prune_base() {
  local base="${1:-}" omit="${2:-}" mcm="${3:-}" py_fn="${4:-}" n
  [ -n "$base" ] && [ -f "$base" ] || return 0
  [ -n "$omit" ] && [ -s "$omit" ] || return 0
  [ -n "$mcm" ] && [ -f "$mcm" ] || return 0
  command -v "$py_fn" >/dev/null 2>&1 || return 0
  n="$(grep -c . "$omit" 2>/dev/null || echo 0)"
  if "$py_fn" "$mcm" prune-base --manifest "$base" --omit-file "$omit" >/dev/null 2>&1; then
    echo "[upgrade] base records only what this run delivered: omitted $n unclassified path(s)"
    echo "                    (they had no historical base entry, so they were PRESERVED, not"
    echo "                     applied — recording upstream's bytes for them would report them"
    echo "                     as YOUR edits next release. They stay reported as 'unknown-base'.)"
  else
    echo "[upgrade] WARN: could not prune unearned entries from $base (decision N6-D1)." >&2
    echo "                The upgrade itself is unaffected, but the NEXT run may report the" >&2
    echo "                $n preserved path(s) as 'consumer-only'. Recovery:" >&2
    echo "                  docs/ADVISORY-2026-08-20-missing-base-upgrade.md" >&2
  fi
  return 0
}
