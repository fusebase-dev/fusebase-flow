"""Self-test layer — Phase 2A proposal output (T24).

Golden-proposal fixtures + the HARD read-only assertion, kept in their own module
along the test-layer seam (FR-25 module ceiling), like selftest_e2e.py:

  1. GOLDEN PROPOSALS (synthetic findings -> expected proposal schema):
       - a `confirmed` rule-5 finding -> exactly one proposal with the full schema;
       - a rule-6 per-element review candidate -> a `prune_review_candidate` proposal;
       - an `inconclusive` finding AND a `dismissed` finding -> NO proposal.
  2. SCHEMA INVARIANTS: every proposal carries operator_confirmation_required=True
     and source="audit"; raw_evidence_refs point at RAW artifacts, never state/audit/
     (self-output quarantine, Codex #5).
  3. QUARANTINE: the evidence collectors do NOT read state/audit/ (an audit report
     planted there cannot become evidence for the next audit).
  4. HARD no-write: a FULL pipeline run (assemble_evidence -> build_report ->
     write_report + proposals JSON) against a real on-disk fixture repo modifies
     NOTHING outside state/audit/ — verified by a before/after filesystem snapshot
     of every path EXCEPT state/audit/.

Non-writing layers (1-3) build proposals in memory. Layer 4 intentionally writes,
but ONLY into state/audit/, and proves it.
"""

import datetime
import importlib.util
import shutil
import subprocess
import tempfile
from pathlib import Path

from .constants import CONFIRMED, DISMISSED, INCONCLUSIVE, DEFAULT_WINDOW, PRUNE_REVIEW_CANDIDATE
from . import proposals as P


_SCHEMA_KEYS = {
    "proposal_id", "rule", "verdict", "raw_evidence_refs", "target_kind",
    "target_path", "exact_patch", "operator_confirmation_required", "source",
}


def _load_main():
    spec = importlib.util.spec_from_file_location(
        "fwe_main", str(Path(__file__).resolve().parent.parent / "find-wasted-effort.py"))
    main_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(main_mod)
    return main_mod


def _git(root, *args):
    subprocess.run(["git", *args], cwd=str(root), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)


# --------------------------------------------------------------------------
# Layers 1-3 — golden proposals + schema invariants + quarantine
# --------------------------------------------------------------------------

