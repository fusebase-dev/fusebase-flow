#!/usr/bin/env python3
"""What a push or a merge carries, judged commit by commit (6.0.0-m7 item 3, review r1-23).

git runs no pre-commit for a cherry-pick, a clean merge, a rebase's replays or a revert, so a secret or a protected-path
change committed with --no-verify on one branch reached a remote by any of them. This judges what leaves:
  --push <updates file>   pre-push: every commit the remote lacks (`<tip> --not --remotes ^<remote sha>`);
  --merge                 pre-merge-commit: what the merge brings into the index against HEAD;
  --record                commit-msg: puts the staged protected-path changes the pre-commit (or pre-merge-commit) has
                          just allowed on record;
  --record-commit <sha>   the same for one commit already made, on the operator's go-ahead in chat (a cherry-pick of an
                          approved change onto another base, say).
A commit passes when no added line matches a secret pattern (the scanner's exclusions honoured) and each protected path
it changes goes from its old bytes to its new ones by approved steps on record (one step or a chain of them, so an amend
or a squash of approved commits passes and a revert does not), or it is a `flow:` commit whose every path flow_owned.py
accepts. Not judged: commits a remote-tracking ref holds (they arrived from the remote) and commits from before this
check existed (neither the commit nor a parent carries hooks/git/pre-merge-commit). A merge is judged on the files whose
merged bytes no remote-tracking ref holds at that path. The record: `<git common dir>/flow/approved-changes.tsv`, one
`path, old, new, time` row per approved change, shared by every worktree.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # no console window when the caller has none (pythonw)
MARK = "hooks/git/pre-merge-commit"  # a tree carrying it was committed under this check
NULL, EMPTY_TREE = "0" * 40, "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
FORMAT = "--format=%x01%H%x02%P%x02%s"


def setup(root: Path) -> None:
    """CWD-strip as the pre-push's gate does (pre-commit T32), then this folder, hooks/ and site-packages."""
    sys.path[:] = [p for p in sys.path if p not in ("", ".", str(root))]
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.path.insert(0, str(root / "hooks"))
    from shared.staged_secret_scan import _restore_site_packages
    _restore_site_packages()
    global approved, protected, record_path, steps, write_record
    from range_record import approved, protected, record_path, steps, write_record  # noqa: E402


def run(root: Path, args: list[str], data: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=root, input=data, capture_output=True, creationflags=NO_WINDOW, timeout=600)


def git(root: Path, *args: str) -> str:
    out = run(root, list(args))
    if out.returncode:
        raise RuntimeError(f"git {' '.join(args[:4])} failed: {out.stderr.decode('utf-8', 'replace').strip()}")
    return out.stdout.decode("utf-8", "surrogateescape")


def unquote(path: str) -> str:
    """A path as core.quotePath=false still quotes it (a tab, a newline, a quote or a backslash in it)."""
    if not (path.startswith('"') and path.endswith('"')):
        return path
    raw, out, i = path[1:-1], bytearray(), 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            if raw[i + 1] in "01234567":
                out.append(int(raw[i + 1:i + 4], 8))
                i += 4
                continue
            out += {"t": b"\t", "n": b"\n", '"': b'"', "\\": b"\\"}.get(raw[i + 1], raw[i + 1].encode())
            i += 2
            continue
        out += raw[i].encode("utf-8", "surrogateescape")
        i += 1
    return out.decode("utf-8", "replace")


def raw_entry(line: str) -> tuple[str, str, str, str]:
    """(path, status, parent 1's side, the result's side) of a raw or a combined raw line; a side is `<mode> <sha>`, or
    `-` where the path is absent."""
    meta, path = line.split("\t", 1)
    n = len(meta) - len(meta.lstrip(":"))
    fields = meta.lstrip(":").split()
    modes, shas = fields[:n + 1], fields[n + 1:2 * n + 2]
    side = ["-" if s == NULL or set(m) == {"0"} else f"{m} {s}" for m, s in ((modes[0], shas[0]), (modes[-1], shas[-1]))]
    return unquote(path), fields[-1], side[0], side[1]


