"""Temporal-linkage fixtures for the ceremony evidence window."""

import importlib.util
import json
import shutil
import subprocess
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
               "# Gate report\n## Status\nGate blocked deploy.\n")
        _commit(root, "fixture: old evidence", "VERSION", "docs/specs/old/gate-report.md")

        _write(root, "docs/specs/direct/gate-report.md",
               "# Gate report\n## Status\nGate blocked deploy.\n")
        _write(root, "docs/specs/modified/gate-report.md",
               "# Gate report\n## Status\nNo deviation outcome.\n")
        current = _commit(root, "T9: current window change",
                          "docs/specs/direct/gate-report.md", "docs/specs/modified/gate-report.md")
        _write(root, "docs/specs/modified/gate-report.md",
               "# Gate report\n## Status\nGate blocked deploy.\n")

        _write(root, "docs/specs/explicit/gate-report.md",
               "# Gate report\n## Status\nGate blocked deploy.\nCommit linkage: `%s`.\n" % current)
        _write(root, "docs/specs/unlinked/gate-report.md",
               "# Gate report\n## Status\nGate blocked deploy.\n")
        _write(root, "docs/specs/instruction/verification-gate.md",
               "# Verification gate\nCommit linkage: `%s`.\nIf any probe fails, redirect AI Developer.\n" % current)
        _write(root, "state/approvals/protected_path_edit-old.json",
               json.dumps({"action": "protected_path_edit", "reason": "historical"}))
        _write(root, "state/approvals/protected_path_edit-linked.json",
               json.dumps({"action": "protected_path_edit", "commit_sha": current}))

        main = _load_main()
        evidence = main.assemble_evidence(root, 1)
        linked = {rel for rel, _ in evidence["window_artifacts"]}
        historical = {rel for rel, _ in evidence["historical_artifacts"]}
        check_bool("windowing: artifact committed in selected window is linked",
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
                   evidence["gate_blocks"], 2)
        check_bool("windowing: old, unlinked, and dirty gate outcomes remain historical",
                   evidence["historical_gate_blocks"], 3)
        check_bool("windowing: linked deviation approval affects window contrary evidence",
                   len(evidence["gating_approvals"]), 1)
        check_bool("windowing: approval history is retained outside window verdicts",
                   len(evidence["historical_gating_approvals"]), 1)
        check_bool("windowing: linked instructional fixture cannot fabricate a gate outcome",
                   evidence["gate_blocks"], 2)
        report, _, _, _ = main.build_report(evidence, root, "2026-09-05")
        check_bool("windowing: report labels window and historical evidence separately",
                   "## Temporal evidence split (A7)" in report
                   and "Historical / unlinked" in report, True)
    finally:
        shutil.rmtree(root, ignore_errors=True)
