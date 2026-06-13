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


def _evidence_scoping_cases(check_bool):
    """MED fix (evidence scoping): the round-3 anti-fabrication strip must NOT
    overshoot into FALSE NEGATIVES. Prove BOTH directions:

      (a) genuine recorded OUTCOMES are COUNTED — a `## Rollback result: rollback
          executed` section, a dated `deploy-report-<date>.md` with a real `probe
          failed`, and a recorded report saved at `docs/tmp/handoff/<date>-x-deploy.md`
          (classified by its report HEADER, not its handoff-style path).
      (b) instructional / example / template / cross-artifact-split text is still
          NOT counted (the HIGH guard holds — no regression).
    """
    from . import evidence as E

    # --- DIRECTION (a): genuine recorded outcomes ARE detected ---

    # a1: a genuine rollback RESULT section (heading shares the word "rollback"
    #     with the procedure pattern, but names a RESULT) fires irreversible-loss,
    #     even though a rollback PROCEDURE section sits in the same report.
    report_with_both = (
        "# Deploy report — x\n"
        "## Rollback procedure\n1. git revert <deploy hash>\n2. Redeploy\n"
        "## Rollback result\nrollback executed; reverted the deploy after G-N failed.\n")
    fired = E.collect_firing_evidence([("docs/specs/x/deploy-report.md", report_with_both)])
    check_bool("scoping(a): genuine `## Rollback result: rollback executed` fires irreversible-loss",
               "irreversible-loss" in fired, True)

    # a2: a DATED deploy-report filename with a real probe failure IS classified a
    #     recorded report and its outcome counted (basename variant recognition).
    dated_deploy = (
        "# Deploy report — y\n## 3. Probe results\nG-N health probe: probe failed (observed 500).\n"
        "Operator decided rollback; rolled back the deploy.\n")
    check_bool("scoping(a): dated deploy-report-<date>.md classified deploy-report",
               E.artifact_kind("docs/specs/y/deploy-report-2026-06-13.md", dated_deploy),
               "deploy-report")
    fired = E.collect_firing_evidence([("docs/specs/y/deploy-report-2026-06-13.md", dated_deploy)])
    check_bool("scoping(a): dated deploy-report real probe-fail fires false-green/unauthorized",
               {"false-green-deploy", "unauthorized-deploy"} <= fired, True)
    check_bool("scoping(a): dated deploy-report 'rolled back the deploy' fires irreversible-loss",
               "irreversible-loss" in fired, True)

    # a3: a recorded report saved at a HANDOFF-style path (docs/tmp/handoff/<date>-x-deploy.md)
    #     is classified by its report HEADER ("# Deploy report"), so its recorded
    #     block IS counted — NOT discarded as a handoff.
    handoff_path_report = (
        "# Deploy report — handoff-saved\n## Status\n"
        "G-N health probe: probe failed (observed 503). Operator decided rollback;\n"
        "the deploy was rolled back and we will redeploy after the fix.\n")
    check_bool("scoping(a): report at docs/tmp/handoff/<date>-x-deploy.md classified by HEADER",
               E.artifact_kind("docs/tmp/handoff/2026-06-13-x-deploy.md", handoff_path_report),
               "deploy-report")
    appr, blk = E.collect_gate_outcomes([("docs/tmp/handoff/2026-06-13-x-deploy.md", handoff_path_report)])
    check_bool("scoping(a): handoff-path RECORDED report's probe-fail counted as a block",
               blk >= 1, True)
    fired = E.collect_firing_evidence([("docs/tmp/handoff/2026-06-13-x-deploy.md", handoff_path_report)])
    check_bool("scoping(a): handoff-path recorded 'deploy was rolled back' fires irreversible-loss",
               "irreversible-loss" in fired, True)

    # a4: a genuine `## Rollback result` recovery RESULT (recovery + outcome word)
    #     keeps the recovery firing path open too (recovery taken/executed).
    recovery_report = (
        "# Deploy report — r\n## Recovery taken\n"
        "G-O probe failed; we rolled back the deploy and filed a follow-up.\n")
    fired = E.collect_firing_evidence([("docs/specs/r/deploy-report.md", recovery_report)])
    check_bool("scoping(a): `## Recovery taken` result section keeps probe-fail firing",
               {"false-green-deploy", "unauthorized-deploy"} <= fired, True)

    # --- DIRECTION (b): instructional / template / split text still NOT counted ---

    # b1: a deploy-report TEMPLATE body (procedure + placeholders + instruction
    #     lines) yields NO firing — the round-3 HIGH guard still holds.
    template_body = (
        "# Deploy report — <slug>\n## Rollback procedure\n1. git revert <deploy hash>\n2. Redeploy\n"
        "## If a probe FAILED — use this section instead\nReplace this section with the failure section.\n"
        "If ANY probe fails, do NOT bypass; redirect AI Developer.\n")
    fired = E.collect_firing_evidence([("docs/specs/t/deploy-report.md", template_body)])
    check_bool("scoping(b): deploy-report TEMPLATE/procedure body fires NOTHING",
               fired, set())
    appr, blk = E.collect_gate_outcomes([("docs/specs/t/deploy-report.md", template_body)])
    check_bool("scoping(b): deploy-report TEMPLATE/procedure body yields 0 blocks", blk, 0)

    # b2: a -deploy.md handoff at a handoff path with a HANDOFF header (not a report
    #     header) stays instructional even with rollback EXAMPLE text in it.
    real_handoff = (
        "# Deploy handoff — x\n## Role bootstrap\nRollback: git revert <hash>.\n"
        "## Rollback procedure\n1. git revert <deploy hash>\n2. Redeploy\n")
    check_bool("scoping(b): a real deploy HANDOFF (handoff header) stays 'handoff'",
               E.artifact_kind("docs/tmp/handoff/2026-06-13-x-deploy.md", real_handoff), "handoff")
    fired = E.collect_firing_evidence([("docs/tmp/handoff/2026-06-13-x-deploy.md", real_handoff)])
    check_bool("scoping(b): real deploy handoff fires NOTHING (instructional)", fired, set())

    # b3: spec.md / verification-gate.md / -implement.md are NEVER reclassified to a
    #     recorded report even if they carry a report-looking header (HIGH guard).
    check_bool("scoping(b): spec.md never a recorded report",
               E.artifact_kind("docs/specs/x/spec.md", "# Deploy report — sneaky\nrolled back the deploy\n")
               in E.RECORDED_REPORT_KINDS, False)
    check_bool("scoping(b): verification-gate.md never a recorded report",
               E.artifact_kind("docs/specs/x/verification-gate.md",
                               "# Gate report\ngate blocked\n") in E.RECORDED_REPORT_KINDS, False)
    check_bool("scoping(b): -implement.md handoff never a recorded report",
               E.artifact_kind("docs/tmp/handoff/2026-06-13-x-implement.md",
                               "# Deploy report\nrolled back the deploy\n")
               in E.RECORDED_REPORT_KINDS, False)

    # b4: cross-artifact token SPLIT still does not fabricate (per-artifact rule):
    #     `probe failed` in one report + `rolled back the deploy` in another must NOT
    #     combine — each is counted only within its own report (no concatenation).
    split = [
        ("docs/specs/s/deploy-report.md", "# Deploy report\n## Status\nprobe failed (observed 500).\n"),
        ("docs/specs/s/gate-report.md", "# Gate report\n## Status\nrolled back the deploy.\n"),
    ]
    fired = E.collect_firing_evidence(split)
    # both fire (legitimately, each within its own report) — but assert NO cross
    # combination created a phantom class beyond what each report independently shows.
    check_bool("scoping(b): split reports each fire only their own class (no concatenation)",
               fired == {"false-green-deploy", "unauthorized-deploy", "irreversible-loss"}, True)


