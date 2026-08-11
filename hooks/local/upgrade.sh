#!/usr/bin/env bash
# Fusebase Flow — upgrade.sh  (F1: in-place CONTENT upgrade)
#
# PROVENANCE:
#   Shipped Fusebase Flow v3.6.0+. Lives at hooks/local/ — outside the FuseBase
#   CLI refresh manifest, so it survives `fusebase update`.
#
# PURPOSE:
#   The missing "upgrade an installed overlay" path. Unlike upgrade-engine.sh
#   (which syncs only the 3 engine scripts + VERSION), this refreshes the
#   CANONICAL CONTENT from the upstream clone and re-mirrors it, then bumps
#   VERSION as the LAST step — so VERSION can never advance ahead of content.
#
#   Order (deliberate — see F8):
#     1. Refresh canonical content from .fusebase-flow-source/:
#          skills/ agents/ workflows/ policies/ templates/ hooks/ FLOW_RULES.md
#          (U2: hooks/ included so the hook layer — incl. this engine — isn't
#          left stale; preserves hooks/local/*.local.* and CLI-owned .claude/hooks/**)
#     2. Re-mirror: mirror-skills.sh + mirror-agents.sh  (canonical → providers)
#     3. Sync derived attestation strings from the repo (sync-version-strings.sh:
#          version + FR-range + skill count; U3)
#     4. Refresh drifted AGENTS.md/CLAUDE.md overlay blocks (version-aware; F2).
#          The operator's FLOW:PRESERVE region (e.g. ### Project-specific values)
#          is carried forward verbatim — refresh never clobbers it (U1).
#     5. Bump VERSION to match upstream  (LAST — never before content)
#
#   Backups: every touched path gets a .pre-upgrade-<ts> copy. Dry-run shows the
#   plan without writing. Abort leaves the tree untouched.
#
# What it does NOT do:
#   - Touch .claude/settings.json or wire hooks (that's opt-in via
#     post-fusebase-update.sh --wire-hooks; F3).
#   - Touch CLI-owned provider assets (.claude/hooks/**, CLI provider skills,
#     MCP/fusebase.json/skills-lock.json) — those are CLI-owned.
#   - Touch local-only areas (internal/, docs/fusebase-health/).
#   - Copy framework docs into the consumer's docs/ (U4) — only with
#     --with-framework-docs, and then namespaced under docs/_fusebase-flow/.
#
# Prerequisite:
#   .fusebase-flow-source/ present (git clone OR plain dir copy; F5). Refresh:
#     cd .fusebase-flow-source && git pull origin main   # if a git clone
#   For a PRE-3.6.0 install with no engine scripts yet, use
#     bash hooks/local/bootstrap-upgrade.sh   (U5) — it stages the source clone,
#     copies the engine scripts in, then runs this script.
#
# Usage:
#   bash hooks/local/upgrade.sh                       # interactive: show plan, confirm
#   bash hooks/local/upgrade.sh --dry-run             # show plan, write nothing
#   bash hooks/local/upgrade.sh --auto-yes            # non-interactive
#   bash hooks/local/upgrade.sh --with-framework-docs # also stage framework docs (namespaced)
#
# Exit: 0 success / no-op; 1 source missing or error; 2 bad arg; 3 declined.

set -euo pipefail

# v3.20.1: the WHOLE body lives in main() so bash parses the entire file before
# executing a single step. Step 1 refreshes hooks/ — INCLUDING THIS RUNNING
# FILE. Without the wrapper, bash keeps streaming the (now-replaced) script at
# a stale byte offset and aborts mid-upgrade with a syntax error (observed on
# the 3.19.1 -> 3.20.1 hop; nondeterministic before that — offset-dependent).
# Engines ≤3.20.0 lack this guard: from those versions use
#   bash hooks/local/bootstrap-upgrade.sh -- --auto-yes   (stages the new engine FIRST,
# so the self-overwrite is byte-identical).
main() {

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# U7: recovery hint on interruption/failure. The upgrade is multi-step and refreshes
# the hook layer mid-run; if the operator Ctrl-C's or a step dies AFTER writing has
# begun, print the exact re-run commands so a half-applied tree is recoverable
# without guessing. The trap is ARMED just before step 1 (the first write) so the
# pre-write FATAL/declined exits don't print a spurious "half-applied" hint; a
# clean finish sets UPGRADE_FINISHED=1 to suppress it.
UPGRADE_FINISHED=0
print_recovery_hint() {
  [ "$UPGRADE_FINISHED" -eq 1 ] && return 0
  echo "" >&2
  echo "[upgrade] INTERRUPTED or FAILED before completion - the tree may be HALF-APPLIED." >&2
  # M19: the re-run is NOT "the same thing again". Step 1 refreshes hooks/ INCLUDING this file,
  # so by the time this hint prints, the engine on disk may already be the REFRESHED one while
  # the failure came from the copy bash had parsed into memory. Flow cannot enumerate a
  # consumer's own seam (a locally wired gate is invisible upstream) - the generic statement is
  # the whole fix, and the part that matters: a clean exit from the re-run is not evidence that
  # a check the failed engine ran still exists. Do NOT soften this back into "idempotent, just
  # re-run" - that phrasing is what sent a consumer into a gate-less engine after being told
  # their security substance was gone. ASCII only: this crosses a non-UTF-8 Windows console.
  echo "[upgrade] Recover by re-running - but read this first: the content refresh may ALREADY" >&2
  echo "          have replaced this engine on disk, so the re-run executes the REFRESHED engine," >&2
  echo "          not the one that just failed. Its behaviour may differ, INCLUDING seams it does" >&2
  echo "          not invoke. A clean exit from the re-run is NOT evidence that a check the failed" >&2
  echo "          engine ran still exists - if you rely on a local gate wired into this engine," >&2
  echo "          run that gate yourself afterwards and read its verdict." >&2
  echo "    bash hooks/local/upgrade.sh" >&2
  echo "    bash hooks/local/post-fusebase-update.sh --refresh-overlays  # re-apply adapters + slash commands" >&2
  echo "    bash hooks/local/sync-version-strings.sh                 # re-sync derived attestation strings" >&2
  echo "    bash hooks/local/preflight.sh && bash hooks/local/fusebase-flow-health-check.sh  # verify (HEALTHY)" >&2
}

# ---- WS5 (v3.30.4): Windows-safe bounded exit for the long child steps ----
# The busy-loop / 255-at-tail on MSYS came from unbounded fork-heavy steps (the
# re-mirror + the per-stem prune_pre_backups traversal — fixed to single-pass below).
# Reuse the WS2 bounded-run core so long steps are killable + observable. If the lib
# is absent (a pre-3.28 bootstrap that hasn't staged hooks/local/lib/), degrade to an
# UNBOUNDED direct run (never fail the upgrade for a missing helper).
FFHC_STEP_LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"
FFHC_STEP_LIB_OK=0
if [ -f "$FFHC_STEP_LIB" ]; then
  # shellcheck source=/dev/null
  . "$FFHC_STEP_LIB" 2>/dev/null && command -v ffhc_run_bounded >/dev/null 2>&1 && { ffhc_detect_timeout; FFHC_STEP_LIB_OK=1; }
fi

# ffhc_run_step SECS CRITICAL LABEL CMD...: run one upgrade step bounded to SECS with a
# flushed progress echo. CRITICAL=1 => a timeout/kill/failure PRINTS the recovery hint and
# EXITS 1 (never mask a partial/broken upgrade as success). CRITICAL=0 => a timeout/kill/
# failure WARNs and CONTINUES (rc stays 0). No timeout binary => the core SKIPs (rc 125):
# treated as "could not bound", so a CRITICAL step then runs UNBOUNDED (correctness over
# observability — never skip the content copy / version write), an optional step is skipped
# with a warning. On any bound the step's own rc is preserved for the caller's decision.
ffhc_run_step() {
  local secs="$1" critical="$2" label="$3"; shift 3
  printf '[upgrade] step: %s (bounded %ss)…\n' "$label" "$secs" >&2
  local rc
  # TRIPWIRE (set -e safety): the engine runs `set -euo pipefail` WITHOUT `set -E`, so a
  # nonzero `wait "$bpid"` deep in ffhc_run_bounded (rc 124 timeout OR the child's own
  # failure) would ABORT the whole upgrade at that `wait` — before rc capture and before
  # this function's optional-warn/critical-hint decision, and with no ERR-trap inheritance.
  # Neutralize -e around EVERY invocation + rc capture, restore it before the decision, so
  # an OPTIONAL failure/timeout warns+continues and a CRITICAL one exits WITH the hint.
  local _had_e=0; case $- in *e*) _had_e=1 ;; esac
  set +e
  if [ "$FFHC_STEP_LIB_OK" -eq 1 ]; then
    ffhc_run_bounded "$secs" "$@"; rc=$FFHC_LAST_RC
    [ -n "$FFHC_LAST_OUT" ] && printf '%s\n' "$FFHC_LAST_OUT" >&2
    if [ "${FFHC_LAST_SKIPPED:-0}" = "1" ]; then
      if [ "$critical" = "1" ]; then
        printf '[upgrade] step %s: no timeout binary — running UNBOUNDED (critical, correctness first)…\n' "$label" >&2
        "$@"; rc=$?
      else
        printf '[upgrade] WARN: step %s SKIPPED (no timeout binary to bound an optional step) — continuing.\n' "$label" >&2
        [ "$_had_e" = 1 ] && set -e
        return 0
      fi
    fi
  else
    "$@"; rc=$?
  fi
  [ "$_had_e" = 1 ] && set -e
  if [ "$rc" -ne 0 ]; then
    if [ "$critical" = "1" ]; then
      printf '[upgrade] FATAL: CRITICAL step failed/killed (rc %s): %s — the upgrade is INCOMPLETE.\n' "$rc" "$label" >&2
      print_recovery_hint
      exit 1
    fi
    printf '[upgrade] WARN: optional step failed/killed (rc %s): %s — continuing (upgrade still valid).\n' "$rc" "$label" >&2
  fi
  return 0
}

