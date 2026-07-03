#!/usr/bin/env bash
# Fusebase Flow — sync-version-strings.sh
#
# PURPOSE (F7):
#   The live self-attestation / banner strings ("... under Fusebase Flow vX.Y.Z",
#   "This repo runs **Fusebase Flow vX.Y.Z**") drift from the VERSION file whenever
#   a release bumps VERSION but not the prose. A fresh agent invoked as Product
#   Owner / AI Developer reads the agent definition + adapters, so a stale string
#   there makes it self-attest the wrong version. This script derives the version
#   from VERSION and rewrites ONLY those live strings, so VERSION is the single
#   source of truth.
#
# CONTEXT-ANCHORED (critical): it rewrites only the two live phrasings —
#     "under Fusebase Flow v<semver>"
#     "runs **Fusebase Flow v<semver>**"
#   It deliberately does NOT do a blanket `Fusebase Flow v<semver>` replace,
#   because many files carry HISTORICAL/provenance refs that must be preserved:
#     "Shipped as part of Fusebase Flow v2.3.0+"   (upgrade-engine.sh)
#     "Available since: Fusebase Flow v2.4.0"       (health-check-deferrals.md)
#     "DEPRECATED (Fusebase Flow v3.2.0 / B5)"      (deprecated stop hooks)
#     "v2 (Fusebase Flow v2.7.0+)"                  (approval-policy.yml)
#   Rewriting those would falsify history.
#
# U4 (v3.24.x) — EXECUTABLE FRAMEWORK-OWNED ALLOWLIST (anti-GEMINI under-reach):
#   The scan set is an IN-SCRIPT allowlist (SYNC_ROOTS + SYNC_FILES), NOT a broad
#   `find` + a prune deny-list. A deny-list is unbounded against consumer doc
#   layouts (the v3.21.1 friction: FR refs got rewritten inside consumer
#   docs/product-backlog/**), and an allowlist that silently OMITS a framework
#   file recreates the GEMINI-stuck-at-v2.1 drift in reverse. Both failure modes
#   are guarded by hooks/tests/test-sync-allowlist.sh (the under-reach guard):
#   it FAILS if a token-bearing framework file is missing from the allowlist, and
#   FAILS if a consumer doc root would be synced. Edit the allowlist below + that
#   test together; never reintroduce a broad find.
#
# U5 (v3.24.x) — GEMINI 2-part / Local header: the version regex matches
#   `Fusebase Flow (Local )?v<2-or-3-part-semver>` so a consumer's
#   `Fusebase Flow Local v2.1` header syncs (was stuck because the old anchor
#   demanded a literal 3-part `v[0-9]+.[0-9]+.[0-9]+` and no `Local`).
#
# U2 (v3.24.x) — PORTABLE NEWLINE-STATE PRESERVATION: the previous
#   `printf '%s' "$after" > "$f"` STRIPPED the file's trailing newline, churning
#   every token-bearing file it scanned (11 consumer docs on one upgrade). We now
#   capture each file's EOF-newline state and restore it on write — portable
#   across Git-Bash/GNU/BSD (no bare `sed -i`, whose -i '' / unterminated-final-
#   line / NUL behavior differs by platform). Proven by hooks/tests/test-newline-
#   preserve.sh on both trailing-newline and no-trailing-newline fixtures.
#
#   It then RE-MIRRORS (mirror-agents.sh + mirror-skills.sh) so the generated
#   provider copies under .claude/ .agents/ .codex/ — and their audit manifests —
#   reflect the canonical edits. (Those dirs are generated; never edited directly.)
#
# What it NEVER touches:
#   - Dated history: CHANGELOG.md, docs/release-notes/**, docs/handoff/** (archive),
#     docs/tmp/handoff/** (formal dated relays), docs/specs/**, docs/changes/**.
#   - Generated mirror dirs directly (.claude/ .agents/ .codex/ — refreshed via
#     re-mirror so a single canonical source of truth is preserved).
#   - Consumer doc trees (docs/product-backlog|problem-catalog|product-execution|
#     client-workflows/**) — never in the allowlist (U4 guard enforces this).
#   - .fusebase-flow-source/, internal/, node_modules/, .git/, *.pre-* backups.
#
# Usage:
#   bash hooks/local/sync-version-strings.sh            # apply (+ re-mirror)
#   bash hooks/local/sync-version-strings.sh --dry-run  # show what would change
#
# Exit: 0 success (or nothing to do); 1 error; 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --help|-h) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -f VERSION ]; then
  echo "[sync-version-strings] FATAL: VERSION file missing." >&2
  exit 1
fi
VER="$(tr -d '\n\r' < VERSION)"
if [ -z "$VER" ]; then
  echo "[sync-version-strings] FATAL: VERSION is empty." >&2
  exit 1
fi