def commits(root: Path, args: list[str]) -> list[dict]:
    """Each commit `git log <args>` lists, with its raw changes against its first parent (a merge: the paths that
    differ from every parent)."""
    found: list[dict] = []
    log = git(root, "-c", "core.quotePath=false", "log", "-c", "--raw", "--root", "--no-renames", "--no-abbrev", "-r",
              FORMAT, *args)
    for line in log.split("\n"):
        if line.startswith("\x01"):
            sha, parents, subject = (line[1:].split("\x02") + ["", ""])[:3]
            found.append({"sha": sha, "parents": parents.split(), "subject": subject, "changes": []})
        elif line.startswith(":") and found:
            found[-1]["changes"].append(raw_entry(line))
    return found


def carriers(root: Path, revs: set[str]) -> set[str]:
    """The revisions among `revs` whose tree carries MARK ("" is the index)."""
    specs = sorted(revs)
    out = run(root, ["cat-file", "--batch-check=%(objecttype)"], "".join(f"{s}:{MARK}\n" for s in specs).encode())
    return {s for s, a in zip(specs, out.stdout.decode("utf-8", "replace").split("\n")) if a.strip() == "blob"}


def staged(root: Path) -> list[tuple[str, str, str, str]]:
    base = "HEAD" if run(root, ["rev-parse", "-q", "--verify", "HEAD"]).returncode == 0 else EMPTY_TREE
    out = git(root, "-c", "core.quotePath=false", "diff", "--cached", "--raw", "--no-renames", "--no-abbrev", base)
    return [raw_entry(line) for line in out.split("\n") if line.startswith(":")]


def secrets(root: Path, diff_args: list[str], keep=None) -> dict[str, list[str]]:
    """{commit sha, or "index": the pattern ids that block in its added lines}; `keep(path)` filters files."""
    from shared.secret_scanner import block_decision, scan
    from shared.staged_secret_scan import _EXCLUDE_PATHSPECS
    text = git(root, "-c", "core.quotePath=false", *diff_args, "--", ".", *_EXCLUDE_PATHSPECS)
    added: dict[str, list[str]] = {}
    key, columns, current = "index", 1, ""
    for line in text.split("\n"):
        if line.startswith("\x01"):
            sha, parents = (line[1:].split("\x02") + [""])[:2]
            key, columns = sha, max(1, len(parents.split()))
        elif line.startswith("diff --git "):
            current = unquote(line.split(" b/", 1)[-1])
        elif line.startswith(("diff --cc ", "diff --combined ")):
            current = unquote(line.split(" ", 2)[2])
        elif line.startswith("+" * columns) and not line.startswith("+++") and (keep is None or keep(current)):
            added.setdefault(key, []).append(line[columns:])
    found = {}
    for key, lines in added.items():
        matches = scan("\n".join(lines), tool_context="git_pre_commit")
        if matches and block_decision(matches) == "deny":
            found[key] = sorted({m.pattern_id for m in matches})
    return found


def flow_commit_ok(root: Path, c: dict) -> bool:
    """A `flow:` commit (Flow's install, migration or upgrade) whose every path flow_owned.py accepts."""
    import flow_owned
    if not c["subject"].startswith("flow:") or len(c["parents"]) > 1:
        return False
    base = c["parents"][0] if c["parents"] else EMPTY_TREE
    return not flow_owned.foreign(root, [(s, p) for p, s, _, _ in c["changes"]], base=base, tip=c["sha"])


def push(root: Path, updates: str) -> list[str]:
    tips, remote = [], []
    for line in updates.split("\n"):
        parts = line.split()
        if len(parts) == 4 and parts[1] != NULL:
            tips.append(parts[1])
            if parts[3] != NULL and run(root, ["cat-file", "-e", parts[3]]).returncode == 0:
                remote.append(parts[3])
    if not tips:
        return []
    args = [*tips, "--not", "--remotes", *remote]
    listed = commits(root, args)
    marked = carriers(root, {s for c in listed for s in [c["sha"], *c["parents"]]})
    judged = {c["sha"]: c for c in listed if marked & {c["sha"], *c["parents"]}}
    graph, bad = steps(root), []
    for c in judged.values():
        if flow_commit_ok(root, c):
            continue
        bad += [f"{c['sha'][:12]} {c['subject'][:60]}: {p} changed with no approval on record"
                for p, _, old, new in c["changes"] if protected(p) and not approved(graph, p, old, new)]
    if judged:
        found = secrets(root, ["log", "-p", "-U0", "--cc", "--root", "--no-renames", "--full-history", FORMAT, *args])
        bad += [f"{sha[:12]} {judged[sha]['subject'][:60]}: secret pattern {', '.join(ids)} (redacted)"
                for sha, ids in found.items() if sha in judged]
    return bad