# U3 (W2): the baseline merge rule lives in a sourced, unit-tested lib so the
# engine stays small (FR-25) and AC3 can test the rule directly.
#
# v3.25.1 (the bootstrap/adoption-hop fix): a PRE-v3.25 install — or a bootstrap
# that didn't stage hooks/local/lib/ — has NO local merge lib when this engine
# starts, so sourcing only $ROOT/... left merge_module_size_baseline undefined and
# the Step 1a guard silently skipped the merge → baseline clobbered. The merge MUST
# be driven by the TARGET-version lib (the running engine may predate it), so we
# source from $SOURCE_TREE FIRST (authoritative), falling back to the local copy.
# Defined here; called after the source boundary is established (and again, belt-and-suspenders,
# right before the Step 1a guard) — never silently skipped.
MERGE_LIB="$ROOT/hooks/local/lib/merge-module-size-baseline.sh"
source_merge_lib() {
  command -v merge_module_size_baseline >/dev/null 2>&1 && return 0
  local src_lib="$SOURCE_TREE/hooks/local/lib/merge-module-size-baseline.sh"
  [ -f "$src_lib" ] && . "$src_lib" 2>/dev/null
  command -v merge_module_size_baseline >/dev/null 2>&1 && return 0
  [ -f "$MERGE_LIB" ] && . "$MERGE_LIB" 2>/dev/null
  command -v merge_module_size_baseline >/dev/null 2>&1
}

SOURCE_REPO=".fusebase-flow-source"
AUTO_YES=0
DRY_RUN=0
WITH_DOCS=0          # U4: framework docs are NOT copied into the consumer by default
# TRIPWIRE (K20a): --unsafe-legacy-copy re-enables the pre-4.7.0 destructive whole-tree
# copy. No diagnostic anywhere may suggest it; it exists only as a deliberate escape.
UNSAFE_LEGACY=0
SOURCE_TREE_ARG=""       # internal boundary handoff (decision M1) — not an operator flag
SOURCE_TREE_OWNED=0
SRC_COMMIT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto-yes|-y) AUTO_YES=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --with-framework-docs) WITH_DOCS=1 ;;
    --unsafe-legacy-copy) UNSAFE_LEGACY=1 ;;
    --source-tree)         SOURCE_TREE_ARG="${2:-}"; shift ;;
    --source-tree=*)       SOURCE_TREE_ARG="${1#*=}" ;;
    --source-tree-owned)   SOURCE_TREE_OWNED=1 ;;
    --source-repo)         SOURCE_REPO="${2:-}"; shift ;;
    --source-repo=*)       SOURCE_REPO="${1#*=}" ;;
    --source-commit)       SRC_COMMIT="${2:-}"; shift ;;
    --source-commit=*)     SRC_COMMIT="${1#*=}" ;;
    --help|-h) sed -n '2,52p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
  shift
done

if [ ! -d "$SOURCE_REPO" ]; then
  echo "[upgrade] FATAL: $SOURCE_REPO/ not found." >&2
  echo "          Provide an upstream copy first, e.g.:" >&2
  echo "            git clone https://github.com/fusebase-dev/fusebase-flow.git $SOURCE_REPO" >&2
  exit 1
fi

