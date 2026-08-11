#!/usr/bin/env bash
# Fusebase Flow — S1/T9: docs/install-fusebase-cli-project.md is an INSTALL CONTRACT, so its
# ownership claims are executable. Contract + audit scope: docs/specs/backlog-triage-execution/
# execution-plan.md § S1 (and P7: the audit is the whole ownership contract, not one path).
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT:
#   These are STATIC assertions over the shipped document, cross-checked against the shipped
#   tree and (for --wire-hooks) the shipped script. They prove that every path the document
#   tells an operator to copy exists, that the Bash and PowerShell blocks name the same source
#   set, and that four named ownership claims match the code. They do NOT run an install, and
#   they cannot prove an install succeeds.
#
# Why it exists: the PowerShell block copied `.fusebase-flow-source\skills` — the canonical dir
# moved root skills/ -> flow-skills/ in v3.9.0 — so a Windows operator following the canonical
# procedure installed ZERO Flow skills, while the Bash block at the same step was correct. A
# per-shell divergence in a copy list is invisible to every reader who uses only one shell.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: install-doc <name>" / "FAIL: install-doc <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DOC="$ROOT/docs/install-fusebase-cli-project.md"
UPDATE="$ROOT/hooks/local/post-fusebase-update.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: install-doc $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: install-doc $1 (${2:-})"; }
finish() { echo "[test-install-fusebase-cli-project-doc] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$DOC" ]    || { bad "setup-doc-present" "missing $DOC"; finish; }
[ -f "$UPDATE" ] || { bad "setup-update-script-present" "missing $UPDATE"; finish; }

# norm_src <token>: ".fusebase-flow-source<sep><path>" -> "<path>", backslashes folded to
# forward slashes, trailing glob/separator stripped. TRIPWIRE: the PowerShell block uses `\`
# and the Bash block uses `/`; folding here is what lets one comparison cover both shells.
norm_src() {
  local p="${1#.fusebase-flow-source}"
  p="${p//\\//}"
  p="${p#/}"
  p="${p%/}"; p="${p%/\*}"; p="${p%\*}"; p="${p%/}"
  printf '%s\n' "$p"
}

# ---- 1. Every documented source path exists in the shipped tree -------------------------
# The whole document, both shells, every section — not just the copy blocks.
f=""; seen=""
while IFS= read -r tok; do
  rel="$(norm_src "$tok")"
  [ -z "$rel" ] && continue
  case " $seen " in *" $rel "*) continue ;; esac
  seen="$seen $rel"
  [ -e "$ROOT/$rel" ] || f="$f [documented source does not exist: .fusebase-flow-source/$rel]"
done < <(grep -oE '\.fusebase-flow-source[/\\][^ )"'"'"'`]+' "$DOC" | sort -u)
if [ -z "$seen" ]; then
  bad "documented-source-paths-exist" "extracted ZERO .fusebase-flow-source/<path> tokens - the extraction regex no longer matches the document, so this assertion was passing vacuously"
elif [ -z "$f" ]; then
  ok "documented-source-paths-exist (every .fusebase-flow-source/<path> in the document resolves in this repo; existence only, not content)"
else
  bad "documented-source-paths-exist" "$f"
fi

# ---- 2. Bash and PowerShell copy blocks name the SAME source set -------------------------
# The v3.9.0 defect class: one shell's list is corrected and the other is not. Set equality
# makes the two blocks impossible to drift apart silently.
BASH_SET="$(grep -E '^[[:space:]]*cp ' "$DOC" | grep -oE '\.fusebase-flow-source/[^ ]+' \
  | while IFS= read -r t; do norm_src "$t"; done | sort -u)"
PS_SET="$(grep -E '^[[:space:]]*Copy-Item ' "$DOC" | grep -oE '\.fusebase-flow-source\\[^ ]+' \
  | while IFS= read -r t; do norm_src "$t"; done | sort -u)"
if [ -z "$BASH_SET" ] || [ -z "$PS_SET" ]; then
  bad "bash-powershell-copy-parity" "one of the two copy blocks extracted EMPTY (bash rows: $(printf '%s' "$BASH_SET" | grep -c .), powershell rows: $(printf '%s' "$PS_SET" | grep -c .)) - the block markers changed, so this assertion cannot compare anything"
elif [ "$BASH_SET" = "$PS_SET" ]; then
  ok "bash-powershell-copy-parity ($(printf '%s\n' "$BASH_SET" | grep -c .) sources identical in both shells; source set only - destinations and flags are not compared)"
else
  bad "bash-powershell-copy-parity" "the two shells copy different source sets:
--- bash only ---
$(comm -23 <(printf '%s\n' "$BASH_SET") <(printf '%s\n' "$PS_SET"))
--- powershell only ---
$(comm -13 <(printf '%s\n' "$BASH_SET") <(printf '%s\n' "$PS_SET"))"
fi