# Version is not the only derived attestation fact. The live self-attestation also
# names the FR-range ("FR-01 through FR-NN" / "FR-01..FR-NN") and some adapters/
# overlays name the skill count ("(NN canonical skills total)"). All three are
# derived from the framework and must match on every upgrade — otherwise an
# adapter ends up self-attesting "vX.Y.Z … FR-01 through FR-(N-1)".
FR_MAX="$(grep -oE 'FR-[0-9]+' FLOW_RULES.md 2>/dev/null | sed 's/FR-//' | sort -n | tail -1)"
if [ -n "$FR_MAX" ]; then
  FR_HI="$(printf 'FR-%02d' "$FR_MAX")"     # e.g. FR-26
else
  FR_HI=""
fi
# Canonical skills: flow-skills/ (v3.9.0+); legacy root skills/ as fallback.
SKILLS_CANON="flow-skills"; [ -d "$SKILLS_CANON" ] || SKILLS_CANON="skills"
SKILL_COUNT="$(find "$SKILLS_CANON" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

###############################################################################
# U4 — EXECUTABLE framework-owned sync allowlist (NOT a broad find + prune).
###############################################################################
# SYNC_ROOTS: directory globs whose framework *.md / *.mdc are syncable. SYNC_FILES:
# explicit standalone files. The under-reach guard test (test-sync-allowlist.sh)
# scans these roots for token-bearing files and FAILS on any omission; it also
# FAILS if a consumer doc root is added here. Plugin metadata (.claude-plugin/
# plugin.json) is version-checked by preflight §8 (a parity check, NOT a sed here).
SYNC_ROOTS=(
  "agents"                                  # agents/**/AGENT.md (canonical sub-agents)
  "flow-skills"                             # flow-skills/**/*.md (SKILL.md + references/*)
  "workflows"                              # workflows/*.md
  "templates"                              # templates/*.md
  "hooks/local/fusebase-flow-overlays"     # overlay recovery snapshots (adapters + commands)
  ".github/instructions"                   # .github/instructions/*.instructions.md
  ".cursor/rules"                          # .cursor/rules/*.mdc
)
SYNC_FILES=(
  "AGENTS.md" "CLAUDE.md" "GEMINI.md" "FLOW_RULES.md"
  ".github/copilot-instructions.md"
  "CONTRIBUTING.md"
  # Framework reference docs (top-level docs/*.md only — NOT consumer doc trees).
  "README.md" "ROADMAP.md"
  "docs/rail-mapping.md" "docs/architecture-overview.md" "docs/framework.md"
  "docs/compatibility.md" "docs/fusebase-cli-edition.md"
  "docs/install-fusebase-cli-project.md" "docs/install-existing-project.md"
  "docs/constitution.md" "docs/operator-discipline.md"
  # Tripwire: these three carry a LIVE `FR-01..FR-NN` string (found by the
  # under-reach guard test-sync-allowlist.sh). Removing them recreates the
  # GEMINI-stuck drift. docs/health-check-deferrals.md is deliberately NOT here:
  # its only token is historical provenance ("Available since: v2.4.0").
)

# Enumerate the allowlisted candidate set (framework files only; *.md / *.mdc).
declare -a CANDIDATES=()
for root in "${SYNC_ROOTS[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] && CANDIDATES+=("$f")
  done < <(find "$root" -type f \( -name '*.md' -o -name '*.mdc' \) 2>/dev/null)
done
for f in "${SYNC_FILES[@]}"; do
  [ -f "$f" ] && CANDIDATES+=("$f")
done

###############################################################################
# Context-anchored substitutions — live attestation + banner + FR-range + skill
# count only. Never a blanket replace (historical/provenance refs must survive).
###############################################################################
# U5: the version regex matches an optional " Local " and a 2- OR 3-part semver
#   `Fusebase Flow (Local )?v[0-9]+(\.[0-9]+){1,2}` so a stuck `Local v2.1`
#   header syncs. The replacement re-emits the canonical 3-part live form
#   `Fusebase Flow v<VER>` (dropping any stale " Local " in the live banner /
#   attestation phrasings — those two live forms are always the plain v<semver>).
SED_EXPRS=(
  "s/(under Fusebase Flow )(Local )?v[0-9]+(\.[0-9]+){1,2}/\1v${VER}/g"
  "s/(runs \*\*Fusebase Flow )(Local )?v[0-9]+(\.[0-9]+){1,2}/\1v${VER}/g"
)
if [ -n "$FR_HI" ]; then
  SED_EXPRS+=( "s/FR-01 through FR-[0-9]+/FR-01 through ${FR_HI}/g" )
  SED_EXPRS+=( "s/FR-01\.\.FR-[0-9]+/FR-01..${FR_HI}/g" )
fi
if [ -n "$SKILL_COUNT" ] && [ "$SKILL_COUNT" -gt 0 ] 2>/dev/null; then
  # Only the parenthesized "(NN canonical … skills total)" form (overlays/adapters);
  # leaves README's bold/heading counts to release-time edits.
  SED_EXPRS+=( "s/\(([0-9]+) canonical/(${SKILL_COUNT} canonical/g" )