# ---- Canonical source boundary (decision M1) ----
# TRIPWIRE: SOURCE_REPO is metadata / kind detection / ref resolution ONLY. EVERY incoming
# content read below uses SOURCE_TREE. Reading source content from the mutable staging
# WORKTREE is the F2 defect (stale pre-pin CRLF -> permanent manifest drift) this removes.
SOURCE_TREE="$SOURCE_REPO"
[ -n "$SOURCE_TREE_ARG" ] && SOURCE_TREE="$SOURCE_TREE_ARG"
# TRIPWIRE (source trust): the boundary implementation comes from the tree the CALLER already
# materialized and verified (the bootstrap hop's --source-tree), else from TRUSTED LOCAL CODE
# (this install's own copy). NEVER from $SOURCE_REPO's mutable worktree: that copy could redefine
# materialization and verification before any canonical tree exists.
FF_MMS_LIB=""
if [ -n "$SOURCE_TREE_ARG" ] && [ -f "$SOURCE_TREE_ARG/hooks/local/lib/materialize-managed-source.sh" ]; then
  FF_MMS_LIB="$SOURCE_TREE_ARG/hooks/local/lib/materialize-managed-source.sh"
elif [ -f "$ROOT/hooks/local/lib/materialize-managed-source.sh" ]; then
  FF_MMS_LIB="$ROOT/hooks/local/lib/materialize-managed-source.sh"
fi
if [ -n "$FF_MMS_LIB" ]; then
  . "$FF_MMS_LIB"
  trap 'ff_source_cleanup' EXIT     # armed BEFORE materialization so every abort path cleans up
  ff_source_open "$SOURCE_REPO" "$SOURCE_TREE_ARG" "$SOURCE_TREE_OWNED" "${FF_SOURCE_REF:-}" || exit 1
  SOURCE_TREE="$FF_SOURCE_TREE"
  [ -n "$SRC_COMMIT" ] || SRC_COMMIT="$FF_SOURCE_COMMIT"
elif [ -n "$SOURCE_TREE_ARG" ]; then
  echo "[upgrade] WARN: the caller materialized $SOURCE_TREE_ARG but ships no canonical materializer" >&2
  echo "          (pre-4.7.0 source) — reading that tree as-is; it can carry stale pre-EOL-pin bytes (F2)." >&2
  # --source-tree-owned still transferred ownership, and the caller `exec`d, so its own trap will
  # never run: without this the tree we now own outlives the process. Same one-owner rule and same
  # ff-source- template guard as ff_source_cleanup, which is simply not loadable on this path.
  if [ "$SOURCE_TREE_OWNED" = "1" ]; then
    ff_orphan_tree_cleanup() {
      local t="$SOURCE_TREE_ARG"
      SOURCE_TREE_OWNED=0
      # TRIPWIRE (destructive): only a directory the boundary created from the ff-source- template.
      case "${t##*/}" in
        ff-source-*) [ -d "$t" ] && rm -rf -- "$t" ;;
      esac
      return 0
    }
    trap 'ff_orphan_tree_cleanup' EXIT
    trap 'rc=$?; ff_orphan_tree_cleanup; exit $rc' INT TERM
  fi
else
  echo "[upgrade] FATAL: this install ships no hooks/local/lib/materialize-managed-source.sh, so the" >&2
  echo "          canonical source boundary (decision M1 / AC2) cannot run here. Reading the mutable" >&2
  echo "          $SOURCE_REPO/ worktree instead would let unverified source code define its own" >&2
  echo "          verification — refusing. Run the bootstrap hop, which materializes and verifies" >&2
  echo "          the source before handing off to this engine:" >&2
  echo "            bash hooks/local/bootstrap-upgrade.sh" >&2
  echo "          NOTHING was written." >&2
  exit 1
fi

# Backup hygiene (git-exclude + retention prune) — one home, shared with bootstrap-upgrade.sh
# and cleanup-flow-backups.sh. Target-version copy wins; a missing lib degrades to a warning
# (both consumers are already best-effort steps that never fail an otherwise-valid upgrade).
FF_BH_LIB="$SOURCE_TREE/hooks/local/lib/backup-hygiene.sh"
[ -f "$FF_BH_LIB" ] || FF_BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
[ -f "$FF_BH_LIB" ] && . "$FF_BH_LIB"

# Load the baseline-merge lib now that $SOURCE_TREE is confirmed present — from the
# authoritative target-version tree first (the running engine may predate the merge
# rule). Step 1a re-checks and warns loudly if it is somehow still undefined.
source_merge_lib || true

# F5: a git clone enables HEAD reporting; a plain dir is accepted with a warning.
if [ -n "$SRC_COMMIT" ]; then
  SRC_HEAD="${SRC_COMMIT:0:12} (resolved commit)"
elif [ -e "$SOURCE_REPO/.git" ]; then
  SRC_HEAD=$(cd "$SOURCE_REPO" && git rev-parse --short HEAD 2>/dev/null || echo "?")
else
  SRC_HEAD="(plain dir — no .git; HEAD/diff unavailable)"
  echo "[upgrade] NOTE: $SOURCE_REPO/ is a plain directory (no .git). Proceeding with"
  echo "          file-content comparison only; upstream HEAD/diff is unavailable."
fi

if [ ! -f "$SOURCE_TREE/VERSION" ]; then
  echo "[upgrade] FATAL: $SOURCE_TREE/VERSION missing — cannot determine target version." >&2
  exit 1
fi
SRC_VERSION=$(tr -d '\n\r' < "$SOURCE_TREE/VERSION")
LOCAL_VERSION=$(tr -d '\n\r' < VERSION 2>/dev/null || echo "?")

echo "[upgrade] Source: $SOURCE_REPO/  (HEAD $SRC_HEAD, VERSION $SRC_VERSION)"
echo "[upgrade] Local:  VERSION $LOCAL_VERSION"
echo ""

