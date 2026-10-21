#!/usr/bin/env python3
"""DONE check (design section 6; handoff WP 7b): `done.py <slice>`; exit 0 done, 1 not done, 2 no such slice.

A task counts when a commit since the phase's base carries exactly one T<n> in its subject, that id, and touches a
path under the task's globs; body mentions, trivial-tier commits and plan:/ship: commits do not count. The builder's
state/returns/<slice>.json must name every task with the SHA of a commit on the branch carrying its id; a missing file
fails. Writes state/done/<slice>.json: `committed`, the field the ledger derives, and `open`.
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import flow_docs as fd  # noqa: E402


def returns_problems(root: Path, slice_id: str, tasks: dict, on_branch: dict[str, str]) -> list[str]:
    ret, why = fd.returns(root, slice_id)
    if ret is None:
        return [why]
    named = {t["id"]: str(t["sha"]) for t in ret["tasks"]}
    problems = [f"{t}: not in the returns file" for t in tasks if t not in named]
    problems += [f"{t}: in the returns file but not a task of {slice_id}" for t in named if t not in tasks]
    for tid, sha in named.items():
        full = fd.git(root, "rev-parse", "--verify", "-q", f"{sha}^{{commit}}").strip() if fd.SHA.fullmatch(sha) else ""
        if full not in on_branch:
            problems.append(f"{tid}: {sha[:12]} is not a commit on this branch since the phase's base")
        elif fd.TASK.findall(on_branch[full]) != [tid]:
            problems.append(f"{tid}: {sha[:12]} does not carry {tid} alone in its subject")
    return problems


def check(root: Path, slice_id: str) -> tuple[int, list[str], dict]:
    sl = fd.phases(root).get(slice_id)
    if sl is None:
        return 2, [f"done {slice_id}: no such slice in {fd.PHASES}"], {}
    base = sl["base"] or "missing"
    if not fd.SHA.fullmatch(base) or not fd.git(root, "rev-parse", "--verify", "-q", f"{base}^{{commit}}"):
        return 1, [f"done {slice_id}: the phase's base is {base}: write `- base: <sha>` under its heading"], {}
    match, trivial, tasks = fd.globber(), fd.tier(fd.policy(root)), {t["id"]: t for t in sl["tasks"]}
    log, committed = fd.commits(root, base), {}
    why = {tid: "no commit carries it alone in its subject" for tid in tasks}
    for sha, subject, paths in log:
        ids = fd.TASK.findall(subject)
        if len(ids) != 1 or ids[0] not in tasks or ids[0] in committed or subject.startswith(("plan:", "ship:")):
            continue
        if paths and all(match(p, trivial) for p in paths):
            why[ids[0]] = "only trivial-tier commits carry it"
        elif any(match(p, tasks[ids[0]]["globs"]) for p in paths):
            committed[ids[0]] = sha
        else:
            why[ids[0]] = "its commits touch none of its globs"
    problems = returns_problems(root, slice_id, tasks, {sha: subject for sha, subject, _ in log})
    lines = [f"done {slice_id}: {len(committed)}/{len(tasks)} committed since {base[:12]}"]
    lines += [f"  {t} committed {committed[t][:12]}" if t in committed else f"  {t} OPEN: {why[t]}" for t in tasks]
    record = {"slice": slice_id, "checked": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "committed": committed, "open": [t for t in tasks if t not in committed], "returns": problems}
    return int(bool(record["open"] or problems)), lines + [f"  returns: {p}" for p in problems], record


def main(argv: list[str]) -> int:
    fd.utf8_output()
    ap = argparse.ArgumentParser(prog="done.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("slice")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    rc, lines, record = check(args.root.resolve(), args.slice)
    if record:
        out = args.root.resolve() / "state/done" / f"{args.slice}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("\n".join(lines + [f"DONE: {'PASS' if rc == 0 else 'FAIL'}"]))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
