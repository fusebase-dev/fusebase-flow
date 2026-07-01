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
# Engines ≤3.20.0 lack this guard: from those versions, either upgrade via
#   bash hooks/local/bootstrap-upgrade.sh -- --auto-yes   (stages the new
# engine FIRST, so the self-overwrite is byte-identical and harmless), or
# simply RE-RUN upgrade.sh after the abort — the refreshed engine completes
# the remaining steps idempotently.
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
  echo "[upgrade] INTERRUPTED or FAILED before completion — the tree may be HALF-APPLIED." >&2
  echo "[upgrade] Recover by re-running (idempotent — the refreshed engine finishes the rest):" >&2
  echo "    bash hooks/local/upgrade.sh                              # re-run; completes remaining steps" >&2
  echo "    bash hooks/local/post-fusebase-update.sh --refresh-overlays  # re-apply adapters + slash commands" >&2
  echo "    bash hooks/local/sync-version-strings.sh                 # re-sync derived attestation strings" >&2
  echo "    bash hooks/local/preflight.sh && bash hooks/local/fusebase-flow-health-check.sh  # verify (HEALTHY)" >&2
}

# U3 (W2): the baseline merge rule lives in a sourced, unit-tested lib so the
# engine stays small (FR-25) and AC3 can test the rule directly.
#
# v3.25.1 (the bootstrap/adoption-hop fix): a PRE-v3.25 install — or a bootstrap
# that didn't stage hooks/local/lib/ — has NO local merge lib when this engine
# starts, so sourcing only $ROOT/... left merge_module_size_baseline undefined and
# the Step 1a guard silently skipped the merge → baseline clobbered. The merge MUST
# be driven by the TARGET-version lib (the running engine may predate it), so we
# source from $SOURCE_CLONE FIRST (authoritative), falling back to the local copy.
# Defined here; called after SOURCE_CLONE is validated (and again, belt-and-suspenders,
# right before the Step 1a guard) — never silently skipped.
MERGE_LIB="$ROOT/hooks/local/lib/merge-module-size-baseline.sh"
source_merge_lib() {
  command -v merge_module_size_baseline >/dev/null 2>&1 && return 0
  local src_lib="$SOURCE_CLONE/hooks/local/lib/merge-module-size-baseline.sh"
  [ -f "$src_lib" ] && . "$src_lib" 2>/dev/null
  command -v merge_module_size_baseline >/dev/null 2>&1 && return 0
  [ -f "$MERGE_LIB" ] && . "$MERGE_LIB" 2>/dev/null
  command -v merge_module_size_baseline >/dev/null 2>&1
}

SOURCE_CLONE=".fusebase-flow-source"
AUTO_YES=0
DRY_RUN=0
WITH_DOCS=0          # U4: framework docs are NOT copied into the consumer by default

for arg in "$@"; do
  case "$arg" in
    --auto-yes|-y) AUTO_YES=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --with-framework-docs) WITH_DOCS=1 ;;
    --help|-h) sed -n '2,52p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if [ ! -d "$SOURCE_CLONE" ]; then
  echo "[upgrade] FATAL: $SOURCE_CLONE/ not found." >&2
  echo "          Provide an upstream copy first, e.g.:" >&2
  echo "            git clone https://github.com/fusebase-dev/fusebase-flow.git $SOURCE_CLONE" >&2
  exit 1
fi

# Load the baseline-merge lib now that $SOURCE_CLONE is confirmed present — from the
# authoritative target-version tree first (the running engine may predate the merge
# rule). Step 1a re-checks and warns loudly if it is somehow still undefined.
source_merge_lib || true

# F5: a git clone enables HEAD reporting; a plain dir is accepted with a warning.
if [ -d "$SOURCE_CLONE/.git" ]; then
  SRC_HEAD=$(cd "$SOURCE_CLONE" && git rev-parse --short HEAD 2>/dev/null || echo "?")
else
  SRC_HEAD="(plain dir — no .git; HEAD/diff unavailable)"
  echo "[upgrade] NOTE: $SOURCE_CLONE/ is a plain directory (no .git). Proceeding with"
  echo "          file-content comparison only; upstream HEAD/diff is unavailable."
fi

if [ ! -f "$SOURCE_CLONE/VERSION" ]; then
  echo "[upgrade] FATAL: $SOURCE_CLONE/VERSION missing — cannot determine target version." >&2
  exit 1
fi
SRC_VERSION=$(tr -d '\n\r' < "$SOURCE_CLONE/VERSION")
LOCAL_VERSION=$(tr -d '\n\r' < VERSION 2>/dev/null || echo "?")

