#!/usr/bin/env bash

ffcf_t59_preflight_headings() {
  local d="$TMP_BASE/t59-preflight-headings" out="$TMP_BASE/t59-preflight.out"
  local diagnostic="CLAUDE.md missing an exact Flow adapter heading"
  ffcf_conflict_tree "$d"
  cp hooks/local/preflight.sh "$d/hooks/local/preflight.sh"
  printf '# fixture\n' > "$d/GEMINI.md"
  printf '4.15.0\n' > "$d/VERSION"

  printf '%s\n' \
    '# FuseBase CLI Claude instructions' \
    'CURRENT CLI CLAUDE SENTINEL' \
    '## FuseBase Flow — Claude Code adapter' > "$d/CLAUDE.md"
  ( cd "$d" && bash hooks/local/preflight.sh > "$out" 2>&1 ) || true
  grep -qF "preflight finished" "$out" || fail "T59: canonical did not complete preflight"
  ! grep -qF "$diagnostic" "$out" || fail "T59: canonical was rejected"

  # shellcheck source=/dev/null
  . "$ROOT/hooks/local/lib/preflight-overlay-headings.sh"
  ffcf_t59_predicate_case() {
    local name="$1" expected="$2" eol="$3"
    shift 3
    case "$eol" in
      lf) printf '%s\n' "$@" > "$d/CLAUDE.md" ;;
      crlf) printf '%s\r\n' "$@" > "$d/CLAUDE.md" ;;
      *) fail "T59: unknown line ending $eol" ;;
    esac
    if [ "$expected" = "accepted" ]; then
      ffpf_claude_overlay_present "$d/CLAUDE.md" || fail "T59: $name was rejected"
    else
      ! ffpf_claude_overlay_present "$d/CLAUDE.md" || fail "T59: $name was accepted"
    fi
  }

  ffcf_t59_predicate_case canonical-lf accepted lf '## FuseBase Flow — Claude Code adapter'
  ffcf_t59_predicate_case canonical-crlf accepted crlf '## FuseBase Flow — Claude Code adapter'
  ffcf_t59_predicate_case legacy-current-lf accepted lf '## FuseBase Flow — additional rules (overlay)'
  ffcf_t59_predicate_case legacy-current-crlf accepted crlf '## FuseBase Flow — additional rules (overlay)'
  ffcf_t59_predicate_case legacy-original-lf accepted lf '## Fusebase Flow — additional rules (overlay)'
  ffcf_t59_predicate_case legacy-original-crlf accepted crlf '## Fusebase Flow — additional rules (overlay)'
  ffcf_t59_predicate_case source-template-lf accepted lf '# CLAUDE.md — Claude Code adapter for Fusebase Flow'
  ffcf_t59_predicate_case source-template-crlf accepted crlf '# CLAUDE.md — Claude Code adapter for Fusebase Flow'
  ffcf_t59_predicate_case absent rejected lf '# FuseBase CLI Claude instructions'
  ffcf_t59_predicate_case prefix-lf rejected lf 'prefix ## FuseBase Flow — Claude Code adapter'
  ffcf_t59_predicate_case prefix-crlf rejected crlf 'prefix ## FuseBase Flow — Claude Code adapter'
  ffcf_t59_predicate_case suffix-lf rejected lf '## FuseBase Flow — Claude Code adapter suffix'
  ffcf_t59_predicate_case suffix-crlf rejected crlf '## FuseBase Flow — Claude Code adapter suffix'
  ffcf_t59_predicate_case prose-lf rejected lf \
    '# FuseBase CLI Claude instructions' \
    'This prose mentions the Claude Code adapter for Fusebase Flow but has no heading.'
  ffcf_t59_predicate_case prose-crlf rejected crlf \
    '# FuseBase CLI Claude instructions' \
    'This prose mentions the Claude Code adapter for Fusebase Flow but has no heading.'

  unset -f ffcf_t59_predicate_case ffpf_claude_overlay_present
  pass "T59: preflight accepts LF/CRLF exact canonical/legacy/source CLAUDE headings and rejects prefix/suffix/prose markers"
}