# Canonical content trees + files to refresh (NOT provider mirrors; step 2 regenerates
# those). copy_dir copies upstream OVER local without deleting extras, so operator
# overrides (hooks/local/*.local.*) and CLI-owned `.claude/hooks/**` stay untouched.
#
# TRIPWIRE (decision K14): the managed list has ONE home — managed_content_manifest.py,
# read via `list-managed`. Never re-declare it here; the manifest and this engine would
# drift on what "managed" means. The SOURCE tree's copy wins (the incoming definition).
MCM_LIB="hooks/local/lib/managed_content_manifest.py"
MCM="$SOURCE_TREE/$MCM_LIB"
[ -f "$MCM" ] || MCM="$MCM_LIB"
CLASSIFY_OK=0
CONTENT_DIRS=()
CONTENT_FILES=()
# TRIPWIRE (re-review B5): the classifier decides WHAT IS MANAGED and WHAT GETS WRITTEN, so its
# interpreter is as trust-bearing as the source verifier's — and it is reached AFTER the source
# verdict, where a clean verdict would otherwise buy an attacker nothing. `-I -S` keeps a
# sitecustomize/.pth on an inherited PYTHONPATH, and a json.py sitting next to the module, from
# forging list-managed or the apply plan. Mirrors ff_boot_py / _ff_mms_py; the module is
# stdlib-only, so isolation costs it nothing. Never call a bare python3 for a classifier answer.
ff_up_py() { python3 -I -S "$@"; }
if [ -f "$MCM" ] && command -v python3 >/dev/null 2>&1; then
  while IFS= read -r line; do [ -n "$line" ] && CONTENT_DIRS+=("$line"); done < <(ff_up_py "$MCM" list-managed --dirs 2>/dev/null)
  while IFS= read -r line; do [ -n "$line" ] && CONTENT_FILES+=("$line"); done < <(ff_up_py "$MCM" list-managed --files 2>/dev/null)
  [ "${#CONTENT_DIRS[@]}" -gt 0 ] && CLASSIFY_OK=1
fi
# FAIL CLOSED (decision K20a). The legacy whole-directory refresh IS the pre-4.7.0
# overwrite behaviour this release exists to remove, and it bypasses --auto-yes
# containment entirely. Trigger is "classifier EXPECTED but unavailable" — i.e. the
# SOURCE tree ships the module — not "classifier absent from the universe": a genuinely
# pre-4.7.0 source tree has no classification to do and may still upgrade.
CLASSIFIER_EXPECTED=0
[ -f "$SOURCE_TREE/$MCM_LIB" ] && CLASSIFIER_EXPECTED=1
if [ "$CLASSIFY_OK" -ne 1 ] && [ "$CLASSIFIER_EXPECTED" -eq 1 ] && [ "$UNSAFE_LEGACY" -ne 1 ]; then
  echo "[upgrade] ABORT: this version ships the conflict classifier, but it cannot run here." >&2
  if ! command -v python3 >/dev/null 2>&1; then
    echo "          Missing prerequisite: python3 is not on PATH." >&2
    echo "          Recovery: install Python 3.11+, then re-run this upgrade." >&2
  else
    echo "          Missing prerequisite: $MCM_LIB could not be read or listed no managed paths." >&2
    echo "          Recovery: bash hooks/local/bootstrap-upgrade.sh" >&2
  fi
  echo "          NOTHING was written. Proceeding without classification would overwrite" >&2
  echo "          consumer-edited managed files — the exact defect this release fixes." >&2
  exit 1
fi
if [ "$CLASSIFY_OK" -ne 1 ]; then
  echo "[upgrade] WARN: classifier unavailable; using the LEGACY whole-directory refresh." >&2
  echo "          Consumer edits to managed files WILL be overwritten (no classification)." >&2
  # Mirrors managed_content_manifest.py MANAGED_DIRS exactly — including its deliberate omission
  # of the publisher-only .claude-plugin/ and .codex-plugin/, which are never consumer content.
  CONTENT_DIRS=( "flow-skills" "agents" "workflows" "policies" "templates" "hooks" )
  CONTENT_FILES=( "FLOW_RULES.md" "FLOW_RULES_HISTORY.md" "audit/hook-layer-manifest.json" )
fi
# The consumer's recorded base: what upstream shipped THEM last time (decision K13).
BASE_MANIFEST="audit/managed-content-manifest.json"
# Framework reference docs (top-level docs/*.md). U4: NOT copied into the consumer
# by default (they're framework-dev docs that collide with consumer doc layouts).
# With --with-framework-docs they land under docs/_fusebase-flow/ (namespaced),
# never the consumer's docs/ root.
DOC_GLOB="docs"
DOC_DEST_PREFIX="docs/_fusebase-flow/"

TS=$(date -u +%Y%m%dT%H%M%SZ)
PLAN=()

dir_differs() { ! diff -rq "$SOURCE_TREE/$1" "$1" >/dev/null 2>&1; }

# ---- Three-way classification (K9) -> per-file apply plan (K15) ---------------------
# The OLD engine asked only "does this directory differ" and then `cp -R`'d upstream over
# it wholesale, so it could not tell an upstream change from a consumer edit and silently
# overwrote local hardening. Classification is per PATH and apply is per FILE: a directory
# holding one consumer-edited file among a hundred upstream-updated ones refreshes the
# hundred and preserves the one.
APPLY_PLAN=""
CLASSIFY_REPORT=""
CLASSIFY_ABORT=0
if [ "$CLASSIFY_OK" -eq 1 ]; then
  APPLY_PLAN="$(mktemp)"
  CLASSIFY_REPORT="$(mktemp)"
  MCM_DECISIONS=""
  if [ "$AUTO_YES" -ne 1 ]; then
    # Attended: K9's per-class defaults, applied non-interactively per CLASS (never a
    # per-file prompt storm). The report below names every affected path, and
    # changed-by-both still stops the run so a human reconciles it deliberately.
    MCM_DECISIONS="consumer-only=keep,upstream-deleted-dirty=keep,consumer-deleted=keep,unknown-base=keep,changed-by-both=abort"
  fi
  MCM_BASE_ARG=()
  [ -f "$BASE_MANIFEST" ] && MCM_BASE_ARG=(--base "$BASE_MANIFEST")
  set +e
  ff_up_py "$MCM" plan --root "$ROOT" --upstream "$SOURCE_TREE" \
    "${MCM_BASE_ARG[@]}" \
    $( [ "$AUTO_YES" -eq 1 ] && echo --auto-yes ) \
    ${MCM_DECISIONS:+--decisions "$MCM_DECISIONS"} \
    --plan-file "$APPLY_PLAN" --report-file "$CLASSIFY_REPORT" \
    --backup-suffix "$TS" --resume-command "bash hooks/local/upgrade.sh"
  MCM_RC=$?
  set -e
  cat "$CLASSIFY_REPORT"
  if [ "$MCM_RC" -eq 9 ]; then
    CLASSIFY_ABORT=1
  elif [ "$MCM_RC" -ne 0 ]; then
    echo "[upgrade] FATAL: classification failed (rc $MCM_RC) — refusing to apply blind." >&2
    exit 1
  fi
  if [ "$CLASSIFY_ABORT" -eq 1 ]; then
    # NOTHING has been written yet (the plan stage is read-only), so this is a clean stop.
    exit 3
  fi
  while IFS=$'\t' read -r op path; do
    [ -n "${path:-}" ] || continue
    case "$op" in
      copy)   PLAN+=("refresh file: $path") ;;
      delete) PLAN+=("remove file:  $path (upstream dropped it)") ;;
    esac
  done < "$APPLY_PLAN"
