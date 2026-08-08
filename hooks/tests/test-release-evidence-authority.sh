#!/usr/bin/env bash
# Fusebase Flow — release-evidence authority gate (architecture-review step 1).
#
# The defect this pins shut: the MACHINERY publishes only after the CI `verify` job passes
# on the tagged SHA (.github/workflows/fusebase-flow-release.yml -> `needs: verify` ->
# fusebase-flow-verify.yml), while the PROSE claimed a local run was the release gate.
# `PUBLISHING.md` demanded a local full run and `docs/maintainer-execution.md` demanded two
# platforms, against an Ubuntu-only enforced job. Prose and machinery disagreed; a release
# claim was being sourced from a terminal on one unpinned host.
#
# LIMITATION — stated, not hidden: this is a GREP check over a FIXED surface list, not a
# semantic one. It proves the recorded false-claim phrasings are gone and the correction's
# anchors are present; it cannot prove an arbitrary paraphrase is absent. It is a
# regression net for the defect that shipped, not a proof of the claim's absence.
#
# Two arms:
#   A. LEDGER (exact)      — each recorded false-claim phrasing must be absent from every
#                            checked surface. Restoring one turns this red.
#   B. CLASS NET (rule)    — any line in a checked surface that says "release
#                            proof/evidence/claim" must ALSO name the CI authority
#                            (CI / verify / tagged SHA) or carry an explicit negation
#                            (not / never / no). You may not assert release authority in
#                            these files without naming who holds it or denying it.
#                            The canonical section NAME ("Release evidence authority") is
#                            accepted as a pointer, not a claim — it is how every surface
#                            cites the one statement instead of re-deriving it.
#   plus positive anchors that the correction is actually delivered at each surface.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: release-authority <name>" / "FAIL: release-authority <name>"; exit = failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: release-authority $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: release-authority $1 (${2:-})"; }
finish() { echo "[test-release-evidence-authority] $pass/$((pass + fail)) PASS"; exit $fail; }

# Checked surfaces: what ships to a consumer or states the maintainer release contract.
# Deliberately EXCLUDES the historical record (docs/problem-catalog, docs/backlog,
# docs/specs, docs/release-notes, CHANGELOG, docs/tmp/handoff*) — those record what was
# believed at the time and must not be rewritten, and the superseded active handoff.
# TRIPWIRE: this file is not in the list — it quotes the banned phrasings on purpose.
SURFACES=(
    "PUBLISHING.md"
    "README.md"
    "AGENTS.md"
    "CLAUDE.md"
    "GEMINI.md"
    "FLOW_RULES.md"
    "docs/maintainer-execution.md"
    "docs/fusebase-cli-edition.md"
    "hooks/tests/run-tests.sh"
    "hooks/local/lane-router.sh"
    "hooks/local/lib/hook-integrity-check.sh"
    "hooks/local/lib/run-with-timeout.sh"
    "hooks/local/fusebase-flow-health-check.sh"
    "flow-skills/validation-and-qa/SKILL.md"
    ".agents/skills/validation-and-qa/SKILL.md"
    ".claude/skills/validation-and-qa/SKILL.md"
    "workflows/verification-gate.md"
    "workflows/greenlight-deploy.md"
    "workflows/greenlight-implement.md"
    "workflows/git-discipline.md"
    "docs/compatibility.md"
    ".github/workflows/fusebase-flow-verify.yml"
    ".github/workflows/fusebase-flow-release.yml"
)

# Arm A ledger: the exact phrasings that shipped the false claim. ERE, matched -i.
# Rows 5-6 are architecture-review step 6: two-platform gating was "required in prose and
# unenforced in machinery". The machinery now enforces it, so a surface that still calls it
# unenforced, or still calls the required job Ubuntu-only, is the false claim restored.
BANNED=(
    "pre-deploy gate MUST be a full"
    "full unscoped two-platform run before release"
    "gate harness a release claim rests on"
    "a gate report may cite ONLY state/audit/hook-test-results.md — never"
    "NOT YET ENFORCED"
    "Ubuntu-only"
)

# --- guard: the surface list must resolve, else every scan below is vacuously green -----
# TRIPWIRE (MSYS cost): both scans below grep the resolved list in ONE spawn each. The
# per-file/per-pattern loop this replaced cost ~200 process spawns => 125s on MSYS, which
# would have priced this phase out of the fast local default it is meant to live in.
FILES=(); missing=""
for s in "${SURFACES[@]}"; do
    if [ -f "$ROOT/$s" ]; then FILES+=("$ROOT/$s"); else missing="$missing $s"; fi
done
if [ "${#FILES[@]}" -ge 12 ]; then
    ok "surfaces-resolve (${#FILES[@]} of ${#SURFACES[@]} present;${missing:- none missing})"
else
    bad "surfaces-resolve" "only ${#FILES[@]} surfaces resolved — the scan would be vacuously green"
fi

rel() { sed "s#${ROOT}/##g" | tr '\n' '|'; }   # absolute paths back to repo-relative for the reason string

# --- arm A: no recorded false-claim phrasing survives ------------------------------------
banned_re="$(printf '%s|' "${BANNED[@]}")"; banned_re="${banned_re%|}"
hits="$(grep -niE "$banned_re" "${FILES[@]}" 2>/dev/null | cut -c1-160 | head -8 | rel)"
if [ -z "$hits" ]; then
    ok "no-legacy-local-is-release-gate-phrasing (${#BANNED[@]} ledger rows)"
