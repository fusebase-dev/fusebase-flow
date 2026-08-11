#!/usr/bin/env bash
# Fusebase Flow — INSTALLED_FROM typed consumed-source provenance (T1 / S1; AC1-AC9).
# Spec: docs/specs/consumer-escalation-v480/spec.md.
#
# What this phase owns: the AC9 regression matrix — Git direct, Git bootstrap, plain source,
# early already-current no-op (with and without a prior marker), failure after materialization,
# prior-marker preservation, atomic replacement, source-manifest exclusion, missing marker,
# malformed marker — plus the AC1 typed-schema rules the writer and reader share.
#
# TRIPWIRE (decision M10): the plain-source rows are not optional coverage. A plain directory is
# a SUPPORTED source with no commit SHA, so a git-only provenance design fails there; deleting
# those rows is what would let such a design look green.
#
# What it does NOT claim: nothing here detects a moved tag. S1 is attribution only (R3 stays
# open), and a consumer that never upgrades keeps reporting `unknown`.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: installed-from <name>" / "FAIL: installed-from <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: installed-from $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: installed-from $1 (${2:-})"; }
finish() { echo "[test-installed-from-provenance] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: installed-from skipped-no-python3"; pass=1; finish; }
command -v git >/dev/null 2>&1 || { echo "PASS: installed-from skipped-no-git"; pass=1; finish; }

# shellcheck source=lib/upgrade-fixtures.sh
. "$ROOT/hooks/tests/lib/upgrade-fixtures.sh"
# The unit under test is the SHIPPED lib, sourced directly — the schema has exactly one
# implementation and the reader validates by re-rendering through it.
# shellcheck source=../local/lib/installed-provenance.sh
. "$ROOT/hooks/local/lib/installed-provenance.sh"

MARKER="INSTALLED_FROM"
SCHEMA="fusebase-flow/installed-from/v1"
HEX40="0123456789abcdef0123456789abcdef01234567"
HEX64="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

marker_line() { head -1 "$1/$MARKER" 2>/dev/null; }
marker_bytes() { wc -c < "$1/$MARKER" 2>/dev/null | tr -cd '0-9'; }
tmp_residue() { find "$1" -maxdepth 1 -name ".$MARKER.ff-prov-tmp.*" 2>/dev/null | head -1; }

# A consumer + plain source that are ALREADY identical and ship no classifier, which is the
# only shape that actually reaches upgrade.sh's pre-write "already matches upstream" exit.
noop_case() {   # <dir> -> echoes the consumer root
  local D="$1" L U f
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/local/lib" "$L/workflows" "$U"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t )
  echo "4.8.0" > "$L/VERSION"
  printf 'wf v1\n' > "$L/workflows/wf.md"
  cp "$ROOT/hooks/local/upgrade.sh" "$L/hooks/local/"
  for f in materialize-managed-source.sh backup-hygiene.sh installed-provenance.sh run-with-timeout.sh; do
    [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$L/hooks/local/lib/"
  done
  cp -R "$L/hooks" "$L/workflows" "$L/VERSION" "$U/"
  echo "$L"
}

# ---- AC1: the typed schema is the writer's ONLY vocabulary -----------------------------------
# Render is also the reader's validator, so every rule proved here is enforced on read too.
a1=""
[ "$(ff_prov_render git "$HEX40")" = "{\"schema\":\"$SCHEMA\",\"source_kind\":\"git\",\"git_commit\":\"$HEX40\"}" ] \
  || a1="$a1 [git render is not the canonical form]"
[ "$(ff_prov_render plain "$HEX64")" = "{\"schema\":\"$SCHEMA\",\"source_kind\":\"plain\",\"content_digest\":\"sha256:$HEX64\"}" ] \
  || a1="$a1 [plain render is not the canonical form]"
for bad_case in "git:$HEX64" "git:${HEX40}0" "git:${HEX40%?}" "git:${HEX40^^}" "git:" \
                "plain:$HEX40" "plain:${HEX64}0" "plain:sha256:$HEX64" "plain:" \
                "unknown:$HEX40" "invalid:$HEX40" ":$HEX40"; do
  if ff_prov_render "${bad_case%%:*}" "${bad_case#*:}" >/dev/null 2>&1; then
    a1="$a1 [render accepted '$bad_case']"
  fi
done
[ -z "$a1" ] && ok "ac1-typed-schema-rejects-wrong-kind-length-and-case" \
             || bad "ac1-typed-schema-rejects-wrong-kind-length-and-case" "$a1"

# ---- AC2: direct Git upgrade records the EXACT resolved commit -------------------------------
G_ROOT="$(mktemp -d)"
GL="$(bnd_plain_case "$G_ROOT/case")"
GU="$GL/.fusebase-flow-source"
bnd_git_source "$GU"
# The consumer gets its OWN commit so "not the caller's HEAD" is a real discriminator, not a
# vacuous one against an unborn HEAD.
git -C "$GL" commit -q --allow-empty -m base >/dev/null 2>&1
G_EXPECT="$(git -C "$GU" rev-parse HEAD)"
G_CALLER="$(git -C "$GL" rev-parse HEAD 2>/dev/null || echo none)"
G_LOG="$G_ROOT/log"
( cd "$GL" && bash hooks/local/upgrade.sh --auto-yes ) > "$G_LOG" 2>&1
G_RC=$?
g=""
[ "$G_RC" -eq 0 ] || g="$g [upgrade exited $G_RC]"
ff_prov_read "$GL" || true
[ "$FF_PROV_STATE" = "git" ] || g="$g [state=$FF_PROV_STATE, expected git]"
[ "$FF_PROV_VALUE" = "$G_EXPECT" ] || g="$g [recorded '$FF_PROV_VALUE', expected the resolved $G_EXPECT]"
[ "$FF_PROV_VALUE" != "$G_CALLER" ] || g="$g [recorded the CALLER's HEAD, not the source commit]"
case "$(marker_line "$GL")" in
  *'"source_kind":"git"'*) ;;
  *) g="$g [marker is not source_kind git]" ;;