def _golden_cases(check_bool):
    # A confirmed rule-5 finding + evidence that names the round's raw artifacts.
    ev = {
        "artifacts": [
            ("docs/handoff/2026-01-01-tiny-typo-round-fix-deploy.md", "# Deploy handoff\nFull lane.\n"),
            ("state/audit/find-wasted-effort-2026-01-01.md", "# prior audit (MUST NOT be cited)\n"),
        ],
        "lane_candidates": {"round": "tiny-typo-round-fix", "clear": True, "files": 1, "lines": 8},
        "full_suite_runs_per_round": {},
        "cross_session_rederivation": None,
    }
    confirmed_r5 = {"rule": 5, "verdict": CONFIRMED,
                    "summary": "round tiny-typo-round-fix: 1 file/8 net lines, zero design decisions, Full ceremony",
                    "contrary": "none found"}
    inconclusive_r1 = {"rule": 1, "verdict": INCONCLUSIVE, "summary": "window too small", "contrary": "x"}
    dismissed_r2 = {"rule": 2, "verdict": DISMISSED, "summary": "fail-set differed", "contrary": "x"}

    out = P.build_proposals(ev, [confirmed_r5, inconclusive_r1, dismissed_r2])
    check_bool("proposals: confirmed->1, inconclusive/dismissed->0 (exactly one proposal)",
               len(out), 1)
    p = out[0]
    check_bool("proposals: schema keys complete", set(p.keys()), _SCHEMA_KEYS)
    check_bool("proposals: rule == 5", p["rule"], 5)
    check_bool("proposals: verdict == confirmed", p["verdict"], CONFIRMED)
    check_bool("proposals: operator_confirmation_required is True",
               p["operator_confirmation_required"], True)
    check_bool("proposals: source == audit", p["source"], "audit")
    check_bool("proposals: cites the RAW round artifact",
               "docs/handoff/2026-01-01-tiny-typo-round-fix-deploy.md" in p["raw_evidence_refs"], True)
    # Self-output quarantine: a state/audit/ artifact in evidence is NEVER cited.
    cites_audit = any(r.startswith("state/audit/") for r in p["raw_evidence_refs"])
    check_bool("proposals: NEVER cites a state/audit/ artifact (self-output quarantine)",
               cites_audit, False)
    check_bool("proposals: target_path is an operator decision, not an applied file",
               "operator" in p["target_path"].lower(), True)

    # Rule 6 -> one prune_review_candidate PER per-element CONFIRMED review candidate.
    r6 = {"rule": 6, "verdict": CONFIRMED, "summary": "1 element un-annotated", "contrary": "x",
          "elements": [
              {"file": "templates/x.md", "element": "E-orphan", "verdict": CONFIRMED,
               "prevents": [], "why": "no prevents + no firing", "catastrophic": False},
              {"file": "templates/y.md", "element": "E-governed", "verdict": DISMISSED,
               "prevents": ["false-green-deploy"], "why": "governed", "catastrophic": False},
              {"file": "templates/z.md", "element": "E-idle", "verdict": INCONCLUSIVE,
               "prevents": ["unattended-prod-cutover"], "why": "catastrophic idle", "catastrophic": True},
          ]}
    ev6 = {"artifacts": [], "lane_candidates": None, "full_suite_runs_per_round": {},
           "cross_session_rederivation": None}
    out6 = P.build_proposals(ev6, [r6])
    check_bool("proposals: rule6 yields ONE prune_review_candidate (only the CONFIRMED element)",
               len(out6), 1)
    p6 = out6[0]
    check_bool("proposals: rule6 verdict == prune_review_candidate", p6["verdict"], PRUNE_REVIEW_CANDIDATE)
    check_bool("proposals: rule6 NEVER an auto-prune/recorded-prune (review only in target_kind)",
               p6["target_kind"], "ratchet-prune-review")
    check_bool("proposals: rule6 operator_confirmation_required True", p6["operator_confirmation_required"], True)
    check_bool("proposals: rule6 cites ratchet-governance.yml (raw policy, not audit output)",
               "policies/ratchet-governance.yml" in p6["raw_evidence_refs"], True)
    check_bool("proposals: rule6 governed/idle elements emit NO proposal (only confirmed -> candidate)",
               all(p["target_kind"] == "ratchet-prune-review" for p in out6) and len(out6) == 1, True)

    # No findings at all -> no proposals.
    check_bool("proposals: empty findings -> empty proposals", P.build_proposals(ev6, []), [])

    # Determinism: same inputs -> identical proposal_id (golden id stability).
    again = P.build_proposals(ev, [confirmed_r5])
    check_bool("proposals: proposal_id deterministic across runs",
               again[0]["proposal_id"], p["proposal_id"])


def _quarantine_cases(check_bool):
    """The evidence collectors must NOT read state/audit/ — so a planted prior
    audit report cannot become evidence for the next audit (self-output quarantine,
    Codex #5). collect_artifacts globs are the surface to assert."""
    from . import evidence as E
    base = Path(tempfile.mkdtemp(prefix="fwe-quarantine-"))
    try:
        repo = base / "repo"
        (repo / "state" / "audit").mkdir(parents=True)
        (repo / "VERSION").write_text("0.0.0\n", encoding="utf-8")
        # plant a prior audit report + proposals JSON in state/audit/
        (repo / "state" / "audit" / "find-wasted-effort-2026-01-01.md").write_text(
            "# Find-wasted-effort audit\nGate blocked: deviation rejected.\n"
            "rolled back the deploy.\n", encoding="utf-8")
        (repo / "state" / "audit" / "find-wasted-effort-proposals-2026-01-01.json").write_text(
            '{"proposals": []}\n', encoding="utf-8")
        # also a legitimate raw report so we know collect_artifacts DOES find raw ones
        (repo / "docs" / "specs" / "r").mkdir(parents=True)
        (repo / "docs" / "specs" / "r" / "gate-report.md").write_text(
            "# Gate report\n## Status\nall good.\n", encoding="utf-8")
        arts = E.collect_artifacts(repo)
        rels = {rel for rel, _ in arts}
        in_audit = {r for r in rels if r.startswith("state/audit/")}
        check_bool("quarantine: collect_artifacts reads NOTHING under state/audit/",
                   in_audit, set())
        check_bool("quarantine: collect_artifacts DOES read raw reports",
                   "docs/specs/r/gate-report.md" in rels, True)
    finally:
        shutil.rmtree(base, ignore_errors=True)


# --------------------------------------------------------------------------
# Layer 4 — HARD no-write: a full run modifies nothing outside state/audit/
# --------------------------------------------------------------------------

def _snapshot(root):
    """Map relpath -> (mtime_ns, size) for every file under root EXCEPT anything
    inside state/audit/ and .git/. The HARD test asserts this snapshot is byte-for-
    byte identical before and after a full analyzer run."""
    snap = {}
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(root)).replace("\\", "/")
        if rel.startswith("state/audit/") or rel.startswith(".git/") or "/.git/" in ("/" + rel):
            continue
        st = p.stat()
        snap[rel] = (st.st_mtime_ns, st.st_size)
    return snap


