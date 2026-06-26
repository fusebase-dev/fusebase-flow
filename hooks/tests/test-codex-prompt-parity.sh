#!/usr/bin/env bash
# Fusebase Flow — codex-slash-command-parity regression test (spec
# docs/specs/codex-slash-command-parity). Exercises the REAL shipped surfaces:
# the AGENTS.md command-equivalents table (AC1), the installer's single-sourced
# transform (AC2 drift-guard), and the installer's structural safety (AC3).
#
# AC1 — AGENTS.md carries the 6-row table: all 6 commands + the Portable column,
#       outside FLOW:PRESERVE.
# AC2 — install-codex-prompts.sh generates each prompt FROM the canonical command
#       body (description kept, .claude/agents -> .codex/agents, Flow marker).
#       Genuine RED-then-GREEN: a temp edit to a CANONICAL body changes the
#       generated output -> proves single-sourcing (no hand-maintained copy).
# AC3 — installer writes MARKED files to a temp CODEX_HOME, is idempotent, and
#       REFUSES to overwrite an UNMARKED file without --force.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: codex-parity <name>"
# / "FAIL: codex-parity <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AGENTS="$ROOT/AGENTS.md"
INSTALLER="$ROOT/hooks/local/install-codex-prompts.sh"
SRC_DIR="$ROOT/hooks/local/fusebase-flow-overlays/commands"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: codex-parity $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: codex-parity $1 ($2)"; }
finish() { echo "[test-codex-prompt-parity] $pass/$((pass + fail)) PASS"; exit $fail; }

# Loud setup preconditions — a missing input must FAIL, never false-green.
[ -f "$AGENTS" ]    || { bad "setup-agents-present"    "missing $AGENTS"; finish; }
[ -f "$INSTALLER" ] || { bad "setup-installer-present" "missing $INSTALLER"; finish; }
[ -d "$SRC_DIR" ]   || { bad "setup-src-present"       "missing $SRC_DIR"; finish; }
ok "setup-inputs-present"

COMMANDS=(product-owner onboard handoff fusebase-health token-waste-audit find-wasted-effort)

###############################################################################
# AC1 — the AGENTS.md command-equivalents table.
###############################################################################
# The table header row carries the four columns including the Portable column.
if grep -qF '| Command | Claude Code | Codex (`/prompts:<cmd>` if installed) | Portable (any agent) |' "$AGENTS"; then
  ok "ac1-table-header-present"
else
  bad "ac1-table-header-present" "command-equivalents table header (with Portable column) not found in AGENTS.md"
fi

# Each of the 6 commands appears in a table row with its /prompts:<cmd> equivalent.
ac1_missing=""
for cmd in "${COMMANDS[@]}"; do
  grep -qF "\`/$cmd\`" "$AGENTS" || ac1_missing="$ac1_missing /$cmd"
  grep -qF "/prompts:$cmd" "$AGENTS" || ac1_missing="$ac1_missing /prompts:$cmd"
done
if [ -z "$ac1_missing" ]; then
  ok "ac1-all-six-commands-listed"
else
  bad "ac1-all-six-commands-listed" "missing from AGENTS.md table:$ac1_missing"
fi

# The portable fallback column actually carries the skill-invocation guidance.
grep -qF 'invoke the `handoff` skill' "$AGENTS" \
  && ok "ac1-portable-column-has-skill-invocation" \
  || bad "ac1-portable-column-has-skill-invocation" "portable skill-invocation text missing"

# Outside FLOW:PRESERVE: the table line must sit ABOVE the FLOW:PRESERVE:BEGIN
# marker (the operator-owned region must not carry framework content).
table_ln="$(grep -nF '| Command | Claude Code |' "$AGENTS" | head -1 | cut -d: -f1)"
preserve_ln="$(grep -nF 'FLOW:PRESERVE:BEGIN' "$AGENTS" | head -1 | cut -d: -f1)"
if [ -n "$table_ln" ] && [ -n "$preserve_ln" ] && [ "$table_ln" -lt "$preserve_ln" ]; then
  ok "ac1-table-outside-flow-preserve"
else
  bad "ac1-table-outside-flow-preserve" "table line=$table_ln not strictly above FLOW:PRESERVE:BEGIN=$preserve_ln"
fi

###############################################################################
# AC2/AC3 helper — run the installer against an isolated temp CODEX_HOME.
###############################################################################
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_install() { # run_install <codex-home> [args...] -> stdout+stderr; sets RC
  local home="$1"; shift
  CODEX_HOME="$home" bash "$INSTALLER" "$@" >"$TMP_ROOT/out" 2>&1
  RC=$?
}

