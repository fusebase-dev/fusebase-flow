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

# PROSE PINNED TO MACHINERY — STRUCTURALLY (MAJOR 10, final-architecture-review finding 10).
# The claims above are only true while the workflow job graph holds. That used to be asserted by
# distributed grep anchors over workflow TEXT, and those were comment-blind: an in-memory
# mutation commenting out the Windows matrix row retained EVERY anchor, and an unsafe publish
# condition retained them too. "An assertion a comment can satisfy asserts nothing."
# hooks/tests/lib/workflow_graph_check.py parses both workflows as YAML — a parser cannot see a
# comment, so comment-blindness stops being a property anyone has to remember to re-check — and
# asserts the graph: reusability, trigger scope, both matrix legs, fail-fast, absence of job-level
# `if:`/continue-on-error, the committed wall, the always-reporting aggregate gate, the publish
# needs-edge, the tripwire, the B2 tag binding before AND after `gh release create`, least
# privilege, and committed defaults in both required jobs.
# It RETAINS six red-before mutations; each must turn its named assertion red, and a mutation that
# leaves the graph green is reported as a FAILURE (a vacuous assertion), never skipped.
GRAPH="$ROOT/hooks/tests/lib/workflow_graph_check.py"
graph_py="${PYTHON:-python3}"
command -v "$graph_py" >/dev/null 2>&1 || graph_py=python
if [ ! -f "$GRAPH" ]; then
    bad "workflow-graph-validation" "missing $GRAPH — the structural assertions are ABSENT, which is not the same as passing"
elif ! command -v "$graph_py" >/dev/null 2>&1; then
    bad "workflow-graph-validation" "no python interpreter, so the structural assertions could not run — reported red, never as a pass"
else
    graph_out="$("$graph_py" "$GRAPH" --root "$ROOT" 2>&1)"; graph_rc=$?
    printf '%s\n' "$graph_out" | grep -E '^(PASS|FAIL): release-authority ' || true
    graph_p="$(printf '%s\n' "$graph_out" | grep -c '^PASS: release-authority ')"
    graph_f="$(printf '%s\n' "$graph_out" | grep -c '^FAIL: release-authority ')"
    pass=$((pass + graph_p)); fail=$((fail + graph_f))
    # A validator that dies before reporting (missing PyYAML, unparseable workflow) must not
    # vanish into a green phase.
    if [ "$graph_rc" -ne 0 ] && [ "$graph_f" -eq 0 ]; then
        bad "workflow-graph-validation" "the validator exited $graph_rc without reporting any row: $(printf '%s' "$graph_out" | tr '\n' ' ' | cut -c1-200)"
    fi
    printf '%s\n' "$graph_out" | grep -vE '^(PASS|FAIL): release-authority ' >&2 || true
fi

finish