def merge(root: Path) -> list[str]:
    if not carriers(root, {"HEAD", ""}):
        return []  # a tree from before this check
    changes = staged(root)
    tips = sorted(set(git(root, "for-each-ref", "--format=%(objectname)", "refs/remotes").split()))
    specs = [f"{t}:{p}" for p, _, _, _ in changes for t in tips]
    out = run(root, ["cat-file", "--batch-check=%(objectname)"], "".join(s + "\n" for s in specs).encode("utf-8", "surrogateescape"))
    at_remote = {(s.split(":", 1)[1], a.strip()) for s, a in zip(specs, out.stdout.decode("utf-8", "replace").split("\n"))}
    mine = [c for c in changes if (c[0], c[3].split(" ")[-1]) not in at_remote]  # bytes no remote holds there
    import flow_owned
    names = {p for p, _, _, _ in mine}
    own = names - set(flow_owned.foreign(root, [(s, p) for p, s, _, _ in mine]))
    graph = steps(root)
    bad = [f"{p} changed with no approval on record" for p, _, old, new in mine
           if protected(p) and p not in own and not approved(graph, p, old, new)]
    for _, ids in secrets(root, ["diff", "--cached", "-U0", "--no-renames", "HEAD"], keep=names.__contains__).items():
        bad.append(f"a secret pattern in what the merge brings in: {', '.join(ids)} (redacted)")
    return bad


FIX = {"pre-push": "A secret: rotate it, then rewrite the branch without it; never push it. A protected-path change the "
                   "operator approves in chat: python hooks/local/lib/range_check.py --record-commit <sha>, then push.",
       "pre-merge-commit": "A secret: rotate it and take it out of the branch first. A protected-path change the operator "
                           "approves in chat: git merge --no-commit <branch>, mint (bash "
                           "hooks/local/write-bootstrap-approval.sh), git commit, then consume."}


def main(argv: list[str]) -> int:
    mode, rest = (argv[0], argv[1:]) if argv else ("", [])
    root, hook = Path.cwd(), {"--push": "pre-push", "--merge": "pre-merge-commit"}.get(mode, "commit-msg")
    try:
        setup(root)
        if mode == "--push" and rest:
            bad = push(root, Path(rest[0]).read_bytes().decode("utf-8", "surrogateescape"))
        elif mode == "--merge":
            bad = merge(root)
        elif mode == "--record":
            write_record(root, staged(root))
            return 0
        elif mode == "--record-commit" and rest:
            for row in write_record(root, commits(root, ["-1", rest[0]])[0]["changes"]):
                print(f"[fusebase-flow] on record: {row}")
            return 0
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except BaseException as e:  # noqa: BLE001 — a check that cannot run never lets the commits through
        if mode == "--record":
            print(f"[fusebase-flow:commit-msg] WARNING — the approval record was not written ({e!r}); a push of this "
                  "commit is refused until the operator records it (range_check.py --record-commit <sha>).",
                  file=sys.stderr)
            return 0
        print(f"[fusebase-flow:{hook}] BLOCK — the range check errored ({e!r}). Failing closed. NEVER use --no-verify.",
              file=sys.stderr)
        return 1
    if bad:
        print(f"[fusebase-flow:{hook}] BLOCK — changes no Flow hook checked (a cherry-pick, a rebase, a revert, a merge "
              "or a commit made with --no-verify):", file=sys.stderr)
        for line in bad:
            print(f"  {line}", file=sys.stderr)
        print(f"{FIX[hook]} NEVER use --no-verify.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
