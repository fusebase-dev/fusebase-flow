"""Maintainer-only feedback must never become a publication path."""

from copy import deepcopy
from pathlib import Path

import yaml


WORKFLOW = ".github/workflows/fusebase-flow-maintainer.yml"
OWNER_GUARD = "github.repository == 'fusebase-dev/fusebase-flow' || github.event_name == 'workflow_dispatch'"
PLATFORMS = {"linux": "ubuntu-latest", "windows-msys": "windows-latest"}
CONTRACTS = {"fixtures", "git-smoke", "newline-preserve", "baseline-merge", "lane-router",
             "command-policy", "upgrade-classify", "validation-instructions", "release-authority"}


def failures(workflow: dict) -> set[str]:
    failed = set()
    triggers = workflow.get("on", workflow.get(True, {})) or {}
    jobs = workflow.get("jobs", {})
    job = jobs.get("contracts", {})
    steps = job.get("steps", [])
    matrix = job.get("strategy", {}).get("matrix", {}).get("include", [])
    checkout = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
    selected = [s for s in steps if s.get("run") == "bash hooks/tests/run-tests.sh"]
    data = yaml.safe_dump(workflow)
    checks = {
        "maintainer-triggers": set(triggers) == {"push", "pull_request", "workflow_dispatch"},
        "maintainer-owner-guard": job.get("if") == OWNER_GUARD,
        "maintainer-both-platforms": {r.get("platform"): r.get("os") for r in matrix} == PLATFORMS
            and job.get("strategy", {}).get("fail-fast") is False,
        "maintainer-read-only": workflow.get("permissions") == {"contents": "read"}
            and set(jobs) == {"contracts"} and "permissions" not in job and "gh release" not in data and "secrets." not in data,
        "maintainer-exact-source": len(checkout) == 1
            and checkout[0].get("with", {}).get("ref") == "${{ github.sha }}"
            and checkout[0].get("with", {}).get("persist-credentials") is False
            and job.get("env", {}).get("EXPECTED_SHA") == "${{ github.sha }}"
            and any('test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"' in s.get("run", "")
                    and "if" not in s for s in steps),
        "maintainer-focused-contracts": len(selected) == 1 and "if" not in selected[0]
            and set(selected[0].get("env", {}).get("FF_ONLY", "").split(",")) == CONTRACTS,
        "maintainer-real-recovery": any(s.get("run") == "bash hooks/tests/test-cli-flow-recovery.sh --only t14"
            and "if" not in s for s in steps),
        "maintainer-failures-visible": "continue-on-error" not in data
            and isinstance(job.get("timeout-minutes"), int) and 0 < job["timeout-minutes"] <= 20,
    }
    for name, passed in checks.items():
        if not passed:
            failed.add(name)
    return failed


def check_maintainer(root: Path) -> list[tuple[str, str, str]]:
    try:
        workflow = yaml.safe_load((root / WORKFLOW).read_text(encoding="utf-8"))
        failed = failures(workflow)
    except (OSError, yaml.YAMLError, AttributeError, TypeError, KeyError) as error:
        return [("maintainer-workflow", "FAIL", str(error))]
    names = ["maintainer-triggers", "maintainer-owner-guard", "maintainer-both-platforms",
             "maintainer-read-only", "maintainer-exact-source", "maintainer-focused-contracts",
             "maintainer-real-recovery", "maintainer-failures-visible"]
    rows = [(name, "FAIL" if name in failed else "PASS", "unsafe or missing contract" if name in failed else "")
            for name in names]
    for name in names:
        mutant = deepcopy(workflow)
        job = mutant["jobs"]["contracts"]
        if name == "maintainer-triggers":
            mutant["on" if "on" in mutant else True]["pull_request_target"] = None
        elif name == "maintainer-owner-guard":
            job.pop("if", None)
        elif name == "maintainer-both-platforms":
            job["strategy"]["matrix"]["include"] = job["strategy"]["matrix"]["include"][:1]
        elif name == "maintainer-read-only":
            mutant["permissions"]["contents"] = "write"
        elif name == "maintainer-exact-source":
            next(s for s in job["steps"] if str(s.get("uses", "")).startswith("actions/checkout@"))["with"]["ref"] = "main"
        elif name == "maintainer-focused-contracts":
            next(s for s in job["steps"] if s.get("run") == "bash hooks/tests/run-tests.sh")["env"]["FF_ONLY"] = ""
        elif name == "maintainer-real-recovery":
            job["steps"] = [s for s in job["steps"] if s.get("run") != "bash hooks/tests/test-cli-flow-recovery.sh --only t14"]
        else:
            job["continue-on-error"] = True
        detected = name in failures(mutant)
        rows.append(("negative-" + name, "PASS" if detected else "FAIL", "" if detected else "unsafe mutation accepted"))
    return rows
