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

finish
