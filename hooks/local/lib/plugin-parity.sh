#!/usr/bin/env bash
# Fusebase Flow — plugin-manifest VERSION parity, PUBLISHER-ONLY (ticket N6, slice S5 / N4).
#
# PROVENANCE:
#   Extracted from preflight.sh §8 so the scoping rule has one home and can be tested without
#   running a full preflight. Sourced by preflight; never run standalone in production.
#
# WHY THIS IS SCOPED TWICE, and why neither test is redundant:
#
#   1. OWNERSHIP (`name == fusebase-flow`). Existence is not ownership:
#      docs/install-fusebase-cli-project.md targets projects that may already carry their own
#      Fusebase CLI-generated .codex-plugin/plugin.json, and an existence-only check made
#      following the install guide produce an immediate false error about a manifest Flow does
#      not own.
#
#   2. PUBLISHER CONTEXT (the release ledger exists). The name test alone was not enough, and a
#      consumer proved it: all three of their manifests carry `name: fusebase-flow` — because
#      they were generated FROM Flow's — so the check fired in their repo. Meanwhile
#      `list-managed --dirs` returns only flow-skills agents workflows policies templates hooks,
#      so no upgrade will ever refresh those files. The consumer was left hand-editing after
#      every release; they did it twice (4.9.2, 4.11.0) before reporting it.
#
#      The question this check actually asks is "does the manifest match the version being
#      RELEASED?" — meaningful only where VERSION is Flow's own release version. In a consumer,
#      VERSION is the version of Flow they INSTALLED, and their plugin surface has its own
#      lifecycle. So the two tests are AND-ed, never swapped.
#
# TRIPWIRE — do NOT "fix" this by adding the three manifests to the managed set instead. That
# lets an upgrade OVERWRITE a consumer's own plugin manifest; managed_content_manifest.py:38-44
# already records the reasoning. A publisher-context check that misses enforcement fails
# VISIBLY (a release goes out with a stale manifest and someone notices). Managed adoption
# corrupts ownership SILENTLY as provider schemas and consumer ownership evolve. Prefer the
# failure you can see.
#
# TRIPWIRE — scoping must never become DISABLING. marketplace.json in particular is NOT written
# by sync-version-strings.sh, and it silently drifted ~20 minor versions before this check
# existed. In a publisher repo every arm below must still fire.
#
# PUBLISHER MARKER: docs/release-fingerprints.md — the release ledger. It is not managed content
# (docs/ is not in MANAGED_DIRS), and --with-framework-docs stages framework docs under
# docs/_fusebase-flow/ rather than this path. preflight §10 already scopes the tag-row assertion
# with exactly this marker; one marker, two publisher-only checks. FFPP_LEDGER overrides it.
#
# CONTRACT
#   ffpp_errors -> one line per parity violation (empty == none). Read-only. Silent, rc 0, in
#                  any repo that is not the publisher's.

ffpp_is_publisher() { [ -f "${FFPP_LEDGER:-docs/release-fingerprints.md}" ]; }

# ffpp_field FILE PYEXPR: echo a field, or "" when the file is absent/unparsable.
ffpp_field() {
  command -v python3 >/dev/null 2>&1 || return 0
  [ -f "$1" ] || return 0
  FF_PJ="$1" python3 -c "
import json, os, sys
try:
    d = json.load(open(os.environ['FF_PJ'], encoding='utf-8'))
except Exception:
    sys.exit(0)
print($2 or '')
" 2>/dev/null
}

ffpp_errors() {
  ffpp_is_publisher || return 0
  local ver pj pj_name pj_ver mkt_name mkt_ver
  ver="$(tr -d '\n\r' < VERSION 2>/dev/null)"
  [ -n "$ver" ] || return 0

  for pj in .claude-plugin/plugin.json .codex-plugin/plugin.json; do
    pj_name="$(ffpp_field "$pj" "d.get('name','')")"
    [ "$pj_name" = "fusebase-flow" ] || continue
    pj_ver="$(ffpp_field "$pj" "d.get('version','')")"
    [ -n "$pj_ver" ] && [ "$pj_ver" != "$ver" ] && \
      echo "$pj version ($pj_ver) != VERSION ($ver); bump them together"
  done

  mkt_name="$(ffpp_field .claude-plugin/marketplace.json "(d.get('plugins') or [{}])[0].get('name', d.get('name',''))")"
  if [ "$mkt_name" = "fusebase-flow" ]; then
    mkt_ver="$(ffpp_field .claude-plugin/marketplace.json "(d.get('plugins') or [{}])[0].get('version','')")"
    [ -n "$mkt_ver" ] && [ "$mkt_ver" != "$ver" ] && \
      echo ".claude-plugin/marketplace.json plugins[0].version ($mkt_ver) != VERSION ($ver); bump them together"
  fi
  return 0
}
