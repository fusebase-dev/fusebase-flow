#!/usr/bin/env bash
# Fusebase Flow — po-investigate read-only-guarantee regression test.
# The PO investigation wrapper (hooks/local/po-investigate.sh) forwards args to
# git diff/log/show. Those subcommands accept args that WRITE FILES (--output=<path>)
# or RUN EXTERNAL PROGRAMS (--ext-diff + GIT_EXTERNAL_DIFF, a pager, an editor) — a
# "read-only" wrapper that forwards them isn't read-only (Phase C audit M2).
#
# Genuine RED->GREEN: the RED arm reconstructs the PRE-FIX wrapper from git history
# (the parent of the hardening commit) and proves the escape vector WAS live there;
# the GREEN arm proves the SHIPPED wrapper refuses it with no file written. If the
# hardening is ever reverted, GREEN fails; if the RED baseline stops breaching, the
# test surfaces that its premise moved (loud, never false-green).
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: po-investigate <name>"
# / "FAIL: po-investigate <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WRAPPER="$ROOT/hooks/local/po-investigate.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: po-investigate $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: po-investigate $1 ($2)"; }
finish() { echo "[test-po-investigate] $pass/$((pass + fail)) PASS"; rm -rf "$TMP" 2>/dev/null; exit $fail; }

TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/po-inv-$$")"
mkdir -p "$TMP"

[ -f "$WRAPPER" ] || { bad "setup-wrapper-present" "missing $WRAPPER"; finish; }
command -v git >/dev/null 2>&1 || { bad "setup-git-present" "git not on PATH"; finish; }
ok "setup-inputs-present"

# ---------------------------------------------------------------------------
# RED baseline: reconstruct the pre-hardening wrapper and prove the vector bit.
# The hardening lives in the commit that changed WRAPPER; its parent is the RED
# source. If WRAPPER isn't yet committed (implement-loop), fall back to the last
# commit that touched it — still the pre-fix content until this change lands.
# ---------------------------------------------------------------------------
LAST_WRAP_COMMIT="$(git -C "$ROOT" log -1 --format=%H -- hooks/local/po-investigate.sh 2>/dev/null || true)"
RED_REF=""
if [ -n "$LAST_WRAP_COMMIT" ]; then
    # If the wrapper is already hardened at HEAD (committed), RED = its parent.
    if git -C "$ROOT" show "${LAST_WRAP_COMMIT}:hooks/local/po-investigate.sh" 2>/dev/null | grep -q "_reject_git_escapes"; then
        RED_REF="${LAST_WRAP_COMMIT}~1"
    else
        RED_REF="$LAST_WRAP_COMMIT"
    fi
fi

RED_WRAPPER="$TMP/po-investigate.red.sh"
if [ -n "$RED_REF" ] && git -C "$ROOT" show "${RED_REF}:hooks/local/po-investigate.sh" > "$RED_WRAPPER" 2>/dev/null && [ -s "$RED_WRAPPER" ]; then
    if grep -q "_reject_git_escapes" "$RED_WRAPPER"; then
        # The chosen RED ref is already hardened — premise moved; surface loudly.
        bad "red-baseline-is-prefix" "RED ref $RED_REF already carries the fix (cannot prove the vector was live)"
    else
        red_out="$TMP/red-breach.txt"; rm -f "$red_out"
        bash "$RED_WRAPPER" diff --output="$red_out" HEAD~1 HEAD >/dev/null 2>&1 || true
        if [ -f "$red_out" ]; then
            ok "red-prefix-wrapper-breaches (--output wrote a file pre-fix)"
        else
            bad "red-prefix-wrapper-breaches" "pre-fix wrapper did NOT write via --output (vector premise unproven)"
        fi
    fi
else
    # No git history for the wrapper (fresh copy / shallow) — skip RED, keep GREEN authoritative.
    ok "red-baseline-skipped-no-history"
fi

# ---------------------------------------------------------------------------
# GREEN: the shipped wrapper refuses every write/exec-escape (no file written),
# and legit read-only investigation still works unchanged.
# ---------------------------------------------------------------------------

# Each refused-vector case: run it, assert NO file written AND nonzero exit (fail closed).
refuse_case() { # refuse_case <name> <expect-file> <cmd...>
    local name="$1" f="$2"; shift 2
    rm -f "$f"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [ -f "$f" ]; then
        bad "$name" "escape STILL wrote $(basename "$f")"
    elif [ "$rc" -eq 0 ]; then
        bad "$name" "escape did not write but wrapper exited 0 (must fail closed, nonzero)"
    else
        ok "$name (refused, no file, rc=$rc)"
    fi
}

refuse_case "green-diff-output-refused"  "$TMP/g-diff.txt"  bash "$WRAPPER" diff --output="$TMP/g-diff.txt" HEAD~1 HEAD
refuse_case "green-diff-output-eq-o"     "$TMP/g-o.txt"     bash "$WRAPPER" diff -o "$TMP/g-o.txt" HEAD~1 HEAD
refuse_case "green-show-output-refused"  "$TMP/g-show.txt"  bash "$WRAPPER" show --output="$TMP/g-show.txt" HEAD
refuse_case "green-log-output-refused"   "$TMP/g-log.txt"   bash "$WRAPPER" log --output="$TMP/g-log.txt" --oneline -3
refuse_case "green-ext-diff-flag-refused" "$TMP/g-ext.txt"  env GIT_EXTERNAL_DIFF="touch $TMP/g-ext.txt;" bash "$WRAPPER" diff --ext-diff HEAD~1 HEAD
refuse_case "green-c-config-refused"     "$TMP/g-cfg.txt"   bash "$WRAPPER" diff -c "diff.external=touch $TMP/g-cfg.txt;" --ext-diff HEAD~1 HEAD
refuse_case "green-paginate-refused"     "$TMP/g-pag.txt"   env GIT_PAGER="touch $TMP/g-pag.txt; cat" bash "$WRAPPER" log --paginate --oneline -3

# Env scrub: an inherited GIT_EXTERNAL_DIFF must NOT fire even on a legit diff (no --ext-diff).
scrub_out="$TMP/g-scrub.txt"; rm -f "$scrub_out"
if GIT_EXTERNAL_DIFF="touch $scrub_out;" bash "$WRAPPER" diff HEAD~1 HEAD >/dev/null 2>&1 && [ ! -f "$scrub_out" ]; then
    ok "green-env-scrub-no-external-exec"
else
    [ -f "$scrub_out" ] && bad "green-env-scrub-no-external-exec" "scrubbed env still executed GIT_EXTERNAL_DIFF" \
                        || bad "green-env-scrub-no-external-exec" "legit diff failed under inherited env"
fi

# Legit read-only investigation still works (exit 0), unchanged.
legit_case() { # legit_case <name> <cmd...>
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name" "legit command rc=$?"; fi
}
legit_case "legit-diff"           bash "$WRAPPER" diff HEAD~1 HEAD
legit_case "legit-diff-stat"      bash "$WRAPPER" diff --stat HEAD~1 HEAD
legit_case "legit-diff-no-ext"    bash "$WRAPPER" diff --no-ext-diff HEAD~1 HEAD
legit_case "legit-log-oneline"    bash "$WRAPPER" log --oneline -20
legit_case "legit-show-file"      bash "$WRAPPER" show HEAD:VERSION
legit_case "legit-status"         bash "$WRAPPER" status
legit_case "legit-output-indicator-not-overblocked" bash "$WRAPPER" diff --output-indicator-new=+ HEAD~1 HEAD

finish