def _deviation_gating_kind_cases(check_bool):
    """LOW fix: DEVIATION_GATING_APPROVALS must contain ONLY real require_approval
    deviation kinds. Probe every kind: each included one dismisses rule 1 via
    deviation_gating_approvals(); routine-deploy kinds + non-kinds (incl. the
    `direct_to_main` workflow MODE) do NOT. Also cross-check membership against the
    real require_approval kinds in policies/approval-policy.yml."""
    from . import evidence as E
    from .constants import DEVIATION_GATING_APPROVALS, ROUTINE_DEPLOY_KINDS

    # every INCLUDED kind is consumed as contrary evidence (dismisses)
    for kind in sorted(DEVIATION_GATING_APPROVALS):
        gating = E.deviation_gating_approvals([{"file": "f", "kind": kind}])
        check_bool("dev-kind: %s consumed as rule-1 contrary evidence" % kind,
                   len(gating) == 1, True)
        v = R.rule1_unused_gate_stops(
            {**_base_ev(), "gating_approvals": gating})["verdict"]
        check_bool("dev-kind: %s dismisses rule 1" % kind, v, DISMISSED)

    # routine-deploy kinds + non-kinds (incl. direct_to_main MODE) are NOT consumed
    non_gating = sorted(ROUTINE_DEPLOY_KINDS) + ["direct_to_main", "branch_pr",
                                                 "not_a_kind"]
    for kind in non_gating:
        gating = E.deviation_gating_approvals([{"file": "f", "kind": kind}])
        check_bool("dev-kind: %s is NOT rule-1 contrary evidence" % kind,
                   gating, [])
        check_bool("dev-kind: %s is excluded from DEVIATION_GATING_APPROVALS" % kind,
                   kind in DEVIATION_GATING_APPROVALS, False)

    # cross-check: every member is a real require_approval kind in approval-policy.yml
    pol = Path(__file__).resolve().parent.parent.parent.parent / "policies" / "approval-policy.yml"
    if pol.is_file():
        import re as _re
        text = pol.read_text(encoding="utf-8", errors="replace")
        # parse the require_approval: block's immediate-child keys (2-space indent)
        kinds = set()
        in_block = False
        for line in text.splitlines():
            if _re.match(r"^require_approval:\s*$", line):
                in_block = True
                continue
            if in_block:
                if _re.match(r"^\S", line):       # dedented back to top-level key
                    break
                m = _re.match(r"^  ([a-z_]+):\s*$", line)
                if m:
                    kinds.add(m.group(1))
        check_bool("dev-kind: every DEVIATION_GATING kind is a real require_approval kind",
                   DEVIATION_GATING_APPROVALS <= kinds, True)
        check_bool("dev-kind: direct_to_main is NOT a require_approval kind (it's a mode)",
                   "direct_to_main" in kinds, False)
    else:
        check_bool("dev-kind: approval-policy.yml present for cross-check",
                   None, None, skipped=True)


# --------------------------------------------------------------------------
# Layer 2 — end-to-end fixture repos (real assemble_evidence on disk)
#
# Extracted to selftest_e2e.py along the test-layer seam (FR-25 module ceiling):
# the end-to-end fixture layer is the largest, self-contained responsibility.
# --------------------------------------------------------------------------

from .selftest_e2e import e2e_cases as _e2e_cases   # noqa: E402


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
    _evidence_scoping_cases(check_bool)
    _deviation_gating_kind_cases(check_bool)
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