echo "[upgrade] Source: $SOURCE_CLONE/  (HEAD $SRC_HEAD, VERSION $SRC_VERSION)"
echo "[upgrade] Local:  VERSION $LOCAL_VERSION"
echo ""

# Canonical content trees + files to refresh (NOT provider mirrors; those are
# regenerated by the mirror scripts in step 2). U2: `hooks` is included so the
# Flow-owned hook layer (handlers, shared, git, tests, local *.sh — incl. this
# engine + sync-version-strings) is refreshed too; otherwise a downstream gets new
# skills/rules but a stale hook layer (e.g. the v3.7.0 tier-aware deploy gate would
# silently not work). copy_dir copies upstream OVER local without deleting extras,
# so operator overrides (hooks/local/*.local.*) and CLI-owned `.claude/hooks/**`
# (a separate tree) are preserved/untouched.
# v3.9.0: canonical skills moved root skills/ -> flow-skills/ (the FuseBase CLI
# deprecates the root ./skills name). Step 1b below migrates an existing install's
# legacy root skills/ away after the new flow-skills/ lands.
# v3.20.1: .claude-plugin included — preflight §8 requires plugin.json version
# == VERSION, but nothing refreshed it on upgrade, so every 3.14.1+ consumer
# upgrade landed with a version-mismatch ERROR (same installer-parity class as
# the slash-command gap).
CONTENT_DIRS=( "flow-skills" "agents" "workflows" "policies" "templates" "hooks" ".claude-plugin" )
CONTENT_FILES=( "FLOW_RULES.md" )
# Framework reference docs (top-level docs/*.md). U4: NOT copied into the consumer
# by default (they're framework-dev docs that collide with consumer doc layouts).
# With --with-framework-docs they land under docs/_fusebase-flow/ (namespaced),
# never the consumer's docs/ root.
DOC_GLOB="docs"
DOC_DEST_PREFIX="docs/_fusebase-flow/"

TS=$(date -u +%Y%m%dT%H%M%SZ)
PLAN=()

dir_differs() { ! diff -rq "$SOURCE_CLONE/$1" "$1" >/dev/null 2>&1; }

for d in "${CONTENT_DIRS[@]}"; do
  if [ -d "$SOURCE_CLONE/$d" ] && dir_differs "$d"; then
    PLAN+=("refresh dir:  $d/")
  fi
done
for f in "${CONTENT_FILES[@]}"; do
  if [ -f "$SOURCE_CLONE/$f" ] && ! diff -q "$SOURCE_CLONE/$f" "$f" >/dev/null 2>&1; then
    PLAN+=("refresh file: $f")
  fi
done
# Top-level framework docs (docs/*.md) — only with --with-framework-docs, and
# namespaced under docs/_fusebase-flow/ so they never collide with consumer docs.
if [ "$WITH_DOCS" -eq 1 ] && [ -d "$SOURCE_CLONE/$DOC_GLOB" ]; then
  while IFS= read -r srcdoc; do
    dest="${DOC_DEST_PREFIX}$(basename "$srcdoc")"
    if [ -f "$dest" ] && ! diff -q "$srcdoc" "$dest" >/dev/null 2>&1; then
      PLAN+=("refresh doc:  $dest")
    elif [ ! -f "$dest" ]; then
      PLAN+=("add doc:      $dest")
    fi
  done < <(find "$SOURCE_CLONE/$DOC_GLOB" -maxdepth 1 -name "*.md" -type f 2>/dev/null)
fi

# v3.9.0 migration: a legacy root skills/ alongside the incoming flow-skills/ will
# be retired (backed up). Only when the source actually ships flow-skills/.
MIGRATE_LEGACY_SKILLS=0
if [ -d "skills" ] && [ -d "$SOURCE_CLONE/flow-skills" ]; then
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

# ---- Step 1: refresh canonical content (with backups) ----
echo "[upgrade] Step 1/5: refreshing canonical content (${#CONTENT_DIRS[@]} dir(s) + ${#CONTENT_FILES[@]} file(s))…"
copy_dir() {
  local d="$1"
  [ -d "$SOURCE_CLONE/$d" ] || return 0
  if [ -d "$d" ]; then cp -R "$d" "$d.pre-upgrade-$TS"; fi
  # Replace contents (canonical is source of truth; do not delete extra local files
  # blindly — copy upstream over, leaving any project-local additions in place).
  mkdir -p "$d"   # new dir on first migration (e.g. flow-skills/ on a pre-3.9.0 tree)
  cp -R "$SOURCE_CLONE/$d/." "$d/"
}
for d in "${CONTENT_DIRS[@]}"; do
  if [ -d "$SOURCE_CLONE/$d" ] && dir_differs "$d"; then copy_dir "$d"; fi
