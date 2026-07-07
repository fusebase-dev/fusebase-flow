"""Self-test Layer 2 — end-to-end fixture repos (real assemble_evidence on disk).

Extracted from selftest.py along the test-layer seam (FR-25): the synthetic /
evidence-sourcing / containment layers stay in selftest.py; this module owns the
end-to-end layer that builds a temp git repo on disk (git log + reports +
ratchet-governance.yml), runs the REAL assemble_evidence() + rule evaluators
against it, and asserts each rule's verdict — including NEGATIVE false-positive
fixtures (a clean / governed / catastrophic-idle repo must NOT be flagged) and the
MED-fix scoping fixtures (a genuine recorded outcome at a dated/handoff-style path
IS counted).

Non-writing: e2e fixtures build their report IN MEMORY (build_report) and never
call write_report against the real repo. Temp dirs are cleaned up.
"""

import datetime
import importlib.util
import shutil
import subprocess
import tempfile
from pathlib import Path

from .constants import CONFIRMED, DISMISSED, INCONCLUSIVE, DEFAULT_WINDOW


def _git(root, *args):
    subprocess.run(["git", *args], cwd=str(root), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)


def _init_fixture_repo(root, files, commits):
    """Build a temp git repo: write `files` ({relpath: text}), then make `commits`
    (each a list of (relpath, text)) so git log + numstat are real."""
    (root / "VERSION").write_text("0.0.0-fixture\n", encoding="utf-8")
    _git(root, "init", "-q")
    _git(root, "config", "user.email", "fixture@example.com")
    _git(root, "config", "user.name", "Fixture")
    for rel, text in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    if files:
        _git(root, "add", "-A")
        _git(root, "commit", "-q", "-m", "fixture: base")
    for subject, changes in commits:
        for rel, text in changes:
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        _git(root, "add", "-A")
        _git(root, "commit", "-q", "-m", subject)


def _load_main():
    """Load the thin CLI orchestrator (find-wasted-effort.py) as a module."""
    spec = importlib.util.spec_from_file_location(
        "fwe_main", str(Path(__file__).resolve().parent.parent / "find-wasted-effort.py"))
    main_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(main_mod)
    return main_mod


def _verdict_for(rule_no, root):
    """Run the REAL pipeline against a fixture repo and return one rule's verdict."""
    main_mod = _load_main()
    ev = main_mod.assemble_evidence(root, DEFAULT_WINDOW)
    # build_report must succeed (renders rule 6 per-element table etc.) and never write.
    today = datetime.date.today().isoformat()
    _report, _counts, findings, _proposals = main_mod.build_report(ev, root, today)
    by_rule = {f["rule"]: f for f in findings}
    return by_rule[rule_no]["verdict"], ev, _report


GOV_FIXTURE = """schema_version: 1
annotation_marker:
  severity_tag: "catastrophic-low-frequency"
incident_classes:
  false-green-deploy:
    description: "x"
coverage:
  annotated_elements:
    - file: templates/handoff-deploy.md
      element: "DP.6 confirm"
      prevents: [unattended-prod-cutover]
      severity: catastrophic-low-frequency
    - file: templates/handoff-deploy.md
      element: "DP.10 smoke integrity"
      prevents: [false-green-deploy]
  not_in_scope_phase1:
    - "x"
"""