else
    bad "no-legacy-local-is-release-gate-phrasing" "$hits"
fi

# --- arm B: a release-authority sentence must name CI or negate ---------------------------
# Negation-blind by construction (see header): the filter accepts an explicit negation, so
# the corrected sentences ("a local run is NEVER release evidence") do not self-trip.
offenders="$(grep -niE 'release (proof|evidence|claim)' "${FILES[@]}" 2>/dev/null \
    | grep -viE '\b(not|never|no|nothing)\b|\bCI\b|verify|tagged SHA|Release evidence authority' \
    | cut -c1-160 | head -8 | rel)"
if [ -z "$offenders" ]; then
    ok "release-authority-lines-name-ci-or-negate"
else
    bad "release-authority-lines-name-ci-or-negate" "$offenders"
fi

# --- positive anchors: the correction is delivered where the claim used to live ------------
anchor() { # anchor <name> <file> <ere>...
    local name="$1" f="$2"; shift 2
    if [ ! -f "$ROOT/$f" ]; then bad "$name" "$f missing"; return; fi
    local missing_pat=""
    for p in "$@"; do
        grep -qiE "$p" "$ROOT/$f" 2>/dev/null || missing_pat="$missing_pat [$p]"
    done
    if [ -z "$missing_pat" ]; then ok "$name"; else bad "$name" "$f lacks$missing_pat"; fi
}

# PUBLISHING.md must name the enforcing machinery by workflow, job and SHA scope.
anchor "publishing-names-the-ci-job" "PUBLISHING.md" \
    "fusebase-flow-release\.yml" "needs: verify" "tagged SHA"
# ... and must state outright that a local run is not the evidence.
anchor "publishing-declares-local-not-evidence" "PUBLISHING.md" \
    "^## Release evidence authority" "never release evidence"
# The runner and the QA skill point at that one canonical statement rather than re-deriving it.
anchor "runner-header-points-at-authority" "hooks/tests/run-tests.sh" \
    "Release evidence authority"
anchor "qa-skill-points-at-authority" "flow-skills/validation-and-qa/SKILL.md" \
    "Release evidence authority"
anchor "qa-skill-mirror-agents-points-at-authority" ".agents/skills/validation-and-qa/SKILL.md" \
    "Release evidence authority"
anchor "qa-skill-mirror-claude-points-at-authority" ".claude/skills/validation-and-qa/SKILL.md" \
    "Release evidence authority"
# The two-platform REQUIREMENT survives; step 6 made it ENFORCED, so both maintainer-facing
# surfaces must name the two required jobs rather than an Ubuntu-only gate.
anchor "maintainer-doc-states-two-platform-enforced" "docs/maintainer-execution.md" \
    "two-platform gating is mandatory" "verify-linux" "verify-windows-msys"
anchor "publishing-states-two-platform-enforced" "PUBLISHING.md" \
    "Two-platform gating is enforced" "verify-linux" "verify-windows-msys"

# PROSE PINNED TO MACHINERY. The claims above are only true while the workflow graph below
# holds; without these anchors the two surfaces could keep asserting enforcement after the
# jobs were deleted — the exact prose/machinery divergence step 6 exists to close.
anchor "verify-workflow-runs-both-platforms" ".github/workflows/fusebase-flow-verify.yml" \
    "name: verify-\\\$\\{\\{ matrix.platform \\}\\}" "platform: linux" "platform: windows-msys" \
    "ubuntu-latest" "windows-latest" "timeout-minutes: 60"
# verify-gate is what makes a SKIPPED or TIMED-OUT leg red instead of absent.
# TRIPWIRE: the `needs:` patterns are ANCHORED to YAML key indentation (`^    needs: verify$`).
# A bare "needs: verify" was satisfied by the PROSE COMMENT describing the gate — mutation-tested:
# deleting the real key left the anchor green. An assertion a comment can satisfy asserts nothing.
anchor "verify-workflow-has-the-aggregate-gate" ".github/workflows/fusebase-flow-verify.yml" \
    "^  verify-gate:$" "^    needs: verify$" "needs.verify.result" "!= \"success\""
# publish must stay structurally downstream of that aggregate.
anchor "release-workflow-publish-needs-verify" ".github/workflows/fusebase-flow-release.yml" \
    "^    uses: \\./\\.github/workflows/fusebase-flow-verify\\.yml$" \
    "^      sha: \\\$\\{\\{ github\\.sha \\}\\}$" \
    "^    needs: verify$"

# NEGATIVE: no committed-default override may appear in either required job. An FF_SKIP_* or an
# FF_*_TIMEOUT in CI turns a passing gate into a gate that was told to pass.
ovr="$(grep -nE 'FF_SKIP_|FF_ONLY|FF_CLI_RECOVERY_TIMEOUT|FF_PHASE_TIMEOUT' \
        "$ROOT/.github/workflows/fusebase-flow-verify.yml" \
        "$ROOT/.github/workflows/fusebase-flow-release.yml" 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*#' | cut -c1-160 | head -8 | rel)"
if [ -z "$ovr" ]; then
    ok "required-jobs-run-committed-defaults (no FF_SKIP_*/FF_ONLY/timeout override outside comments)"
else
    bad "required-jobs-run-committed-defaults" "$ovr"
fi

finish
