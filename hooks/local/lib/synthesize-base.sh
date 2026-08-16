#!/usr/bin/env bash
# Fusebase Flow — classifier base synthesis (decision K13a), shared by BOTH upgrade engines.
#
# PROVENANCE:
#   Extracted verbatim from bootstrap-upgrade.sh by ticket n5-upgrade-silent-no-op (decision
#   N1). It lived only in bootstrap-upgrade.sh, so the ordinary `upgrade.sh` path — the one
#   most consumers take — never synthesized a base. Every managed path then classified
#   `unknown-base`, K9 preserved all of them, and the upgrade reported SUCCESS while
#   installing NOTHING (N5: 26 paths kept, 0 refreshed, VERSION advanced anyway).
#
# WHY THIS IS LOAD-BEARING (decision K13a): a consumer on <= 4.6.1 has no
# audit/managed-content-manifest.json. Without a base, EVERY managed path classifies
# `unknown-base`, K9 preserves all of them, and the upgrade reports success while
# installing NOTHING. The classifier release could not deliver its own content.
#
# The fix is not a guess: the upstream tag equal to the consumer's installed VERSION is
# BYTE-IDENTICAL to what their last install/upgrade wrote. Stamping a base from that tag
# is a reconstruction of a fact, not an inference. Only when the tag cannot be resolved
# (a forked or unreleased VERSION) does the tree fall through to `unknown-base` — which is
# preserve + report, never abort (K9 row 10).
#
# EXTRACT, NEVER COPY (decision N1 / K14 one-home): the M1 line-ending block below is
# annotated "VERIFIED, do not simplify this away", and a 2026-07-28 review's contrary claim
# was disproved by reproducing whole-tree misclassification. A second copy is a second
# chance to lose it, in the two scripts that must agree about what a consumer edit is.
#
# CONTRACT
#   ffsb_synthesize_base <log-prefix> <base-rel> <mcm-src> <source-repo> <py-fn>
#     log-prefix   e.g. "bootstrap-upgrade" | "upgrade"  (message bodies are IDENTICAL; only
#                  the bracketed prefix differs, and AC13b greps the body, not the prefix)
#     base-rel     repo-relative path of the base manifest
#     mcm-src      managed_content_manifest.py in the SOURCE tree
#     source-repo  git repo carrying the tags (the staging clone)
#     py-fn        name of the caller's ISOLATED python runner (ff_boot_py / ff_up_py) —
#                  never a bare python3: the synthesized base IS the classifier's input, so a
#                  startup-file injection here decides what counts as a consumer edit later
#                  (re-review B5).
#   rc 0 = base present or synthesized · rc 1 = none (caller falls through to unknown-base)
#   Sets FFSB_REASON: present | synthesized | no-module | no-version | no-git | no-tag |
#                     extract-failed | stamp-failed

