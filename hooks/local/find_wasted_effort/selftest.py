"""Self-test for find-wasted-effort.

Three layers, so the suite is NOT tautological (MED finding):
  1. SYNTHETIC per-rule unit fixtures — a hand-built evidence dict per verdict.
  2. END-TO-END fixtures — build a temp fixture repo on disk (git log + reports +
     ratchet-governance.yml), run the REAL assemble_evidence() + rule evaluators
     against it, and assert each rule's verdict. Includes NEGATIVE false-positive
     fixtures (a clean / governed / catastrophic-idle repo must NOT be flagged).
  3. PATH-CONTAINMENT fixtures — the --root / symlink-escape guard (HIGH finding):
     a traversal root, a non-Flow root, and a symlinked state/audit must all be
     rejected by resolve_root() / contained_report_path().

Non-writing: end-to-end fixtures build their report IN MEMORY (build_report) and
never call write_report against the real repo. Temp dirs are cleaned up.
"""

import datetime
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .constants import CONFIRMED, DISMISSED, INCONCLUSIVE, DEFAULT_WINDOW
from . import rules as R


# --------------------------------------------------------------------------
# Layer 1 — synthetic per-rule unit fixtures
# --------------------------------------------------------------------------

def _base_ev():
    return {
        "gate_blocks": 0, "gate_approvals": 0, "gating_approvals": [],
        "full_suite_runs_per_round": {}, "full_suite_reason": "no traces",
        "duplicate_blocks": [],
        "lane_candidates": None, "lane_reason": "no candidate",
        "annotated_files": {}, "annotated_lines": {},
        "governance_ok": True, "governance_elements": [],
        "fired_classes": set(), "severity_tag": "catastrophic-low-frequency",
        "cross_session_rederivation": None, "cross_session_reason": "no signal",
        "approvals": [], "rounds": {}, "commits": [],
        "artifacts": [], "window": DEFAULT_WINDOW,
    }


