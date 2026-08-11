#!/usr/bin/env bash
# Fusebase Flow — conservative deny-rule explanation (T3 / S4a; AC14-AC17).
# Spec: docs/specs/consumer-escalation-v480/spec.md.
#
# The reported problem: a consumer could not file an upstream report THROUGH the guard, because
# prose quoting a destructive pattern is denied, and the denial did not say which rule or which
# pattern fired. S4a explains the denial from `rule_id` and `matched_pattern`, which the deny
# decision already retained.
#
# TRIPWIRE — the negative half of this phase is the point. The message must claim NO location.
# Attributing a match to a span/payload needs the shell parsing K21/M8 reserve (that is S4b), so
# `no-location-claim` and `behavior-invariant` are not decoration: they are what stops this text
# from growing into a half-parser. Never relax them to let a "helpful" span through.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: denial-message <name>" / "FAIL: denial-message <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
finish() { echo "[test-command-policy-denial-message] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: denial-message skipped-no-python3"; pass=1; finish; }

OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, re, shutil, sys, tempfile
from pathlib import Path
import yaml

root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.command_policy import (  # noqa: E402
    POLICY_ERROR_RULE_ID, evaluate, explain_rule_denial,
)
from shared.policy_loader import reset_cache  # noqa: E402

FUTURE = "2099-01-01T00:00:00Z"
rows = []


def row(name, failures):
    rows.append((name, [f for f in failures if f]))


def make_repo(tmp: Path) -> Path:
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    for p in ("approval-policy.yml", "command-policy.yml"):
        shutil.copy(root / "policies" / p, tmp / "policies" / p)
    reset_cache()
    return tmp


def decide(repo: Path, command: str):
    reset_cache()
    return evaluate(command, root=repo)


def expected(rule_id: str, pattern: str) -> str:
    """The AC14 sentence, written out here rather than imported, so a change to the shipped
    wording has to be made in two places deliberately."""
    return (f"Denied: raw command matched rule {rule_id}, pattern {pattern}. "
            "Quoted prose can match this pattern; no match location is claimed.")


policy = yaml.safe_load((root / "policies" / "command-policy.yml").read_text(encoding="utf-8"))
deny_rules = policy["deny"]

# One matching command per SHIPPED deny rule. Completeness is asserted below, so a new deny rule
# lands here as a FAIL rather than as silent uncovered surface.
SAMPLES = {
    r'\brm\s+-rf\b': "rm -rf build",
    r'\bfind\b.*-delete\b': "find . -name '*.tmp' -delete",
    r'\bgit\s+push\s+(.+\s+)?--force(?:-with-lease)?\b': "git push origin feature --force",
    r'\bgit\s+reset\s+--hard\b': "git reset --hard HEAD~1",
    r'\bgit\s+checkout\s+--\s+\.': "git checkout -- .",
    r'\bgit\s+clean\s+-fdx?\b': "git clean -fdx",
    r'\bgit\s+add\s+(\.(\s|$)|--all\b|-A\b)': "git add -A",
    r'--no-verify\b': "git commit --no-verify -m wip",
}

