"""Temporal-linkage fixtures for the ceremony evidence window."""

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def _git(root, *args):
    return subprocess.run(
        ["git", *args], cwd=str(root), capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=30,
    )


def _write(root, rel, body):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    return path


def _commit(root, subject, *paths):
    _git(root, "add", "--", *paths)
    result = _git(root, "commit", "-q", "-m", subject)
    if result.returncode != 0:
        raise RuntimeError(result.stderr)
    return _git(root, "rev-parse", "HEAD").stdout.strip()


def _load_main():
    spec = importlib.util.spec_from_file_location(
        "fwe_window_main", str(Path(__file__).resolve().parent.parent / "find-wasted-effort.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def windowing_cases(check_bool):
    root = Path(tempfile.mkdtemp(prefix="fwe-windowing-"))
    try:
        _git(root, "init", "-q")
        _git(root, "config", "user.email", "fixture@example.test")
        _git(root, "config", "user.name", "Fixture")
        _write(root, "VERSION", "fixture\n")
        _write(root, "docs/specs/old/gate-report.md",
               "# Gate report\n## Conclusion: old\n## Status\nOutcome: Gate blocked deploy.\nTask: T1\nCommit: pending\n")
        unstructured = "# Gate report\n## Status\nOutcome: Gate blocked deploy.\n"
        _write(root, "docs/specs/unstructured/gate-report.md", unstructured)
        old = _commit(root, "T1: old evidence", "VERSION", "docs/specs/old/gate-report.md",
                      "docs/specs/unstructured/gate-report.md")

        _write(root, "docs/specs/direct/gate-report.md", "# Gate report\n")
        _write(root, "docs/specs/modified/gate-report.md",
               "# Gate report\n## Status\nNo deviation outcome.\n")
        _write(root, "docs/specs/unstructured/gate-report.md", unstructured + "Cosmetic footer.\n")
        current = _commit(root, "T9 protected_path_edit: current window change",
                          "docs/specs/direct/gate-report.md", "docs/specs/modified/gate-report.md",
                          "docs/specs/unstructured/gate-report.md")
        _write(root, "docs/specs/modified/gate-report.md",
               "# Gate report\n## Status\nGate blocked deploy.\n")

        linked_record = ("## Conclusion: current\n## Status\nOutcome: Gate blocked deploy.\n"
                         "Task: T9\nCommit: %s\n" % current)
        _write(root, "docs/specs/direct/gate-report.md", "# cosmetic footer\n" + linked_record)
        _write(root, "docs/specs/explicit/gate-report.md", "# Gate report\n" + linked_record)
        _write(root, "docs/specs/unlinked/gate-report.md",
               "# Gate report\n## Conclusion: mismatch\n## Status\nOutcome: Gate blocked deploy.\nTask: T8\nCommit: %s\n" % current)
        _write(root, "docs/specs/mixed/gate-report.md",
               "# Gate report\n" + linked_record +
               "## Conclusion: historical\n## Status\nOutcome: Gate blocked deploy.\nTask: T8\nCommit: %s\n" % current)
        _write(root, "docs/specs/cosmetic/gate-report.md",
               "# Gate report\n## Conclusion: old outcome\n## Status\nOutcome: Gate blocked deploy.\n"
               "Task: T1\nCommit: %s\n\nFooter updated for %s\n" % (old, current))
        base_unproven = "# Gate report\n## Conclusion: unproven\n## Status\nOutcome: Gate blocked deploy.\nTask: T9\n"
        _write(root, "docs/specs/missing/gate-report.md", base_unproven)
        _write(root, "docs/specs/empty/gate-report.md", base_unproven + "Commit:    \n")
        _write(root, "docs/specs/invalid/gate-report.md", base_unproven + "Commit: pending\n")
        _write(root, "docs/specs/generic/gate-report.md",
               base_unproven + "Reference only: %s\n" % current)
        _write(root, "docs/specs/instruction/verification-gate.md",
               "# Verification gate\nCommit linkage: `%s`.\nIf any probe fails, redirect AI Developer.\n" % current)
        _write(root, "state/approvals/protected_path_edit-old.json",
               json.dumps({"action": "protected_path_edit", "reason": "historical"}))
        _write(root, "state/approvals/protected_path_edit-linked.json",
               json.dumps({"action": "protected_path_edit", "task": "T9",
                           "commit_sha": current}))
        _write(root, "state/approvals/protected_path_edit-generic.json",
               json.dumps({"action": "protected_path_edit",
                           "reason": "generic reference %s" % current}))

        main = _load_main()
        evidence = main.assemble_evidence(root, 1)
        linked = {rel for rel, _ in evidence["window_artifacts"]}
        historical = {rel for rel, _ in evidence["historical_artifacts"]}
        check_bool("windowing: exact outcome/task/commit match is linked",
                   "docs/specs/direct/gate-report.md" in linked, True)
        check_bool("windowing: explicit selected-commit SHA links an uncommitted artifact",
                   "docs/specs/explicit/gate-report.md" in linked, True)
        check_bool("windowing: old committed artifact is historical outside selected window",
                   "docs/specs/old/gate-report.md" in historical, True)
        check_bool("windowing: unlinked artifact remains historical",
                   "docs/specs/unlinked/gate-report.md" in historical, True)
        check_bool("windowing: dirty content is not linked by an older clean commit",
                   "docs/specs/modified/gate-report.md" in historical, True)
        check_bool("windowing: only linked recorded reports affect window gate outcomes",
                   evidence["gate_blocks"], 3)
        check_bool("windowing: mixed report partitions conclusions",
                   sum(rel == "docs/specs/mixed/gate-report.md" for rel in linked) == 1
                   and sum(rel == "docs/specs/mixed/gate-report.md" for rel in historical) == 1, True)
        check_bool("windowing: task mismatch and unstructured dirty outcomes remain historical",
                   evidence["historical_gate_blocks"], 10)
        check_bool("windowing: cosmetic footer cannot promote old structured outcome",
                   "docs/specs/cosmetic/gate-report.md" in historical, True)
        check_bool("windowing: cosmetic current commit cannot promote unstructured outcome",
                   "docs/specs/unstructured/gate-report.md" in historical, True)
        check_bool("windowing: missing empty invalid and generic Commit evidence is historical",
                   all("docs/specs/%s/gate-report.md" % name in historical
                       for name in ("missing", "empty", "invalid", "generic")), True)
        check_bool("windowing: linked deviation approval affects window contrary evidence",
                   len(evidence["gating_approvals"]), 1)
        check_bool("windowing: approval history is retained outside window verdicts",
                   len(evidence["historical_gating_approvals"]), 2)
        check_bool("windowing: generic approval SHA mention cannot link",
                   any(item["file"].endswith("-generic.json")
                       for item in evidence["historical_gating_approvals"]), True)
        check_bool("windowing: linked instructional fixture cannot fabricate a gate outcome",
                   evidence["gate_blocks"], 3)
        report, _, _, _ = main.build_report(evidence, root, "2026-09-05")
        check_bool("windowing: report labels window and historical evidence separately",
                   "## Temporal evidence split (A7)" in report
                   and "Historical / unlinked" in report, True)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    template_cases(check_bool)
    real_template_cases(check_bool)


def _template_report(slug, rows, status=True, task_range=None):
    head = ["# Gate report — %s (T7)" % slug, ""]
    if status:
        head.append("**Status:** Gate reached; awaiting PO review and deploy handoff")
    if task_range:
        head.append("**Task range:** %s" % task_range)
    table = ["", "## 1. Per-task commit table", "",
             "| Task | Title | Commit SHA | Lint |", "|---|---|---|---|"]
    table += ["| %s | work | %s | ✓ |" % row for row in rows]
    gate = ["", "## 7. Gate satisfaction", "",
            "| Gate item | Required | Actual | Evidence | Status |", "|---|---|---|---|---|",
            "| lint | 0 errors | 0 errors | lint.log | PASS |",
            "| smoke | green | 2 checks red | smoke.log | FAIL |", ""]
    return "\n".join(head + table + gate)


def template_cases(check_bool):
    root = Path(tempfile.mkdtemp(prefix="fwe-template-"))
    try:
        _git(root, "init", "-q")
        _git(root, "config", "user.email", "fixture@example.test")
        _git(root, "config", "user.name", "Fixture")
        _write(root, "VERSION", "fixture\n")
        _commit(root, "chore: fixture base", "VERSION")
        shas = {}
        for task, name in (("T5", "alpha"), ("T6", "beta"), ("T9", "gamma")):
            _write(root, "src/%s.txt" % name, name + "\n")
            shas[task] = _commit(root, "%s: add %s" % (task, name), "src/%s.txt" % name)
        _write(root, "docs/specs/b5/gate-report.md",
               "# Gate report — b5 (T9)\n\n**Status:** Gate reached\nOutcome: Gate blocked deploy.\n")
        _commit(root, "docs(gate): T9 gate report", "docs/specs/b5/gate-report.md")
        short = {task: "`%s`" % sha[:7] for task, sha in shas.items()}
        _write(root, "docs/specs/ranged/gate-report.md", _template_report(
            "ranged", [("T5", short["T5"]), ("T6", short["T6"]),
                       ("T7", "(no commit — this file)")], task_range="T5..T7"))
        _write(root, "docs/specs/prose/gate-report.md",
               "# Gate report — prose (T9)\n\n**Status:** Gate reached\n"
               "T9 shipped in %s.\nOutcome: Gate blocked deploy.\n" % short["T9"])
        _write(root, "docs/specs/mismatch/gate-report.md",
               _template_report("mismatch", [("T7", short["T9"])]))
        _write(root, "docs/specs/nostatus/gate-report.md",
               _template_report("nostatus", [("T9", short["T9"])], status=False))

        main = _load_main()
        from find_wasted_effort.evidence import build_rounds
        from find_wasted_effort.rounds import round_claims
        evidence = main.assemble_evidence(root, 4)
        window = [rel for rel, _ in evidence["window_artifacts"]]
        historical = {rel for rel, _ in evidence["historical_artifacts"]}
        ranged = "docs/specs/ranged/gate-report.md"
        table_rows = [row for row in evidence["artifact_linkage"]
                      if row["file"].startswith(ranged + "#table-")]
        check_bool("windowing: template report with a resolving commit-table row is linked",
                   ranged in window, True)
        check_bool("windowing: two resolving commit-table rows add the report once",
                   window.count(ranged) == 1
                   and sorted(row["task"] for row in table_rows) == ["T5", "T6"], True)
        check_bool("windowing: two-row linked report counts its gate outcome once",
                   evidence["gate_blocks"], 1)
        check_bool("windowing: linked template FAIL row without a block phrase counts a gate block",
                   evidence["gate_blocks"] >= 1, True)
        check_bool("windowing: linked template report carries its gate-satisfaction row outcomes",
                   {row["outcome"] for row in table_rows}, {"1 PASS / 1 FAIL"})
        check_bool("windowing: commit SHA only in report prose stays historical",
                   "docs/specs/prose/gate-report.md" in historical, True)
        check_bool("windowing: commit-table row whose commit subject lacks the task stays historical",
                   "docs/specs/mismatch/gate-report.md" in historical, True)
        check_bool("windowing: template report without a Status line stays historical",
                   "docs/specs/nostatus/gate-report.md" in historical, True)
        check_bool("windowing: docs(gate) commit cannot link an unstructured report (B5)",
                   "docs/specs/b5/gate-report.md" in historical, True)
        check_bool("rounds: Task range groups T5 and T6 commits into one round keyed by the spec dir",
                   set(evidence["rounds"].get("ranged", {}).get("commits", [])),
                   {shas["T5"], shas["T6"]})
        a_sha, b_sha, c_sha = "a" * 40, "b" * 40, "c" * 40
        later = [(c_sha, "T3: tidy"), (b_sha, "T2: feat(c-new-ticket) add delta"),
                 (a_sha, "T1: add older")]
        older = _template_report("older", [("T1", "`%s`" % a_sha[:7])], task_range="T1..T3")
        later_rounds = build_rounds(
            later, {}, round_claims([("docs/specs/older/gate-report.md", older)], later))
        check_bool("rounds: an older Task range cannot claim another ticket's commit absent from its table",
                   {rid: r["commits"] for rid, r in later_rounds.items()},
                   {"older": [a_sha], "c-new-ticket": [b_sha], "ccccccc": [c_sha]})
        shared = [(c_sha, "T25: outside range"), (b_sha, "T21: fix(shared-work-item) x"),
                  (a_sha, "T20: amb-a only")]
        amb = [("docs/specs/amb-a/gate-report.md", _template_report(
                    "amb-a", [("T20", "`aaaaaaa`"), ("T21", "`bbbbbbb`")], task_range="T20..T21")),
               ("docs/specs/amb-b/gate-report.md", _template_report(
                    "amb-b", [("T21", "`bbbbbbb`"), ("T25", "`ccccccc`")], task_range="T21–T22"))]
        amb_claims = round_claims(amb, shared)
        check_bool("rounds: a commit two reports' tables both resolve falls back to the subject",
                   build_rounds(shared, {}, amb_claims).get("shared-work-item", {}).get("commits"),
                   [b_sha])
        check_bool("rounds: a resolving row outside the report's Task range stays unclaimed",
                   amb_claims, {a_sha: "amb-a"})
        report, _, _, _ = main.build_report(evidence, root, "2026-10-15")
        check_bool("windowing: report names commit-table linkage",
                   "gate report whose per-task commit table row" in report, True)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def _real_template_report(task, sha, approval, all_pass):
    text = (Path(__file__).resolve().parents[3] / "templates" / "gate-report.md").read_text(encoding="utf-8")
    body = text[text.index("```markdown\n") + len("```markdown\n"):text.index("\n## Fill-in checklist")]
    body = body[:body.rindex("\n```")]
    for marker in ("T<first>", "T<first+1>", "T<gate-1>", "T<gate>"):
        body = body.replace(marker, task)
    body = body.replace("<sha>", sha).replace(
        "<self-approved per FR-03 / yes per operator chat>", approval)
    if all_pass:
        body = body.replace("| FAIL |", "| PASS |")
    # Every placeholder filled: an unfilled line is stripped before matching, hiding the relay text.
    return re.sub(r"<[^<>!\n]+>", "1", body)


def real_template_cases(check_bool):
    root = Path(tempfile.mkdtemp(prefix="fwe-real-template-"))
    try:
        _git(root, "init", "-q")
        _git(root, "config", "user.email", "fixture@example.test")
        _git(root, "config", "user.name", "Fixture")
        _write(root, "VERSION", "fixture\n")
        _commit(root, "chore: fixture base", "VERSION")
        _write(root, "src/alpha.txt", "alpha\n")
        sha = _commit(root, "T5: add alpha", "src/alpha.txt")[:7]
        rel = "docs/specs/real/gate-report.md"
        main = _load_main()
        from find_wasted_effort.constants import CONFIRMED
        from find_wasted_effort.rules import rule1_unused_gate_stops
        _write(root, rel, _real_template_report("T5", sha, "self-approved per FR-03", True))
        evidence = main.assemble_evidence(root, 2)
        check_bool("windowing: real gate-report template with all-PASS gate rows is linked",
                   rel in [path for path, _ in evidence["window_artifacts"]], True)
        check_bool("windowing: real template relay block adds no gate block",
                   evidence["gate_blocks"], 0)
        check_bool("windowing: real template all-PASS report fires no control class",
                   evidence["fired_classes"], set())
        check_bool("windowing: real template deviations section still counts its approval",
                   evidence["gate_approvals"], 1)
        _write(root, rel, _real_template_report(
            "T5", sha, ", ".join(["self-approved per FR-03"] * 3), False))
        evidence = main.assemble_evidence(root, 2)
        check_bool("windowing: real template FAIL row counts one gate block",
                   evidence["gate_blocks"], 1)
        check_bool("windowing: rule 1 cannot confirm over a linked template FAIL row",
                   rule1_unused_gate_stops(evidence)["verdict"] != CONFIRMED, True)
        from find_wasted_effort.evidence import collect_gate_outcomes
        deploy = _template_report("d", [("T5", sha)]).replace("| FAIL |", "| PASS |").replace(
            "# Gate report", "# Deploy report") + "\n## 3. Probe results\n\nProbe failed on /health.\n"
        check_bool("windowing: a deploy report with a commit table keeps its recorded block phrase",
                   collect_gate_outcomes([("docs/specs/d/deploy-report.md", deploy)]), (0, 1))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=("temporal",), required=True)
    parser.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    cases = []

    def check_bool(name, got, want):
        cases.append((name, got, want))

    windowing_cases(check_bool)
    for name, got, want in cases:
        print(("PASS" if got == want else "FAIL") + " " + name)
    passed = sum(got == want for _, got, want in cases)
    print("[selftest-windowing --only temporal] %d/%d PASS" % (passed, len(cases)))
    return 1 if passed != len(cases) else 0


if __name__ == "__main__":
    raise SystemExit(main())