def e2e_cases(check_e2e):
    # --- POSITIVE end-to-end: a real "wasteful" round ---
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-pos-"))
    try:
        gate = (
            "# Gate report\n\nRound for waste-fixture-round-one.\n\n"
            "Ran the full suite (run-tests): all PASS.\n"
            "Ran the full suite (run-tests) again: all PASS.\n"
            "Ran the full suite (run-tests) a third time: all PASS.\n"
        )
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            "templates/handoff-deploy.md":
                "DP.6 confirm <!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->\n"
                "DP.10 smoke <!-- prevents: false-green-deploy -->\n",
            "docs/specs/waste-fixture-round-one/gate-report.md": gate,
        }
        commits = [
            ("T1: waste-fixture-round-one small tweak (D1)",
             [("docs/specs/waste-fixture-round-one/x.txt", "a\n")]),
        ]
        _init_fixture_repo(tmp, files, commits)
        v2, ev, report = _verdict_for(2, tmp)
        check_e2e("e2e r2 confirmed (3 full-suite runs + identical recorded fail-sets)", v2, CONFIRMED)
        v6, _, _ = _verdict_for(6, tmp)
        # both governed elements are catastrophic-idle or governed -> not confirmed waste
        check_e2e("e2e r6 not-confirmed (governed/catastrophic elements)",
                  v6 in (DISMISSED, INCONCLUSIVE), True)
        check_e2e("e2e report has rule-6 per-element table",
                  "per-element ratchet inventory" in report, True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- NEGATIVE / false-positive (HIGH finding): suite-RUN counts recorded but
    #     fail-SETS NOT recorded. >baseline+end runs but no recorded fail-set per
    #     run -> rule 2 MUST be inconclusive, never confirmed (rule-signatures.md:20-25).
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-r2-nofs-"))
    try:
        gate = (
            "# Gate report\n\nRound for nofs-fixture-round-one.\n\n"
            "Ran the full suite (run-tests) at the first checkpoint.\n"
            "Ran the full suite (run-tests) at the second checkpoint.\n"
            "Ran the full suite (run-tests) at the third checkpoint.\n"
        )
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            "docs/specs/nofs-fixture-round-one/gate-report.md": gate,
        }
        commits = [
            ("T1: nofs-fixture-round-one small tweak (D1)",
             [("docs/specs/nofs-fixture-round-one/x.txt", "a\n")]),
        ]
        _init_fixture_repo(tmp, files, commits)
        v2, _, _ = _verdict_for(2, tmp)
        check_e2e("e2e r2 inconclusive (runs recorded, fail-sets ABSENT -> NOT confirmed)",
                  v2, INCONCLUSIVE)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- NEGATIVE / false-positive: a clean, non-duplicated round ---
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-neg-"))
    try:
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            "templates/handoff-deploy.md":
                "DP.6 confirm <!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->\n"
                "DP.10 smoke <!-- prevents: false-green-deploy -->\n",
            "docs/specs/clean-fixture-round/gate-report.md":
                "# Gate report\n\nRan the full suite (run-tests): all PASS.\n",
        }
        commits = [
            ("T1: clean-fixture-round substantial subsystem work (D1)",
             [("src/big.txt", "\n".join("line%d" % i for i in range(200)))]),
        ]
        _init_fixture_repo(tmp, files, commits)
        v2, _, _ = _verdict_for(2, tmp)
        check_e2e("e2e r2 NOT confirmed on a single baseline run (no false positive)",
                  v2 != CONFIRMED, True)
        v5, _, _ = _verdict_for(5, tmp)
        check_e2e("e2e r5 NOT confirmed on a large diff (no false positive)",
                  v5 != CONFIRMED, True)
        v1, _, _ = _verdict_for(1, tmp)
        check_e2e("e2e r1 inconclusive on no recorded gate outcomes (honest)",
                  v1, INCONCLUSIVE)
        v7, _, _ = _verdict_for(7, tmp)
        check_e2e("e2e r7 inconclusive on no cross-session re-derivation (honest)",
                  v7, INCONCLUSIVE)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- end-to-end rule 5 POSITIVE: tiny diff, zero decisions, Full ceremony ---
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-r5-"))
    try:
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            "docs/handoff/2026-01-01-tiny-typo-round-fix-deploy.md":
                "# Deploy handoff\n\nFull lane. Verification gate. production_deploy.\n"
                "No design decisions; trivial typo.\n",
        }
        commits = [
            ("T1: tiny-typo-round-fix one-char fix",
             [("README.md", "typo fixed\n")]),
        ]
        _init_fixture_repo(tmp, files, commits)
        v5, ev, _ = _verdict_for(5, tmp)
        check_e2e("e2e r5 confirmed (small diff + 0 decisions + Full ceremony)", v5, CONFIRMED)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- end-to-end rule 7 POSITIVE: same deploy-hash recorded across 2 artifacts ---
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-r7-"))
    try:
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            "docs/handoff/2026-01-01-hash-round-one-deploy.md":
                "# Deploy handoff\n\nDeploy hash: `abc1234def`\n",
            "docs/handoff/2026-01-02-hash-round-one-implement.md":
                "# Implement handoff\n\nPredecessor deployed hash `abc1234def` (re-stated here).\n",
        }
        _init_fixture_repo(tmp, files, [])
        v7, _, _ = _verdict_for(7, tmp)
        check_e2e("e2e r7 confirmed (deploy-hash re-derived across 2 dated artifacts)", v7, CONFIRMED)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- end-to-end (HIGH finding): INSTRUCTIONAL text must NOT fabricate a gate
    #     BLOCK (rule 1) or a control FIRING (rule 6). A verification-gate TEMPLATE
    #     instance carries "redirect AI Developer. Do NOT bypass."; a spec carries a
    #     `git revert <hash>` rollback EXAMPLE; a handoff carries `abort` and the
    #     APPROVE-DEPLOY-NOW phrase in INSTRUCTION grammar. None may be read as a
    #     recorded outcome. Pre-fix: rule 1 dismissed on fake "6 block(s)" and rule 6
    #     dismissed on fabricated firings. Post-fix: rule 1 honest (no recorded
    #     outcomes -> inconclusive) and rule 6 sees NO firing from instructional text.
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-instr-"))
    try:
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            # verification-gate instance — pure INSTRUCTION/template text
            "docs/specs/instr-fixture-round/verification-gate.md":
                "# Verification gate\n## Cross-artifact consistency check\n"
                "If ANY item fails, redirect AI Developer. Do NOT bypass.\n"
                "## Rollback procedure\n1. git revert <deploy hash>\n2. Redeploy\n",
            # spec — rollback EXAMPLE + abort/APPROVE-DEPLOY-NOW in instruction grammar
            "docs/specs/instr-fixture-round/spec.md":
                "# Spec\nExample: deploy with no documented `git revert <hash>` rollback.\n"
                "On failure the operator may abort; the phrase is APPROVE-DEPLOY-NOW.\n",
            "templates/handoff-deploy.md":
                "DP.6 confirm <!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->\n"
                "DP.10 smoke <!-- prevents: false-green-deploy -->\n"
                "Rollback <!-- prevents: irreversible-loss (catastrophic-low-frequency) -->\n",
        }
        commits = [
            ("T1: instr-fixture-round work (D1)",
             [("docs/specs/instr-fixture-round/x.txt", "a\n")]),
        ]
        _init_fixture_repo(tmp, files, commits)
        v1, ev1, _ = _verdict_for(1, tmp)
        check_e2e("e2e r1 NOT dismissed on instructional 'Do NOT bypass' (no fake block)",
                  v1 != DISMISSED, True)
        check_e2e("e2e instructional text sources ZERO gate-blocks", ev1["gate_blocks"], 0)
        check_e2e("e2e instructional text sources ZERO firing classes",
                  ev1["fired_classes"], set())
        # rule 6: the catastrophic elements (unattended-prod-cutover / irreversible-loss)
        # must NOT be dismissed-via-firing — with no firing they are catastrophic-idle
        # (inconclusive) or governed (dismissed by marker), never dismissed by a FAKE firing.
        v6, ev6, _ = _verdict_for(6, tmp)
        check_e2e("e2e r6 sees no fabricated firing from instructional text",
                  ev6["fired_classes"], set())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- end-to-end (MED fix): a GENUINE recorded rollback/probe outcome saved at
    #     a DATED report filename AND at a handoff-style path (header-classified) is
    #     COLLECTED by the real pipeline (collect_artifacts globs + artifact_kind),
    #     so rule 6 sees the firing and dismisses the matching class via a REAL
    #     outcome — while the instructional template text above still fires nothing.
    tmp = Path(tempfile.mkdtemp(prefix="fwe-e2e-scoping-"))
    try:
        files = {
            "policies/ratchet-governance.yml": GOV_FIXTURE,
            "templates/handoff-deploy.md":
                "DP.6 confirm <!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->\n"
                "DP.10 smoke <!-- prevents: false-green-deploy -->\n",
            # a DATED deploy-report with a genuine recorded probe failure + rollback
            "docs/specs/scoping-fixture-round/deploy-report-2026-06-13.md":
                "# Deploy report — scoping-fixture-round\n## Rollback procedure\n"
                "1. git revert <deploy hash>\n2. Redeploy\n"
                "## 3. Probe results\nG-N health probe: probe failed (observed 500).\n"
                "## Rollback result\nOperator decided rollback; rolled back the deploy.\n",
            # a recorded report saved at a HANDOFF-style path, classified by HEADER
            "docs/tmp/handoff/2026-06-13-scoping-fixture-round-deploy.md":
                "# Deploy report — scoping-fixture-round (handoff-saved)\n## Status\n"
                "G-O probe failed (observed 503); the deploy was rolled back.\n",
        }
        commits = [
            ("T1: scoping-fixture-round work (D1)",
             [("docs/specs/scoping-fixture-round/x.txt", "a\n")]),
        ]
        _init_fixture_repo(tmp, files, commits)
        # the real pipeline collects the genuine recorded outcomes as firings
        main2 = _load_main()
        ev = main2.assemble_evidence(tmp, DEFAULT_WINDOW)
        check_e2e("e2e scoping: genuine recorded probe-fail collected as firing",
                  {"false-green-deploy", "unauthorized-deploy"} <= ev["fired_classes"], True)
        check_e2e("e2e scoping: genuine recorded rollback collected as firing",
                  "irreversible-loss" in ev["fired_classes"], True)
        check_e2e("e2e scoping: genuine recorded gate-block counted (blocks >= 1)",
                  ev["gate_blocks"] >= 1, True)
        # rule 6: the false-green-deploy element is now dismissed by a REAL firing.
        v6, ev6, _ = _verdict_for(6, tmp)
        check_e2e("e2e scoping: rule 6 sees genuine firing (false-green-deploy fired)",
                  "false-green-deploy" in ev6["fired_classes"], True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