# ---- 3. Canonical skills path is flow-skills/, never the pre-3.9.0 root skills/ -----------
# TRIPWIRE: named separately from assertion 1 on purpose. If root skills/ is ever recreated
# for a legacy fallback, assertion 1 would go green while this document still sent CLI-edition
# operators at the wrong canonical dir.
f=""
# TRIPWIRE: capture, never let grep write to stdout - run_shell_phase parses this stream.
LEGACY_HITS="$(grep -nE '\.fusebase-flow-source[/\\]skills([/\\ ]|$)' "$DOC")"
[ -n "$LEGACY_HITS" ] \
  && f="[document still copies the pre-3.9.0 root skills/ - canonical is flow-skills/: $(printf '%s' "$LEGACY_HITS" | tr '\n' ' ')]"
grep -qE '\.fusebase-flow-source[/\\]flow-skills' "$DOC" \
  || f="$f [document never names .fusebase-flow-source/flow-skills - the canonical Flow skill source]"
[ -z "$f" ] && ok "canonical-flow-skills-path (root skills/ absent as a copy source; flow-skills/ present)" \
  || bad "canonical-flow-skills-path" "$f"

# ---- 4. Plugin manifest dirs are declared publisher-only and are copied by neither shell --
# .codex-plugin/ and .claude-plugin/ declare THIS repository as a marketplace plugin and carry
# Flow's own VERSION; preflight cross-checks them against VERSION when present. They appeared
# only in the collision/preserve lists, so their ownership was never stated either way.
PUBLISHER_SECTION="$(awk '/^### Publisher-only/{p=1} p&&/^#{2,3} /&&!/^### Publisher-only/{exit} p{print}' "$DOC")"
f=""
[ -n "$PUBLISHER_SECTION" ] || f="$f [no '### Publisher-only' section - plugin-dir ownership is unstated]"
printf '%s' "$PUBLISHER_SECTION" | grep -q '\.codex-plugin'  || f="$f [publisher-only section does not name .codex-plugin/]"
printf '%s' "$PUBLISHER_SECTION" | grep -q '\.claude-plugin' || f="$f [publisher-only section does not name .claude-plugin/]"
printf '%s' "$PUBLISHER_SECTION" | grep -qiE 'do not copy|never cop|not install content' \
  || f="$f [publisher-only section states no do-not-copy rule]"
if grep -E '^[[:space:]]*(cp|Copy-Item) ' "$DOC" | grep -qE '(codex-plugin|claude-plugin)'; then
  f="$f [a copy command still uses a plugin manifest dir as a source]"
fi
[ -z "$f" ] && ok "plugin-dirs-publisher-only (both manifest dirs named, do-not-copy stated, neither shell copies them)" \
  || bad "plugin-dirs-publisher-only" "$f"

# ---- 5. Provider skill dirs are derived mirrors, not a copy source ------------------------
# The document warned "Flow must never restore CLI provider skills ... from this repository's
# bundled copy" and then copied .fusebase-flow-source/.agents/skills/* and .claude/skills/* -
# the bundled snapshot contains BOTH Flow mirrors and CLI-owned provider skills. Regenerating
# the Flow half from flow-skills/ is the only path that does not import CLI-owned bytes, and
# it is why parity in assertion 2 is structural (there is no per-shell copy to diverge).
f=""
if grep -E '^[[:space:]]*(cp|Copy-Item) ' "$DOC" | grep -qE '\.fusebase-flow-source[/\\]\.(agents|claude)[/\\]skills'; then
  f="$f [document still copies the bundled provider skill snapshot - contradicts the CLI-owned-skills rule]"
fi
grep -q 'hooks/local/mirror-skills.sh' "$DOC" \
  || f="$f [document never tells the operator to regenerate Flow provider mirrors with mirror-skills.sh]"
grep -qiE 'derived mirror|mirrors live in|regenerat' "$DOC" \
  || f="$f [document states no derived-mirror ownership for .agents/skills and .claude/skills]"
[ -z "$f" ] && ok "provider-mirrors-are-derived (no bundled-snapshot copy in either shell; mirror-skills.sh named; derived ownership stated)" \
  || bad "provider-mirrors-are-derived" "$f"

# ---- 6. The --wire-hooks claim matches the shipped branch --------------------------------
# Ground truth first: if the script's default ever starts merging settings.json, this assertion
# must fail so the document is re-checked rather than silently becoming true-by-accident.
f=""
awk '/^# Step 5 - Merge \.claude\/settings\.json/{p=1} p&&/WIRE_HOOKS/{found=1; exit} p&&/^# Step 6/{exit} END{exit !found}' "$UPDATE" \
  || f="$f [post-fusebase-update.sh step 5 is no longer guarded by WIRE_HOOKS - the shipped default may now merge settings.json; re-verify the document]"
RECOVERY_SECTION="$(awk '/^### When `fusebase update` changes shared agent files/{p=1; next} p&&/^#{2,3} /{exit} p{print}' "$DOC")"
if [ -z "$RECOVERY_SECTION" ]; then
  f="$f [recovery section heading not found - cannot check the --wire-hooks claim]"