def _hard_no_write_case(check_bool):
    main_mod = _load_main()
    base = Path(tempfile.mkdtemp(prefix="fwe-nowrite-"))
    try:
        repo = base / "repo"
        repo.mkdir()
        # A realistic project surface the run could (wrongly) try to write to:
        # memory / overlays / specs / provider files / policies — plus raw artifacts
        # that DO produce confirmed findings (so proposals are non-empty and the
        # run exercises the write path with real content).
        files = {
            "VERSION": "0.0.0\n",
            "FLOW_RULES.md": "# rules (must NOT change)\n",
            "AGENTS.md": "# agents (must NOT change)\n",
            "policies/ratchet-governance.yml":
                "schema_version: 1\nannotation_marker:\n  severity_tag: \"catastrophic-low-frequency\"\n"
                "coverage:\n  annotated_elements:\n"
                "    - file: templates/orphan.md\n      element: \"E-orphan\"\n      prevents: []\n"
                "  not_in_scope_phase1:\n    - \"x\"\n",
            "templates/orphan.md": "An un-annotated ceremony element (no prevents marker).\n",
            ".claude/skills/some-skill/SKILL.md": "# a provider mirror (must NOT change)\n",
            "docs/north-star.md": "# memory/overlay-ish file (must NOT change)\n",
            # a tiny-diff Full-ceremony round -> rule 5 confirmed -> a proposal
            "docs/handoff/2026-01-01-tiny-typo-round-fix-deploy.md":
                "# Deploy handoff\nFull lane. Verification gate. production_deploy.\n"
                "No design decisions; trivial typo.\n",
        }
        for rel, text in files.items():
            p = repo / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        _git(repo, "init", "-q")
        _git(repo, "config", "user.email", "fixture@example.com")
        _git(repo, "config", "user.name", "Fixture")
        _git(repo, "add", "-A")
        _git(repo, "commit", "-q", "-m", "fixture: base")
        _git(repo, "commit", "-q", "--allow-empty", "-m", "T1: tiny-typo-round-fix one-char fix")

        before = _snapshot(repo)

        # FULL run through the real CLI pipeline (report + proposals JSON), contained.
        root = main_mod.resolve_root(str(repo))
        today = datetime.date.today().isoformat()
        ev = main_mod.assemble_evidence(root, DEFAULT_WINDOW)
        report, _counts, _findings, proposals = main_mod.build_report(ev, root, today)
        report_path = main_mod.contained_report_path(root, today)
        main_mod.write_report(root, report_path, report)
        import json as _json
        json_path = main_mod.contained_proposals_path(root, today)
        main_mod.write_audit_file(
            root, json_path,
            _json.dumps({"date": today, "proposals": proposals}, indent=2, sort_keys=True) + "\n")

        after = _snapshot(repo)

        # (a) NOTHING outside state/audit/ changed (no new file, no modified file).
        check_bool("hard-no-write: nothing outside state/audit/ modified or created",
                   after, before)
        # (b) the run DID produce its contained outputs (proof the write path ran).
        check_bool("hard-no-write: report written inside state/audit/",
                   report_path.is_file() and
                   str(report_path.relative_to(repo)).replace("\\", "/").startswith("state/audit/"),
                   True)
        check_bool("hard-no-write: proposals JSON written inside state/audit/",
                   json_path.is_file() and
                   str(json_path.relative_to(repo)).replace("\\", "/").startswith("state/audit/"),
                   True)
        # (c) the run actually emitted a proposal (so the no-write proof is meaningful).
        check_bool("hard-no-write: a confirmed finding produced >=1 proposal",
                   len(proposals) >= 1, True)
        # (d) the report carries the Phase-2A proposals section.
        check_bool("hard-no-write: report has the 'Proposed memory entries' section",
                   "Proposed memory entries" in report, True)
        # (e) protected/worker-undisturbed files are byte-identical (explicit re-check).
        for guarded in ("FLOW_RULES.md", "policies/ratchet-governance.yml",
                        ".claude/skills/some-skill/SKILL.md", "docs/north-star.md",
                        "templates/orphan.md"):
            check_bool("hard-no-write: %s untouched" % guarded,
                       (repo / guarded).read_text(encoding="utf-8") == files[guarded], True)
    finally:
        shutil.rmtree(base, ignore_errors=True)


def proposal_cases(check_bool):
    _golden_cases(check_bool)
    _quarantine_cases(check_bool)
    _hard_no_write_case(check_bool)
