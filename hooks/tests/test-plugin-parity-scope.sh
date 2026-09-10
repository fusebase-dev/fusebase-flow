#!/usr/bin/env bash
# Fusebase Flow — N4 residual: plugin-manifest parity is PUBLISHER-ONLY.
# Spec: docs/specs/half-apply-self-seals/spec.md § S5.
#
# THE COMPLAINT: all three of the consumer's manifests carry `name: fusebase-flow`, so the
# ownership-scoped parity check fires in THEIR repo — while `list-managed --dirs` returns only
# flow-skills agents workflows policies templates hooks, so no upgrade will ever refresh them.
# Result: a hand edit after every release. They have now done it twice (4.9.2, 4.11.0).
#
# WHY SCOPING AND NOT ADOPTION — the review locked this and it is the whole point of the slice:
# adopting the three manifests into the managed set would let an upgrade OVERWRITE a consumer's
# own (Fusebase CLI-generated) plugin manifest. managed_content_manifest.py:38-44 already
# records that reasoning. A publisher-context check that misses enforcement fails VISIBLY; a
# managed adoption corrupts ownership SILENTLY, and silently is the one that costs a year.
#
# WHY `name` ALONE WAS NOT ENOUGH: existence is not ownership, and neither is the name. The
# consumer's manifests are named fusebase-flow because they were generated FROM Flow's. The
# question the check actually asks — "does plugin.json's version match the version being
# released?" — is only meaningful where VERSION is Flow's own release version, i.e. in the
# publisher repo. In a consumer, VERSION is the version of Flow they INSTALLED, and their
# plugin surface has its own lifecycle.
#
# THE PUBLISHER MARKER is docs/release-fingerprints.md — the release ledger. It is not managed
# content (docs/ is not in MANAGED_DIRS), --with-framework-docs stages framework docs under
# docs/_fusebase-flow/ rather than this path, and preflight §10 already uses exactly this
# marker to scope the tag-row assertion. One marker, two publisher-only checks.
#
# ROW CLASSES:
#   DISCRIMINATOR  n4-consumer-repo-not-checked   — the reported defect: no error in a consumer
#   ANTI-REGRESSION n4-publisher-repo-still-checked — scoping must not disable enforcement
#   PRESERVED      n4-foreign-name-still-skipped  — the existing ownership test still holds
#   PRESERVED      n4-marketplace-scoped-too      — same rule for marketplace.json
#   LOCK           n4-plugin-manifests-not-managed — adoption stays forbidden
#   REAL-PATH      s2-* rows below run the shipped engine over a copy of this tree: wiring is
#                  not selection, and the packaging verdict was unreachable behind BROKEN.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: n4-parity-scope <name>" / "FAIL: n4-parity-scope <name>"; exit = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: n4-parity-scope $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: n4-parity-scope $1$w"; }
skip(){ pass=$((pass + 1)); echo "PASS: n4-parity-scope $1 [SKIP — $2]"; }
finish() { echo "[test-plugin-parity-scope] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { skip setup "no python3"; finish; }

LIB="hooks/local/lib/plugin-parity.sh"
BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-n4.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

# repo <dir> <plugin-name> <plugin-version> <ledger:0|1> [marketplace-version]
repo_at() {
  local D="$1" name="$2" pver="$3" ledger="$4" mver="${5:-}"
  mkdir -p "$D/.claude-plugin" "$D/.codex-plugin" "$D/docs"
  echo "4.11.0" > "$D/VERSION"
  printf '{"name": "%s", "version": "%s"}\n' "$name" "$pver" > "$D/.claude-plugin/plugin.json"
  printf '{"name": "%s", "version": "%s"}\n' "$name" "$pver" > "$D/.codex-plugin/plugin.json"
  [ -n "$mver" ] && printf '{"plugins": [{"name": "%s", "version": "%s"}]}\n' "$name" "$mver" \
    > "$D/.claude-plugin/marketplace.json"
  [ "$ledger" = "1" ] && printf '# Release fingerprints\n\n| tag |\n|---|\n| v4.11.0 |\n' \
    > "$D/docs/release-fingerprints.md"
  return 0
}

errs() { ( cd "$1" && bash -c '. "$0"/'"$LIB"' 2>/dev/null && ffpp_errors' "$ROOT" 2>/dev/null ); }

###############################################################################
# DISCRIMINATOR — the consumer's repo must be left alone
###############################################################################
C="$BASE_TMP/consumer"; repo_at "$C" fusebase-flow 4.9.2 0 4.9.2
OUT="$(errs "$C")"
f=""
[ -f "$LIB" ] || f="$f [$LIB does not exist]"
[ -n "$OUT" ] && f="$f [errored in a CONSUMER repo (no release ledger): '$OUT' — this is the hand edit they have now made after two consecutive releases]"
[ -z "$f" ] && ok "n4-consumer-repo-not-checked (manifests named fusebase-flow but no release ledger => publisher-only check stays silent; no hand edit after every release)" \
            || bad n4-consumer-repo-not-checked "$f"

###############################################################################
# ANTI-REGRESSION — scoping must not become disabling
###############################################################################
P="$BASE_TMP/publisher"; repo_at "$P" fusebase-flow 4.9.2 1
OUT="$(errs "$P")"
f=""
printf '%s' "$OUT" | grep -q "plugin.json" \
  || f="$f [no parity error in a PUBLISHER repo whose plugin.json (4.9.2) lags VERSION (4.11.0) — scoping has turned into disabling, and the drift this check exists for (it once lagged ~20 minor versions) goes unnoticed]"
printf '%s' "$OUT" | grep -q "4.9.2" || f="$f [the error does not name the offending version]"
printf '%s' "$OUT" | grep -q "4.11.0" || f="$f [the error does not name VERSION]"
[ -z "$f" ] && ok "n4-publisher-repo-still-checked (release ledger present => the lagging plugin.json still fails, naming both versions)" \
            || bad n4-publisher-repo-still-checked "$f"

###############################################################################
# PRESERVED — a foreign name is still not ours, ledger or not
###############################################################################
F="$BASE_TMP/foreign"; repo_at "$F" some-other-plugin 1.0.0 1
OUT="$(errs "$F")"
f=""
# ANTI-VACUITY (F-N5-1): "it did not error" is trivially true when the lib does not exist.
[ -f "$LIB" ] || f="$f [$LIB does not exist, so 'no error' proves nothing]"
[ -n "$OUT" ] && f="$f [errored on a manifest Flow does not own ('$OUT') — existence is not ownership, and the name test must survive the new scoping]"
[ -z "$f" ] && ok "n4-foreign-name-still-skipped (a foreign plugin name is skipped even in a publisher repo; the two tests are AND-ed, not swapped)" \
            || bad n4-foreign-name-still-skipped "$f"

###############################################################################
# PRESERVED — marketplace.json follows the same rule (it is manually bumped too)
###############################################################################
M="$BASE_TMP/mkt"; repo_at "$M" fusebase-flow 4.11.0 1 4.9.0
OUT="$(errs "$M")"
f=""
printf '%s' "$OUT" | grep -q "marketplace.json" \
  || f="$f [publisher repo with marketplace.json at 4.9.0 vs VERSION 4.11.0 raised nothing — it is not written by sync-version-strings.sh, so unchecked means it silently drifts]"
M2="$BASE_TMP/mkt-consumer"; repo_at "$M2" fusebase-flow 4.11.0 0 4.9.0
printf '%s' "$(errs "$M2")" | grep -q "marketplace.json" \
  && f="$f [marketplace.json parity still fires in a CONSUMER repo — same defect, different file]"
[ -z "$f" ] && ok "n4-marketplace-scoped-too (marketplace parity is enforced in the publisher repo and silent in a consumer, same as plugin.json)" \
            || bad n4-marketplace-scoped-too "$f"

###############################################################################
# LOCK — adoption into the managed set stays forbidden
###############################################################################
f=""
MANAGED="$(python3 hooks/local/lib/managed_content_manifest.py list-managed 2>/dev/null)"
[ -n "$MANAGED" ] || f="$f [could not read the managed set]"
printf '%s' "$MANAGED" | grep -qE "plugin\.json|marketplace\.json" \
  && f="$f [a plugin manifest is in the MANAGED set — adoption lets an upgrade OVERWRITE a consumer's own Fusebase CLI-generated manifest (managed_content_manifest.py:38-44). A publisher-context check that misses enforcement fails visibly; this corrupts ownership silently]"
[ -z "$f" ] && ok "n4-plugin-manifests-not-managed (the three manifests stay OUT of the managed set — the rejected alternative stays rejected)" \
            || bad n4-plugin-manifests-not-managed "$f"

###############################################################################
# WIRING — the scoping only matters if preflight actually uses it
###############################################################################
f=""
PF="hooks/local/preflight.sh"
grep -q "plugin-parity.sh" "$PF" || f="$f [$PF does not source the lib, so the consumer repo still errors in the field]"
grep -q "ffpp_errors" "$PF" || f="$f [$PF never calls ffpp_errors]"
grep -qE '^[[:space:]]*for pj in \.claude-plugin/plugin\.json' "$PF"   && f="$f [the OLD unscoped parity loop is still present in $PF — two implementations of one rule, and the unscoped one still fires]"
[ -z "$f" ] && ok "n4-check-is-wired (preflight delegates parity to the publisher-scoped lib, and the old unscoped loop is gone — one implementation, not two)"             || bad n4-check-is-wired "$f"


###############################################################################
# HEALTH REUSE (S2) — the health engine must apply BOTH predicates, via the SAME helper
###############################################################################
# THE COMPLAINT, second instance: lib/partial-upgrade-check.sh carried predicate 1 (ownership by
# `name`) but not predicate 2 (publisher context), so the consumer above ALSO got a health
# PARTIAL_UPGRADE verdict for the same three manifests. It drove them to hand-copy the
# publisher's manifest bytes twice to get a clean verdict — the consumer-ownership risk the
# exclusion exists to prevent. Spec: docs/specs/hop-log-truthfulness-and-publisher-scope/spec.md § S2.
PU_LIB="hooks/local/lib/partial-upgrade-check.sh"
C3_PREFIX_SHA="44d0fd2"   # the reviewed pre-fix health arm; C3 anti-regression source
ENGINE="hooks/local/fusebase-flow-health-check.sh"
RECS="hooks/local/lib/health-recommendations.sh"

# Health's packaging arm in <dir>, with a recording record_drift: one "check_id|message" per finding.
health_pkg() {
  ( cd "$1" && bash -c 'PUBLISHER_PACKAGING_FINDINGS=(); record_drift() { printf "%s|%s\n" "$1" "$2"; }; . hooks/local/lib/partial-upgrade-check.sh 2>/dev/null; ffhc_publisher_packaging_collect' 2>/dev/null )
}
health_adapters() {
  ( cd "$1" && bash -c '. hooks/local/lib/partial-upgrade-check.sh 2>/dev/null; ffhc_partial_upgrade_findings' 2>/dev/null )
}
# repo_at plus the libs health sources, so the fixture exercises the shipped code paths.
health_repo_at() {
  repo_at "$@"
  mkdir -p "$1/hooks/local/lib"
  cp "$ROOT/$PU_LIB" "$ROOT/$LIB" "$1/hooks/local/lib/"
}

f=""
[ -f "$ROOT/$PU_LIB" ] || f="$f [$PU_LIB does not exist, so every assertion below is vacuous]"
HC="$BASE_TMP/health-consumer"; health_repo_at "$HC" fusebase-flow 4.9.2 0 4.9.2
OUT="$(health_pkg "$HC")"
[ -n "$OUT" ] && f="$f [health flagged a CONSUMER's copied-name manifests: '$OUT' — the false positive that made them hand-copy our bytes]"
printf '%s' "$(health_adapters "$HC")" | grep -q "plugin.json" \
  && f="$f [the adapter arm still reports plugin.json, so two implementations of the plugin rule are live again]"
# ANTI-REGRESSION: v4.15.3's health arm DID fire on this fixture. Without it the row is vacuous.
OLD_LIB="$BASE_TMP/old-partial-upgrade-check.sh"
if git show v4.15.3:hooks/local/lib/partial-upgrade-check.sh > "$OLD_LIB" 2>/dev/null; then
  OLD_OUT="$( cd "$HC" && bash -c '. "$0"; ffhc_partial_upgrade_findings' "$OLD_LIB" 2>/dev/null )"
  printf '%s' "$OLD_OUT" | grep -q "plugin.json" \
    || f="$f [v4.15.3's health arm did NOT flag this consumer fixture, so the fixture is not the reported defect]"
else
  f="$f [could not read the v4.15.3 health arm, so this row cannot establish the regression]"
fi
[ -z "$f" ] && ok "s2-health-consumer-manifests-not-flagged (health applies the publisher predicate too; v4.15.3 flagged this same fixture)" \
            || bad s2-health-consumer-manifests-not-flagged "$f"

f=""
HP="$BASE_TMP/health-publisher"; health_repo_at "$HP" fusebase-flow 4.9.2 1
OUT="$(health_pkg "$HP")"
printf '%s' "$OUT" | grep -q "plugin.json" \
  || f="$f [a PUBLISHER manifest lagging VERSION raised nothing — scoping has turned into disabling]"
printf '%s' "$OUT" | grep -q "^publisher_packaging|PACKAGING_DRIFT" \
  || f="$f [the finding does not carry its own class/check_id: '$OUT']"
printf '%s' "$OUT" | grep -q "PARTIAL_UPGRADE" \
  && f="$f [publisher packaging drift is still labelled PARTIAL_UPGRADE — it is packaging drift, not an interrupted upgrade]"
grep -q 'DRIFT_SIGNATURE="PUBLISHER_PACKAGING_DRIFT"' "$ROOT/$ENGINE" \
  || f="$f [$ENGINE has no PUBLISHER_PACKAGING_DRIFT verdict, so the finding cannot get its own interpretation]"
grep -q "PUBLISHER_PACKAGING_DRIFT)" "$ROOT/$RECS" \
  || f="$f [$RECS has no publisher remediation, so the operator still gets the interrupted-upgrade advice]"
grep -A4 "PUBLISHER_PACKAGING_DRIFT)" "$ROOT/$RECS" | grep -qi "interrupted upgrade" \
  || f="$f [the publisher remediation does not say this is NOT an interrupted upgrade]"
[ -z "$f" ] && ok "s2-publisher-mismatch-is-packaging-not-partial-upgrade (still fails in the publisher repo, under its own class, verdict and remediation)" \
            || bad s2-publisher-mismatch-is-packaging-not-partial-upgrade "$f"

f=""
HM="$BASE_TMP/health-mkt"; health_repo_at "$HM" fusebase-flow 4.11.0 1 4.9.0
printf '%s' "$(health_pkg "$HM")" | grep -q "marketplace.json" \
  || f="$f [marketplace.json parity is NOT in health's scope; the recorded decision to include it was not implemented]"
HM2="$BASE_TMP/health-mkt-consumer"; health_repo_at "$HM2" fusebase-flow 4.11.0 0 4.9.0
printf '%s' "$(health_pkg "$HM2")" | grep -q "marketplace.json" \
  && f="$f [marketplace.json parity fires in a CONSUMER repo through health — same defect, different file]"
[ -z "$f" ] && ok "s2-marketplace-included-deliberately (decision: marketplace.json IS in health's publisher arm; still silent in a consumer)" \
            || bad s2-marketplace-included-deliberately "$f"

f=""
HI="$BASE_TMP/health-indep"; health_repo_at "$HI" fusebase-flow 4.9.2 0
rm -f "$HI/hooks/local/lib/plugin-parity.sh"
printf 'runs **Fusebase Flow v4.1.0**\n' > "$HI/AGENTS.md"
printf '| FR-01 |\n' > "$HI/FLOW_RULES.md"
printf '%s' "$(health_adapters "$HI")" | grep -q "AGENTS.md" \
  || f="$f [a stale consumer adapter stopped failing once the plugin helper was unavailable — the diagnostics are not independent]"
printf '%s' "$(health_pkg "$HI")" | grep -q . \
  && f="$f [the packaging arm invented a finding with no helper present]"
[ -z "$f" ] && ok "s2-adapter-checks-stay-independent (a missing plugin helper does not suppress the stale-adapter findings)" \
            || bad s2-adapter-checks-stay-independent "$f"

f=""
HR="$BASE_TMP/health-readonly"; health_repo_at "$HR" fusebase-flow 4.9.2 1
BEFORE="$(cd "$HR" && find . -type f -exec cksum {} + 2>/dev/null | sort)"
health_pkg "$HR" >/dev/null 2>&1
health_adapters "$HR" >/dev/null 2>&1
AFTER="$(cd "$HR" && find . -type f -exec cksum {} + 2>/dev/null | sort)"
[ -n "$BEFORE" ] || f="$f [could not snapshot the fixture, so read-only proves nothing]"
[ "$BEFORE" = "$AFTER" ] || f="$f [health's checks changed bytes in the tree they inspect]"
[ -z "$f" ] && ok "s2-health-stays-read-only (both arms leave every byte of the inspected tree untouched)" \
            || bad s2-health-stays-read-only "$f"

###############################################################################
# R2 — CR/LF normalization must be SYMMETRIC, and one violation must stay one line
###############################################################################
# THE DEFECT (corrections.md § Round 2, R2): ffpp_field returned the JSON value verbatim, so a
# version carrying CRLF made the echo emit TWO lines for ONE violation with the first
# CR-terminated, while the classifier stripped a trailing CR from the PREFLIGHT side only. A run
# that genuinely was packaging-only was rejected and reported BROKEN.
R2_SHA="13ebe20"   # the rejecting bytes; round-2 anti-regression source

f=""
CRV="$BASE_TMP/crlf-value"; repo_at "$CRV" fusebase-flow 4.11.0 1   # in-sync elsewhere: the CRLF value is the ONLY violation
# JSON escapes, so the PARSED value carries a real CR+LF inside it (not a trailing CR).
printf '{"name": "fusebase-flow", "version": "4.15.2\\r\\n-rc1"}\n' > "$CRV/.claude-plugin/plugin.json"
OUT="$(errs "$CRV")"
R2_LINES="$(printf '%s\n' "$OUT" | grep -c 'plugin.json version')"
[ "$R2_LINES" = "1" ] \
  || f="$f [a CRLF-bearing version produced $R2_LINES parity lines, not 1 — one violation must be one line (the lib's CONTRACT) or health can never match it line for line]"
printf '%s' "$OUT" | grep -qF '4.15.2\r\n-rc1' || f="$f [the finding does not render the value it found: '$OUT']"
[ "$(printf '%s' "$OUT" | wc -c)" = "$(printf '%s' "$OUT" | tr -d '\r\n' | wc -c)" ] \
  || f="$f [the finding still carries a CR or LF byte, so the preflight line it produces cannot match it]"
[ -z "$f" ] && ok "r2-crlf-value-is-one-finding (a JSON version carrying CRLF yields exactly one CR/LF-free parity line)" \
            || bad r2-crlf-value-is-one-finding "$f"

###############################################################################
# R4 — the rendering must not decide the comparison
###############################################################################
# THE DEFECT (corrections.md § Round 2, R4): R2 stripped CR/LF inside ffpp_field, i.e. BEFORE the
# ownership and equality tests, so a manifest version whose raw bytes differ from VERSION but whose
# stripped text equals it produced NO finding at all — in preflight and in health. R2's fixture
# (4.15.2\r\n-rc1) stays unequal after stripping, so it cannot catch this; this one strips to equal.
R4_SHA="d763f6c"   # the losing bytes; the escape replaced them

f=""
EQV="$BASE_TMP/crlf-strips-to-equal"; repo_at "$EQV" fusebase-flow 4.11.0 1
# repo_at writes VERSION=4.11.0. The PARSED value is 4.11.<CR><LF>0: byte-different from VERSION,
# byte-IDENTICAL to it once CR/LF is removed.
printf '{"name": "fusebase-flow", "version": "4.11.\\r\\n0"}\n' > "$EQV/.claude-plugin/plugin.json"
OUT="$(errs "$EQV")"
R4_LINES="$(printf '%s\n' "$OUT" | grep -c 'plugin.json version')"
[ "$R4_LINES" = "1" ] \
  || f="$f [a version that differs from VERSION only in CR/LF bytes produced $R4_LINES parity lines, not 1 — the mismatch is real and must be reported, once]"
printf '%s' "$OUT" | grep -qF '4.11.\r\n0' \
  || f="$f [the finding does not render the CR/LF the manifest actually carries, so the operator cannot see WHY it differs: '$OUT']"
[ "$(printf '%s' "$OUT" | wc -c)" = "$(printf '%s' "$OUT" | tr -d '\r\n' | wc -c)" ] \
  || f="$f [the finding carries a raw CR or LF byte, so health can never match it line for line]"
# ANTI-REGRESSION: $R4_SHA normalized before comparing and emitted NOTHING here. Without this the
# row cannot tell the fix from the defect.
R4_OLD_PP="$BASE_TMP/r4-old-plugin-parity.sh"
if git show "$R4_SHA:$LIB" > "$R4_OLD_PP" 2>/dev/null && [ -s "$R4_OLD_PP" ]; then
  R4_OLD="$( cd "$EQV" && bash -c '. "$0" 2>/dev/null && ffpp_errors' "$R4_OLD_PP" 2>/dev/null )"
  printf '%s' "$R4_OLD" | grep -q . \
    && f="$f [$R4_SHA reported '$R4_OLD' on this fixture; if it did not lose the finding, this row is vacuous]"
else
  f="$f [could not extract $R4_SHA's $LIB, so this row cannot establish the regression]"
fi
[ -z "$f" ] && ok "r4-stripped-equal-is-still-a-mismatch (a version equal to VERSION only after stripping still reports one line; on $R4_SHA's bytes it reported nothing)" \
            || bad r4-stripped-equal-is-still-a-mismatch "$f"

# Ownership is an identifier match on the RAW name: `fusebase-flow<CR><LF>` is not the name, so the
# manifest is not Flow's to police — 13ebe20's behaviour, which R2's strip had silently widened.
f=""
NCR="$BASE_TMP/crlf-name"; repo_at "$NCR" fusebase-flow 4.11.0 1
printf '{"name": "fusebase-flow\\r\\n", "version": "9.9.9"}\n' > "$NCR/.claude-plugin/plugin.json"
OUT="$(errs "$NCR")"
printf '%s' "$OUT" | grep -q '.claude-plugin/plugin.json' \
  && f="$f [a manifest whose name is not exactly fusebase-flow was policed anyway: '$OUT'; ownership must not be decided by a normalization either]"
printf '%s' "$OUT" | grep -q . \
  && f="$f [an unrelated finding appeared on this fixture: '$OUT']"
[ -z "$f" ] && ok "r4-ownership-compares-raw-name (a CR/LF-bearing name is not the fusebase-flow identifier, so the manifest is left alone)" \
            || bad r4-ownership-compares-raw-name "$f"

# pkg_only <finding> <one preflight error text> -> the shipped classifier's rc.
# The finished line is part of the synthetic output because completion is one of the conditions.
pkg_only() {
  bash -c 'PUBLISHER_PACKAGING_FINDINGS=("$1"); . "$0" 2>/dev/null
ffhc_preflight_is_packaging_only "[preflight] ERROR: $2
[preflight] preflight finished — errors: 1, warnings: 0"' "$ROOT/$PU_LIB" "$1" "$2"
}

f=""
R2_CR="$(printf '\r')"
pkg_only "pkg finding$R2_CR" "pkg finding$R2_CR" \
  || f="$f [a finding and a preflight line that BOTH end in CR were rejected — the strip is still one-sided]"
pkg_only "pkg finding$R2_CR" "pkg finding" \
  || f="$f [a finding ending in CR was rejected against a clean preflight line — the asymmetry R2 names]"
pkg_only "pkg finding" "some other error" \
  && f="$f [a preflight line that is NOT a packaging finding was accepted as packaging-only]"
[ -z "$f" ] && ok "r2-classifier-normalizes-both-sides (a trailing CR on either side or both still matches; a non-finding line still does not)" \
            || bad r2-classifier-normalizes-both-sides "$f"

# crlf_rc <plugin-parity.sh> <partial-upgrade-check.sh> -> classifier rc on the CRLF fixture,
# with the preflight output rebuilt from THAT helper's own findings (one err per line, as preflight does).
crlf_rc() {
  ( cd "$CRV" && bash -c 'PUBLISHER_PACKAGING_FINDINGS=(); . "$0" 2>/dev/null; . "$1" 2>/dev/null
out=""; n=0
while IFS= read -r e; do
  [ -n "$e" ] || continue
  PUBLISHER_PACKAGING_FINDINGS+=("$e"); n=$((n + 1)); out="$out[preflight] ERROR: $e
"
done < <(ffpp_errors 2>/dev/null)
out="$out[preflight] preflight finished — errors: $n, warnings: 0"
ffhc_preflight_is_packaging_only "$out"; echo $?' "$1" "$2" 2>/dev/null )
}

f=""
[ "$(crlf_rc "$ROOT/$LIB" "$ROOT/$PU_LIB")" = "0" ] \
  || f="$f [the CRLF fixture is still NOT read as packaging-only, so a publisher whose manifest carries a line break is still reported BROKEN]"
R2_OLD_PP="$BASE_TMP/r2-old-plugin-parity.sh"; R2_OLD_PU="$BASE_TMP/r2-old-pu.sh"
if git show "$R2_SHA:$LIB" > "$R2_OLD_PP" 2>/dev/null && git show "$R2_SHA:$PU_LIB" > "$R2_OLD_PU" 2>/dev/null \
   && [ -s "$R2_OLD_PP" ] && [ -s "$R2_OLD_PU" ]; then
  R2_OLD_RC="$(crlf_rc "$R2_OLD_PP" "$R2_OLD_PU")"
  [ "$R2_OLD_RC" = "1" ] \
    || f="$f [$R2_SHA's helper+classifier returned rc '$R2_OLD_RC' on the CRLF fixture; if it was not the rejection (1) this row is vacuous]"
else
  f="$f [could not extract $R2_SHA's $LIB / $PU_LIB, so this row cannot establish the regression]"
fi
[ -z "$f" ] && ok "r2-crlf-fixture-is-packaging-only (the CRLF fixture now classifies as packaging-only; on $R2_SHA's bytes the same fixture was rejected)" \
            || bad r2-crlf-fixture-is-packaging-only "$f"

###############################################################################
# R1 unit rows — positive establishment: completed AND reconciled AND text
###############################################################################
# THE PRINCIPLE (corrections.md § Round 2, R1): absence of parseable evidence is not evidence of
# packaging-only. Each condition below is necessary; none is sufficient alone.
FIN1='[preflight] preflight finished — errors: 1, warnings: 0'
FIN2='[preflight] preflight finished — errors: 2, warnings: 0'
# pkg_raw <finding> <raw combined output> -> the shipped classifier rc (empty finding => no findings).
pkg_raw() {
  bash -c 'if [ -n "$1" ]; then PUBLISHER_PACKAGING_FINDINGS=("$1"); else PUBLISHER_PACKAGING_FINDINGS=(); fi
. "$0" 2>/dev/null; ffhc_preflight_is_packaging_only "$2"' "$ROOT/$PU_LIB" "$1" "$2"
}

f=""
pkg_raw "pkg finding" "[preflight] ERROR: pkg finding" \
  && f="$f [no completion marker, yet the run was read as packaging-only — an unfinished run establishes nothing]"
pkg_raw "pkg finding" "[preflight] ERROR: pkg finding
$FIN2" \
  && f="$f [the finished line reported 2 errors against 1 matched line and the run was still read as packaging-only — the unprefixed failure is exactly what (b) must catch]"
pkg_raw "pkg finding" "[preflight] ERROR: pkg finding
$FIN1" \
  || f="$f [a completed, reconciled, text-matching run was NOT read as packaging-only — the positive path is broken]"
pkg_raw "pkg finding" "" \
  && f="$f [an EMPTY capture was read as packaging-only — this is mechanism 1, the false-HEALTHY]"
pkg_raw "" "[preflight] ERROR: pkg finding
$FIN1" \
  && f="$f [no packaging findings were collected, yet a preflight error was attributed to packaging]"
pkg_raw "pkg finding" "$FIN1" \
  && f="$f [a completed run with NO prefixed error line was read as packaging-only — (c) requires at least one]"
pkg_raw "pkg finding" "[preflight] ERROR: pkg finding
[preflight] preflight finished — errors: , warnings: 0" \
  && f="$f [an unparsable error count was accepted — an unreadable marker establishes nothing]"
[ -z "$f" ] && ok "r1-packaging-only-must-be-positively-established (completed + reconciled + text; empty, unfinished, unreconciled and findingless inputs all fall through to BROKEN)" \
            || bad r1-packaging-only-must-be-positively-established "$f"



###############################################################################
# S2/C3 — REAL-PATH verdict selection. The rows above prove the arm is WIRED; these prove the
# verdict is SELECTED. An ordinary publisher manifest mismatch also fails preflight, and BROKEN
# is decided before the packaging class, so PUBLISHER_PACKAGING_DRIFT was unreachable in a real
# run. Driven through the shipped engine — no replaced record_drift, no grepping for strings.
###############################################################################
PUB="$BASE_TMP/publisher-tree"
BK="$BASE_TMP/backup"; mkdir -p "$PUB" "$BK"
copy_ok=0
if ( cd "$ROOT" && tar -cf - --exclude=./.git --exclude=./.fusebase-flow-source . ) 2>/dev/null \
   | ( cd "$PUB" && tar -xf - ) 2>/dev/null; then
  [ -f "$PUB/VERSION" ] && [ -f "$PUB/$ENGINE" ] && [ -f "$PUB/docs/release-fingerprints.md" ] && copy_ok=1
fi
# health <dir> -> prints "<exit>|<verdict>"; the full report is left at <dir>/.hc.out
health_verdict() {
  local out rc
  out="$( cd "$1" && bash hooks/local/fusebase-flow-health-check.sh --no-upstream 2>&1 )"; rc=$?
  printf '%s' "$out" > "$1/.hc.out"
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | grep -m1 '^Verdict: ' | sed 's/^Verdict: //')"
}

if [ "$copy_ok" -ne 1 ]; then
  bad s2-publisher-packaging-only-is-not-broken "could not stage a copy of the publisher tree, so the real-path rows cannot run"
  bad s2-prefix-engine-read-packaging-as-broken "no publisher tree fixture"
  bad s2-unrelated-preflight-error-still-broken "no publisher tree fixture"
  bad s2-consumer-lagged-manifest-is-not-publisher-drift "no publisher tree fixture"
else
  ( cd "$PUB" && git init -q . && git config user.email t@example.invalid && git config user.name t ) >/dev/null 2>&1
  cp "$PUB/.claude-plugin/plugin.json" "$BK/plugin.json"
  cp "$PUB/GEMINI.md" "$BK/GEMINI.md" 2>/dev/null
  # Lag the plugin manifest by one patch: parity is then the ONLY preflight error.
  python3 - "$PUB" <<'PY' 2>/dev/null
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]) / ".claude-plugin/plugin.json"
o = json.loads(p.read_text(encoding="utf-8"))
a, b, c = o["version"].split(".")
o["version"] = "%s.%s.%d" % (a, b, int(c) - 1)
p.write_text(json.dumps(o, indent=2) + "\n", encoding="utf-8")
PY

  f=""
  PF_OUT="$( cd "$PUB" && bash hooks/local/preflight.sh 2>&1 )"
  PF_ERRS="$(printf '%s\n' "$PF_OUT" | grep -c '^\[preflight\] ERROR: ')"
  [ "$PF_ERRS" = "1" ] \
    || f="$f [the copied tree has $PF_ERRS preflight errors, not 1 — parity must be the only one for this row to be the defect: $(printf '%s\n' "$PF_OUT" | grep '^\[preflight\] ERROR: ' | head -3)]"
  printf '%s\n' "$PF_OUT" | grep -q 'plugin.json version' \
    || f="$f [the lagged manifest did not produce the parity preflight error]"
  R="$(health_verdict "$PUB")"
  [ "$R" = "1|PUBLISHER_PACKAGING_DRIFT" ] \
    || f="$f [a publisher tree whose ONLY preflight error is manifest parity reported '$R', not 1|PUBLISHER_PACKAGING_DRIFT. Non-OK items: $(grep -E '^  [✗⚠]' "$PUB/.hc.out" | head -3). A stale audit/hook-layer-manifest.json in the SOURCE tree lands here as FLOW_LAYER_DRIFT: re-stamp before re-running]"
  grep -q '^Verdict: BROKEN' "$PUB/.hc.out" && f="$f [the run still reports BROKEN]"
  grep -qi 'NOT an interrupted upgrade' "$PUB/.hc.out" \
    || f="$f [the packaging remediation ('packaging drift, NOT an interrupted upgrade') never reached the operator]"
  [ -z "$f" ] && ok "s2-publisher-packaging-only-is-not-broken (real run: parity is the only preflight error => Verdict: PUBLISHER_PACKAGING_DRIFT, exit 1, with the packaging remediation)" \
              || bad s2-publisher-packaging-only-is-not-broken "$f"

  # ANTI-REGRESSION: the pre-fix engine on this same fixture recorded BROKEN, which outranks the
  # packaging class — that is why the verdict was unreachable.
  f=""
  OLD_ENGINE="$BASE_TMP/old-engine.sh"; OLD_PU="$BASE_TMP/old-pu.sh"
  if git show "$C3_PREFIX_SHA:$ENGINE" > "$OLD_ENGINE" 2>/dev/null \
     && git show "$C3_PREFIX_SHA:$PU_LIB" > "$OLD_PU" 2>/dev/null \
     && [ -s "$OLD_ENGINE" ] && [ -s "$OLD_PU" ]; then
    cp "$PUB/$ENGINE" "$BK/engine.sh"; cp "$PUB/$PU_LIB" "$BK/pu.sh"
    cp "$OLD_ENGINE" "$PUB/$ENGINE"; cp "$OLD_PU" "$PUB/$PU_LIB"
    R="$(health_verdict "$PUB")"
    cp "$BK/engine.sh" "$PUB/$ENGINE"; cp "$BK/pu.sh" "$PUB/$PU_LIB"
    [ "${R#*|}" = "BROKEN" ] \
      || f="$f [$C3_PREFIX_SHA's engine reported '$R' on the packaging-only fixture; if it was not BROKEN the verdict was already reachable and these rows prove nothing]"
  else
    f="$f [could not extract $C3_PREFIX_SHA's engine/lib, so this row cannot establish the regression]"
  fi
  [ -z "$f" ] && ok "s2-prefix-engine-read-packaging-as-broken (anti-vacuity: on the same fixture $C3_PREFIX_SHA reports BROKEN, so PUBLISHER_PACKAGING_DRIFT was unreachable)" \
              || bad s2-prefix-engine-read-packaging-as-broken "$f"

  # One preflight error that is NOT a packaging finding must still be BROKEN.
  f=""
  rm -f "$PUB/GEMINI.md"
  R="$(health_verdict "$PUB")"
  [ "$R" = "2|BROKEN" ] \
    || f="$f [packaging drift plus an unrelated preflight error reported '$R', not 2|BROKEN — a real breakage was reclassified as packaging]"
  [ -f "$BK/GEMINI.md" ] && cp "$BK/GEMINI.md" "$PUB/GEMINI.md"
  [ -z "$f" ] && ok "s2-unrelated-preflight-error-still-broken (one non-parity preflight error alongside the packaging finding still reports BROKEN, exit 2)" \
              || bad s2-unrelated-preflight-error-still-broken "$f"

  # A consumer (no release ledger) with the same lagged manifest: parity is silent end to end.
  f=""
  mv "$PUB/docs/release-fingerprints.md" "$BK/release-fingerprints.md"
  PF_OUT="$( cd "$PUB" && bash hooks/local/preflight.sh 2>&1 )"
  printf '%s\n' "$PF_OUT" | grep -q 'plugin.json version' \
    && f="$f [the parity check fired in a tree with no release ledger — the consumer defect is back]"
  R="$(health_verdict "$PUB")"
  case "${R#*|}" in
    BROKEN|PUBLISHER_PACKAGING_DRIFT) f="$f [a consumer tree with a lagged manifest reported '$R']" ;;
  esac
  mv "$BK/release-fingerprints.md" "$PUB/docs/release-fingerprints.md"
  [ -z "$f" ] && ok "s2-consumer-lagged-manifest-is-not-publisher-drift (no ledger: preflight is clean on parity and the verdict is neither BROKEN nor PUBLISHER_PACKAGING_DRIFT)" \
              || bad s2-consumer-lagged-manifest-is-not-publisher-drift "$f"

  ###############################################################################
  # R1 REAL-PATH — a preflight FAILURE is a fact of its own, not a property of its output
  ###############################################################################
  # Both mechanisms the re-review executed from the shipped statements, driven through the engine.
  # The anti-regression stages ALL THREE changed files from $R1_SHA together: the fix spans the
  # engine, the classifier and preflight, and any one alone would misreport the pre-fix state.
  R1_SHA="13ebe20"
  R1_OLD_ENGINE="$BASE_TMP/r1-old-engine.sh"; R1_OLD_PU="$BASE_TMP/r1-old-pu.sh"; R1_OLD_PF="$BASE_TMP/r1-old-preflight.sh"
  r1_have_old=0
  git show "$R1_SHA:$ENGINE" > "$R1_OLD_ENGINE" 2>/dev/null \
    && git show "$R1_SHA:$PU_LIB" > "$R1_OLD_PU" 2>/dev/null \
    && git show "$R1_SHA:$PF" > "$R1_OLD_PF" 2>/dev/null \
    && [ -s "$R1_OLD_ENGINE" ] && [ -s "$R1_OLD_PU" ] && [ -s "$R1_OLD_PF" ] && r1_have_old=1
  # preflight.sh IS a hook-layer asset, so every byte swap below re-stamps the FIXTURE manifest:
  # without it an integrity finding, not the verdict under test, would carry the row.
  r1_swap() {   # r1_swap old|new -> put that generation of the three files in $PUB and re-stamp
    if [ "$1" = old ]; then
      cp "$R1_OLD_ENGINE" "$PUB/$ENGINE"; cp "$R1_OLD_PU" "$PUB/$PU_LIB"; cp "$R1_OLD_PF" "$PUB/$PF"
    else
      cp "$ROOT/$ENGINE" "$PUB/$ENGINE"; cp "$ROOT/$PU_LIB" "$PUB/$PU_LIB"; cp "$ROOT/$PF" "$PUB/$PF"
    fi
    ( cd "$PUB" && bash hooks/local/stamp-hook-manifest.sh ) >/dev/null 2>&1
  }

  # --- Row R1-traceback: an UNPREFIXED failure beside a packaging finding ---
  # plugin.json is still lagged from the rows above; the frontmatter reader raises on an undecodable
  # SKILL.md (read_text(encoding="utf-8")), which at $R1_SHA raised errors with no prefixed line.
  # Mirror drift is a warn, not an err, so this adds exactly one unprefixed failure.
  f=""
  R1_SKILL="$PUB/flow-skills/zoom-out/SKILL.md"
  if [ "$r1_have_old" -ne 1 ]; then
    f="$f [could not extract $ENGINE / $PU_LIB / $PF at $R1_SHA, so the anti-regression cannot run]"
  elif [ ! -f "$R1_SKILL" ]; then
    f="$f [$R1_SKILL is absent, so the undecodable-skill injection cannot run]"
  else
    cp "$R1_SKILL" "$BK/zoom-out-SKILL.md"
    python3 -c 'import pathlib,sys
