#!/usr/bin/env python3
"""Flow 6.0.0 WP 6: checks on the six core skill drafts.

Fold map, carry list, byte budget and substitution table: docs/changes/2026-10-16-v600-wp6-skills/README.md.
Stdlib only.

Usage:
  python skill_carry_anchors.py --root DIR [--repo PATH] [--source-ref v5.11] [--readme FILE]

DIR holds <skill>/SKILL.md for the six skills. The same code runs in wave 1 against the
draft folder and in wave 3 against the canonical folder (pass --readme there).

What it checks, and nothing more: five verbatim blocks against `git show <ref>:<path>`
after SUBSTITUTIONS (a missing ref is a FAIL, never a skip); SUBSTITUTIONS equal to the
README § 4 table row for row; the ANCHORS phrases; the interface names; the three briefs
carry no rule text or default verdict; byte ceilings; no tool or model names; no Karpathy
text; the AC19 claim stays out of ship. Fold-map rows without an anchor are review-checked.
It also prints the projected boot totals (README § 3); those are informational, never a case.

Output contract (run-tests.sh run_shell_phase): "PASS: skill-carry <case>" /
"FAIL: skill-carry <case> (<detail>)"; exit code = number of failures.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

SKILLS = ("plan", "build", "verify", "ship", "security-checklist", "writing-card")
# Byte ceilings: README § 3 Byte counts and loading.
CEILING = {"plan": 6000, "build": 10000, "verify": 15000, "ship": 7000,
           "security-checklist": 5000, "writing-card": 1500}
TOTAL_CEILING = 40000
DESCRIPTION_CEILING = 200

# Applied in order to the 5.11 lines before comparison. TRIPWIRE: must equal the README § 4
# table row for row (case substitutions-match-readme); the table is an open owner question.
SUBSTITUTIONS = (
    ("`flow-skills/validation-and-qa/SKILL.md` Sub-mode C", "Sub-mode C (below)"),
    ("`validation-and-qa` Sub-mode C", "Sub-mode C (below)"),
    ("under `docs/tmp/handoff/<date>-<slug>-smoke/`",
     "in the tool's native output, cited by an evidence row with path, sha256 and size"),
    ("in the evidence dir", "in the run log"),
    ("docs/specs/<slug>/verification-gate.md", "backlog.md"),
    ("(spec or S<n> pass criterion)", "(the item's criterion or S<n> pass criterion)"),
    ("Systemic → `requirements-specification` fix spec", "Systemic → a new backlog item"),
    ("Systemic → fix spec (prompt/tooling/guard)", "Systemic → a new backlog item (prompt/tooling/guard)"),
    (" (the classic FR-10 close)", ""),
    ("For the reproducing test/probe required by `flow-skills/zoom-out/references/karpathy-guidelines.md` §4, reproduce",
     "For the reproducing test or probe, reproduce"),
    ("(mirrors `smoke-testing` § Flaky-result \"Explained\")", "(mirrors § Flaky-result \"Explained\" above)"),
    ("(DP.1: an action not presented is not covered)", "(an action not presented is not covered)"),
)

# (case, skill, 5.11 path, first line, last line, optional sentence regex to cut out of the range)
VERBATIM = (
    ("T147-six-live-run-bullets", "verify", "flow-skills/smoke-testing/SKILL.md", 116, 121, None),
    ("T142-flaky-semantics", "verify", "flow-skills/smoke-testing/SKILL.md", 93, 112, None),
    ("T142-sub-mode-c-verdict-table", "verify", "flow-skills/validation-and-qa/SKILL.md", 109, 126, None),
    ("T159-claude-code-wake-row", "build", "flow-skills/liveness-discipline/SKILL.md", 128, 128,
     r"a background shell command's exit.*?only your watcher sees a hung call"),
    ("T145-DP1-presentation-sentence", "ship", "flow-skills/task-delegation/SKILL.md", 287, 287,
     r"Before the signal, present what the environment.*$"),
)

# Anchor phrases that must stay (whitespace-insensitive substring match).
ANCHORS = (
    ("end-the-turn-after-dispatch", "build", "## End the turn after dispatch"),
    ("T149-dispatch-before-turn-ends", "build", "Before the turn ends, dispatch every already-authorized independent slice"),
    ("T149-parks-only-gated-action", "build", "parks only the gated action and its dependents; it opens no gate and grants no authorization"),
    ("T145-cross-slice-order", "build", "wait until every slice they cover is DONE; a parked slice parks them"),
    ("T145-own-brief-redispatch", "build", "re-dispatched as their own slice, with that slice's brief"),
    ("T145-grant-is-not-approval", "ship", "a grant in chat is evidence of the conversation, not an approval artifact"),
    ("T145-worker-never-mints", "ship", "A worker never mints."),
    ("T152-blocked-at-input", "build", "A slice that prints `BLOCKED-AT-input` is not dispatched"),
    ("T152-question-not-fallback", "plan", "An input no profile can read is a question now, never a build-time fallback."),
    ("T158-read-before-edit", "writing-card", "Read the whole file before you edit against its invariants or close verification on it."),
    ("T159-never-the-only-wake", "build", "never the only wake"),
    ("codex-polled-boundary", "build", "the next operator message starts the next task boundary, where you read `state/status.line` and poll `state/returns/`"),
    ("codex-reader-held-turn", "build", "the turn is held for that bounded run (minutes), never for a build"),
    ("codex-unproven", "build", "Codex: unproven"),
    ("typed-return-file", "build", "state/returns/<slice>.json"),
    ("pause-at-boundary", "build", "check state/pause"),
    ("retry-envelope", "build", "at most 3 attempts within 5 minutes"),
    ("gate-rounds-a", "verify", "`gate_rounds` (default 2) lives in `policies/approval-policy.yml`"),
    ("gate-rounds-b", "verify", "A local override may lower the limit, never raise it."),
    ("gate-rounds-c", "verify", "A script failure costs no round."),
    ("gate-rounds-d", "verify", "Review rounds share the limit and keep their own counter."),
    ("gate-rounds-e", "verify", "the operator closes. An unattended run closes only when the operator authorized that beforehand."),
    ("gate-budget-carry-over", "verify", "security, privacy, data-loss and owner-answer contradictions first"),
    ("two-skeptics-per-phase", "verify", "per phase gate, never per slice"),
    ("done-send-back", "verify", "Review never starts on PARTIAL work."),
    ("fail-stays-fail", "verify", "FAIL stays FAIL."),
    ("no-commit-raw-output", "verify", "Never commit screenshots or raw run output"),
    ("pre-minted-dev-deploy", "ship", "the exact dev deploy command is minted before an unattended run starts"),
    ("helper-never-deploys", "ship", "a helper agent never deploys"),
    ("deploy-phrase", "ship", "`approve deploy now`"),
    ("north-star-line", "plan", "`docs/north-star.md` when it exists"),
    # Evidence schema and run log (OD3).
    ("evidence-row-schema", "verify", "one row per criterion id with its status (`PASS` or `FAIL`; a FAIL row's "
     "`Note` says why, including a runner's `BLOCKED-AT-<reason>` or a run that hit its deadline), the "
     "capture's path, sha256 and size, and the run log path"),
    ("evidence-test-id-row", "verify", "A test-id row cites `<file path>::<test name>` and a TAP log in the run directory."),
    ("evidence-hash-in-place", "verify", "The validator hashes captures in place"),
    ("runs-index-only", "verify", "`state/runs/<phase>/` holds one index line per run (run id, phase, directory, "
     "started, exit code)"),
    ("run-log-is-the-tools", "verify", "the live runner's run-directory `README.md` (`| Time (UTC) | Row | Record |`), "
     "a TAP log for test-id rows. Attempts, the contract commit and the rows run under each commit go in the run log."),
    ("sub-mode-c-step-4-run-log", "verify", "4. Record the attempts in the run log with commands, inputs and observed outputs."),
    ("deploy-jsonl-fields", "ship", "(`env`, `command`, `started`, `finished`, `rc`, `head`, `env_file_sha256`, "
     "`version_id`, `deploy_id`, `readiness`, `approval`)"),
    # Safety carries restored in review round 1 (README § 2).
    ("review-blocker-criteria", "verify", "BLOCKER: a defect reachable on a production path; any test gap above on "
     "changed production behaviour; moved code in a file whose name states no responsibility"),
    ("grade-never-replaces-blocker", "verify", "A grade never replaces BLOCKER for the cases above."),
    ("ship-blocker-whatever-grade", "ship", "A review blocker is a finding returned as BLOCKER or one that meets the "
     "review brief's BLOCKER criteria, whatever grade it carries; it stays open until fixed or waived, and another "
     "review round does not close it."),
    ("security-policy-missing-stop", "security-checklist", "`policies/approval-policy.yml` missing: stop"),
    ("security-never-org-only", "security-checklist", "Never treat the app as org-only: an inherited `visitor` "
     "principal changes the severity of every finding."),
    ("security-compliance-signoff", "security-checklist", "a blocker until the operator obtains the compliance "
     "reviewer's signoff"),
    ("security-vendor-advisory", "security-checklist", "file a new backlog item and name it as a known limitation"),
    ("approval-verdict-valid", "security-checklist", "| `VALID` | satisfied |"),
    ("approval-verdict-missing-expiry", "security-checklist", "| `MISSING_EXPIRY` | accepted until "
     "`strict_approvals` is on; flag it for reissue |"),
    ("approval-verdict-rejected", "security-checklist", "| `EXPIRED`, `MALFORMED`, `ACTION_MISMATCH`, "
     "`BINDING_MISMATCH` | not satisfied; treat it as missing |"),
    ("cleanup-exceptions", "verify", "delete the test data this item created and keep shared fixtures; redact or "
     "delete any capture that recorded operator-session content"),
    ("cleanup-retained-side-effects", "verify", "or record each one kept on purpose with its approval"),
    ("named-harness", "verify", "Run the named harness, or the script written for this live run; a weaker manual "
     "or static check never replaces it. If it cannot run, the row is `FAIL` and its `Note` says why "
     "(operator smoke pending), never PASS."),
    ("two-strike-exceptions", "writing-card", "Not strikes: a reproduction trial (verify), a rerun after a real "
     "change, a bounded retry of an external failure, a delegate re-dispatch inside the retry envelope"),
    ("slice-about-50-calls", "plan", "planned at about 50 tool calls or fewer"),
    ("slice-never-truncation", "plan", "never truncation: a builder past it finishes its slice"),
)

# Review round 1's undocumented substitution (README § 4).
NEGATIVE_PAIR = ("product timeouts and retries are never lengthened", "product timeouts and retries may be lengthened")

# Pending interface names (owning WP in the plan). A rename elsewhere must trip this case.
INTERFACE_TOKENS = (
    "slice.py", "--brief", "BLOCKED-AT-input", "gate.py", "state/gate/<slice>.txt",
    "state/returns/<slice>.json", "state/status.line", "checks.py --rule", "gate_rounds",
    "BLOCKED-AT-gate-budget", "evidence.md", "backlog.md", "phases.md", "state/pause",
    "state/runs/<phase>/", "policies/evidence-classes.yml", "policies/agent-tools.yml",
    "approve-local.sh --inventory", "`builder`", "`reader`", "`plan:`", "`ship:`",
    "state/flags/*.tsv", "state/audit/liveness/*.hb", "bounded_run", "state/deploys/<env>.jsonl",
)

BRIEF_DENY = (r"\bFR-\d", r"\bTE-\d", r"\bFlow\b", r"\bdefault\b", r"\bassum", r"\bpresum",
              r"\blikely\b", r"\bif (unsure|in doubt)\b", r"\bexpected verdict\b")
NAME_DENY = r"\b(Figma|Sketch|Jira|Linear|Asana|Trello|Opus|Sonnet|Haiku|Fable|GPT|Gemini)\b"
# Distinctive lines of the MIT-licensed karpathy-guidelines.md; none may be copied.
KARPATHY = ("Minimum code that solves the problem", "Touch only what you must",
            "Don't assume. Don't hide confusion", "Would a senior engineer say this is overcomplicated")
# test-approval-writer.sh:403 (AC19) checks this claim in deploy.md, which retires; ship carries it now.
AC19 = r"hooks? (check|enforce|verif)[a-z]* this against|against the self-attested role"

FAILS = 0


def report(case, good, detail=""):
    global FAILS
    if good:
        print(f"PASS: skill-carry {case}")
    else:
        FAILS += 1
        print(f"FAIL: skill-carry {case} ({detail})")


def squash(text):
    return re.sub(r"\s+", " ", text).strip()


def substitute(text):
    for old, new in SUBSTITUTIONS:
        text = text.replace(old, new)
    return text


def frontmatter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, flags=re.DOTALL)
    return m.group(1) if m else None


def code_span(cell):
    """One table cell: a code span (CommonMark: strip one space each side only when both exist) or `removed`."""
    if cell == "removed":
        return ""
    m = re.fullmatch(r"(`+)(.+?)\1", cell, flags=re.DOTALL)
    if not m:
        return None
    body = m.group(2)
    if len(body) > 1 and body[0] == " " and body[-1] == " " and body.strip():
        body = body[1:-1]
    return body


def readme_substitutions(text):
    """Pairs of the README § 4 table in row order, or (None, reason)."""
    sec = re.search(r"^## 4\. Substitution table.*?$(.*?)(?=^## )", text, flags=re.M | re.S)
    if not sec:
        return None, "no '## 4. Substitution table' section"
    pairs = []
    for line in sec.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
        if len(cells) != 4 or not cells[0].isdigit():
            continue
        old, new = code_span(cells[1]), code_span(cells[2])
        if old is None or new is None or int(cells[0]) != len(pairs) + 1:
            return None, f"row {cells[0]} unparseable or out of order"
        pairs.append((old, new))
    return (pairs, "") if pairs else (None, "no table rows")


def substitution_mismatches(table, subs):
    out = [f"count {len(subs)} vs README {len(table)}"] if len(subs) != len(table) else []
    out += [f"row {i + 1}" for i, (a, b) in enumerate(zip(subs, table)) if a != b]
    return out


def projected(path):
    """LF bytes of a projection file without its label line, or None."""
    if not path.is_file():
        return None
    text = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
    if text.startswith("<!-- projection"):
        text = text.split("\n", 1)[1]
    return len(text.encode("utf-8"))


def git_show(repo, ref, path):
    out = subprocess.run(["git", "-C", str(repo), "show", f"{ref}:{path}"],
                         capture_output=True, timeout=60)
    if out.returncode != 0:
        return None
    return out.stdout.decode("utf-8").replace("\r\n", "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--source-ref", default="v5.11")
    ap.add_argument("--readme", help="file holding the § 4 substitution table (default ROOT/README.md)")
    args = ap.parse_args()
    root = Path(args.root)
    readme = Path(args.readme) if args.readme else root / "README.md"

    bodies, total, desc_total = {}, 0, 0
    for s in SKILLS:
        p = root / s / "SKILL.md"
        if not p.is_file():
            report(f"present-{s}", False, f"missing {p}")
            continue
        # Measure and match the LF form: a CRLF checkout must neither inflate bytes nor hide text.
        text = p.read_bytes().decode("utf-8").replace("\r\n", "\n")
        raw = text.encode("utf-8")
        bodies[s] = text
        total += len(raw)
        fm = frontmatter(text)
        name_ok = fm is not None and re.search(rf"^name:\s*{re.escape(s)}\s*$", fm, re.M)
        dm = fm and re.search(r"^description:\s*(.+)$", fm, re.M)
        report(f"present-{s}", bool(name_ok and dm), "frontmatter name or description")
        if dm:
            dlen = len(dm.group(1).encode("utf-8"))
            desc_total += dlen
            report(f"description-bytes-{s}", dlen <= DESCRIPTION_CEILING, f"{dlen} > {DESCRIPTION_CEILING}")
        report(f"bytes-{s}", len(raw) <= CEILING[s], f"{len(raw)} > {CEILING[s]}")
    report("bytes-total", total <= TOTAL_CEILING, f"{total} > {TOTAL_CEILING}")
    print(f"[skill-carry] bytes total {total}; descriptions total {desc_total}")

    if "writing-card" in bodies:
        body = bodies["writing-card"].split("\n---\n", 1)[-1]
        lines = [ln for ln in body.splitlines() if ln.strip() and not ln.startswith("#")]
        report("writing-card-under-eight-lines", len(lines) < 8, f"{len(lines)} body lines")

    table, why = (None, f"missing {readme}") if not readme.is_file() else \
        readme_substitutions(readme.read_bytes().decode("utf-8").replace("\r\n", "\n"))
    if table is None:
        report("substitutions-match-readme", False, why)
        report("negative-undocumented-substitution-caught", False, why)
    else:
        bad = substitution_mismatches(table, SUBSTITUTIONS)
        report("substitutions-match-readme", not bad, "differ from README § 4: " + ", ".join(bad))
        added = substitution_mismatches(table, SUBSTITUTIONS + (NEGATIVE_PAIR,))
        swapped = substitution_mismatches(table, SUBSTITUTIONS[:-1] + (NEGATIVE_PAIR,))
        report("negative-undocumented-substitution-caught", bool(added and swapped),
               "an added or swapped pair would pass")

    for case, skill, path, a, b, cut in VERBATIM:
        src = git_show(args.repo, args.source_ref, path)
        if src is None:
            report(f"verbatim-{case}", False, f"cannot read {args.source_ref}:{path}")
            continue
        chunk = "\n".join(src.split("\n")[a - 1:b])
        if cut:
            m = re.search(cut, chunk, flags=re.DOTALL)
            chunk = m.group(0) if m else ""
        want = squash(substitute(chunk))
        have = squash(bodies.get(skill, ""))
        report(f"verbatim-{case}", bool(want) and want in have, f"{path}:{a}-{b} not carried in {skill}")

    for case, skill, phrase in ANCHORS:
        report(f"anchor-{case}", squash(phrase) in squash(bodies.get(skill, "")), f"missing in {skill}")

    everything = "\n".join(bodies.values())
    missing = [t for t in INTERFACE_TOKENS if t not in everything]
    report("interface-tokens", not missing, "missing: " + ", ".join(missing))

    briefs = re.findall(r"```text\n(.*?)```", bodies.get("verify", ""), flags=re.DOTALL)
    briefs = [b for b in briefs if b.startswith(("REVIEW BRIEF", "SKEPTIC BRIEF", "VERDICT BRIEF"))]
    report("briefs-present", len(briefs) == 3, f"{len(briefs)} of 3 briefs")
    hits = [f"{b.split(chr(10), 1)[0]}: {pat}" for b in briefs for pat in BRIEF_DENY if re.search(pat, b, re.I)]
    report("briefs-no-rule-text-no-default-verdict", not hits, "; ".join(hits))

    names = sorted(set(re.findall(NAME_DENY, everything)))
    report("no-model-design-tool-ticket-names", not names, ", ".join(names))
    copied = [k for k in KARPATHY if k in everything]
    report("no-karpathy-text", not copied, ", ".join(copied))
    report("ac19-no-authorship-claim-in-ship", not re.search(AC19, bodies.get("ship", ""), re.I), "AC19 claim")

    print_projected_boot(root / "projection", bodies)
    print(f"[skill-carry] {FAILS} FAIL")
    return FAILS


def print_projected_boot(pdir, bodies):
    """Informational (README § 3): WP 5 owns the boot lists and their size test."""
    kernel, bcard, pcard, state = (projected(pdir / f) for f in (
        "kernel-FLOW_RULES.md", "builder-AGENT.md", "planner-AGENT.md", "planner-state.md"))
    push = re.search(r"```text\n(FLOW BUILDER CONTRACT\n.*?)```", bodies.get("build", ""), flags=re.S)
    if None in (kernel, bcard, pcard, state) or not push or "writing-card" not in bodies:
        print(f"[skill-carry] projected boot: not measured (needs {pdir} and the build, writing-card drafts)")
        return
    size = lambda s: len(bodies[s].encode("utf-8"))
    push_b = len(push.group(1).encode("utf-8"))
    builder = kernel + bcard + push_b + size("writing-card")
    planner = kernel + pcard + state
    print(f"[skill-carry] projected builder boot {builder} B (kernel {kernel} + card {bcard} + push block "
          f"{push_b} + writing card {size('writing-card')}); risk-tagged slice "
          f"{builder + size('security-checklist')} B; target 6,144")
    print(f"[skill-carry] projected planner boot {planner} B (kernel {kernel} + card {pcard} + state lines {state}); "
          f"+ writing card {planner + size('writing-card')} B; target 8,192")


if __name__ == "__main__":
    sys.exit(main())