done
for f in "${CONTENT_FILES[@]}"; do
  if [ -f "$SOURCE_CLONE/$f" ] && ! diff -q "$SOURCE_CLONE/$f" "$f" >/dev/null 2>&1; then
    [ -f "$f" ] && cp "$f" "$f.pre-upgrade-$TS"
    cp "$SOURCE_CLONE/$f" "$f"
  fi
done

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
# definitely present) AND $SOURCE_CLONE/hooks/local/lib/ is authoritative — re-source
# in case the early load was a no-op (pre-v3.25 install / un-staged bootstrap).
source_merge_lib || true
if [ -n "$LOCAL_BASELINE_SNAPSHOT" ] && command -v merge_module_size_baseline >/dev/null 2>&1; then
  UPSTREAM_BASELINE="$SOURCE_CLONE/$BASELINE_REL"
  MERGED_BASELINE="$(mktemp)"
  merge_module_size_baseline "$LOCAL_BASELINE_SNAPSHOT" "$UPSTREAM_BASELINE" "$MERGED_BASELINE"
  if ! diff -q "$MERGED_BASELINE" "$BASELINE_REL" >/dev/null 2>&1; then
    cp "$BASELINE_REL" "$BASELINE_REL.pre-upgrade-$TS" 2>/dev/null || true
    cp "$MERGED_BASELINE" "$BASELINE_REL"
    echo "[upgrade] U3: merge-preserved module-size baseline project rows (see $BASELINE_REL)"
  fi
  rm -f "$MERGED_BASELINE" "$LOCAL_BASELINE_SNAPSHOT"
elif [ -n "$LOCAL_BASELINE_SNAPSHOT" ]; then
  # The merge lib could not be loaded from $SOURCE_CLONE OR locally — the W2 fix
  # cannot run. NEVER silently skip: the wholesale policies/ copy has clobbered the
  # consumer's module-size baseline with upstream's, so `check-module-size --all` may
  # now fail. Tell the operator loudly + give the exact recovery.
  echo "" >&2
  echo "[upgrade] ============================ WARNING ============================" >&2
  echo "[upgrade] module-size baseline was NOT merge-preserved — merge_module_size_baseline" >&2
  echo "[upgrade] could not be sourced from $SOURCE_CLONE/hooks/local/lib/ or $MERGE_LIB." >&2
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
  cp -R "skills" "skills.pre-upgrade-$TS"
  rm -rf "skills"
  echo "[upgrade] migrated canonical: retired legacy root skills/ (now flow-skills/; backup skills.pre-upgrade-$TS)"
fi
if [ "$WITH_DOCS" -eq 1 ] && [ -d "$SOURCE_CLONE/$DOC_GLOB" ]; then
  mkdir -p "$DOC_DEST_PREFIX"
  while IFS= read -r srcdoc; do
    dest="${DOC_DEST_PREFIX}$(basename "$srcdoc")"
    if [ ! -f "$dest" ] || ! diff -q "$srcdoc" "$dest" >/dev/null 2>&1; then
      [ -f "$dest" ] && cp "$dest" "$dest.pre-upgrade-$TS"
      cp "$srcdoc" "$dest"
    fi
  done < <(find "$SOURCE_CLONE/$DOC_GLOB" -maxdepth 1 -name "*.md" -type f 2>/dev/null)
fi

# ---- Step 2: re-mirror canonical -> providers ----
# B4: progress echoes bracket the otherwise-silenced re-mirror so a long mirror
# pass is visible (not a silent stall) on the operator's terminal.
echo "[upgrade] Step 2/3: re-mirroring skills + agents (canonical -> providers)…" >&2
[ -x hooks/local/mirror-skills.sh ] && bash hooks/local/mirror-skills.sh >/dev/null 2>&1 || true
[ -x hooks/local/mirror-agents.sh ] && bash hooks/local/mirror-agents.sh >/dev/null 2>&1 || true
echo "[upgrade] Step 2/3: re-mirror done." >&2

# ---- Step 3: sync embedded version strings (uses LOCAL VERSION; bumped in step 5,
# so run AFTER bump? No — strings should reflect the TARGET version. Write VERSION
# first into a temp, but per F1 VERSION file itself is bumped LAST. Resolve by
# passing the target explicitly: temporarily VERSION is still old, so we bump the
# file, then sync strings, then the "VERSION never leads content" invariant still
# holds because content (steps 1-2) already landed.) ----