###############################################################################
# AC2 — single-sourced transform + drift-guard.
###############################################################################
CH="$TMP_ROOT/codex"
run_install "$CH"
gen="$CH/prompts/product-owner.md"
if [ "$RC" -eq 0 ] && [ -f "$gen" ]; then
  ok "ac2-installer-generated-files"
else
  bad "ac2-installer-generated-files" "installer rc=$RC; $gen absent ($(cat "$TMP_ROOT/out"))"
  finish
fi

# Description frontmatter is KEPT (not stripped — D1 ground truth).
grep -qF "$(grep -m1 '^description:' "$SRC_DIR/product-owner.md")" "$gen" \
  && ok "ac2-description-frontmatter-kept" \
  || bad "ac2-description-frontmatter-kept" "canonical description: line not present in generated body"

# Agent path repointed; the Claude path must NOT survive.
if grep -qF '.codex/agents/product-owner.md' "$gen" && ! grep -qF '.claude/agents/' "$gen"; then
  ok "ac2-agents-path-repointed"
else
  bad "ac2-agents-path-repointed" ".claude/agents not converted to .codex/agents in generated body"
fi

# Flow-generated marker present (the single-source provenance + collision sentinel).
grep -qF 'FUSEBASE-FLOW-GENERATED' "$gen" \
  && ok "ac2-flow-marker-present" \
  || bad "ac2-flow-marker-present" "Flow-generated marker header missing"

# PO-boot block markers pass through untouched.
if grep -qF 'PO-BOOT-BLOCK:START' "$gen" && grep -qF 'PO-BOOT-BLOCK:END' "$gen"; then
  ok "ac2-po-boot-block-preserved"
else
  bad "ac2-po-boot-block-preserved" "PO-activation boot block markers not preserved"
fi

