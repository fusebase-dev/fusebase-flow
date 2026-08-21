#!/usr/bin/env bash
# Fusebase Flow — shared upgrade-test fixture builders.
#
# One home for the consumer/source trees the upgrade phases build, so the source-boundary and
# repair-managed phases cannot drift apart on what "a consumer at 4.6.1 with a staged source"
# means. Caller must set ROOT (repo root) before sourcing; MCM is exported here.
#
# API:
#   has_cr <file>                 0 iff the file holds >=1 CR byte
#   copy_boundary_libs <lib-dir>  the 4.7.0+ boundary libs, if this tree ships them
#   bnd_plain_case <dir>          -> echoes a consumer root with .fusebase-flow-source/ staged
#   bnd_legacy_engine <src-tree>  replaces the source engine with a PRE-boundary one
#   bnd_git_source <src-dir>      turns a staged plain source into a git source

MCM="$ROOT/hooks/local/lib/managed_content_manifest.py"

# THE measurand for every byte assertion — `diff` normalizes line endings, so it can never
# answer this question (that is why the original report read a true-positive drift as false).
has_cr() { [ -n "$(tr -dc '\r' < "$1" 2>/dev/null)" ]; }

# `[ -f ]`-guarded so a fixture still BUILDS against a pre-boundary baseline tree — that is how
# these discriminators are observed RED.
#
# TRIPWIRE (N1/N3, n5-upgrade-silent-no-op): synthesize-base.sh + upgrade-delivery-guard.sh are
# SOURCED by both engines. A fixture tree that omits them synthesizes no base, classifies every
# path `unknown-base`, and preserves the lot — so the phase silently measures the PRE-N5 engine
# while claiming to measure this one. Adding an engine-sourced lib means adding it here.
copy_boundary_libs() {   # <lib-dest-dir>
  local f
  for f in materialize-managed-source.sh backup-hygiene.sh synthesize-base.sh upgrade-delivery-guard.sh truthful-base.sh; do
    [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$1/"
  done
  return 0
}

# A plain-directory (non-git) source case: a consumer with a VALID recorded base and a
# copy-eligible upstream change (control.sh v1 -> v2), so a "nothing was written" assertion
# can never pass through unknown-base preservation instead of a real abort.
bnd_plain_case() {   # <dir> -> echoes the consumer root
  local D="$1" L U d
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/local/lib" "$L/workflows" "$U/hooks/local/lib" "$U/workflows"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t )
  echo "4.6.1" > "$L/VERSION"; printf 'control v1\n' > "$L/hooks/local/control.sh"
  echo "4.7.0" > "$U/VERSION"; printf 'control v2\n' > "$U/hooks/local/control.sh"
  printf 'wf v1\n' > "$L/workflows/wf.md"; printf 'wf v1\n' > "$U/workflows/wf.md"
  for d in "$L" "$U"; do
    cp "$ROOT/hooks/local/upgrade.sh" "$ROOT/hooks/local/bootstrap-upgrade.sh" "$d/hooks/local/"
    cp "$MCM" "$d/hooks/local/lib/"
    copy_boundary_libs "$d/hooks/local/lib"
    ( cd "$d" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  done
  echo "$L"
}

# A PRE-boundary engine: no `--source-tree)` token, and it reads the staging directory itself,
# exactly as every engine before the canonical tree did.
bnd_legacy_engine() {   # <source tree>
  cat > "$1/hooks/local/upgrade.sh" <<'LEGACY'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" > "./legacy-engine-argv.txt"
cp ".fusebase-flow-source/hooks/local/control.sh" "hooks/local/control.sh"
echo "[legacy-upgrade] refreshed content from .fusebase-flow-source"
exit 0
LEGACY
}

bnd_git_source() {   # <source dir>
  ( cd "$1" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false && git add -A && git commit -qm src && git branch -M main )
}

# ff_m16_remediation_ran <rc> <run-log>  — 0 iff this rc is a legitimate outcome for an M16
# remediation that RAN. M16's contract is "the emitted remediation is a command that RUNS and
# restores the artifact"; `rc == 0` was a PROXY for that, and N3 legitimately introduced a second
# honest outcome. Callers assert restoration separately — this decides only the rc half.
#
# WHY TWO RCs ARE LEGITIMATE (N3 + N4, ticket n5-upgrade-silent-no-op): the missing-manifest shape
# has a plain-directory source, so no tag resolves, no base is synthesized, every managed path
# classifies unknown-base and is preserved. The only thing the run can deliver is
# audit/managed-content-manifest.json — which N4 EXCLUDES from the delivered count by design,
# because classifier bookkeeping the engine writes for itself is not delivery. So N3 fires: the
# artifact is restored, VERSION is correctly NOT bumped, and the run exits 4.
#
# TRIPWIRE — how this was found, because the lesson generalizes: before the fixture carried
# lib/upgrade-delivery-guard.sh, this assertion passed with rc 0 — and it passed by advancing
# VERSION 4.6.1 -> 4.7.0 with 2 paths unknown-base and NOT ONE file refreshed. That is the exact
# N5 defect. The green assertion was CERTIFYING THE BUG. An oracle can be green because it is
# measuring the defect; that is why these fixtures must model a real release rather than a
# convenient one. Same family as the inert guard (N4) and the fake control.
#
# A NAKED 4 MUST NOT SATISFY M16 — an unrelated future failure that happens to exit 4 is not an
# honest refusal, so the N3 report itself must be present. Do not relax this to a bare rc test.
ff_m16_remediation_ran() {   # <rc> <run-log>
  case "${1:-}" in
    0) return 0 ;;
    4) grep -q "DELIVERED NOTHING" "${2:-}" 2>/dev/null \
         && grep -q "refusing to bump VERSION" "${2:-}" 2>/dev/null && return 0 ;;
  esac
  return 1
}