else
  for d in "${CONTENT_DIRS[@]}"; do
    if [ -d "$SOURCE_TREE/$d" ] && dir_differs "$d"; then
      PLAN+=("refresh dir:  $d/")
    fi
  done
  for f in "${CONTENT_FILES[@]}"; do
    if [ -f "$SOURCE_TREE/$f" ] && ! diff -q "$SOURCE_TREE/$f" "$f" >/dev/null 2>&1; then
      PLAN+=("refresh file: $f")
    fi
  done
fi
# Top-level framework docs (docs/*.md) — only with --with-framework-docs, and
# namespaced under docs/_fusebase-flow/ so they never collide with consumer docs.
if [ "$WITH_DOCS" -eq 1 ] && [ -d "$SOURCE_TREE/$DOC_GLOB" ]; then
  while IFS= read -r srcdoc; do
    dest="${DOC_DEST_PREFIX}$(basename "$srcdoc")"
    if [ -f "$dest" ] && ! diff -q "$srcdoc" "$dest" >/dev/null 2>&1; then
      PLAN+=("refresh doc:  $dest")
    elif [ ! -f "$dest" ]; then
      PLAN+=("add doc:      $dest")
    fi
  done < <(find "$SOURCE_TREE/$DOC_GLOB" -maxdepth 1 -name "*.md" -type f 2>/dev/null)
fi

# v3.9.0 migration: a legacy root skills/ alongside the incoming flow-skills/ will
# be retired (backed up). Only when the source actually ships flow-skills/.
MIGRATE_LEGACY_SKILLS=0
if [ -d "skills" ] && [ -d "$SOURCE_TREE/flow-skills" ]; then
  MIGRATE_LEGACY_SKILLS=1
  PLAN+=("migrate:      retire legacy root skills/ (canonical -> flow-skills/)")
fi

VERSION_CHANGE=""
[ "$SRC_VERSION" != "$LOCAL_VERSION" ] && VERSION_CHANGE="VERSION: $LOCAL_VERSION -> $SRC_VERSION"

if [ "${#PLAN[@]}" -eq 0 ] && [ -z "$VERSION_CHANGE" ]; then
  echo "[upgrade] Content already matches upstream. Nothing to do."
  exit 0
fi

echo "[upgrade] Plan:"
for p in "${PLAN[@]}"; do echo "  • $p"; done
echo "  • re-mirror skills + agents (canonical -> .claude/.agents/.codex)"
echo "  • sync derived attestation strings (version + FR-range + skill count) from the repo"
echo "  • version-aware refresh of AGENTS.md/CLAUDE.md overlay blocks (operator FLOW:PRESERVE region carried forward)"
echo "  • restore Flow slash commands: recovery snapshot -> .claude/commands/ (new commands install here)"
[ "$WITH_DOCS" -eq 1 ] && echo "  • copy framework docs -> docs/_fusebase-flow/ (--with-framework-docs)" || echo "  • (framework docs NOT copied — pass --with-framework-docs to stage them under docs/_fusebase-flow/)"
[ -n "$VERSION_CHANGE" ] && echo "  • $VERSION_CHANGE  (applied LAST, after content)"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[upgrade] (dry-run; nothing written)"
  exit 0
fi

if [ "$AUTO_YES" -ne 1 ]; then
  printf "[upgrade] Apply this content upgrade? [y/N] "
  read -r ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "[upgrade] Aborted."; exit 3 ;; esac
fi

# U7: arm the recovery trap now — from here on a Ctrl-C / dying step can leave a
# half-applied tree, so an interruption should print the recovery commands.
trap 'rc=$?; print_recovery_hint; exit $rc' INT TERM ERR

# U3 (W2): SNAPSHOT the consumer's project-state baseline BEFORE step 1 clobbers
# policies/ wholesale. The merge after the copy restores the project rows.
BASELINE_REL="policies/module-size-baseline.txt"
LOCAL_BASELINE_SNAPSHOT=""
if [ -f "$BASELINE_REL" ]; then
  LOCAL_BASELINE_SNAPSHOT="$(mktemp)"
  cp "$BASELINE_REL" "$LOCAL_BASELINE_SNAPSHOT"
fi

if command -v ff_git_exclude_backups >/dev/null 2>&1 && ff_git_exclude_backups; then FF_BACKUPS_GITIGNORED=1; else
  FF_BACKUPS_GITIGNORED=0
  echo "[upgrade] WARN: could not update .git/info/exclude — upgrade backups may be stageable by a later 'git add -A' (delete or unstage them before committing)." >&2
fi

# ---- Step 1: refresh canonical content (with backups) ----
echo "[upgrade] Step 1/5: refreshing canonical content (${#CONTENT_DIRS[@]} dir(s) + ${#CONTENT_FILES[@]} file(s))…"
copy_dir() {
  local d="$1"
  [ -d "$SOURCE_TREE/$d" ] || return 0
  # Guard the dest: GNU `cp -R src existing-dir` copies INTO it (a same-second $TS collision
  # / retry would yield `<d>.pre-upgrade-<ts>/<d>/tests/fixtures/…` — nested, so the scanner's
  # root-anchored fixture exclusion would miss it). A backup at this $TS already exists ⇒ skip.
  if [ -d "$d" ] && [ ! -e "$d.pre-upgrade-$TS" ]; then cp -R "$d" "$d.pre-upgrade-$TS"; fi
  # Replace contents (canonical is source of truth; do not delete extra local files
  # blindly — copy upstream over, leaving any project-local additions in place).
  mkdir -p "$d"   # new dir on first migration (e.g. flow-skills/ on a pre-3.9.0 tree)
  cp -R "$SOURCE_TREE/$d/." "$d/"
}
if [ "$CLASSIFY_OK" -eq 1 ]; then
  # ---- PER-FILE apply (decision K15) ----
  # Driven by the classification plan, NOT by whole-directory `cp -R`. The existing
  # DIRECTORY-level .pre-upgrade-<TS> snapshot is retained unchanged: it already captures
  # everything before any write, so no second (per-file) backup scheme is introduced and
  # the U10 retention prune below stays correct.
  for d in "${CONTENT_DIRS[@]}"; do
    if [ -d "$d" ] && [ ! -e "$d.pre-upgrade-$TS" ] && grep -qE "^(copy|delete)"$'\t'"$d/" "$APPLY_PLAN" 2>/dev/null; then
      cp -R "$d" "$d.pre-upgrade-$TS"
    fi
  done
  ff_applied=0; ff_removed=0; ff_preserved=0
  while IFS=$'\t' read -r op path; do
    [ -n "${path:-}" ] || continue
    # TRIPWIRE (K13b): the base manifest is the LAST thing written, after all content —
    # the plan already orders it last. Reordering makes the classifier single-shot: the
    # next upgrade would compare new content against a base that predates it.
    case "$op" in
      copy)
        [ -f "$SOURCE_TREE/$path" ] || continue
        mkdir -p "$(dirname "$path")"
        [ -f "$path" ] && [ ! -e "$path.pre-upgrade-$TS" ] && \
          case "$path" in */*) : ;; *) cp "$path" "$path.pre-upgrade-$TS" ;; esac
        cp "$SOURCE_TREE/$path" "$path"
        ff_applied=$((ff_applied + 1)) ;;
      delete)
        if [ -e "$path" ]; then
          # Recoverable: top-level managed FILES get their own twin (they have no parent
          # dir snapshot); files inside a managed dir are already in that dir's snapshot.
          case "$path" in */*) : ;; *) cp "$path" "$path.pre-upgrade-$TS" 2>/dev/null || true ;; esac
          rm -f "$path"
          ff_removed=$((ff_removed + 1))
        fi ;;
      skip) ff_preserved=$((ff_preserved + 1)) ;;
    esac
  done < "$APPLY_PLAN"
  echo "[upgrade] applied $ff_applied file(s), removed $ff_removed, preserved $ff_preserved (per-file, K15)."
  rm -f "$APPLY_PLAN" "$CLASSIFY_REPORT"
