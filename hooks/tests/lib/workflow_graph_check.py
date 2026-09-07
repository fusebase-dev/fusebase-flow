#!/usr/bin/env python3
"""Semantic job-graph validation for the release workflows (MAJOR 10).

WHY-home: docs/specs/backlog-triage-execution/final-architecture-review.md finding 10 —
the release-architecture assertions were distributed greps over workflow TEXT, so a
commented-out matrix row still satisfied them ("an assertion a comment can satisfy asserts
nothing"). This parses both workflows as YAML and asserts the JOB GRAPH. Comments are
invisible to a parser by construction, so comment-blindness is not a property this file has
to remember to check.

TRIPWIRE: every assertion below is paired with a MUTATION in ``MUTATIONS``. A mutation that
fails to turn its assertion red is reported as a FAILURE, not skipped — an unmutated
assertion is an unproven assertion, which is the defect this module replaces.

Output contract (parsed by run-tests.sh run_shell_phase via the calling shell phase):
  "PASS: release-authority <name>" / "FAIL: release-authority <name> (reason)"
Exit status = number of failed rows.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml
from maintainer_ci_check import check_maintainer

TAG = "release-authority"
VERIFY_WF = ".github/workflows/fusebase-flow-verify.yml"
RELEASE_WF = ".github/workflows/fusebase-flow-release.yml"
MEASURE_WF = ".github/workflows/fusebase-flow-measure-windows.yml"

# The committed matrix contract: platform -> runner. Both legs are REQUIRED; this map is the
# single place the pair is stated, so adding a leg is a deliberate edit here too.
REQUIRED_PLATFORMS = {"linux": "ubuntu-latest", "windows-msys": "windows-latest"}

# Any of these appearing in a required job means the gate was told to pass.
OVERRIDE_TOKENS = ("FF_SKIP_", "FF_ONLY", "FF_FULL", "FF_PHASE_TIMEOUT", "FF_CLI_RECOVERY_TIMEOUT")

# The exact committed windows matrix row, used by the comment-blindness mutation. Kept
# verbatim so a reformat makes the mutation UNAVAILABLE (a reported failure) rather than
# silently vacuous.
WINDOWS_ROW_TEXT = """          - platform: windows-msys
            os: windows-latest
            python: python