fi
# FLOW_RULES.md carries its dated amendment log below "## Amendment log" —
# substitutions there falsify history, so its sed program is range-limited to the
# live section above the heading.
SED_ARGS=()
SED_ARGS_PRELOG=()
for expr in "${SED_EXPRS[@]}"; do
  SED_ARGS+=( -e "$expr" )
  SED_ARGS_PRELOG+=( -e "1,/^## Amendment log\$/ ${expr}" )
done

# U1: grep -lE prefilter (chunked for ARG_MAX). Only files containing a syncable
# token can change; the rest yield before==after with no write. SUPERSET_RE is a
# strict superset of every SED match condition for ANY version/FR/skill-count
# value, so nothing the sed would touch is dropped. Chunk via xargs -0 -n N so a
# very large candidate set never blows ARG_MAX.
SUPERSET_RE='Fusebase Flow (Local )?v[0-9]|FR-01 through FR-|FR-01\.\.FR-|\([0-9]+ canonical'
declare -a MATCHED=()
if [ "${#CANDIDATES[@]}" -gt 0 ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && MATCHED+=("$f")
  done < <(printf '%s\0' "${CANDIDATES[@]}" | xargs -0 -n 256 grep -lZE "$SUPERSET_RE" -- 2>/dev/null | tr '\0' '\n')
fi

echo "[sync-version-strings] scanning ${#CANDIDATES[@]} allowlisted file(s); ${#MATCHED[@]} contain a syncable token…"

###############################################################################
# U2 — portable newline-state-preserving rewrite.
###############################################################################
# Command substitution strips ALL trailing newlines, so we cannot infer the
# original EOF state from `$after`. Capture it explicitly from the file, run the
# substitution, then re-emit `after` WITH or WITHOUT the single trailing newline
# to match the original. before/after are compared on content (newline-agnostic),
# and we only write when content OR the realized bytes differ.
had_trailing_newline() { # had_trailing_newline <file> -> 0 (yes) / 1 (no)
  [ -s "$1" ] || return 1
  [ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" = "0a" ]
}

CHANGED=()
TOUCHED_CANONICAL=0
for f in "${MATCHED[@]}"; do
  [ -f "$f" ] || continue
  # Strip null bytes so command substitution doesn't warn on a stray-NUL file.
  before="$(tr -d '\0' < "$f")"
  if [ "$f" = "FLOW_RULES.md" ] || [ "$f" = "./FLOW_RULES.md" ]; then
    after="$(printf '%s' "$before" | sed -E "${SED_ARGS_PRELOG[@]}")"
  else
    after="$(printf '%s' "$before" | sed -E "${SED_ARGS[@]}")"
  fi
  if [ "$before" != "$after" ]; then
    CHANGED+=("$f")
    case "$f" in
      agents/*|./agents/*|flow-skills/*|./flow-skills/*|skills/*|./skills/*) TOUCHED_CANONICAL=1 ;;
    esac
    if [ "$DRY_RUN" -eq 0 ]; then
      if had_trailing_newline "$f"; then
        printf '%s\n' "$after" > "$f"        # restore the single trailing newline
      else
        printf '%s' "$after" > "$f"          # original had none — keep it that way
      fi
    fi
  fi
done

DERIVED="version v$VER${FR_HI:+, FR-01..$FR_HI}${SKILL_COUNT:+, $SKILL_COUNT skills}"

if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "[sync-version-strings] All live derived strings already match the repo ($DERIVED)."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[sync-version-strings] (dry-run) would sync derived strings ($DERIVED) in:"
  for c in "${CHANGED[@]}"; do echo "  • $c"; done
  case " ${CHANGED[*]} " in
    *" agents/"*|*" ./agents/"*|*" flow-skills/"*|*" ./flow-skills/"*|*" skills/"*|*" ./skills/"*) echo "  • (would re-mirror agents + skills to refresh provider copies)";;
  esac
  exit 0
fi

echo "[sync-version-strings] synced derived strings ($DERIVED) in:"
for c in "${CHANGED[@]}"; do echo "  • $c"; done

# Propagate canonical agent/skill edits into the generated provider mirrors
# (and refresh their audit manifests). Re-mirroring is idempotent: if the edit
# only touched non-canonical adapters, this is skipped. A mirror-script failure
# here MUST NOT be swallowed — a swallowed failure prints "re-mirrored" while the
# provider copies stay stale, exactly the drift the mirror step exists to close.
if [ "$TOUCHED_CANONICAL" -eq 1 ]; then
  remirror_rc=0
  if [ -x hooks/local/mirror-agents.sh ]; then
    bash hooks/local/mirror-agents.sh >/dev/null 2>&1 || remirror_rc=$?
  fi
  if [ -x hooks/local/mirror-skills.sh ]; then
    bash hooks/local/mirror-skills.sh >/dev/null 2>&1 || remirror_rc=$?
  fi
  if [ "$remirror_rc" -ne 0 ]; then
    echo "[sync-version-strings] ERROR: re-mirror FAILED (rc=$remirror_rc) — run mirror-skills.sh/mirror-agents.sh manually" >&2
    exit 1
  fi
  echo "  • re-mirrored agents + skills (provider copies + manifests refreshed)"
fi
exit 0