# ---- Step 5 (bump VERSION) BEFORE string-sync, but AFTER content (steps 1-2). ----
if [ -n "$VERSION_CHANGE" ]; then
  cp VERSION "VERSION.pre-upgrade-$TS" 2>/dev/null || true
  echo "$SRC_VERSION" > VERSION
fi

# ---- Step 3: sync embedded version strings now that VERSION reflects target ----
echo "[upgrade] Step 3/3: syncing derived attestation strings (sync-version-strings)…" >&2
[ -x hooks/local/sync-version-strings.sh ] && bash hooks/local/sync-version-strings.sh || true

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
  if bash hooks/local/install-git-hooks.sh 2>&1 | grep -qi 'custom .* detected'; then
    echo "[upgrade] NOTE: a custom .git/hooks hook was preserved (not overwritten). To install the"
    echo "          Flow hook, run: bash hooks/local/install-git-hooks.sh --force"
  else
    echo "[upgrade] (re)installed Flow git fallback hooks (.git/hooks/pre-commit, commit-msg)"
  fi
fi

# ---- .pyc scrub (F6) ----
find . -path ./.fusebase-flow-source -prune -o -name "*.pyc" -print -delete 2>/dev/null | grep -q . \
  && echo "[upgrade] scrubbed stray .pyc files" || true

# ---- U10: .pre-* backup retention (keep the most-recent N per stem) ----
# Every upgrade drops *.pre-upgrade-<ts> (and recovery drops *.pre-refresh-<ts>)
# backups; left unpruned they accrete (~70 observed, dotfile-prefixed so easy to
# miss). Keep the newest N per backup STEM (the path before the .pre-*-<ts> suffix),
# delete older ones. The <ts> is a sortable UTC stamp (date -u +%Y%m%dT%H%M%SZ), so
# lexicographic reverse-sort == newest-first. Conservative: only OUR timestamped
# suffixes, never the clone / .git. Default N=3 (FF_PRE_RETAIN override).
PRE_RETAIN="${FF_PRE_RETAIN:-3}"
prune_pre_backups() {
  local stem count bak
  # Group every timestamped backup by stem (path with the .pre-*-<ts> suffix removed).
  while IFS= read -r stem; do
    [ -n "$stem" ] || continue
    count=0
    # Newest-first by the trailing UTC timestamp (reverse lexicographic sort).
    while IFS= read -r bak; do
      [ -e "$bak" ] || continue
      count=$((count + 1))
      [ "$count" -le "$PRE_RETAIN" ] && continue
      rm -rf -- "$bak" && echo "[upgrade] U10: pruned old backup $bak"
    done < <(find . -path ./.git -prune -o -path ./.fusebase-flow-source -prune -o \
               \( -name "$(basename "$stem").pre-upgrade-*" -o -name "$(basename "$stem").pre-refresh-*" \) -print 2>/dev/null \
             | grep -E "^${stem//./\\.}\.pre-(upgrade|refresh)-" | sort -r)
  done < <(find . -path ./.git -prune -o -path ./.fusebase-flow-source -prune -o \
             \( -name '*.pre-upgrade-*' -o -name '*.pre-refresh-*' \) -print 2>/dev/null \
           | sed -E 's/\.pre-(upgrade|refresh)-[^/]*$//' | sort -u)
}
prune_pre_backups || true

echo ""
echo "[upgrade] Content upgrade applied. VERSION now: $(tr -d '\n\r' < VERSION)"
echo "[upgrade] Backups written with suffix .pre-upgrade-$TS — remove once validated."
echo "[upgrade] NOTE: the hooks/ layer (incl. this engine + sync-version-strings.sh) was"
echo "          refreshed. The in-memory run finished on the OLD engine; any NEW engine"
echo "          logic takes effect on the NEXT run. Operator overrides (hooks/local/*.local.*)"
echo "          and CLI-owned .claude/hooks/** were left untouched."
echo ""
echo "[upgrade] Recommended next:"
echo "  bash hooks/local/preflight.sh                       # expect 0 errors / 0 warnings"
echo "  bash hooks/local/fusebase-flow-health-check.sh      # expect HEALTHY"
echo "  git diff                                            # review"
echo "  # Stage the upgraded paths, then commit through the wired pre-commit (NO --no-verify):"
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
echo "            rm -rf .fusebase-flow-source                         # transient; re-created next upgrade"
echo "          or add it to your eslint ignores (next to .claude/**):"
echo "            bash hooks/local/eslint-ignore-flow-paths.sh"

# U7: clean finish — suppress the recovery hint and clear the trap.
UPGRADE_FINISHED=1
trap - INT TERM ERR
exit 0

}

main "$@"