else
  for d in "${CONTENT_DIRS[@]}"; do
    if [ -d "$SOURCE_TREE/$d" ] && dir_differs "$d"; then copy_dir "$d"; fi
  done
  for f in "${CONTENT_FILES[@]}"; do
    if [ -f "$SOURCE_TREE/$f" ] && ! diff -q "$SOURCE_TREE/$f" "$f" >/dev/null 2>&1; then
      [ -f "$f" ] && cp "$f" "$f.pre-upgrade-$TS"
      mkdir -p "$(dirname "$f")"   # D11: older installs may lack audit/ entirely
      cp "$SOURCE_TREE/$f" "$f"
    fi
  done
fi

# ---- Step 1a (U3 / W2): merge-preserve the module-size baseline project state ----
# policies/ was just refreshed wholesale, which OVERWROTE the consumer's baseline
# with upstream's. Re-apply the LOCKED merge rule (upstream counts for upstream
# rows; consumer PROJECT rows preserved verbatim; ownership = upstream-baseline
# membership, NOT path prefixes) so check-module-size --all still passes post-upgrade.
# approval-policy.workflow_mode + protected-paths worker_undisturbed.paths are the
# OTHER project-state in policies/ — those are preserved via *.local.yml (deep-merged
# by policy_loader.py; the wholesale copy never ships a *.local.yml so it can't
# clobber them) + the policy-state-preserve test (AC7).
# Belt-and-suspenders: Step 1 just refreshed hooks/ (so the local lib is now
# definitely present) AND $SOURCE_TREE/hooks/local/lib/ is authoritative — re-source
# in case the early load was a no-op (pre-v3.25 install / un-staged bootstrap).
source_merge_lib || true
if [ -n "$LOCAL_BASELINE_SNAPSHOT" ] && command -v merge_module_size_baseline >/dev/null 2>&1; then
  UPSTREAM_BASELINE="$SOURCE_TREE/$BASELINE_REL"
  MERGED_BASELINE="$(mktemp)"
  merge_module_size_baseline "$LOCAL_BASELINE_SNAPSHOT" "$UPSTREAM_BASELINE" "$MERGED_BASELINE"
  if ! diff -q "$MERGED_BASELINE" "$BASELINE_REL" >/dev/null 2>&1; then
    cp "$BASELINE_REL" "$BASELINE_REL.pre-upgrade-$TS" 2>/dev/null || true
    cp "$MERGED_BASELINE" "$BASELINE_REL"
    echo "[upgrade] U3: merge-preserved module-size baseline project rows (see $BASELINE_REL)"
  fi
  rm -f "$MERGED_BASELINE" "$LOCAL_BASELINE_SNAPSHOT"
elif [ -n "$LOCAL_BASELINE_SNAPSHOT" ]; then
  # The merge lib could not be loaded from $SOURCE_TREE OR locally — the W2 fix
  # cannot run. NEVER silently skip: the wholesale policies/ copy has clobbered the
  # consumer's module-size baseline with upstream's, so `check-module-size --all` may
  # now fail. Tell the operator loudly + give the exact recovery.
  echo "" >&2
  echo "[upgrade] ============================ WARNING ============================" >&2
  echo "[upgrade] module-size baseline was NOT merge-preserved — merge_module_size_baseline" >&2
  echo "[upgrade] could not be sourced from $SOURCE_TREE/hooks/local/lib/ or $MERGE_LIB." >&2
  echo "[upgrade] Your project rows in $BASELINE_REL may have been clobbered by upstream's." >&2
  echo "[upgrade] RECOVER (restore your pre-upgrade baseline):" >&2
  echo "    cp $BASELINE_REL.pre-upgrade-$TS $BASELINE_REL" >&2
  echo "    # (or, if the wholesale copy backed up the dir: cp policies.pre-upgrade-$TS/module-size-baseline.txt $BASELINE_REL)" >&2
  echo "[upgrade] Then re-run the upgrade via the bootstrap path so the lib is staged first:" >&2
  echo "    bash hooks/local/bootstrap-upgrade.sh -- --auto-yes" >&2
  echo "[upgrade] =================================================================" >&2
  # Preserve a copy so the recovery command above has a target even though the
  # wholesale copy already overwrote policies/.
  cp "$LOCAL_BASELINE_SNAPSHOT" "$BASELINE_REL.pre-upgrade-$TS" 2>/dev/null || true
  rm -f "$LOCAL_BASELINE_SNAPSHOT"
fi

# ---- Step 1b: retire legacy root skills/ (v3.9.0 canonical relocation) ----
# flow-skills/ has now landed (step 1). Remove the superseded root skills/ so the
# FuseBase CLI's "obsolete ./skills" warning no longer applies and there's a single
# canonical source. Backed up; idempotent (no-op if already migrated).
if [ "$MIGRATE_LEGACY_SKILLS" -eq 1 ] && [ -d "skills" ] && [ -d "flow-skills" ]; then
  [ -e "skills.pre-upgrade-$TS" ] || cp -R "skills" "skills.pre-upgrade-$TS"   # skip on $TS collision (existing backup preserves state; no nested cp)
  rm -rf "skills"
  echo "[upgrade] migrated canonical: retired legacy root skills/ (now flow-skills/; backup skills.pre-upgrade-$TS)"