esac
grep -q 'content_digest' "$GL/$MARKER" 2>/dev/null && g="$g [git marker carries content_digest]"
grep -qE 'main|4\.7\.0' "$GL/$MARKER" 2>/dev/null && g="$g [marker carries a branch name or a VERSION]"
[ "$(tr -d '\n\r' < "$GL/VERSION")" = "4.7.0" ] || g="$g [VERSION did not advance to the source value]"
python3 "$MCM" verify --root "$GL" >/dev/null 2>&1 || g="$g [managed-content manifest does not verify MATCH]"
[ -z "$g" ] && ok "ac2-git-direct-records-resolved-commit" \
            || bad "ac2-git-direct-records-resolved-commit" "$g :: $(tail -6 "$G_LOG" | tr '\n' '|')"

# ---- AC5 (part) + AC9: the marker is absent from the source manifests -------------------------
# Run against the tree that ACTUALLY has one, so this cannot pass by the file simply not existing.
x=""
[ -f "$GL/$MARKER" ] || x="$x [PRECONDITION: no marker to exclude]"
python3 "$MCM" stamp --root "$GL" >/dev/null 2>&1 || x="$x [stamp failed]"
grep -q "$MARKER" "$GL/audit/managed-content-manifest.json" 2>/dev/null \
  && x="$x [managed-content manifest lists $MARKER]"
python3 "$MCM" verify --root "$GL" >/dev/null 2>&1 \
  || x="$x [marker present makes the managed-content manifest DRIFT (reported as extra?)]"
# Both resolvers, and — the part that can actually regress — the exclusion holding even when the
# marker IS named as managed content. Without that arm this row passes for free, because a root
# file outside MANAGED_FILES is excluded by accident rather than by rule.
python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/hooks/local/lib")
import hook_manifest, managed_content_manifest as mcm
from pathlib import Path
root = Path(sys.argv[2])
bad = [n for n, fn in (("hook-layer", hook_manifest.collect_assets),
                       ("managed-content", mcm.collect_paths))
       if "INSTALLED_FROM" in fn(root)]
mcm.MANAGED_FILES = tuple(mcm.MANAGED_FILES) + ("INSTALLED_FROM",)
if "INSTALLED_FROM" in mcm.collect_paths(root):
    bad.append("managed-content-when-declared")
print(",".join(bad))
' "$ROOT" "$GL" 2>/dev/null | grep -q . && x="$x [a manifest resolver collects $MARKER]"
[ -z "$x" ] && ok "ac5-source-manifests-exclude-the-marker" \
            || bad "ac5-source-manifests-exclude-the-marker" "$x"
rm -rf "$G_ROOT"