def _synthetic_cases(check):
    # Rule 1
    ev = _base_ev(); ev["gate_approvals"] = 4
    check("r1 confirmed (4 approvals, 0 blocks)", R.rule1_unused_gate_stops, ev, CONFIRMED)
    ev = _base_ev(); ev["gate_approvals"] = 4; ev["gate_blocks"] = 1
    check("r1 dismissed (a block present)", R.rule1_unused_gate_stops, ev, DISMISSED)
    # MED: a deviation-gating approval artifact is contrary evidence -> dismissed,
    # even with many rubber-stamped approvals and zero recorded blocks.
    ev = _base_ev(); ev["gate_approvals"] = 4
    ev["gating_approvals"] = [{"file": "state/approvals/protected_path_edit-x-20260613.json",
                               "kind": "protected_path_edit"}]
    check("r1 dismissed (deviation-gating approval consumed as contrary evidence)",
          R.rule1_unused_gate_stops, ev, DISMISSED)
    ev = _base_ev(); ev["gating_approvals"] = [{"file": "f", "kind": "database_migration"}]
    check("r1 dismissed (gating approval alone, no recorded gate-outcome text)",
          R.rule1_unused_gate_stops, ev, DISMISSED)
    ev = _base_ev(); ev["gate_approvals"] = 1
    check("r1 inconclusive (window < min)", R.rule1_unused_gate_stops, ev, INCONCLUSIVE)

    # Rule 2 — tuple is (run_count, identical_failsets, failset_complete).
    # POSITIVE: runs > norm, fail-sets recorded for every run AND identical -> confirmed.
    ev = _base_ev(); ev["full_suite_runs_per_round"] = {"R1": (5, True, True)}
    check("r2 confirmed (5 identical runs, fail-sets complete)", R.rule2_per_commit_full_suite, ev, CONFIRMED)
    ev = _base_ev(); ev["full_suite_runs_per_round"] = {"R1": (5, False, True)}
    check("r2 dismissed (fail-set differed, complete)", R.rule2_per_commit_full_suite, ev, DISMISSED)
    # NEGATIVE / FALSE-POSITIVE GUARD (HIGH finding): run counts present but fail-sets
    # NOT recorded (failset_complete False) MUST be inconclusive, never confirmed.
    ev = _base_ev(); ev["full_suite_runs_per_round"] = {"R1": (5, False, False)}
    check("r2 inconclusive (runs present, fail-sets ABSENT -> not confirmed)",
          R.rule2_per_commit_full_suite, ev, INCONCLUSIVE)
    ev = _base_ev(); ev["full_suite_runs_per_round"] = {"R1": (5, True, False)}
    check("r2 inconclusive (runs present, fail-sets PARTIAL -> not confirmed)",
          R.rule2_per_commit_full_suite, ev, INCONCLUSIVE)
    ev = _base_ev()
    check("r2 inconclusive (no counts -> honest reason)", R.rule2_per_commit_full_suite, ev, INCONCLUSIVE)

    # Rule 3
    ev = _base_ev(); ev["duplicate_blocks"] = [{"count": 4, "files": ["a", "b", "c", "d"], "bootstrapping": False}]
    check("r3 confirmed (substantive dup)", R.rule3_artifact_duplication, ev, CONFIRMED)
    ev = _base_ev(); ev["duplicate_blocks"] = [{"count": 4, "files": ["a", "b", "c", "d"], "bootstrapping": True}]
    check("r3 dismissed (self-bootstrapping)", R.rule3_artifact_duplication, ev, DISMISSED)
    ev = _base_ev()
    check("r3 inconclusive (no dup)", R.rule3_artifact_duplication, ev, INCONCLUSIVE)

    # Rule 5
    ev = _base_ev(); ev["lane_candidates"] = {"round": "R7", "clear": True, "files": 1, "lines": 8}
    check("r5 confirmed (small+0-decision+Full)", R.rule5_lane_misclassification, ev, CONFIRMED)
    ev = _base_ev(); ev["lane_candidates"] = {"round": "R7", "clear": False, "files": 2, "lines": 30}
    check("r5 inconclusive (ambiguous)", R.rule5_lane_misclassification, ev, INCONCLUSIVE)
    ev = _base_ev()
    check("r5 inconclusive (no candidate -> honest reason)", R.rule5_lane_misclassification, ev, INCONCLUSIVE)

    # Rule 6 — per-element
    ev = _base_ev()
    ev["governance_elements"] = [{"file": "templates/x.md", "element": "E1",
                                  "prevents": ["false-green-deploy"], "severity": None}]
    ev["annotated_files"] = {"templates/x.md": {"false-green-deploy"}}
    check("r6 dismissed (declared+on-disk marker)", R.rule6_ratchet_inventory, ev, DISMISSED)
    ev = _base_ev()
    ev["governance_elements"] = [{"file": "templates/x.md", "element": "E1",
                                  "prevents": [], "severity": None}]
    check("r6 confirmed (coverage element, no prevents, no firing)", R.rule6_ratchet_inventory, ev, CONFIRMED)
    ev = _base_ev()
    ev["governance_elements"] = [{"file": "templates/x.md", "element": "E1",
                                  "prevents": ["unattended-prod-cutover"],
                                  "severity": "catastrophic-low-frequency"}]
    ev["annotated_files"] = {"templates/x.md": {"unattended-prod-cutover"}}
    check("r6 inconclusive (catastrophic idle, clean window)", R.rule6_ratchet_inventory, ev, INCONCLUSIVE)
    ev = _base_ev()
    ev["governance_elements"] = [{"file": "templates/x.md", "element": "E1",
                                  "prevents": ["false-green-deploy"], "severity": None}]
    ev["annotated_files"] = {"templates/x.md": {"false-green-deploy"}}
    ev["fired_classes"] = {"false-green-deploy"}
    check("r6 dismissed (control fired in window)", R.rule6_ratchet_inventory, ev, DISMISSED)
    ev = _base_ev()
    ev["governance_elements"] = [{"file": "templates/x.md", "element": "E1",
                                  "prevents": ["false-green-deploy"], "severity": None}]
    ev["annotated_files"] = {}     # declared but NO on-disk marker -> coverage gap
    check("r6 inconclusive (declared but no on-disk marker = coverage gap)",
          R.rule6_ratchet_inventory, ev, INCONCLUSIVE)
    ev = _base_ev(); ev["governance_ok"] = False
    check("r6 inconclusive (no governance file)", R.rule6_ratchet_inventory, ev, INCONCLUSIVE)

    # Rule 7
    ev = _base_ev(); ev["cross_session_rederivation"] = {"record_present": True,
                                                         "record": "deploy-hash abc1234", "sessions": ["a", "b"]}
    check("r7 confirmed (re-derived present record)", R.rule7_watch_vs_read, ev, CONFIRMED)
    ev = _base_ev(); ev["cross_session_rederivation"] = {"record_present": False, "record": "x"}
    check("r7 dismissed (observability gap)", R.rule7_watch_vs_read, ev, DISMISSED)
    ev = _base_ev()
    check("r7 inconclusive (no signal -> honest reason)", R.rule7_watch_vs_read, ev, INCONCLUSIVE)