fi
if [ "$WITH_DOCS" -eq 1 ] && [ -d "$SOURCE_TREE/$DOC_GLOB" ]; then
  mkdir -p "$DOC_DEST_PREFIX"
  while IFS= read -r srcdoc; do
    dest="${DOC_DEST_PREFIX}$(basename "$srcdoc")"
    if [ ! -f "$dest" ] || ! diff -q "$srcdoc" "$dest" >/dev/null 2>&1; then
      [ -f "$dest" ] && cp "$dest" "$dest.pre-upgrade-$TS"
      cp "$srcdoc" "$dest"
    fi
  done < <(find "$SOURCE_TREE/$DOC_GLOB" -maxdepth 1 -name "*.md" -type f 2>/dev/null)
fi

# ---- Step 2: re-mirror canonical -> providers (OPTIONAL, bounded) ----
# B4: progress echoes bracket the otherwise-silenced re-mirror so a long mirror
# pass is visible (not a silent stall) on the operator's terminal.
# WS5: bounded via ffhc_run_step (fork-heavy on MSYS — a prime busy-loop candidate).
# OPTIONAL: a killed/failed mirror WARNs + continues — content + version are already
# landed, so the upgrade is still valid; the operator re-mirrors from the recovery hint.
echo "[upgrade] Step 2/3: re-mirroring skills + agents (canonical -> providers)…" >&2
[ -x hooks/local/mirror-skills.sh ] && ffhc_run_step "${FF_MIRROR_TIMEOUT:-300}" 0 "re-mirror skills" bash hooks/local/mirror-skills.sh
[ -x hooks/local/mirror-agents.sh ] && ffhc_run_step "${FF_MIRROR_TIMEOUT:-300}" 0 "re-mirror agents" bash hooks/local/mirror-agents.sh
echo "[upgrade] Step 2/3: re-mirror done." >&2

# ---- Step 5 (bump VERSION) BEFORE string-sync, but AFTER content (steps 1-2). ----
# TRIPWIRE: string-sync reads VERSION, so VERSION must already hold the TARGET value —
# but never before content landed ("VERSION never leads content", F1). This order is the
# only one satisfying both; do not move the bump back after the sync.
# WS5: VERSION write is a CRITICAL step. It is a fast atomic local write (no busy-loop /
# nothing to bound), but if it does not land, the upgrade must FAIL with the recovery hint —
# never leave content refreshed while VERSION still reads the old value (or is truncated).
if [ -n "$VERSION_CHANGE" ]; then
  cp VERSION "VERSION.pre-upgrade-$TS" 2>/dev/null || true
  if ! echo "$SRC_VERSION" > VERSION || [ "$(tr -d '\n\r' < VERSION 2>/dev/null)" != "$SRC_VERSION" ]; then
    echo "[upgrade] FATAL: CRITICAL step failed — VERSION write did not land ($SRC_VERSION) — the upgrade is INCOMPLETE." >&2
    print_recovery_hint
    exit 1
  fi
fi

# ---- Step 3: sync embedded version strings now that VERSION reflects target (OPTIONAL, bounded) ----
# WS5: attestation-string sync is cosmetic-derived (VERSION already landed), so a
# killed/failed sync WARNs + continues; the operator re-runs it from the recovery hint.
echo "[upgrade] Step 3/3: syncing derived attestation strings (sync-version-strings)…" >&2
[ -x hooks/local/sync-version-strings.sh ] && ffhc_run_step "${FF_SYNC_TIMEOUT:-180}" 0 "sync-version-strings" bash hooks/local/sync-version-strings.sh

# ---- Step 4: version-aware overlay refresh (F2) + slash-command restore ----
# post-fusebase-update.sh Step 8 installs any NEW commands from the (just-
# refreshed) recovery snapshot hooks/local/fusebase-flow-overlays/commands/ —
# this is the installer step for command-adding releases (v3.20.1).
# v3.21.1: output captured and SURFACED — the old fully-silenced call
# (>/dev/null || true) let a mid-run recovery crash half-apply (stale command
# files) with the root cause masked. Note: the recovery exits 1 on warnings
# as well as crashes, so non-zero means "review it", not "upgrade failed".
RECOVERY_LOG="$(mktemp)"
if bash hooks/local/post-fusebase-update.sh --refresh-overlays > "$RECOVERY_LOG" 2>&1; then
  grep -E "^  \* " "$RECOVERY_LOG" | sed 's/^/[upgrade] recovery: /' || true
else
  echo "[upgrade] WARN: overlay/command recovery reported warnings or FAILED — it may have"
  echo "          HALF-APPLIED (stale slash commands / overlay blocks possible). Last output:"
  tail -15 "$RECOVERY_LOG" | sed 's/^/          | /'
  echo "          Re-run it directly and review:  bash hooks/local/post-fusebase-update.sh --refresh-overlays"
fi
rm -f "$RECOVERY_LOG"

# ---- Step 4b: command doc-ref self-check (v3.20.1) ----
# The overlay refresh above is the injection path for CLAUDE.md command refs.
# If a consumer's CLAUDE.md is customized past marker recovery, the refresh can
# miss — preflight would then fail with a missing /<cmd> reference. Convert that
# silent BROKEN into an actionable notice here.
if [ -f CLAUDE.md ] && [ -d hooks/local/fusebase-flow-overlays/commands ]; then
  for cmd_file in hooks/local/fusebase-flow-overlays/commands/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd="$(basename "$cmd_file" .md)"
    if ! grep -q "/$cmd\b" CLAUDE.md; then
      echo "[upgrade] WARN: CLAUDE.md does not reference the /$cmd slash command —"
      echo "          add /$cmd to the 'Slash commands (.claude/commands/)' line in the"
      echo "          Fusebase Flow overlay block (preflight errors until it is listed)."
    fi
  done
fi