# ---- AC3: the bootstrap hop records the commit it archived -----------------------------------
B_ROOT="$(mktemp -d)"
BL="$(bnd_plain_case "$B_ROOT/case")"
BU="$BL/.fusebase-flow-source"
bnd_git_source "$BU"
B_EXPECT="$(git -C "$BU" rev-parse main)"
B_LOG="$B_ROOT/log"
( cd "$BL" && bash hooks/local/bootstrap-upgrade.sh --ref main -- --auto-yes ) > "$B_LOG" 2>&1
B_RC=$?
b=""
[ "$B_RC" -eq 0 ] || b="$b [bootstrap exited $B_RC]"
ff_prov_read "$BL" || true
[ "$FF_PROV_STATE" = "git" ] || b="$b [state=$FF_PROV_STATE, expected git]"
[ "$FF_PROV_VALUE" = "$B_EXPECT" ] || b="$b [recorded '$FF_PROV_VALUE', expected the archived $B_EXPECT]"
# The engine echoes the commit it was HANDED, so this proves the value crossed the hop rather
# than being re-derived on the far side.
grep -q "${B_EXPECT:0:12} (resolved commit)" "$B_LOG" 2>/dev/null \
  || b="$b [the resolved commit did not cross the bootstrap handoff]"
[ -z "$b" ] && ok "ac3-git-bootstrap-records-archived-commit" \
            || bad "ac3-git-bootstrap-records-archived-commit" "$b :: $(tail -8 "$B_LOG" | tr '\n' '|')"
rm -rf "$B_ROOT"

# ---- AC4: a plain-directory source is content-addressed, never given an invented SHA ----------
P_ROOT="$(mktemp -d)"
PL="$(bnd_plain_case "$P_ROOT/case")"
PU="$PL/.fusebase-flow-source"
P_LOG="$P_ROOT/log"
( cd "$PL" && bash hooks/local/upgrade.sh --auto-yes ) > "$P_LOG" 2>&1
P_RC=$?
p=""
[ "$P_RC" -eq 0 ] || p="$p [upgrade exited $P_RC]"
ff_prov_read "$PL" || true
[ "$FF_PROV_STATE" = "plain" ] || p="$p [state=$FF_PROV_STATE, expected plain]"
grep -q 'git_commit' "$PL/$MARKER" 2>/dev/null && p="$p [plain marker invented a git_commit member]"
# The consumed snapshot is a copy of a .git-less plain source, so the digest must be
# recomputable from the source itself — otherwise the value is not verifiable by anyone.
P_RECOMPUTED="$(ff_prov_tree_digest "$PU" 2>/dev/null || true)"
[ -n "$P_RECOMPUTED" ] || p="$p [digest is not recomputable from the source directory]"
[ "$FF_PROV_VALUE" = "sha256:$P_RECOMPUTED" ] \
  || p="$p [recorded '$FF_PROV_VALUE' but the source digests to 'sha256:$P_RECOMPUTED']"
python3 "$MCM" verify --root "$PL" >/dev/null 2>&1 || p="$p [managed-content manifest does not verify MATCH]"
[ -z "$p" ] && ok "ac4-plain-source-records-consumed-content-digest" \
            || bad "ac4-plain-source-records-consumed-content-digest" "$p :: $(tail -6 "$P_LOG" | tr '\n' '|')"

# ---- AC9: atomic replacement — one line, no temp residue, prior value gone --------------------
r=""
P_FIRST="$(marker_line "$PL")"
printf '{"schema":"%s","source_kind":"git","git_commit":"%s"}\n' "$SCHEMA" "$HEX40" > "$PL/$MARKER"
( cd "$PL" && bash hooks/local/upgrade.sh --auto-yes ) > "$P_ROOT/log2" 2>&1 || r="$r [second upgrade failed]"
[ "$(marker_line "$PL")" = "$P_FIRST" ] || r="$r [replacement did not restore the consumed-source value]"
[ "$(marker_bytes "$PL")" = "$(( ${#P_FIRST} + 1 ))" ] \
  || r="$r [marker is not exactly one line + newline — appended rather than replaced?]"
[ -z "$(tmp_residue "$PL")" ] || r="$r [a .$MARKER.ff-prov-tmp.* temp file survived]"
[ -z "$r" ] && ok "ac9-atomic-replacement-leaves-one-line-and-no-residue" \
            || bad "ac9-atomic-replacement-leaves-one-line-and-no-residue" "$r"
rm -rf "$P_ROOT"