# --------------------------------------------------------------------------
# Layer 1b — evidence-sourcing integrity (HIGH finding): blocks/firings come ONLY
# from recorded-report OUTCOME text, never from instructional/spec/template/example
# text, and are matched PER-ARTIFACT (no cross-file token combination).
# --------------------------------------------------------------------------

def _evidence_sourcing_cases(check_bool):
    from . import evidence as E

    # (a) INSTRUCTIONAL text is NOT a block/firing. The verification-gate TEMPLATE
    #     instruction + a spec's rollback EXAMPLE + a handoff: none may source one.
    vgate = (
        "## Cross-artifact consistency check\n"
        "If ANY item fails, redirect AI Developer. Do NOT bypass.\n"
        "## Rollback procedure\n1. git revert <deploy hash>\n2. Redeploy\n")
    spec = ("# Spec\nExample: deploy with no documented `git revert <hash>` rollback line.\n"
            "On failure the operator may abort; the DP.6 phrase is APPROVE-DEPLOY-NOW.\n")
    handoff = ("# Implement handoff\nRedirect AI Developer if any item fails. Do NOT bypass.\n"
               "Rollback: git revert <hash>.\n")
    instructional = [
        ("docs/specs/x/verification-gate.md", vgate),
        ("docs/specs/x/spec.md", spec),
        ("docs/tmp/handoff/2026-01-01-x-implement.md", handoff),
    ]
    appr, blk = E.collect_gate_outcomes(instructional)
    check_bool("evidence: instructional text yields 0 gate-blocks", blk, 0)
    fired = E.collect_firing_evidence(instructional)
    check_bool("evidence: instructional text yields NO firing classes", fired, set())

    # (b) a GENUINE recorded gate-block / firing in a gate-report / deploy-report
    #     OUTCOME section IS counted.
    gate_report = (
        "# Gate report\n## 7. Gate satisfaction\nGate blocked: deviation rejected by the operator.\n")
    deploy_report = (
        "# Deploy report\n## 3. Probe results\nG-N health probe: probe failed (observed 500).\n"
        "Operator decided rollback; rolled back the deploy.\n")
    recorded = [
        ("docs/specs/y/gate-report.md", gate_report),
        ("docs/specs/y/deploy-report.md", deploy_report),
    ]
    appr, blk = E.collect_gate_outcomes(recorded)
    check_bool("evidence: recorded gate-block IS counted (>=1)", blk >= 1, True)
    fired = E.collect_firing_evidence(recorded)
    check_bool("evidence: recorded probe-fail fires false-green/unauthorized",
               {"false-green-deploy", "unauthorized-deploy"} <= fired, True)
    check_bool("evidence: recorded 'rolled back the deploy' fires irreversible-loss",
               "irreversible-loss" in fired, True)

    # (c) tokens SPLIT across two artifacts do NOT combine into one event:
    #     `abort` in one report + `APPROVE-DEPLOY-NOW` in another must NOT fabricate
    #     an unattended-prod-cutover firing (per-artifact matching).
    split = [
        ("docs/specs/z/gate-report.md", "# Gate report\n## Status\nOperator chose to abort.\n"),
        ("docs/specs/z/deploy-report.md", "# Deploy report\n## Status\nTyped APPROVE-DEPLOY-NOW.\n"),
    ]
    fired = E.collect_firing_evidence(split)
    check_bool("evidence: split abort+APPROVE-DEPLOY-NOW across 2 reports does NOT fire",
               "unattended-prod-cutover" not in fired, True)
    # but BOTH tokens within ONE report's outcome text DO fire it.
    together = [("docs/specs/z/deploy-report.md",
                 "# Deploy report\n## Status\nDeploy aborted: operator never typed APPROVE-DEPLOY-NOW.\n")]
    fired = E.collect_firing_evidence(together)
    check_bool("evidence: abort+APPROVE-DEPLOY-NOW within ONE report DOES fire",
               "unattended-prod-cutover" in fired, True)

    # (d) artifact_kind classifies the recorded-report vs instructional surfaces.
    check_bool("evidence: gate-report classified recorded",
               E.artifact_kind("docs/specs/x/gate-report.md") == "gate-report", True)
    check_bool("evidence: verification-gate classified instructional (not recorded)",
               E.artifact_kind("docs/specs/x/verification-gate.md") in
               (E.RECORDED_REPORT_KINDS), False)


# --------------------------------------------------------------------------
# Layer 2 — end-to-end fixture repos (real assemble_evidence on disk)
# --------------------------------------------------------------------------