with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))

    # ---- AC14: EVERY applicable deny renders the message, with that rule's own identifiers ----
    f = []
    uncovered = [r["pattern"] for r in deny_rules if r["pattern"] not in SAMPLES]
    if uncovered:
        f.append(f"deny rules with no sample command: {uncovered}")
    for rule in deny_rules:
        cmd = SAMPLES.get(rule["pattern"])
        if cmd is None:
            continue
        dec = decide(repo, cmd)
        if dec.decision != "deny":
            f.append(f"{cmd!r}: expected deny, got {dec.decision}")
            continue
        want = expected(rule.get("rule_id", "FR-06"), rule["pattern"])
        if want not in dec.reason:
            f.append(f"{cmd!r}: message missing/wrong -> {dec.reason!r}")
    row("ac14-every-shipped-deny-rule-renders-the-exact-message", f)

    # ---- AC14: the reported case — prose that merely QUOTES a pattern ----
    f = []
    prose = [
        'git commit -m "the guard denies rm -rf, which is why I am filing this"',
        'echo "our runbook says never run git reset --hard on main" >> report.md',
    ]
    for cmd in prose:
        dec = decide(repo, cmd)
        if dec.decision != "deny":
            f.append(f"{cmd!r}: expected deny (raw-string matching still over-fires), got {dec.decision}")
            continue
        want = expected(dec.rule_id, dec.matched_pattern)
        if want not in dec.reason:
            f.append(f"{cmd!r}: message missing/wrong -> {dec.reason!r}")
        if "Quoted prose can match this pattern" not in dec.reason:
            f.append(f"{cmd!r}: denial does not warn that quoted prose can match")
    row("ac14-quoted-prose-denial-explains-itself", f)

    # ---- AC15: rendered from RETAINED facts only ----
    # The renderer is a pure function of (rule_id, matched_pattern): it never sees the command,
    # so it cannot re-match, tokenize or extract a payload even in principle.
    f = []
    dec = decide(repo, "rm -rf /var/data")
    if expected(dec.rule_id, dec.matched_pattern) not in dec.reason:
        f.append("rendered identifiers are not the decision's own rule_id/matched_pattern")
    synthetic = explain_rule_denial("SYNTHETIC-ID", "SYNTHETIC-PATTERN")
    if synthetic != expected("SYNTHETIC-ID", "SYNTHETIC-PATTERN"):
        f.append(f"renderer output is not a pure substitution: {synthetic!r}")
    for token in ("rm", "/var/data", "SYNTHETIC-COMMAND"):
        if token in synthetic and token not in ("SYNTHETIC-ID", "SYNTHETIC-PATTERN"):
            f.append(f"renderer leaked command text {token!r}")
    row("ac15-rendered-from-retained-rule-id-and-pattern-only", f)

    # ---- AC15: NO location claim ----
    f = []
    LOCATION_WORDS = ("offset", "column", "char ", "character", "position", "index",
                      "span", "token", "at byte", "occurrence", "line 1", "argument ")
    for cmd in ["rm -rf build", 'git commit -m "never rm -rf anything"']:
        dec = decide(repo, cmd)
        lowered = dec.reason.lower()
        for word in LOCATION_WORDS:
            if word in lowered:
                f.append(f"{cmd!r}: denial claims a location via {word!r}")
        # The command's own payload must not be echoed back as a located excerpt.
        if '"never rm -rf anything"' in dec.reason:
            f.append(f"{cmd!r}: denial quotes the -m payload back")
    row("ac15-no-match-location-is-claimed", f)

    # ---- AC16: outcomes, rule selection and stage routing are unchanged ----
    # Pinned expectations: decision + rule_id + matched_pattern per command. A matching change
    # anywhere in the deny stage breaks this row before it reaches a consumer's gate.
    f = []
    PINNED = [
        ("rm -rf build",                     "deny",  "FR-06", r'\brm\s+-rf\b'),
        ("git commit --no-verify -m wip",    "deny",  "FR-13", r'--no-verify\b'),
        ("git add -A",                       "deny",  "FR-06", r'\bgit\s+add\s+(\.(\s|$)|--all\b|-A\b)'),
        ("echo hello",                       "allow", "",      ""),
        ("git status --short",               "allow", "",      ""),
        ("npm run build",                    "allow", "",      ""),
        ("git add hooks/shared/x.py",        "allow", "",      ""),
        ("fusebase deploy",                  "deny",  "FR-12", r'\bfusebase\s+deploy\b'),
        ("npx prisma migrate deploy",        "deny",  "FR-12", r'\b(npx\s+)?prisma\s+migrate\s+(deploy|reset)\b'),
    ]
    for cmd, want_decision, want_rule, want_pattern in PINNED:
        dec = decide(repo, cmd)
        if (dec.decision, dec.rule_id, dec.matched_pattern) != (want_decision, want_rule, want_pattern):
            f.append(f"{cmd!r}: got {(dec.decision, dec.rule_id, dec.matched_pattern)}, "
                     f"want {(want_decision, want_rule, want_pattern)}")
    # deny still SHORT-CIRCUITS: a command matching both stages never reaches require_approval.
    dec = decide(repo, "git push origin main --force")
    if dec.decision != "deny" or dec.rule_id != "FR-06" or dec.required_actions:
        f.append(f"deny no longer short-circuits require_approval: {dec.decision}/{dec.rule_id}/{dec.required_actions}")
    row("ac16-decisions-rule-selection-and-stage-order-unchanged", f)

    # ---- AC16: the message is scoped to deny-RULE denials only ----
    # An approval denial is not "the raw command matched a forbidden pattern", and a policy error
    # has no pattern at all. Neither may inherit the S4a sentence.
    f = []
    dec = decide(repo, "npx prisma migrate deploy")
    if "no match location is claimed" in dec.reason:
        f.append("an approval denial carries the deny-rule explanation")
    if "BLOCKED (FR-12)" not in dec.reason:
        f.append(f"approval denial shape changed: {dec.reason!r}")
    (repo / "policies" / "command-policy.yml").write_text("{}\n", encoding="utf-8")
    reset_cache()
    dec = evaluate("echo hello", root=repo)
    if dec.rule_id != POLICY_ERROR_RULE_ID or dec.decision != "deny":
        f.append(f"policy-error deny changed: {dec.decision}/{dec.rule_id}")
    if "no match location is claimed" in dec.reason:
        f.append("a policy-error deny carries the deny-rule explanation (it has no pattern)")
    row("ac16-approval-and-policy-error-denials-unchanged", f)

# ---- AC17: the edited file really is protected, so the FR-07 route was mandatory ----
f = []
from shared.path_policy import is_protected  # noqa: E402
protected, category = is_protected("hooks/shared/command_policy.py")
if not protected:
    f.append("hooks/shared/command_policy.py is not protected — the FR-07 claim is vacuous")
if category != "fusebase_flow_internals":
    f.append(f"unexpected protected category: {category}")
if is_protected("hooks/tests/test-command-policy-denial-message.sh")[0]:
    f.append("hooks/tests/** is protected — the T1/T3 no-mint rule would be wrong")
row("ac17-protected-path-policy-covers-the-edited-file", f)

for name, failures in rows:
    if failures:
        print(f"FAIL: denial-message {name} :: " + " | ".join(failures))
    else:
        print(f"PASS: denial-message {name}")
PY
)"
RC=$?
echo "$OUT" | grep -E '^(PASS|FAIL): denial-message ' || true
pass=$(echo "$OUT" | grep -c '^PASS: denial-message ')
fail=$(echo "$OUT" | grep -c '^FAIL: denial-message ')
if [ "$RC" -ne 0 ] && [ "$fail" -eq 0 ]; then
    fail=1
    echo "FAIL: denial-message harness crashed before reporting (exit $RC)"
    echo "$OUT" | tail -15 >&2
fi
finish