# ---- AC6: the early already-current exit happens BEFORE any marker write ----------------------
N_ROOT="$(mktemp -d)"
NL="$(noop_case "$N_ROOT/with")"
N_PRIOR="$(ff_prov_render git "$HEX40")"
printf '%s\n' "$N_PRIOR" > "$NL/$MARKER"
N_LOG="$N_ROOT/log"
( cd "$NL" && bash hooks/local/upgrade.sh --auto-yes ) > "$N_LOG" 2>&1
N_RC=$?
n=""
[ "$N_RC" -eq 0 ] || n="$n [no-op run exited $N_RC]"
grep -q "already matches upstream" "$N_LOG" 2>/dev/null \
  || n="$n [PRECONDITION: the run did not take the already-current exit]"
[ "$(marker_line "$NL")" = "$N_PRIOR" ] || n="$n [the no-op rewrote the prior marker]"
[ "$(marker_bytes "$NL")" = "$(( ${#N_PRIOR} + 1 ))" ] || n="$n [the no-op truncated or grew the prior marker]"
[ -z "$n" ] && ok "ac6-early-noop-preserves-a-prior-marker" \
            || bad "ac6-early-noop-preserves-a-prior-marker" "$n :: $(tail -6 "$N_LOG" | tr '\n' '|')"

NL2="$(noop_case "$N_ROOT/without")"
N2_LOG="$N_ROOT/log2"
( cd "$NL2" && bash hooks/local/upgrade.sh --auto-yes ) > "$N2_LOG" 2>&1
n2=""
grep -q "already matches upstream" "$N2_LOG" 2>/dev/null \
  || n2="$n2 [PRECONDITION: the run did not take the already-current exit]"
[ -e "$NL2/$MARKER" ] && n2="$n2 [the no-op invented a marker]"
ff_prov_read "$NL2" || true
[ "$FF_PROV_STATE" = "unknown" ] || n2="$n2 [state=$FF_PROV_STATE, expected unknown]"
case "$(ff_prov_health_line)" in
  *"unknown (provenance marker unavailable)"*) ;;
  *) n2="$n2 [health line does not carry the exact unknown text]" ;;
esac
[ -z "$n2" ] && ok "ac6-early-noop-without-a-prior-marker-reports-unknown" \
             || bad "ac6-early-noop-without-a-prior-marker-reports-unknown" "$n2"
rm -rf "$N_ROOT"

# ---- AC7: a failure AFTER materialization never touches a prior marker -----------------------
# Two distinct post-materialization stops: a FATAL (the source carries no VERSION) and the
# classifier's changed-by-both ABORT. Both must leave the marker byte-identical.
f7=""
F_ROOT="$(mktemp -d)"
FL="$(bnd_plain_case "$F_ROOT/fatal")"
F_PRIOR="$(ff_prov_render plain "$HEX64")"
printf '%s\n' "$F_PRIOR" > "$FL/$MARKER"
rm -f "$FL/.fusebase-flow-source/VERSION"
( cd "$FL" && bash hooks/local/upgrade.sh --auto-yes ) > "$F_ROOT/fatal.log" 2>&1
[ $? -eq 0 ] && f7="$f7 [the missing-VERSION source upgraded successfully — fixture no longer models a failure]"
grep -q "materialized plain source" "$F_ROOT/fatal.log" 2>/dev/null \
  || f7="$f7 [PRECONDITION: the run failed BEFORE materialization]"
[ "$(marker_line "$FL")" = "$F_PRIOR" ] || f7="$f7 [FATAL path changed the prior marker]"
[ "$(marker_bytes "$FL")" = "$(( ${#F_PRIOR} + 1 ))" ] || f7="$f7 [FATAL path truncated or grew the prior marker]"

AL="$(bnd_plain_case "$F_ROOT/abort")"
AU="$AL/.fusebase-flow-source"
printf '%s\n' "$F_PRIOR" > "$AL/$MARKER"
printf 'wf local\n' > "$AL/workflows/wf.md"          # consumer edit against the recorded base
printf 'wf upstream\n' > "$AU/workflows/wf.md"       # upstream moved the same file
( cd "$AU" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 )
( cd "$AL" && bash hooks/local/upgrade.sh --auto-yes ) > "$F_ROOT/abort.log" 2>&1
A_RC=$?
[ "$A_RC" -eq 3 ] || f7="$f7 [changed-by-both did not abort with 3 (got $A_RC)]"
[ "$(marker_line "$AL")" = "$F_PRIOR" ] || f7="$f7 [ABORT path changed the prior marker]"
[ -z "$(tmp_residue "$AL")" ] || f7="$f7 [ABORT path left a temp marker file]"
[ -z "$f7" ] && ok "ac7-failure-after-materialization-preserves-the-prior-marker" \
             || bad "ac7-failure-after-materialization-preserves-the-prior-marker" \
                    "$f7 :: $(tail -5 "$F_ROOT/abort.log" | tr '\n' '|')"