# DRIFT-GUARD (RED-then-GREEN): editing a CANONICAL body changes the generated
# output -> proves the transform reads the canonical source, not a frozen copy.
# We copy the canonical tree to a temp source, point a temp installer at it, and
# compare generated output before/after a canonical edit. (Editing the real
# canonical file in-place would dirty the tree; we exercise the SAME transform by
# overriding the source dir via a sandbox installer copy.)
SANDBOX_SRC="$TMP_ROOT/sandbox-commands"
mkdir -p "$SANDBOX_SRC"
cp "$SRC_DIR"/*.md "$SANDBOX_SRC/"
SANDBOX_INSTALLER="$TMP_ROOT/install-sandbox.sh"
# Repoint the installer's SRC_DIR at the sandbox so the SAME transform code runs
# over an editable copy. Absolute path (ROOT-relative default would miss it).
sed "s|^SRC_DIR=.*|SRC_DIR=\"$SANDBOX_SRC\"|" "$INSTALLER" > "$SANDBOX_INSTALLER"

CH_BEFORE="$TMP_ROOT/before"
CODEX_HOME="$CH_BEFORE" bash "$SANDBOX_INSTALLER" >/dev/null 2>&1
before_body="$(cat "$CH_BEFORE/prompts/onboard.md")"

# Edit the canonical (sandbox) body — a marker line the transform copies verbatim.
printf '\n<!-- DRIFT-PROBE-SENTINEL-%s -->\n' "$$" >> "$SANDBOX_SRC/onboard.md"
CH_AFTER="$TMP_ROOT/after"
CODEX_HOME="$CH_AFTER" bash "$SANDBOX_INSTALLER" >/dev/null 2>&1
after_body="$(cat "$CH_AFTER/prompts/onboard.md")"

if [ "$before_body" != "$after_body" ] && printf '%s' "$after_body" | grep -qF "DRIFT-PROBE-SENTINEL-$$"; then
  ok "ac2-drift-guard-canonical-edit-propagates"
else
  bad "ac2-drift-guard-canonical-edit-propagates" "a canonical-body edit did NOT change generated output (hand-maintained copy?)"
fi

###############################################################################
# AC3 — installer structural safety: marked, idempotent, collision-safe.
###############################################################################
# Every installed file carries the marker (already covered for one; assert all 6).
ac3_unmarked=""
for cmd in "${COMMANDS[@]}"; do
  grep -qF 'FUSEBASE-FLOW-GENERATED' "$CH/prompts/$cmd.md" 2>/dev/null || ac3_unmarked="$ac3_unmarked $cmd"
done
[ -z "$ac3_unmarked" ] \
  && ok "ac3-all-files-marked" \
  || bad "ac3-all-files-marked" "unmarked generated file(s):$ac3_unmarked"

# Idempotent: a second run writes nothing new (reports "written: 0").
run_install "$CH"
if [ "$RC" -eq 0 ] && grep -q 'written: 0' "$TMP_ROOT/out"; then
  ok "ac3-idempotent-rerun"
else
  bad "ac3-idempotent-rerun" "second run not idempotent (rc=$RC): $(cat "$TMP_ROOT/out")"
fi

# Collision: an UNMARKED existing file must make the installer REFUSE (rc=1) and
# leave that file UNTOUCHED.
printf 'operator-owned prompt, not flow-generated\n' > "$CH/prompts/handoff.md"
run_install "$CH"
if [ "$RC" -eq 1 ] && grep -qF 'operator-owned prompt' "$CH/prompts/handoff.md"; then
  ok "ac3-refuses-unmarked-collision"
else
  bad "ac3-refuses-unmarked-collision" "did not refuse/preserve unmarked file (rc=$RC)"
fi

# RED arm: the refusal is REAL — a marked file in the same spot does NOT block.
# (Re-mark handoff.md via --force, then a plain run must succeed.)
run_install "$CH" --force
if [ "$RC" -eq 0 ] && grep -qF 'FUSEBASE-FLOW-GENERATED' "$CH/prompts/handoff.md"; then
  ok "ac3-force-overwrites-unmarked"
else
  bad "ac3-force-overwrites-unmarked" "--force did not overwrite+mark the unmarked file (rc=$RC)"
fi

run_install "$CH"
[ "$RC" -eq 0 ] \
  && ok "ac3-marked-file-not-blocked" \
  || bad "ac3-marked-file-not-blocked" "a now-marked file blocked a plain run (rc=$RC) — collision guard too broad"

###############################################################################
# AC3+ — marker invariant is TOTAL (Codex LOW, 2026-06-26). A canonical body with
# NO YAML frontmatter must HARD-FAIL the transform: installer exits non-zero AND
# writes no (unmarked) prompt. RED-then-GREEN: prove the pre-fix transform path
# (bare awk, no PIPESTATUS guard) WOULD have streamed an unmarked body for the same
# fixture — so this test bites if the hard-fail is removed.
###############################################################################
NF_SRC="$TMP_ROOT/nofm-commands"
mkdir -p "$NF_SRC"
cp "$SRC_DIR"/*.md "$NF_SRC/"
printf '# /no-frontmatter\n\nBody with NO yaml frontmatter fence.\n' > "$NF_SRC/no-frontmatter.md"
NF_INSTALLER="$TMP_ROOT/install-nofm.sh"
sed "s|^SRC_DIR=.*|SRC_DIR=\"$NF_SRC\"|" "$INSTALLER" > "$NF_INSTALLER"

CH_NF="$TMP_ROOT/nofm-home"
CODEX_HOME="$CH_NF" bash "$NF_INSTALLER" >"$TMP_ROOT/nf_out" 2>&1
NF_RC=$?
if [ "$NF_RC" -ne 0 ]; then
  ok "ac3-no-frontmatter-hard-fails"
else
  bad "ac3-no-frontmatter-hard-fails" "frontmatter-less body did NOT make the installer exit non-zero (rc=$NF_RC)"
fi

# No unmarked prompt may have been written for the offending command — and the
# fail-closed posture means NO prompt at all is written from that run.
if [ ! -f "$CH_NF/prompts/no-frontmatter.md" ]; then
  ok "ac3-no-frontmatter-writes-no-unmarked-file"
else
  bad "ac3-no-frontmatter-writes-no-unmarked-file" "an UNMARKED prompt was written for a frontmatter-less body"
fi

# RED proof: the pre-fix transform (bare awk emitting the marker to stderr, no
# PIPESTATUS hard-fail) would have produced a non-empty stdout BODY for this same
# fixture — i.e. an unmarked prompt. Asserting that body is non-empty confirms the
# hazard was real and that the GREEN arms above are the fix, not a no-op.
prefix_body="$(awk 'BEGIN{fm=0;inserted=0}
  NR==1 && $0=="---"{fm=1;print;next}
  fm==1 && $0=="---"{print;print"";print "MARKER";fm=2;inserted=1;next}
  {print}
  END{if(!inserted) print "MARKER" > "/dev/stderr"}' "$NF_SRC/no-frontmatter.md" 2>/dev/null)"
if [ -n "$prefix_body" ] && ! printf '%s' "$prefix_body" | grep -qF 'MARKER'; then
  ok "ac3-no-frontmatter-red-proof"
else
  bad "ac3-no-frontmatter-red-proof" "pre-fix path did not demonstrate an unmarked body (RED proof inconclusive)"
fi

finish