p = pathlib.Path(sys.argv[1]); p.write_bytes(bytes([255, 254]) + p.read_bytes())' "$R1_SKILL"
    r1_swap old
    R="$(health_verdict "$PUB")"
    [ "$R" = "1|PUBLISHER_PACKAGING_DRIFT" ] \
      || f="$f [$R1_SHA reported '$R' on the traceback fixture, not the SUPPRESSION (1|PUBLISHER_PACKAGING_DRIFT) this row exists to pin. If an unrelated PREFIXED error fired, the fixture is wrong, not the row: $(grep -E '^  [✗⚠]' "$PUB/.hc.out" | head -3)]"
    r1_swap new
    R="$(health_verdict "$PUB")"
    [ "$R" = "2|BROKEN" ] \
      || f="$f [an unprefixed preflight failure beside a packaging finding reported '$R', not 2|BROKEN — a real breakage is still hidden behind the packaging class]"
    grep -q "preflight: errors detected" "$PUB/.hc.out" \
      || f="$f [the run has no preflight BROKEN entry, so an integrity or adapter finding is carrying the verdict]"
  fi
  [ -z "$f" ] && ok "r1-unprefixed-failure-beside-packaging-is-broken (undecodable SKILL.md + lagged manifest: BROKEN/2 now, PUBLISHER_PACKAGING_DRIFT/1 at $R1_SHA)" \
              || bad r1-unprefixed-failure-beside-packaging-is-broken "$f"

  # --- Row R1-source: same count, same exit, one more line ---
  f=""
  if [ "$r1_have_old" -ne 1 ] || [ ! -f "$BK/zoom-out-SKILL.md" ]; then
    f="$f [the traceback fixture was not built, so the preflight comparison cannot run]"
  else
    R1_NEW_OUT="$( cd "$PUB" && bash hooks/local/preflight.sh 2>&1 )"; R1_NEW_RC=$?
    cp "$R1_OLD_PF" "$PUB/$PF"
    R1_OLD_OUT="$( cd "$PUB" && bash hooks/local/preflight.sh 2>&1 )"; R1_OLD_RC=$?
    cp "$ROOT/$PF" "$PUB/$PF"
    printf '%s\n' "$R1_NEW_OUT" | grep -q '^\[preflight\] ERROR: preflight subcheck did not complete cleanly' \
      || f="$f [the raising subcheck produced no PREFIXED fixed-phrase line, so neither the classifier nor a human can see it]"
    R1_NEW_N="$(printf '%s\n' "$R1_NEW_OUT" | sed -n 's/^\[preflight\] preflight finished — errors: \([0-9]*\).*/\1/p' | tail -1)"
    R1_OLD_N="$(printf '%s\n' "$R1_OLD_OUT" | sed -n 's/^\[preflight\] preflight finished — errors: \([0-9]*\).*/\1/p' | tail -1)"
    [ -n "$R1_NEW_N" ] && [ "$R1_NEW_N" = "$R1_OLD_N" ] \
      || f="$f [the finished line reports errors: '$R1_NEW_N' where $R1_SHA reported '$R1_OLD_N' — the wrapper must add the same count, not a different one]"
    [ "$R1_NEW_RC" = "$R1_OLD_RC" ] \
      || f="$f [preflight exited $R1_NEW_RC where $R1_SHA exited $R1_OLD_RC — the exit contract changed]"
    R1_NEW_L="$(printf '%s\n' "$R1_NEW_OUT" | grep -c '^\[preflight\] ERROR: ')"
    R1_OLD_L="$(printf '%s\n' "$R1_OLD_OUT" | grep -c '^\[preflight\] ERROR: ')"
    [ "$R1_NEW_L" = "$((R1_OLD_L + 1))" ] \
      || f="$f [the new preflight printed $R1_NEW_L prefixed lines against $R1_OLD_L at $R1_SHA — expected exactly one more]"
    [ "$R1_OLD_L" -lt "$R1_OLD_N" ] \
      || f="$f [$R1_SHA printed $R1_OLD_L prefixed lines for $R1_OLD_N errors, so this fixture never reproduced the unprefixed failure and the row is vacuous]"
  fi
  [ -z "$f" ] && ok "r1-exception-path-emits-a-prefixed-error (same errors: count, same exit code, exactly one more prefixed line than $R1_SHA)" \
              || bad r1-exception-path-emits-a-prefixed-error "$f"

  # --- Row R1-empty: a failure with NO output at all ---
  # No manifest lag, no packaging findings: rc != 0 with an empty capture must still reach BROKEN.
  f=""
  if [ "$r1_have_old" -ne 1 ]; then
    f="$f [could not extract the three files at $R1_SHA, so the anti-regression cannot run]"
  else
    [ -f "$BK/zoom-out-SKILL.md" ] && cp "$BK/zoom-out-SKILL.md" "$R1_SKILL"
    cp "$BK/plugin.json" "$PUB/.claude-plugin/plugin.json"
    r1_swap old
    printf '#!/usr/bin/env bash\nexit 1\n' > "$PUB/$PF"; chmod +x "$PUB/$PF"
    ( cd "$PUB" && bash hooks/local/stamp-hook-manifest.sh ) >/dev/null 2>&1
    R1_PRE="$(health_verdict "$PUB")"
    [ "$R1_PRE" = "0|HEALTHY" ] \
      || f="$f [$R1_SHA reported '$R1_PRE' on an otherwise clean tree whose preflight failed with empty output; this row exists to pin the FALSE-HEALTHY (0|HEALTHY). Non-OK items: $(grep -E '^  [✗⚠]' "$PUB/.hc.out" | head -3)]"
    grep -qE '^  [✗⚠] preflight' "$PUB/.hc.out" \
      && f="$f [$R1_SHA recorded a preflight item after all, so the mechanism is not the one this row pins]"
    cp "$ROOT/$ENGINE" "$PUB/$ENGINE"; cp "$ROOT/$PU_LIB" "$PUB/$PU_LIB"
    R="$(health_verdict "$PUB")"
    [ "$R" = "2|BROKEN" ] \
      || f="$f [a preflight that failed with EMPTY output reported '$R', not 2|BROKEN — the failure is still inferred from the output instead of recorded as a fact]"
    grep -q "preflight: errors detected" "$PUB/.hc.out" \
      || f="$f [there is no preflight entry in BROKEN, UNVERIFIED or OK — the failure was recorded nowhere]"
  fi
  [ -z "$f" ] && ok "r1-empty-failure-output-is-broken-not-healthy (rc != 0 with no output: BROKEN/2 now; $R1_SHA printed HEALTHY/0 on the same fixture)" \
              || bad r1-empty-failure-output-is-broken-not-healthy "$f"
fi

finish
