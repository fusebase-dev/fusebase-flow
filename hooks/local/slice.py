#!/usr/bin/env python3
"""The slicer (design sections 2 and 11, change 6; handoff WP 9): `slice.py <task|slice> [--agent builder]` prints what a
builder needs for one task (or each task of a slice) and nothing else: the backlog item, its criterion or test id, its
cited owner answers in full, its inputs, the task's globs with their breadth, the estimate, the reference project and
the live state/status.line with the reader's last-seen age. A named input whose tool the agent's profile in
policies/agent-tools.yml lacks prints BLOCKED-AT-input and exits 3, and so does an item whose criterion or test names
the gate of the task's own phase (BLOCKED-AT-criterion): its row cannot pass before that gate, which needs the row.
`slice.py <slice|phase> --brief [review|skeptic|verdict]` prints the reader's brief: the verify skill's block for the
role, filled in, then the items, the evidence rows, the gate block and the flag rows inline. The review block's two rubric
questions are typed fields of its return; a trivial-tier slice's brief drops them.
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import flow_docs as fd  # noqa: E402

ROLES = ("review", "skeptic", "verdict")  # the REVIEW, SKEPTIC and VERDICT BRIEF blocks of the verify skill
VERIFY = Path(__file__).resolve().parents[2] / "flow-skills/verify/SKILL.md"


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


def own_gate(phase: str, items: dict, tasks: list[dict]) -> list[str]:
    """6.0.0-m6 item 6: a criterion or test that names its own phase's gate (P6 gate, phase 6's gate, gate of P6,
    gate.py P6, state/gate/P6.txt) cannot hold before that gate, and the gate needs it to hold."""
    n, out = phase[1:], []
    rx = re.compile(rf"\b(?:{phase}|phase {n})(?:'s)?\s+gate\b|\bgate(?:\.py)?\s+(?:of\s+)?(?:{phase}|phase {n})\b"
                    rf"|state/gate/{phase}\b", re.I)
    for t in tasks:
        item = items.get(t["item"], {})
        if hit := rx.search(f"{item.get('criterion', '')} {item.get('test', '')}"):
            out.append(f"BLOCKED-AT-criterion: {t['id']} serves {t['item']}, whose criterion names \"{hit[0]}\", the gate "
                       f"of {phase}, its own phase: the row cannot pass before that gate, and the gate needs the row. "
                       "Move that part to an item of a later phase (plan skill)")
    return out


def brief(root: Path, target: str, chosen: list[dict], items: dict, answers: dict, role: str) -> list[str]:
    m = re.search(rf"```text\n({role.upper()} BRIEF\n.*?)```", VERIFY.read_text(encoding="utf-8"), re.S)
    if m is None:
        return [f"slice.py: no {role.upper()} BRIEF block in {VERIFY}"]
    sha = fd.git(root, "rev-parse", "--short=12", "HEAD").strip() or "no commit"
    text = re.sub(r"<(slice|phase)>", target, m[1]).replace("<sha>", sha)
    trivial = role == "review" and fd.trivial(fd.slice_log(root, chosen[0]), fd.globber(), fd.tier(fd.policy(root)))
    if trivial:
        text = re.sub(r'Answer two questions.*?\n\(b\)[^\n]*\n|"rubric": \{[^}]*\}, ', "", text, flags=re.S)
    out = [*text.rstrip().splitlines(), "", f"reference: {fd.reference(root)}"]
    wanted = list(dict.fromkeys(t["item"] for s in chosen for t in s["tasks"]))
    for s in chosen:
        for t in s["tasks"]:
            out.append(f"- {t['id']} ({t['item']}, risk {items.get(t['item'], {}).get('risk', '?')}): {t['does']}; "
                       "globs " + ", ".join(f"`{g}`" for g in t["globs"]))
    for i in wanted:
        out += [f"{i} {k}: {items[i][k]}" for k in ("criterion", "test") if items.get(i, {}).get(k)]
        out += [f"{i} answer {a}: {answers[a]['title']}: " + " ".join(answers[a]["text"])
                for a in items.get(i, {}).get("answers", []) if a in answers and role == "review"]
    if role != "review":
        phase = chosen[0]["phase"]
        rows = fd.read(root / f"docs/flow/evidence/{phase}.md") or fd.read(root / "docs/flow/evidence.md")
        out += ["evidence rows:"] + [r for r in rows.splitlines() if re.match(r"\|\s*(B\d+)\s*\|", r)
                                     and r.split("|")[1].strip() in wanted]
    out += ["gate block:", fd.read(root / "state/gate" / f"{target}.txt").strip() or f"(not run: gate.py {target})"]
    if role == "review":
        out += ["flag rows (id, check, task, evidence, ruling):"]
        out += [r for r in fd.read(root / "state/flags" / f"{target}.tsv").splitlines()[1:] if r.strip()] or ["(none)"]
    for f in sorted((root / "state/returns").glob(f"{target}-skeptic*.json")) if role == "verdict" else []:
        out += [f"{f.name}:", f.read_text(encoding="utf-8").strip()]
    return out + (["rubric: not asked (a trivial-tier slice)"] if trivial else [])


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="slice.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("target", help="a task (T12), a slice (P1-S2), or a phase (P1) with --brief")
    ap.add_argument("--agent", default="builder", help="the profile whose tools the inputs need (default builder)")
    ap.add_argument("--brief", nargs="?", const="review", choices=ROLES, help="print a reader's brief instead")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    root = args.root.resolve()
    slices = {sid: {**s, "id": sid} for sid, s in fd.phases(root).items()}
    items, answers = fd.backlog(fd.read(root / fd.BACKLOG))
    if args.brief:
        chosen = [s for s in slices.values() if args.target in (s["id"], s["phase"])]
        print("\n".join(brief(root, args.target, chosen, items, answers, args.brief) if chosen else
                        [f"slice.py: {args.target} is no slice or phase in {fd.PHASES}"]))
        return 0 if chosen else 2
    sl = slices.get(args.target) or next((s for s in slices.values() if any(t["id"] == args.target for t in s["tasks"])), None)
    if sl is None:
        print(f"slice.py: {args.target} is no task or slice in {fd.PHASES}")
        return 2
    tasks = sl["tasks"] if args.target == sl["id"] else [t for t in sl["tasks"] if t["id"] == args.target]
    stop = blocked(root, tasks, items, args.agent) + own_gate(sl["phase"] or "", items, tasks)
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