def _git(root, *args):
    subprocess.run(["git", *args], cwd=str(root), capture_output=True, text=True, timeout=30)


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


def _verdict_for(rule_no, root):
    """Run the REAL pipeline against a fixture repo and return one rule's verdict."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "fwe_main", str(Path(__file__).resolve().parent.parent / "find-wasted-effort.py"))
    main_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(main_mod)
    ev = main_mod.assemble_evidence(root, DEFAULT_WINDOW)
    # build_report must succeed (renders rule 6 per-element table etc.) and never write.
    today = datetime.date.today().isoformat()
    _report, _counts, findings = main_mod.build_report(ev, root, today)
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


def _e2e_cases(check_e2e):
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


# --------------------------------------------------------------------------
# Layer 3 — path-containment / --root escape (HIGH finding)
# --------------------------------------------------------------------------

def _containment_cases(check_bool):
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "fwe_main", str(Path(__file__).resolve().parent.parent / "find-wasted-effort.py"))
    main_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(main_mod)
    RootError = main_mod.RootError
    today = datetime.date.today().isoformat()

    # (a) a non-Flow directory is rejected as a root
    tmp = Path(tempfile.mkdtemp(prefix="fwe-noflow-"))
    try:
        rejected = False
        try:
            main_mod.resolve_root(str(tmp))
        except RootError:
            rejected = True
        check_bool("containment: non-Flow --root rejected", rejected, True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # (b) a traversal root (../outside) does not let the report escape: a Flow
    #     fixture root with a SYMLINKED state/audit pointing outside is rejected.
    base = Path(tempfile.mkdtemp(prefix="fwe-symesc-"))
    try:
        repo = base / "repo"
        outside = base / "outside"
        repo.mkdir(); outside.mkdir()
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")  # Flow marker
        (repo / "state").mkdir()
        symlink_ok = True
        try:
            os.symlink(str(outside), str(repo / "state" / "audit"),
                       target_is_directory=True)
        except (OSError, NotImplementedError):
            symlink_ok = False  # no symlink privilege (some Windows) -> skip, don't fail
        if symlink_ok:
            root = main_mod.resolve_root(str(repo))
            escaped = False
            rejected = False
            try:
                rp = main_mod.contained_report_path(root, today)
                # if not rejected, the resolved report must still be inside repo
                escaped = not main_mod._is_relative_to(rp.resolve(), repo.resolve())
            except RootError:
                rejected = True
            check_bool("containment: symlinked state/audit escape rejected",
                       rejected or not escaped, True)
        else:
            check_bool("containment: symlinked state/audit escape (host lacks symlink privilege)",
                       None, None, skipped=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (c) a well-formed Flow root yields a contained report path inside state/audit
    tmp = Path(tempfile.mkdtemp(prefix="fwe-ok-"))
    try:
        (tmp / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(tmp))
        rp = main_mod.contained_report_path(root, today)
        inside = main_mod._is_relative_to(rp, (root / "state" / "audit").resolve())
        check_bool("containment: valid Flow root -> report inside state/audit", inside, True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # (d) privilege-INDEPENDENT escape guard: a sibling path outside state/audit
    #     must be rejected by the containment predicate (the same predicate
    #     contained_report_path() uses to assert no traversal/absolute/symlink escape).
    base = Path(tempfile.mkdtemp(prefix="fwe-guard-"))
    try:
        repo = base / "repo"; (repo / "state" / "audit").mkdir(parents=True)
        sibling = base / "outside" / "report.md"
        sibling.parent.mkdir(parents=True)
        contained = main_mod._is_relative_to(sibling.resolve(),
                                             (repo / "state" / "audit").resolve())
        check_bool("containment: sibling path rejected by guard predicate", contained, False)
        legit = (repo / "state" / "audit" / "find-wasted-effort-x.md")
        ok = main_mod._is_relative_to(legit.resolve(),
                                      (repo / "state" / "audit").resolve())
        check_bool("containment: in-audit path accepted by guard predicate", ok, True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (e) a traversal-style --root that resolves to a non-Flow dir is rejected
    base = Path(tempfile.mkdtemp(prefix="fwe-trav-"))
    try:
        (base / "sub").mkdir()
        rejected = False
        try:
            # ../ from a Flow-less sub resolves to a Flow-less parent -> RootError
            main_mod.resolve_root(str(base / "sub" / ".." / "nowhere"))
        except RootError:
            rejected = True
        check_bool("containment: traversal --root to non-Flow dir rejected", rejected, True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (f) write_report TOCTOU guard (LOW finding): a symlinked report TARGET planted
    #     after path resolution is rejected via lstat before any write occurs.
    base = Path(tempfile.mkdtemp(prefix="fwe-wsym-"))
    try:
        repo = base / "repo"
        (repo / "state" / "audit").mkdir(parents=True)
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        report_path = main_mod.contained_report_path(root, today)
        outside = base / "outside.md"
        outside.write_text("attacker\n", encoding="utf-8")
        symlink_ok = True
        try:
            os.symlink(str(outside), str(report_path))
        except (OSError, NotImplementedError):
            symlink_ok = False  # no symlink privilege -> skip, don't fail
        if symlink_ok:
            rejected = False
            try:
                main_mod.write_report(root, report_path, "report body")
            except main_mod.RootError:
                rejected = True
            wrote_through = outside.read_text(encoding="utf-8") != "attacker\n"
            check_bool("containment: write_report rejects symlinked report target (lstat)",
                       rejected and not wrote_through, True)
        else:
            check_bool("containment: report-symlink write guard (host lacks symlink privilege)",
                       None, None, skipped=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # (g) write_report happy path: a real Flow root yields a written file inside
    #     state/audit (re-asserted containment lets the legitimate write through).
    base = Path(tempfile.mkdtemp(prefix="fwe-wok-"))
    try:
        repo = base / "repo"; repo.mkdir()
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        root = main_mod.resolve_root(str(repo))
        report_path = main_mod.contained_report_path(root, today)
        wrote = main_mod.write_report(root, report_path, "report body\n")
        inside = main_mod._is_relative_to(Path(wrote).resolve(),
                                          (repo / "state" / "audit").resolve())
        check_bool("containment: write_report writes inside state/audit on a valid root",
                   inside and Path(wrote).read_text(encoding="utf-8") == "report body\n", True)
    finally:
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------

def run_selftest():
    # Each case: (status, name, want, got) where status is "PASS" | "FAIL" | "SKIP".
    # SKIP (LOW fix): a fixture that could not be EXERCISED on this host (e.g. no
    # symlink privilege) is reported SEPARATELY and is NOT counted in the passed
    # tally — the reported pass count reflects only fixtures actually run.
    cases = []

    def check(name, fn, ev, want):
        got = fn(ev)["verdict"]
        cases.append(("PASS" if got == want else "FAIL", name, want, got))

    def check_e2e(name, got, want):
        cases.append(("PASS" if got == want else "FAIL", name, want, got))

    def check_bool(name, got, want, skipped=False):
        if skipped:
            cases.append(("SKIP", name, "(host lacks capability)", "skipped"))
        else:
            cases.append(("PASS" if got == want else "FAIL", name, want, got))

    _synthetic_cases(check)
    _evidence_sourcing_cases(check_bool)
    _e2e_cases(check_e2e)
    _containment_cases(check_bool)

    # prevents: parser fixtures (the annotation forms used on disk)
    from .constants import parse_prevents_classes
    parse_cases = [
        ("single + severity tag",
         "<!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->",
         {"unattended-prod-cutover"}),
        ("single + em-dash pointer",
         "STOP. <!-- prevents: silent-protected-path-drift — taxonomy: x -->",
         {"silent-protected-path-drift"}),
        ("multi-class",
         "<!-- prevents: false-green-deploy, unauthorized-deploy — taxonomy: x (A3) -->",
         {"false-green-deploy", "unauthorized-deploy"}),
        ("multi-class with inline parentheticals",
         "<!-- prevents: broken-main (lint/typecheck), regression-attribution-loss (one task scope), "
         "silent-protected-path-drift (worker-undisturbed) — taxonomy: x -->",
         {"broken-main", "regression-attribution-loss", "silent-protected-path-drift"}),
        ("no marker", "## Rollback procedure", set()),
    ]
    for name, line, want in parse_cases:
        got = parse_prevents_classes(line)
        cases.append(("PASS" if got == want else "FAIL", "parse: " + name,
                      sorted(want), sorted(got)))

    passed = [c for c in cases if c[0] == "PASS"]
    failed = [c for c in cases if c[0] == "FAIL"]
    skipped = [c for c in cases if c[0] == "SKIP"]
    for status, name, want, got in cases:
        print("  %s %s (want=%s got=%s)" % (status, name, want, got))
    # Reported pass count reflects only fixtures ACTUALLY EXERCISED (LOW fix):
    # skips are tallied separately, never folded into "passed".
    exercised = len(passed) + len(failed)
    print("[find-wasted-effort --selftest] %d/%d passed, %d skipped" % (
        len(passed), exercised, len(skipped)))
    return 1 if failed else 0