# ---- WS1c: (re)install the Flow git fallback hooks so the FIXED pre-commit is live ----
# The upgrade refreshed hooks/git/, but the ACTIVE .git/hooks/pre-commit is a COPY —
# stale until reinstalled (the "upgrade doesn't wire the fixed pre-commit" gap). Safe:
# a custom .git/hooks/pre-commit is backed up + preserved (needs --force to replace).
if [ -d .git/hooks ] && [ -x hooks/local/install-git-hooks.sh ]; then
  # TRIPWIRE (T24): capture the installer OUTPUT and RC SEPARATELY. The old
  # `install-git-hooks.sh | grep` gave `$?` of grep, NOT the installer — a nonzero
  # install that didn't print the custom-preserve line fell into the "installed"
  # branch (a silent false "installed"). Neutralize -e around the capture (an rc≠0
  # must NOT abort the upgrade), then decide: rc≠0 warns explicitly (no "installed"
  # claim), rc0+custom preserves, rc0 clean installs.
  _had_e=0; case $- in *e*) _had_e=1 ;; esac
  set +e
  _gh_out="$(bash hooks/local/install-git-hooks.sh 2>&1)"; _gh_rc=$?
  [ "$_had_e" = 1 ] && set -e
  if [ "$_gh_rc" -ne 0 ]; then
    echo "[upgrade] WARN: git fallback hook (re)install FAILED (exit $_gh_rc) — Flow hooks may be stale."
    echo "          Re-run and review: bash hooks/local/install-git-hooks.sh"
    [ -n "$_gh_out" ] && printf '%s\n' "$_gh_out" | sed 's/^/          | /'
  elif printf '%s' "$_gh_out" | grep -qi 'custom .* detected'; then
    echo "[upgrade] NOTE: a custom .git/hooks hook was preserved (not overwritten). To install the"
    echo "          Flow hook, run: bash hooks/local/install-git-hooks.sh --force"
  else
    echo "[upgrade] (re)installed Flow git fallback hooks (.git/hooks/pre-commit, commit-msg)"
  fi
fi

# ---- .pyc scrub (F6) ----
find . -path ./.fusebase-flow-source -prune -o -name "*.pyc" -print -delete 2>/dev/null | grep -q . \
  && echo "[upgrade] scrubbed stray .pyc files" || true

PRE_RETAIN="${FF_PRE_RETAIN:-3}"
# OPTIONAL step. ff_prune_pre_backups is single-pass (O(M) forks) so bounding is belt-only,
# and it is NOT routed through ffhc_run_step: that helper runs the step via `timeout <cmd>`,
# and `timeout` cannot invoke a bash FUNCTION. Run it directly, flushed, `|| true` so a
# prune hiccup never fails an upgrade whose content + version landed.
echo "[upgrade] step: prune old .pre-* backups (single-pass, keep newest $PRE_RETAIN/stem)…" >&2
if command -v ff_prune_pre_backups >/dev/null 2>&1; then
  ff_prune_pre_backups "$PRE_RETAIN" || echo "[upgrade] WARN: backup prune reported an error — continuing (upgrade still valid)." >&2
else
  echo "[upgrade] WARN: backup-hygiene lib absent — old .pre-* backups were NOT pruned." >&2
fi

# S1 (contract: docs/install-existing-project.md): record the consumed source LAST — every
# earlier exit path (no-op, abort, FATAL) must leave a prior INSTALLED_FROM untouched.
FF_PROV_LIB="$SOURCE_TREE/hooks/local/lib/installed-provenance.sh"
[ -f "$FF_PROV_LIB" ] || FF_PROV_LIB="$ROOT/hooks/local/lib/installed-provenance.sh"
if [ -f "$FF_PROV_LIB" ]; then . "$FF_PROV_LIB"; ff_prov_record "$ROOT" "$SOURCE_TREE" "$SRC_COMMIT" || true; fi
echo ""
echo "[upgrade] Content upgrade applied. VERSION now: $(tr -d '\n\r' < VERSION)"
if [ "${FF_BACKUPS_GITIGNORED:-0}" = 1 ]; then
  echo "[upgrade] Backups written with suffix .pre-upgrade-$TS (git-excluded via .git/info/exclude,"
  echo "          so 'git add -A' / fusebase-update checkpoints won't stage them)."
else
  echo "[upgrade] Backups written with suffix .pre-upgrade-$TS. (Could NOT git-exclude them; a later"
  echo "          'git add -A' may stage them — delete or unstage the .pre-* backups before committing.)"
fi
# TRIPWIRE (decision M5): NEVER print a raw recursive delete here. command-policy.yml denies
# `rm -rf` (FR-06) and the framework contradicting its own guard is what this replaced. The
# sanctioned tool's authority is exact stem membership + resolved-path validation.
echo "[upgrade] Once validated, remove them through the sanctioned, validated entry point:"
echo "            bash hooks/local/cleanup-flow-backups.sh --all    # or name exact targets"
echo "[upgrade] NOTE: the pre-commit secret scan skips ONLY Flow's fixture/policy backup twins, so a BLOCK on a"
echo "          .pre-* path is NOT automatically 'just a fixture' — inspect it: rotate if it is a real credential;"
echo "          if it is only a Flow backup you don't want committed, unstage it (git restore --staged <path>)."
echo "          Mid-ticket, answer 'No' to the CLI checkpoint prompt so WIP growth in grandfathered over-ceiling"
echo "          files doesn't trip the FR-25 ratchet on a wholesale add."
echo "[upgrade] NOTE: the hooks/ layer (incl. this engine + sync-version-strings.sh) was"
echo "          refreshed. The in-memory run finished on the OLD engine; any NEW engine"
echo "          logic takes effect on the NEXT run. Operator overrides (hooks/local/*.local.*)"
echo "          and CLI-owned .claude/hooks/** were left untouched."
echo ""
echo "[upgrade] Recommended next:"
echo "  bash hooks/local/preflight.sh                       # expect 0 errors / 0 warnings"
echo "  bash hooks/local/fusebase-flow-health-check.sh      # expect HEALTHY"
echo "  git diff                                            # review"
echo "  # On the operator's go-ahead the AGENT runs the steps below (the operator types no command):"
echo "  # stage the upgraded paths, then commit through the wired pre-commit (NO --no-verify):"
echo "  git add <upgraded paths>                            # explicit paths (not git add -A)"
echo "  bash hooks/local/write-bootstrap-approval.sh        # single-use, digest-bound internals approval"
echo "  git commit -m 'chore(flow): upgrade content to v$SRC_VERSION'"
echo "  bash hooks/local/write-bootstrap-approval.sh --consume   # single-use: clean up after the commit"
echo ""
echo "[upgrade] NOTE: the Flow git fallback pre-commit was (re)installed above so the FIXED"
echo "          pre-commit is live. .claude/settings.json (Claude Code lifecycle hooks) was"
echo "          NOT modified — to (re)wire those, run: bash hooks/local/post-fusebase-update.sh --wire-hooks"
echo ""
echo "[upgrade] NOTE: .fusebase-flow-source/ is a transient staging clone. ESLint flat"
echo "          config does NOT honor .gitignore, so if 'fusebase deploy' runs lint it"
echo "          will lint this clone's CommonJS hooks and fail. Either:"
echo "            bash hooks/local/cleanup-flow-backups.sh .fusebase-flow-source   # transient; re-created next upgrade"
echo "          or add it to your eslint ignores (next to .claude/**):"
echo "            bash hooks/local/eslint-ignore-flow-paths.sh"

# U7: clean finish — suppress the recovery hint and clear the trap.
UPGRADE_FINISHED=1
trap - INT TERM ERR
exit 0

}

main "$@"
