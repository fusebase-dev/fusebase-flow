#!/usr/bin/env python3
"""The slicer (design sections 2 and 11, change 6; handoff WP 9): `slice.py <task|slice> [--agent builder]` prints what a
builder needs for one task (or each task of a slice) and nothing else: the backlog item, its criterion or test id, its
cited owner answers in full, its inputs, the task's globs with their breadth, the estimate, the reference project and
the live state/status.line with the reader's last-seen age. A named input whose tool the agent's profile in
policies/agent-tools.yml lacks prints BLOCKED-AT-input and exits 3.
`slice.py <slice> --brief [review|skeptic|verdict]` prints the reader's brief: the slice, the gate block and the flag
rows inline, and the two rubric questions as typed fields (none on a trivial-tier slice).
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import flow_docs as fd  # noqa: E402

RUBRIC = {"feature_not_asked": "Does the diff add a feature the item's criterion does not ask for?",
          "further_from_reference": "Is the diff further from the reference project's pattern than the task requires?"}
ASK = {"review": "Review the slice's diff against its items and tasks.",
       "skeptic": "Try to refute the gate: find the criterion the evidence does not prove.",
       "verdict": "Decide PASS or FAIL for the phase from the evidence rows and the gate block."}


def status(root: Path) -> str:
    try:
        line = (root / "state/status.line").read_text(encoding="utf-8").strip()
    except OSError:
        return "status: none (state/status.line is absent); last seen: never"
    seen = fd.stamp(line.rsplit("reader=", 1)[-1]) if "reader=" in line else None
    age = f"{int((time.time() - seen) // 60)} min ago" if seen else "never"
    return f"status: {line}; last seen: {age}"


def tools(root: Path, agent: str) -> set[str] | None:
    pol = fd.policy(root, "agent-tools")
    profiles, variants = pol.get("profiles") or {}, pol.get("agents") or {}
    if agent in profiles:
        return set(profiles[agent] or [])
    variant = variants.get(agent) or {}
    base = profiles.get(variant.get("base"))
    return None if base is None else set(base) | set(variant.get("add_tools") or [])


def task_block(root: Path, sl: dict, task: dict, items: dict, answers: dict, match, files: list[str]) -> list[str]:
    item = items.get(task["item"], {})
    out = [f"## {task['id']} {task['does']}", f"slice: {sl['id']} {sl['title']}",
           f"item: {task['item']} {item.get('title', '(not in backlog.md)')}"]
    out += [f"{k}: {item[k]}" for k in ("criterion", "test", "risk") if item.get(k)]
    out += ["inputs:"] + [f"  - {i}" for i in item.get("inputs", [])] if item.get("inputs") else ["inputs: none"]
    out += [f"glob: `{g}` ({sum(match(p, [g]) for p in files)} files at HEAD)" for g in task["globs"]]
    out.append(f"estimate: {task['minutes']}m {task['files']}f" if task["minutes"] is not None else "estimate: none")
    for aid in item.get("answers", []):
        a = answers.get(aid)
        out += [f"answer {aid}: {a['title']} (answered {a.get('answered', '?')})", *[f"> {t}" for t in a["text"]]] \
            if a else [f"answer {aid}: not under ## Answers in backlog.md"]
    return out


def blocked(root: Path, tasks: list[dict], items: dict, agent: str) -> list[str]:
    kinds, have = fd.policy(root, "agent-tools").get("input_kinds") or {}, tools(root, agent)
    out = []
    for t in tasks:
        for ref in items.get(t["item"], {}).get("inputs", []):
            kind = ref.split(":", 1)[0] if ":" in ref and "://" not in ref else ""
            if kind in kinds and (have is None or kinds[kind] not in have):
                out.append(f"BLOCKED-AT-input: {t['id']} input {ref} needs {kinds[kind]}, absent from the {agent} profile")
    return out


def brief(root: Path, sid: str, sl: dict, items: dict, role: str) -> list[str]:
    match, pol = fd.globber(), fd.policy(root)
    trivial = fd.trivial(fd.slice_log(root, sl), match, fd.tier(pol))
    out = [f"# {role.capitalize()} brief: {sid} {sl['title']}", ASK[role],
           "You run as reader (Read, Glob, Grep): return the JSON below and nothing else; the planner records it.",
           f"reference: {fd.reference(root)}", "## Items and tasks"]
    for t in sl["tasks"]:
        item = items.get(t["item"], {})
        out.append(f"- {t['id']} ({t['item']}, risk {item.get('risk', '?')}): {t['does']}; globs "
                   + ", ".join(f"`{g}`" for g in t["globs"]))
        out += [f"  {k}: {item[k]}" for k in ("criterion", "test") if item.get(k)]
    gate = fd.read(root / "state/gate" / f"{sid}.txt").strip()
    out += ["## Gate block", gate or f"(not run: python hooks/local/gate.py {sid})", "## Flags (id, check, task, evidence, ruling)"]
    flags = [r for r in fd.read(root / "state/flags" / f"{sid}.tsv").splitlines()[1:] if r.strip()]
    out += flags or ["(none)"]
    asked = role == "review" and not trivial
    if role == "review":
        out += ["## Rubric (a yes is a flag; on a risk-tagged item it holds the slice until the planner rules)"]
        out += [f"{k}: {q}" for k, q in RUBRIC.items()] if asked else ["not asked: a trivial-tier slice"]
    fields = [f'  "{k}": {{"answer": "yes|no", "evidence": "<one line>"}},' for k in RUBRIC] if asked else []
    return out + ["## Return", "{", f'  "slice": "{sid}", "role": "{role}", "verdict": "PASS|FAIL",', *fields,
                  '  "findings": [{"where": "<path:line>", "what": "<one line>"}]', "}"]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="slice.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("target", help="a task (T12) or a slice (P1-S2)")
    ap.add_argument("--agent", default="builder", help="the profile whose tools the inputs need (default builder)")
    ap.add_argument("--brief", nargs="?", const="review", choices=sorted(ASK), help="print a reader's brief instead")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    root = args.root.resolve()
    slices = {sid: {**s, "id": sid} for sid, s in fd.phases(root).items()}
    items, answers = fd.backlog(fd.read(root / fd.BACKLOG))
    sl = slices.get(args.target) or next((s for s in slices.values() if any(t["id"] == args.target for t in s["tasks"])), None)
    if sl is None:
        print(f"slice.py: {args.target} is no task or slice in {fd.PHASES}")
        return 2
    if args.brief:
        print("\n".join(brief(root, sl["id"], sl, items, args.brief)))
        return 0
    tasks = sl["tasks"] if args.target == sl["id"] else [t for t in sl["tasks"] if t["id"] == args.target]
    stop = blocked(root, tasks, items, args.agent)
    if stop:
        print("\n".join(stop))
        return 3
    match, files = fd.globber(), fd.git(root, "ls-tree", "-r", "--name-only", "HEAD").splitlines()
    out = [f"# Slice {args.target}", f"reference: {fd.reference(root)}", status(root)]
    for t in tasks:
        out += [""] + task_block(root, sl, t, items, answers, match, files)
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