ffsb_synthesize_base() {
  local prefix="$1" base_rel="$2" mcm_src="$3" source_repo="$4" py_fn="$5"
  local ver tag tmp rc eol
  FFSB_REASON=""
  if [ -f "$base_rel" ]; then
    FFSB_REASON="present"
    echo "[$prefix] base manifest already present ($base_rel) — no synthesis needed."
    return 0
  fi
  if [ ! -f "$mcm_src" ] || ! command -v python3 >/dev/null 2>&1; then
    FFSB_REASON="no-module"
    echo "[$prefix] NOTE: the source tree has no managed-content module (pre-4.7.0)" >&2
    echo "                    or python3 is unavailable — no base can be synthesized." >&2
    return 1
  fi
  [ -f VERSION ] || { FFSB_REASON="no-version"; echo "[$prefix] NOTE: no local VERSION — cannot pick a base tag." >&2; return 1; }
  ver="$(tr -d '\n\r' < VERSION)"
  tag="v$ver"
  if [ ! -d "$source_repo/.git" ]; then
    FFSB_REASON="no-git"
    echo "[$prefix] NOTE: $source_repo is a plain directory (no .git), so the" >&2
    echo "                    $tag tree cannot be recovered — skipping base synthesis." >&2
    return 1
  fi
  # A --depth 1 --branch <ref> clone carries no tags; fetch just the one we need.
  if ! git -C "$source_repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    git -C "$source_repo" fetch --depth 1 origin "refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1 || true
  fi
  if ! git -C "$source_repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    FFSB_REASON="no-tag"
    echo "[$prefix] NOTE: upstream tag $tag could not be resolved (forked or"
    echo "                    unreleased VERSION). Proceeding with NO base: every managed"
    echo "                    path will classify 'unknown-base', which PRESERVES it and"
    echo "                    reports it — nothing is overwritten, but little is refreshed."
    return 1
  fi
  tmp="$(mktemp -d)"
  # TRIPWIRE (line endings, decision M1) — VERIFIED, do not "simplify" this away, and do NOT
  # make it match the incoming-U call in materialize-managed-source.sh. This is the historical
  # base B: it models what the consumer's own git WROTE at $tag, so it must keep the
  # CONSUMER's EOL convention. `git archive` DOES apply core.autocrlf to files without an eol
  # attribute (measured: true emits CRLF, false/input emit LF), so without this flag the base
  # hashes differ from the consumer's working tree for EVERY managed path — all of them
  # classify changed-by-both and the upgrade aborts having delivered nothing. Forcing LF here
  # is the OPPOSITE error: it makes every untouched CRLF consumer file look locally edited.
  # (A 2026-07-28 review claimed archive ignores autocrlf; removing the flag reproduced the
  # whole-tree misclassification above, so the claim is false on this platform.)
  eol="$(git config --get core.autocrlf 2>/dev/null || true)"
  [ -n "$eol" ] || eol="false"
  if ! git -C "$source_repo" -c core.autocrlf="$eol" archive "$tag" | tar -x -C "$tmp" 2>/dev/null; then
    FFSB_REASON="extract-failed"
    echo "[$prefix] WARN: could not extract $tag — skipping base synthesis." >&2
    rm -rf "$tmp"; return 1
  fi
  # The caller's ISOLATED runner, never a bare python3 (re-review B5 — see CONTRACT above).
  "$py_fn" "$mcm_src" stamp --root "$tmp" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] || [ ! -f "$tmp/$base_rel" ]; then
    FFSB_REASON="stamp-failed"
    echo "[$prefix] WARN: base stamp from $tag failed (rc $rc) — skipping." >&2
    rm -rf "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$base_rel")"
  cp "$tmp/$base_rel" "$base_rel"
  rm -rf "$tmp"
  FFSB_REASON="synthesized"
  # TRIPWIRE: this exact body is grepped by test-upgrade-conflict-classification.sh AC13b
  # ("synthesized the classifier base from upstream tag v4.6.1"). Only the bracketed prefix
  # may vary between callers.
  echo "[$prefix] synthesized the classifier base from upstream tag $tag -> $base_rel"
  echo "                    (this is what upstream shipped you at $ver, so the upgrade can now"
  echo "                     tell YOUR edits from upstream's.)"
  return 0
}

# ffsb_prepare_base <prefix> <base-rel> <mcm-src> <source-repo> <py-fn> <dry-run 0|1>
#   Sets FFSB_BASE to the path the classifier should use for --base ("" when none could be
#   made), and leaves FFSB_REASON holding WHY.
#
# TRIPWIRE (N3 recovery text): this SETS a variable instead of echoing the path, so the caller
# can invoke it WITHOUT a command substitution. A subshell would discard FFSB_REASON, and
# ff_n5_delivery_guard branches its recovery advice on exactly that value — a lost reason
# silently reverts the guard to its one blanket message, which is circular on a plain-directory
# or forked source (it re-suggests the command already running). Do not restore the echo form.
ffsb_prepare_base() {
  local prefix="$1" base_rel="$2" mcm_src="$3" source_repo="$4" py_fn="$5" dry="${6:-0}"
  FFSB_BASE=""
  if [ -f "$base_rel" ]; then FFSB_REASON="present"; FFSB_BASE="$base_rel"; return 0; fi
  # TRIPWIRE: a dry run writes NOTHING — "(dry-run; nothing written)" must stay true, and the
  # base manifest is the one artifact whose mere presence changes every later classification.
  # So a dry run synthesizes to a TEMP path and classifies against that: the preview still
  # reflects what a real run would deliver. Skipping synthesis in dry-run instead would make
  # the preview predict a refusal the real run would never perform — the opposite lie.
  if [ "$dry" = "1" ]; then
    local d; d="$(mktemp -d)"
    ffsb_synthesize_base "$prefix" "$d/base.json" "$mcm_src" "$source_repo" "$py_fn" >&2 \
      && FFSB_BASE="$d/base.json"
    return 0
  fi
  ffsb_synthesize_base "$prefix" "$base_rel" "$mcm_src" "$source_repo" "$py_fn" >&2 || true
  [ -f "$base_rel" ] && FFSB_BASE="$base_rel"
  return 0
}
