"""Maintainer-only feedback must never become a publication path."""

from copy import deepcopy
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

import yaml


WORKFLOW = ".github/workflows/fusebase-flow-maintainer.yml"
OWNER_GUARD = "github.repository == 'fusebase-dev/fusebase-flow' || github.event_name == 'workflow_dispatch'"
PLATFORMS = {"linux": "ubuntu-latest", "windows-msys": "windows-latest"}
CONTRACTS = {"fixtures", "git-smoke", "newline-preserve", "baseline-merge", "lane-router",
             "command-policy", "upgrade-classify", "validation-instructions", "release-authority"}
DEFAULT_CONTRACTS = "fixtures,git-smoke,newline-preserve,baseline-merge,lane-router,command-policy,upgrade-classify,validation-instructions,release-authority"
DISPATCH_CONCURRENCY = "maintainer-${{ github.workflow }}-${{ github.event_name == 'workflow_dispatch' && github.run_id || github.ref }}"


def selected_steps(steps: list[dict]) -> list[dict]:
    return [s for s in steps if "hooks/tests/run-tests.sh" in s.get("run", "")]


def groups_behavior(run: str) -> str:
    bash = shutil.which("bash")
    if not bash:
        return "bash unavailable: cannot execute groups behavior oracle"
    cases = [("", DEFAULT_CONTRACTS), ("signal-reap,git-capture-guard", "signal-reap,git-capture-guard"),
             ("a;touch PWNED", None), (",", None)]
    for value, expected in cases:
        try:
            with tempfile.TemporaryDirectory(prefix="maintainer-groups-", ignore_cleanup_errors=True) as directory:
                root = Path(directory)
                runner = root / "hooks/tests/run-tests.sh"
                runner.parent.mkdir(parents=True)
                runner.write_text(': > INVOKED\nprintf "FF_ONLY=%s\\n" "$FF_ONLY"\n', encoding="utf-8", newline="\n")
                script = root / "step.sh"
                script.write_text(run, encoding="utf-8", newline="\n")
                env = dict(os.environ, FF_ONLY=DEFAULT_CONTRACTS, FF_DISPATCH_GROUPS=value)
                # TRIPWIRE: this timeout bounds hangs, not host-dependent execution speed.
                result = subprocess.run([bash, "step.sh"], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=60)
                invoked = (root / "INVOKED").exists()
                if (root / "PWNED").exists():
                    return f"groups {value!r}: input executed a command"
                if expected is not None:
                    if result.returncode != 0 or not invoked or result.stdout.strip() != "FF_ONLY=" + expected:
                        return f"groups {value!r}: runner output/exit mismatch (exit {result.returncode}): {result.stderr.strip()}"
                elif result.returncode == 0 or invoked or "FF_ONLY=" in result.stdout:
                    return f"groups {value!r}: invalid input reached runner or succeeded"
        except (OSError, subprocess.TimeoutExpired) as error:
            return f"groups {value!r}: bash oracle could not complete: {error}"
    return ""


def failures(workflow: dict, *, behavior: bool = True, reasons: dict | None = None) -> set[str]:
    failed = set()
    triggers = workflow.get("on", workflow.get(True, {})) or {}
    jobs = workflow.get("jobs", {})
    job = jobs.get("contracts", {})
    steps = job.get("steps", [])
    matrix = job.get("strategy", {}).get("matrix", {}).get("include", [])
    checkout = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
    selected = selected_steps(steps)
    dispatch = triggers.get("workflow_dispatch") or {}
    groups = dispatch.get("inputs", {}).get("groups", {})
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
        "maintainer-dispatch-groups": groups.get("type") == "string" and groups.get("required") is False
            and groups.get("default") == "" and len(selected) == 1
            and selected[0].get("env", {}).get("FF_DISPATCH_GROUPS") == "${{ inputs.groups }}",
        "maintainer-no-expression-in-run": all("${{" not in s.get("run", "")
            for j in jobs.values() for s in j.get("steps", [])),
        "maintainer-dispatch-concurrency": workflow.get("concurrency", {}).get("group") == DISPATCH_CONCURRENCY
            and workflow.get("concurrency", {}).get("cancel-in-progress") is True,
        "maintainer-real-recovery": any(s.get("run") == "bash hooks/tests/test-cli-flow-recovery.sh --only t14"
            and "if" not in s for s in steps),
        "maintainer-failures-visible": "continue-on-error" not in data
            and isinstance(job.get("timeout-minutes"), int) and 0 < job["timeout-minutes"] <= 20,
    }
    if behavior:
        reason = groups_behavior(selected[0]["run"]) if len(selected) == 1 else "missing or ambiguous runner step"
        checks["maintainer-groups-behavior"] = not reason
        if reason and reasons is not None:
            reasons["maintainer-groups-behavior"] = reason
    for name, passed in checks.items():
        if not passed:
            failed.add(name)
    return failed


def check_maintainer(root: Path) -> list[tuple[str, str, str]]:
    try:
        workflow = yaml.safe_load((root / WORKFLOW).read_text(encoding="utf-8"))
        reasons = {}
        failed = failures(workflow, reasons=reasons)
    except (OSError, yaml.YAMLError, AttributeError, TypeError, KeyError) as error:
        return [("maintainer-workflow", "FAIL", str(error))]
    names = ["maintainer-triggers", "maintainer-owner-guard", "maintainer-both-platforms",
             "maintainer-read-only", "maintainer-exact-source", "maintainer-focused-contracts",
             "maintainer-dispatch-groups", "maintainer-no-expression-in-run", "maintainer-groups-behavior",
             "maintainer-dispatch-concurrency",
             "maintainer-real-recovery", "maintainer-failures-visible"]
    rows = [(name, "FAIL" if name in failed else "PASS", reasons.get(name, "unsafe or missing contract") if name in failed else "")
            for name in names]
    for name in names:
        if name == "maintainer-groups-behavior" and name in failed:
            rows.append(("negative-" + name, "FAIL", "behavior oracle prerequisite failed"))
            continue
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
            selected_steps(job["steps"])[0]["env"]["FF_ONLY"] = ""
        elif name == "maintainer-dispatch-groups":
            mutant["on" if "on" in mutant else True]["workflow_dispatch"]["inputs"].pop("groups")
        elif name == "maintainer-no-expression-in-run":
            selected_steps(job["steps"])[0]["run"] += "\necho ${{ inputs.groups }}\n"
        elif name == "maintainer-groups-behavior":
            selected_steps(job["steps"])[0]["run"] = 'set -euo pipefail\nif [[ -n "${FF_DISPATCH_GROUPS:-}" ]]; then\n  export FF_ONLY="$FF_DISPATCH_GROUPS"\nfi\nbash hooks/tests/run-tests.sh\n'
        elif name == "maintainer-dispatch-concurrency":
            mutant["concurrency"]["group"] = "maintainer-${{ github.workflow }}-${{ github.ref }}"
        elif name == "maintainer-real-recovery":
            job["steps"] = [s for s in job["steps"] if s.get("run") != "bash hooks/tests/test-cli-flow-recovery.sh --only t14"]
        else:
            job["continue-on-error"] = True
        detected = name in failures(mutant, behavior=name == "maintainer-groups-behavior")
        rows.append(("negative-" + name, "PASS" if detected else "FAIL", "" if detected else "unsafe mutation accepted"))
    return rows