"""


def triggers(wf: dict) -> dict:
    """The `on:` mapping. YAML 1.1 parses the bare key `on` as the boolean True."""
    for key in ("on", True):
        val = wf.get(key)
        if isinstance(val, dict):
            return val
        if val is not None:
            return {val: None} if isinstance(val, str) else {}
    return {}


def jobs(wf: dict) -> dict:
    j = wf.get("jobs")
    return j if isinstance(j, dict) else {}


def steps_of(job: dict) -> list:
    s = job.get("steps")
    return s if isinstance(s, list) else []


def step_text(step: dict) -> str:
    return "\n".join(
        str(step.get(k, "")) for k in ("run", "uses", "with", "env", "name")
    )


def job_text(job: dict) -> str:
    return yaml.safe_dump(job, default_flow_style=False)


class Checker:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str, str]] = []   # (name, PASS|FAIL, reason)

    def check(self, name: str, condition: bool, reason: str = "") -> None:
        self.rows.append((name, "PASS" if condition else "FAIL", "" if condition else reason))

    @property
    def failed(self) -> list[str]:
        return [n for n, r, _ in self.rows if r == "FAIL"]


def assert_measure(measure: dict, release_text: str) -> Checker:
    """B1's measurement job must stay a MEASUREMENT.

    The whole point of the job is that it produces a number without deciding anything. The
    moment it can publish, be triggered automatically, be depended on, or run a scoped suite,
    it stops being that — and it would do so silently. These are the properties that keep the
    claim "non-publishing, manually triggered, committed defaults" mechanical rather than prose.
    """
    c = Checker()
    mt = triggers(measure)
    mj = jobs(measure)
    job = next((j for j in mj.values() if isinstance(j, dict)), {})
    mtext = yaml.safe_dump(measure, default_flow_style=False)

    c.check("graph-measure-manual-only", set(mt) == {"workflow_dispatch"},
            f"measurement triggers are {sorted(mt)}; anything but workflow_dispatch means it can "
            "run — or be depended on — without a human asking for it")
    c.check("graph-measure-is-non-publishing",
            str(measure.get("permissions", {}).get("contents", "")) == "read"
            and "contents: write" not in mtext and "gh release" not in mtext,
            "the measurement workflow can write contents or create a release; a measurement that "
            "can publish is not a measurement")
    c.check("graph-measure-not-referenced-by-release",
            "measure-windows" not in release_text,
            "the release workflow references the measurement job — it must gate nothing")
    mhits = [t for t in OVERRIDE_TOKENS if t in mtext]
    c.check("graph-measure-runs-committed-defaults", not mhits,
            f"the measurement carries {mhits}; a scoped or bound-overridden run measures nothing "
            "about the committed gate")
    c.check("graph-measure-has-headroom-to-finish",
            isinstance(job.get("timeout-minutes"), int) and job["timeout-minutes"] >= 120,
            "the measurement wall is under 120 minutes, so against the ~88m estimate it would "
            "likely re-report a timeout instead of producing the number")
    c.check("graph-measure-pins-an-exact-sha",
            "inputs.sha" in mtext and "rev-parse HEAD" in mtext,
            "the measurement does not check out and assert an exact SHA, so its timings cannot "
            "be attributed to a commit")
    return c


def assert_graph(verify: dict, release: dict) -> Checker:
    """Every structural claim PUBLISHING.md / docs/maintainer-execution.md make."""
    c = Checker()

    # ---------------- verify workflow ----------------
    vt = triggers(verify)
    vj = jobs(verify)
    vjob = vj.get("verify") if isinstance(vj.get("verify"), dict) else {}
    vgate = vj.get("verify-gate") if isinstance(vj.get("verify-gate"), dict) else {}

    c.check("graph-verify-is-reusable",
            isinstance(vt.get("workflow_call"), dict)
            and "sha" in ((vt["workflow_call"] or {}).get("inputs") or {}),
            "verify workflow is not callable with a `sha` input, so the release job cannot "
            "pin verification to an exact commit")

    # MAJOR 9 — ordinary push/PR must not drag every consumer through the maintainer matrix.
    c.check("graph-verify-not-on-ordinary-push-or-pr",
            "push" not in vt and "pull_request" not in vt,
            f"the full dual-platform matrix is still triggered by {sorted(set(vt) & {'push', 'pull_request'})} "
            "— template consumers inherit maintainer-grade runner cost with no opt-in")

    matrix = ((vjob.get("strategy") or {}).get("matrix") or {})
    include = matrix.get("include") if isinstance(matrix.get("include"), list) else []
    found = {row.get("platform"): row.get("os") for row in include if isinstance(row, dict)}
    c.check("graph-verify-matrix-is-both-platforms",
            found == REQUIRED_PLATFORMS,
            f"matrix legs are {found or '(none)'}; the committed contract is {REQUIRED_PLATFORMS}")

    c.check("graph-verify-fail-fast-off",
            (vjob.get("strategy") or {}).get("fail-fast") is False,
            "fail-fast is not explicitly false — a red Linux leg would CANCEL the Windows leg "
            "and the Windows-only defect class would never report")

    c.check("graph-verify-no-job-condition",
            "if" not in vjob,
            "the verify job carries a job-level `if:`, which can remove a required leg")

    c.check("graph-verify-no-continue-on-error",
            "continue-on-error" not in job_text(vjob),
            "continue-on-error appears in the verify job — a failing step would be counted as a pass")

    c.check("graph-verify-has-committed-wall",
            isinstance(vjob.get("timeout-minutes"), int),
            "the verify job has no committed timeout-minutes; an unbounded required job cannot "
            "fail closed on a hang")

    # The aggregate gate: always-reported, and non-success in EVERY non-success shape.
    gate_run = "\n".join(str(s.get("run", "")) for s in steps_of(vgate))
    c.check("graph-verify-gate-always-reports",
            bool(vgate) and str(vgate.get("if", "")).strip() == "always()"
            and "verify" in (vgate.get("needs") or []),
            "verify-gate is missing, is not `if: always()`, or does not need the matrix — a check "
            "run that never appears is weaker than one that appears RED")
    c.check("graph-verify-gate-demands-success",
            "needs.verify.result" in gate_run and "success" in gate_run,
            "verify-gate does not compare the matrix aggregate against `success`")

    # Committed defaults only, on both required jobs.
    vtext = yaml.safe_dump(vjob, default_flow_style=False)
    hits = [t for t in OVERRIDE_TOKENS if t in vtext]
    c.check("graph-verify-runs-committed-defaults",
            not hits,
            f"the required verify job carries {hits} — a gate that was told to pass is not a passing gate")

    checkout = [s for s in steps_of(vjob) if "actions/checkout" in str(s.get("uses", ""))]
    c.check("graph-verify-checks-out-the-requested-sha",
            any("inputs.sha" in str((s.get("with") or {}).get("ref", "")) for s in checkout),
            "the verify job does not check out the caller's `sha` input, so 'green on the tagged "
            "SHA' would be implied by the trigger rather than mechanical")
    c.check("graph-verify-asserts-head-equals-sha",
            any("rev-parse HEAD" in str(s.get("run", "")) for s in steps_of(vjob)),
            "no step asserts HEAD equals the requested SHA")

    # ---------------- release workflow ----------------
    rt = triggers(release)
    rj = jobs(release)
    rverify = rj.get("verify") if isinstance(rj.get("verify"), dict) else {}
    publish = rj.get("publish") if isinstance(rj.get("publish"), dict) else {}

    c.check("graph-release-triggered-only-by-tag-push",
            set(rt) == {"push"} and "tags" in (rt.get("push") or {}),
            f"release triggers are {sorted(rt)}; anything beyond a tag push is another route to "
            "`gh release create` that does not carry the exact-tag contract")

    c.check("graph-release-calls-the-one-verify-definition",
            str(rverify.get("uses", "")).endswith("/fusebase-flow-verify.yml")
            and "github.sha" in str((rverify.get("with") or {}).get("sha", "")),
            "the release job does not call the reusable verify workflow pinned to github.sha")

    c.check("graph-publish-needs-verify",
            "verify" in (publish.get("needs") or []),
            "publish is not structurally downstream of verify — the gate edge is gone")

    c.check("graph-publish-has-no-bypass-condition",
            "if" not in publish,
            "publish carries a job-level `if:`; `if: always()` there turns the structural gate "
            "into a procedural one")

    psteps = steps_of(publish)
    ptext = "\n".join(step_text(s) for s in psteps)
    c.check("graph-publish-tripwire-present",
            "needs.verify.result" in ptext,
            "the publish tripwire that goes red when the needs-edge is bypassed is gone")

    # B2 — the tag/SHA binding must run BEFORE any release is created, and again after.
    bind_idx = [i for i, s in enumerate(psteps) if "verify-tag-target.sh" in step_text(s)]
    create_idx = [i for i, s in enumerate(psteps) if "gh release create" in str(s.get("run", ""))]
    c.check("graph-publish-binds-tag-to-verified-sha",
            bool(bind_idx) and bool(create_idx) and min(bind_idx) < min(create_idx),
            "no verify-tag-target.sh step runs before `gh release create` — publication would "
            "again match the tag by NAME only and a force-moved tag could publish unverified code")
    c.check("graph-publish-rechecks-tag-after-create",
            len(bind_idx) >= 2 and max(bind_idx) > max(create_idx),
            "the tag binding is not re-asserted after publication, so a tag moved during the "
            "create window would go unreported")

    c.check("graph-release-least-privilege",
            str(release.get("permissions", {}).get("contents", "")) == "read"
            and str((publish.get("permissions") or {}).get("contents", "")) == "write",
            "workflow-level contents permission is not `read` with the write elevation scoped to publish")

    rtext = yaml.safe_dump(release, default_flow_style=False)
    rhits = [t for t in OVERRIDE_TOKENS if t in rtext]
    c.check("graph-release-runs-committed-defaults", not rhits,
            f"the release workflow carries {rhits}")

    return c


# --------------------------------------------------------------------------------------
# Mutations. Each names the assertion it MUST turn red. A mutation that leaves the graph
# green means that assertion is vacuous.
# --------------------------------------------------------------------------------------

def _mut_comment_windows_row(vtext: str, rtext: str):
    """TEXT mutation — the exact review mutation: comment out the Windows matrix row."""
    if WINDOWS_ROW_TEXT not in vtext:
        return None, None
    commented = "".join("# " + ln + "\n" for ln in WINDOWS_ROW_TEXT.rstrip("\n").split("\n"))
    return vtext.replace(WINDOWS_ROW_TEXT, commented), rtext


def _mut_publish_if_always(vtext, rtext):
    marker = "  publish:\n"
    if marker not in rtext:
        return None, None
    return vtext, rtext.replace(marker, marker + "    if: always()\n", 1)


def _mut_drop_verify_gate(vtext, rtext):
    head, sep, _tail = vtext.partition("  verify-gate:")
    if not sep:
        return None, None
    return head, rtext


def _mut_drop_tag_binding(vtext, rtext):
    lines = rtext.split("\n")
    kept, dropping = [], False
    for ln in lines:
        if "verify-tag-target.sh" in ln:
            # drop this line and the `- name:` header immediately above it
            while kept and not kept[-1].lstrip().startswith("- name:"):
                kept.pop()
            if kept:
                kept.pop()
            dropping = True
            continue
        kept.append(ln)
    return (vtext, "\n".join(kept)) if dropping else (None, None)


def _mut_broaden_verify_triggers(vtext, rtext):
    marker = "on:\n"
    if marker not in vtext:
        return None, None
    return vtext.replace(marker, "on:\n  push:\n    branches: [main]\n", 1), rtext


def _mut_drop_publish_needs(vtext, rtext):
    if "    needs: verify\n" not in rtext:
        return None, None
    return vtext, rtext.replace("    needs: verify\n", "", 1)


# Measurement-workflow mutations. Same rule: each must turn its named assertion red.
def _mut_measure_add_push(mtext):
    marker = "on:\n"
    if marker not in mtext:
        return None
    return mtext.replace(marker, "on:\n  push:\n    branches: [main]\n", 1)


def _mut_measure_write_permission(mtext):
    marker = "permissions:\n  contents: read\n"
    if marker not in mtext:
        return None
    return mtext.replace(marker, "permissions:\n  contents: write\n", 1)


def _mut_measure_scope_the_suite(mtext):
    marker = "      PYTHON: python\n"
    if marker not in mtext:
        return None
    return mtext.replace(marker, "      PYTHON: python\n      FF_ONLY: fixtures\n", 1)


MEASURE_MUTATIONS = {
    "measure-triggered-automatically": (_mut_measure_add_push, "graph-measure-manual-only"),
    "measure-granted-write": (_mut_measure_write_permission, "graph-measure-is-non-publishing"),
    "measure-scoped-suite": (_mut_measure_scope_the_suite, "graph-measure-runs-committed-defaults"),
}


MUTATIONS = {
    "comment-out-windows-matrix-row": (_mut_comment_windows_row, "graph-verify-matrix-is-both-platforms"),
    "publish-if-always": (_mut_publish_if_always, "graph-publish-has-no-bypass-condition"),
    "delete-verify-gate": (_mut_drop_verify_gate, "graph-verify-gate-always-reports"),
    "delete-tag-sha-binding": (_mut_drop_tag_binding, "graph-publish-binds-tag-to-verified-sha"),
    "restore-ordinary-push-trigger": (_mut_broaden_verify_triggers, "graph-verify-not-on-ordinary-push-or-pr"),
    "delete-publish-needs-edge": (_mut_drop_publish_needs, "graph-publish-needs-verify"),
}


def emit(name: str, result: str, reason: str = "") -> None:
    if result == "PASS":
        print(f"PASS: {TAG} {name}")
    else:
        print(f"FAIL: {TAG} {name} ({reason})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    args = ap.parse_args()
    root = Path(args.root)

    vpath, rpath = root / VERIFY_WF, root / RELEASE_WF
    if not vpath.is_file() or not rpath.is_file():
        emit("graph-workflows-present", "FAIL", f"missing {vpath} or {rpath}")
        return 1

    vtext = vpath.read_text(encoding="utf-8")
    rtext = rpath.read_text(encoding="utf-8")
    try:
        verify, release = yaml.safe_load(vtext), yaml.safe_load(rtext)
    except yaml.YAMLError as e:
        emit("graph-workflows-parse", "FAIL", f"unparseable workflow YAML: {e!r}")
        return 1

    mpath = root / MEASURE_WF
    if not mpath.is_file():
        emit("graph-measure-present", "FAIL",
             f"missing {mpath} — B1's non-publishing windows measurement job is absent")
        return 1
    mtext = mpath.read_text(encoding="utf-8")
    try:
        measure = yaml.safe_load(mtext)
    except yaml.YAMLError as e:
        emit("graph-measure-parse", "FAIL", f"unparseable measurement workflow: {e!r}")
        return 1

    failures = 0
    checker = assert_graph(verify, release)
    checker.rows += assert_measure(measure, rtext).rows
    checker.rows += check_maintainer(root)
    for name, result, reason in checker.rows:
        emit(name, result, reason)
        failures += result == "FAIL"

    for mut_name, (fn, target) in MEASURE_MUTATIONS.items():
        row = f"graph-mutation-{mut_name}"
        mutated_text = fn(mtext)
        if mutated_text is None:
            emit(row, "FAIL", "mutation could not be applied (its anchor no longer exists "
                              "verbatim) — an unapplied mutation proves nothing")
            failures += 1
            continue
        try:
            mutated = assert_measure(yaml.safe_load(mutated_text), rtext)
        except yaml.YAMLError:
            emit(row, "FAIL", "the mutated measurement workflow does not parse")
            failures += 1
            continue
        if target in mutated.failed:
            emit(row, "PASS")
        else:
            emit(row, "FAIL", f"mutation left {target!r} GREEN — that assertion is vacuous")
            failures += 1

    # Retained red-before mutations: each must turn its named assertion red.
    for mut_name, (fn, target) in MUTATIONS.items():
        row = f"graph-mutation-{mut_name}"
        try:
            mv, mr = fn(vtext, rtext)
        except Exception as e:                                    # noqa: BLE001
            emit(row, "FAIL", f"mutation raised {e!r}")
            failures += 1
            continue
        if mv is None:
            emit(row, "FAIL", "mutation could not be applied (the anchor it edits no longer "
                              "exists verbatim) — an unapplied mutation proves nothing")
            failures += 1
            continue
        try:
            mutated = assert_graph(yaml.safe_load(mv), yaml.safe_load(mr))
        except yaml.YAMLError:
            emit(row, "FAIL", "the mutated workflow does not parse; the mutation is malformed, "
                              "so it does not exercise the assertion")
            failures += 1
            continue
        if target in mutated.failed:
            emit(row, "PASS")
        else:
            emit(row, "FAIL", f"mutation left {target!r} GREEN — that assertion is vacuous")
            failures += 1

    total = len(checker.rows) + len(MUTATIONS) + len(MEASURE_MUTATIONS)
    print(f"[workflow-graph-check] {total - failures}/{total} PASS, {failures} FAIL")
    return failures


if __name__ == "__main__":
    sys.exit(main())
