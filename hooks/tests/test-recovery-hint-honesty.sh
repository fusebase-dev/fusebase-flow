#!/usr/bin/env bash
# Fusebase Flow — M19: the post-failure recovery hint must not imply engine continuity.
# Decision: docs/specs/upgrade-source-integrity-and-observability/decisions.md § M19.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT:
#   M19 is a WORDING fix and claims NO behavioural discriminator. There is no runtime difference
#   to observe: the same commands are printed either way. What changed is whether the text tells
#   the operator the truth about WHICH ENGINE the re-run executes. So these are residency
#   assertions over the shipped `print_recovery_hint`, named accordingly — they establish that
#   the honest statement is present and the withdrawn continuity claim is gone. They do not, and
#   cannot, establish anything about an upgrade run.
#
# Why the wording matters (consumer report 2026-08-04 § 3): the block used to call the re-run
# "idempotent — the refreshed engine finishes the rest". Step 1 refreshes hooks/ INCLUDING the
# engine, so after a mid-run failure the on-disk engine may already be a DIFFERENT one. A
# consumer whose locally wired gate had just reported their security substance was gone was told
# to re-run — into an engine with zero references to that gate. A clean exit would have been
# indistinguishable from "the gate no longer exists".
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: recovery-hint <name>" / "FAIL: recovery-hint <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
UPGRADE="$ROOT/hooks/local/upgrade.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: recovery-hint $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: recovery-hint $1 (${2:-})"; }
finish() { echo "[test-recovery-hint-honesty] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$UPGRADE" ] || { bad "setup-upgrade-present" "missing $UPGRADE"; finish; }

# Comment lines are stripped: the M19 tripwire NAMES the withdrawn claim ("idempotent"), so a
# comment-inclusive grep would flag the tripwire that exists to prevent the regression.
HINT="$(awk '/^print_recovery_hint\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$UPGRADE" | grep -vE '^[[:space:]]*#')"
[ -n "$HINT" ] || { bad "setup-extract-hint" "print_recovery_hint not found in upgrade.sh"; finish; }

# ---- 1. The honest statement is present ------------------------------------------------
f=""
printf '%s' "$HINT" | grep -qi 'REFRESHED engine' \
  || f="$f [does not say the re-run executes the REFRESHED engine]"
printf '%s' "$HINT" | grep -qi 'may differ' \
  || f="$f [does not say the refreshed engine's behaviour may differ from the one that failed]"
printf '%s' "$HINT" | grep -qiE 'seams? it does not invoke|not invoke' \
  || f="$f [does not warn that the refreshed engine may not invoke seams the failed one did]"
printf '%s' "$HINT" | grep -qi 'NOT evidence' \
  || f="$f [does not say a clean exit from the re-run is not evidence the check still exists - that is the operational point]"
[ -z "$f" ] && ok "m19-states-the-engine-swap (residency: names the refreshed engine, that behaviour may differ, unrun seams, and that a clean re-run proves nothing)" \
  || bad "m19-states-the-engine-swap" "$f
--- print_recovery_hint ---
$HINT"

# ---- 2. The withdrawn continuity claim is gone -----------------------------------------
f=""
printf '%s' "$HINT" | grep -qi 'idempotent' \
  && f="$f [still calls the re-run idempotent - M19 removes exactly that continuity claim]"
printf '%s' "$HINT" | grep -qi 'finishes the rest' \
  && f="$f [still says the refreshed engine 'finishes the rest', which asserts continuity across an engine swap]"
[ -z "$f" ] && ok "m19-continuity-claim-removed (no 'idempotent' / 'finishes the rest' in the printed block)" \
  || bad "m19-continuity-claim-removed" "$f
--- print_recovery_hint ---
$HINT"

# ---- 3. Flow must NOT pretend to know a consumer's seam ---------------------------------
# M19 explicitly rejects the reporter's suggested wording ("name the gate the refreshed engine
# does not invoke"): a locally wired gate is invisible upstream, so naming one would be a
# fabricated specific. The generic statement is the fix.
f=""
printf '%s' "$HINT" | grep -qiE 'check-post-upgrade-gate|your gate is|the gate named|does not invoke `[a-z]' \
  && f="$f [names a specific consumer gate - Flow cannot know one, so any name here is fabricated]"
printf '%s' "$HINT" | grep -qi 'run that gate yourself' \
  || f="$f [does not tell the operator to run their own gate afterwards - the actionable half]"
[ -z "$f" ] && ok "m19-no-fabricated-consumer-seam (generic statement only; tells the operator to run their own gate)" \
  || bad "m19-no-fabricated-consumer-seam" "$f
--- print_recovery_hint ---
$HINT"

# ---- 4. The recovery commands themselves are unchanged ---------------------------------
# M19 changes wording, not mechanism. If a command went missing, the hint is worse, not better.
f=""
for cmd in "bash hooks/local/upgrade.sh" \
           "bash hooks/local/post-fusebase-update.sh --refresh-overlays" \
           "bash hooks/local/sync-version-strings.sh" \
           "bash hooks/local/preflight.sh"; do
  printf '%s' "$HINT" | grep -qF "$cmd" || f="$f [recovery command dropped: $cmd]"
done
[ -z "$f" ] && ok "m19-recovery-commands-intact (wording changed, mechanism did not)" \
  || bad "m19-recovery-commands-intact" "$f"

# ---- 5. ASCII only ----------------------------------------------------------------------
# This block reaches a Windows console whose codec is not UTF-8. LC_ALL=C is load-bearing:
# under a UTF-8 locale [[:print:]] matches printable Unicode, so an em-dash would pass.
if printf '%s' "$HINT" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then
  bad "m19-block-is-ascii-only" "non-ASCII bytes in the printed recovery block: $(printf '%s' "$HINT" | LC_ALL=C grep -n '[^[:print:][:space:]]' | head -3)"
else
  ok "m19-block-is-ascii-only (renders on a non-UTF-8 Windows console)"
fi

# ---- 6. The stale continuity claim is gone from the file header too --------------------
# FR-20: the same false statement lived in the main() header comment. Fixing one carrier and
# leaving the other is how a corrected claim comes back.
HEADER="$(sed -n '1,70p' "$UPGRADE")"
if printf '%s' "$HEADER" | grep -qi 'remaining steps idempotently'; then
  bad "m19-header-comment-not-left-stale" "hooks/local/upgrade.sh's main() header still tells a reader the re-run completes 'the remaining steps idempotently' - the same claim M19 removed from the printed block"
else
  ok "m19-header-comment-not-left-stale (the header carries the same correction as the printed block)"
fi

finish