else
  printf '%s' "$RECOVERY_SECTION" | grep -q -- '--wire-hooks' \
    || f="$f [recovery section never names --wire-hooks, so the opt-in step is invisible]"
  RESTORES="$(printf '%s\n' "$RECOVERY_SECTION" | grep -iE '^This restores')"
  [ -n "$RESTORES" ] || f="$f [no 'This restores ...' default-behaviour sentence found]"
  printf '%s' "$RESTORES" | grep -qiE 'settings|hook wiring|git hook|lifecycle hooks' \
    && f="$f [the default-behaviour sentence still claims settings/hook work that only runs under --wire-hooks: $RESTORES]"
fi
[ -z "$f" ] && ok "wire-hooks-claim-matches-code (step 5 is WIRE_HOOKS-guarded in the script; the document's default-restore sentence claims no settings/hook work and names the opt-in flag)" \
  || bad "wire-hooks-claim-matches-code" "$f"

# ---- 7. "Never copied" is checked against the UPGRADE ENGINE, not just the prose --------
# The document said the plugin dirs are never copied while managed_content_manifest.py still
# listed them, so the upgrade engine owned them and could overwrite a consumer's own
# (Fusebase CLI-generated) .codex-plugin/plugin.json. Assertion 4 above only reads the document;
# this one reads the code that actually decides what gets written.
MCM="$ROOT/hooks/local/lib/managed_content_manifest.py"
f=""
if [ ! -f "$MCM" ] || ! command -v python3 >/dev/null 2>&1; then
  bad "plugin-dirs-not-in-managed-set" "cannot run the classifier ($MCM / python3) — the ownership claim is unverified, not satisfied"
else
  MANAGED_DIRS_OUT="$(python3 "$MCM" list-managed --dirs 2>/dev/null)"
  if [ -z "$MANAGED_DIRS_OUT" ]; then
    bad "plugin-dirs-not-in-managed-set" "list-managed --dirs returned NOTHING, so this assertion would pass vacuously"
  else
    printf '%s\n' "$MANAGED_DIRS_OUT" | grep -qx '\.codex-plugin'  && f="$f [.codex-plugin is in the managed/upgrade set]"
    printf '%s\n' "$MANAGED_DIRS_OUT" | grep -qx '\.claude-plugin' && f="$f [.claude-plugin is in the managed/upgrade set]"
    # The legacy no-classifier fallback array writes the same trees; it must agree.
    grep -n 'CONTENT_DIRS=(' "$ROOT/hooks/local/upgrade.sh" | grep -qE '(codex-plugin|claude-plugin)' \
      && f="$f [upgrade.sh's legacy fallback CONTENT_DIRS still lists a plugin dir]"
    [ -z "$f" ] && ok "plugin-dirs-not-in-managed-set (the document's 'never copied' claim matches the classifier AND the legacy fallback: $(printf '%s\n' "$MANAGED_DIRS_OUT" | grep -c .) managed dirs, no plugin dir among them)" \
      || bad "plugin-dirs-not-in-managed-set" "$f"
  fi
fi

# ---- 8. preflight plugin-version parity is scoped to FLOW-OWNED manifests ----------------
# The guide targets repos that may ALREADY have their own .codex-plugin/plugin.json, so an
# existence-only parity check made following the guide produce an immediate false error. Both
# arms are driven, because only the negative arm proving nothing would be the weaker test.
PREFLIGHT="$ROOT/hooks/local/preflight.sh"
if [ ! -f "$PREFLIGHT" ] || ! command -v python3 >/dev/null 2>&1; then
  bad "preflight-parity-scoped-to-flow-manifests" "cannot run $PREFLIGHT — the negative case is unverified, not satisfied"
else
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ff-install-doc.XXXXXX")"
  # A consumer repo: its OWN plugin manifest, a different name, a deliberately different version.
  mkdir -p "$SCRATCH/.codex-plugin"
  printf '%s\n' '{"name": "acme-consumer-app", "version": "0.0.1"}' > "$SCRATCH/.codex-plugin/plugin.json"
  printf '9.9.9\n' > "$SCRATCH/VERSION"
  PARITY_RE='(codex|claude)-plugin/plugin\.json version .* != VERSION'
  foreign_out="$(cd "$SCRATCH" && bash "$PREFLIGHT" 2>&1)"
  # Positive control: same file, Flow's name, still a mismatched version => it MUST be reported.
  printf '%s\n' '{"name": "fusebase-flow", "version": "0.0.1"}' > "$SCRATCH/.codex-plugin/plugin.json"
  owned_out="$(cd "$SCRATCH" && bash "$PREFLIGHT" 2>&1)"
  rm -rf "$SCRATCH" 2>/dev/null
  f=""
  printf '%s\n' "$foreign_out" | grep -qE "$PARITY_RE" \
    && f="$f [a consumer-owned plugin manifest (name acme-consumer-app) tripped the Flow version-parity error]"
  printf '%s\n' "$owned_out" | grep -qE "$PARITY_RE" \
    || f="$f [a FLOW-owned manifest with a mismatched version was NOT reported — the scoping disabled the check instead of narrowing it]"
  [ -z "$f" ] && ok "preflight-parity-scoped-to-flow-manifests (foreign name 0.0.1 vs VERSION 9.9.9 => no parity error; same file renamed fusebase-flow => parity error still raised)" \
    || bad "preflight-parity-scoped-to-flow-manifests" "$f"
fi

finish
