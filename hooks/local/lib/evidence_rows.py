"""The evidence validator's row checks (validate_evidence.py; split out of it in 6.0.0-m8, its 250-line ceiling): the
evidence table's rows, a test-id row against its TAP log and the test file, and a capture row against its file, its run
log and the deploy it follows. Constants: policies/evidence-classes.yml."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

import flow_docs as fd
from evidence_rules import finding_problems, flaky_problems, run_log

IMAGE = (".png", ".jpg", ".jpeg", ".webp", ".gif")  # capture_min_bytes.image applies; other files take .other
ADDED_SKIP = re.compile(r"^\+(?!\+\+).*\b(skip|todo)\b", re.I | re.M)


def table(text: str) -> list[dict]:
    keys = ("status", "capture", "sha256", "bytes", "log", "note")
    found = []
    for line in text.splitlines():
        if m := re.match(r"\|\s*(B\d+)\s*\|(.*)\|\s*$", line):
            found.append({"id": m[1], **dict(zip(keys, [c.strip() for c in m[2].split("|")] + [""] * 6))})
    return found


def deploy_finished(root: Path, env: str) -> tuple[float, str] | None:
    """`finished` of the latest line in state/deploys/<env>.jsonl (runner conventions section 4)."""
    latest = None
    try:
        lines = (root / "state/deploys" / f"{env}.jsonl").read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in lines:
        try:
            value = str(json.loads(line).get("finished", ""))
        except (ValueError, AttributeError):
            continue
        if (t := fd.stamp(value)) is not None and (latest is None or t > latest[0]):
            latest = (t, value)
    return latest


def title(source: str, name: str) -> bool:
    """`name` is a whole test title in `source`: a quoted string that is the name ('...', "..." or `...`), or a function
    the name declares (def, func, fn). A substring of any line was enough before (review r1-28: `a` in 'a real test';
    field item 7.7: a short title like S2 matched wherever the token stood)."""
    q = re.escape(name)
    return bool(name) and bool(re.search(rf"""(['"`]){q}\1|\b(?:def|func|fn)\s+{q}\s*[(<]""", source))


def check_test_row(root: Path, row: dict, base: str, marker: str) -> list[str]:
    """A test-id row: `ok <n> - <name>` in its TAP log, the test present at HEAD, no skip or todo added since base."""
    file, _, name = row["capture"].partition("::")
    problems = []
    try:
        tap = (root / row["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        tap = None
        problems.append(f"log {row['log']} is missing")
    # A line is read after its leading whitespace: Node's test runner indents a subtest's `ok N -` (field item 7.2).
    if tap is not None and not any((m := re.match(marker, ln.lstrip())) and ln.lstrip()[m.end():].strip() == name.strip()
                                   for ln in tap):
        problems.append(f"no `ok <n> - {name.strip()}` line without SKIP or TODO in {row['log']}")
    source = fd.git(root, "show", f"HEAD:{file.strip()}")
    if not title(source, name.strip()):
        problems.append(f"the test is absent at HEAD ({file.strip()}: no test titled `{name.strip()}`)")
    if base and ADDED_SKIP.search(fd.git(root, "diff", base, "HEAD", "--", file.strip())):
        problems.append("a skip or todo token was added to the test file since the phase's base")
    return problems


def check_capture_row(root: Path, row: dict, pol: dict, phase: str, out: list[str]) -> tuple[list[str], str, str]:
    """A capture row: (problems, sha256, evidence class of its run log)."""
    path, problems = (root / row["capture"]).resolve(), []
    if not path.is_file() or not path.is_relative_to(root):
        return [f"capture {row['capture']} is missing"], "", "unit"
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    floor = int((pol.get("capture_min_bytes") or {}).get("image" if path.suffix.lower() in IMAGE else "other", 1))
    out.append(f"    capture {row['capture']} sha256={digest} bytes={len(data)}")
    if len(data) < floor:
        problems.append(f"capture is {len(data)} bytes, under the floor of {floor}")
    if row["sha256"] != digest or row["bytes"].replace(",", "") != str(len(data)):
        problems.append("the row's sha256 or Bytes differ from the file")
    log = run_log(root / row["log"], str(pol.get("run_log_header", "")))
    if log is None:
        return problems + [f"unrecognised run log {row['log']} (no `{pol.get('run_log_header')}` header)"], digest, "unit"
    problems += finding_problems(log, pol)
    env = re.search(r"\(([^()]+)\)\s*$", log["title"])
    # A pre-deploy baseline run (`baseline` in the title before the environment; the ship skill) records the state before
    # the deploy it serves, so it may start before that deploy; every other run starts after it finished.
    baseline = re.search(r"\bbaseline\b", log["title"].rsplit("(", 1)[0], re.I)
    deployed = deploy_finished(root, env[1]) if env and not baseline else None
    started = fd.stamp(log["records"][0][0]) if log["records"] else None
    if deployed and (started is None or started < deployed[0]):
        problems.append(f"the run started {log['records'][0][0] if log['records'] else '?'}, before the "
                        f"{env[1]} deploy finished {deployed[1]}")
    problems += flaky_problems(root, phase, row, pol, out)
    return problems, digest, ("live" if log["title"].startswith("# Live run") else "smoke")
