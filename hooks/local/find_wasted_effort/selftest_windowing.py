"""Temporal-linkage fixtures for the ceremony evidence window."""

import argparse
import importlib.util
import json
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