rm -rf "$F_ROOT"

# ---- AC8: health states, including the exact missing-marker text and its causes ---------------
h=""
H_DIR="$(mktemp -d)"
ff_prov_read "$H_DIR" || true
[ "$FF_PROV_STATE" = "unknown" ] || h="$h [absent marker did not read unknown]"
H_LINE="$(ff_prov_health_line)"
case "$H_LINE" in *"unknown (provenance marker unavailable)"*) ;; *) h="$h [missing text wrong: $H_LINE]" ;; esac
for cause in "pre-marker install" "already-current no-op" "removed marker"; do
  case "$H_LINE" in *"$cause"*) ;; *) h="$h [missing marker does not name the cause '$cause']" ;; esac
done
printf '%s\n' "$(ff_prov_render git "$HEX40")" > "$H_DIR/$MARKER"
ff_prov_read "$H_DIR" || true
case "$(ff_prov_health_line)" in *"git commit $HEX40"*) ;; *) h="$h [git marker does not print its typed value]" ;; esac
printf '%s\n' "$(ff_prov_render plain "$HEX64")" > "$H_DIR/$MARKER"
ff_prov_read "$H_DIR" || true
case "$(ff_prov_health_line)" in
  *"plain content_digest sha256:$HEX64"*) ;;
  *) h="$h [plain marker does not print its typed value]" ;;
esac
# Wiring: the health engine must route invalid -> drift (integrity failure) and everything
# else -> OK. Asserted structurally so a silent unwiring cannot pass this phase.
HC="$ROOT/hooks/local/fusebase-flow-health-check.sh"
grep -q 'ff_prov_read "\$ROOT"' "$HC" || h="$h [health-check does not read the marker]"
grep -q 'record_drift "installed_from_marker"' "$HC" || h="$h [health-check does not fail integrity on invalid]"
[ -z "$h" ] && ok "ac8-health-prints-typed-values-and-the-exact-unknown-text" \
            || bad "ac8-health-prints-typed-values-and-the-exact-unknown-text" "$h"

# ---- AC1 + AC8: a malformed marker is INVALID, never normalized to unknown --------------------
m=""
VALID_GIT="$(ff_prov_render git "$HEX40")"
while IFS='|' read -r label body; do
  [ -n "$label" ] || continue
  printf '%b' "$body" > "$H_DIR/$MARKER"
  ff_prov_read "$H_DIR"
  rc=$?
  [ "$FF_PROV_STATE" = "invalid" ] || m="$m [$label read as '$FF_PROV_STATE', expected invalid]"
  [ "$rc" -eq 1 ] || m="$m [$label returned rc $rc, expected 1]"
done <<MALFORMED
extra-member|{"schema":"$SCHEMA","source_kind":"git","git_commit":"$HEX40","note":"x"}\n
reordered-keys|{"source_kind":"git","schema":"$SCHEMA","git_commit":"$HEX40"}\n
uppercase-hex|{"schema":"$SCHEMA","source_kind":"git","git_commit":"${HEX40%??}AB"}\n
short-commit|{"schema":"$SCHEMA","source_kind":"git","git_commit":"${HEX40%?}"}\n
wrong-schema|{"schema":"fusebase-flow/installed-from/v2","source_kind":"git","git_commit":"$HEX40"}\n
git-with-digest|{"schema":"$SCHEMA","source_kind":"git","git_commit":"$HEX40","content_digest":"sha256:$HEX64"}\n
plain-with-commit|{"schema":"$SCHEMA","source_kind":"plain","content_digest":"sha256:$HEX64","git_commit":"$HEX40"}\n
pretty-printed|{\n  "schema": "$SCHEMA"\n}\n
leading-space| $VALID_GIT\n
two-lines|$VALID_GIT\n$VALID_GIT\n
no-trailing-newline|$VALID_GIT
crlf|$VALID_GIT\r\n
empty-file|
not-json|nonsense\n
MALFORMED
[ -z "$m" ] && ok "ac1-malformed-marker-is-invalid-not-unknown" \
            || bad "ac1-malformed-marker-is-invalid-not-unknown" "$m"
rm -rf "$H_DIR"

finish
