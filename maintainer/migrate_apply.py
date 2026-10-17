#!/usr/bin/env python3
"""The --apply half of `flow.py migrate` (handoff WP 12 steps 3 to 8): backup, removal, the overlay,
install and carry-over, the four documents with the migration report, and the migration commit."""
from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import flow
import migrate as m

BACKUP_PREFIX = ".flow-migrate-"
EXCLUDE_LINES = ("# Fusebase Flow migration backups (flow.py migrate): never stage them.", f"/{BACKUP_PREFIX}*/")
# The journal inside the backup folder (no Flow path starts with it): what the apply creates, the untracked files its
# removal deletes, and, once the migration is complete, the paths and the message of the migration commit.
JOURNAL = ".migrate"
CREATED, UNTRACKED, STAGE, MESSAGE = "created.txt", "untracked.txt", "stage.txt", "message.txt"
SLUG = "flow-migrate"
MINT = f"FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh --slug {SLUG}"
CONSUME = f"bash hooks/local/write-bootstrap-approval.sh --consume --slug {SLUG}"


def say(line: str) -> None:
    print(f"[flow migrate] {line}".rstrip())


def source(target: Path, rel: str) -> Path:
    return m.hooks_dir(target) / rel.rsplit("/", 1)[-1] if rel.startswith(".git/hooks/") else target / rel


def backup_rel(rel: str) -> str:
    return ".git-hooks/" + rel.rsplit("/", 1)[-1] if rel.startswith(".git/hooks/") else rel


def exclude(target: Path, lines: tuple[str, ...]) -> None:
    path = Path(m.git(target, "rev-parse", "--git-path", "info/exclude").stdout.decode().strip())
    path = path if path.is_absolute() else target / path
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    missing = [line for line in lines if line not in text.splitlines()]
    if missing:
        with open(path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(("" if not text or text.endswith("\n") else "\n") + "\n".join(missing) + "\n")


def index_paths(target: Path) -> set[str]:
    return set(m.git(target, "ls-files", "-z").stdout.decode("utf-8", "replace").split("\0")) - {""}


def write_lines(path: Path, lines: list[str]) -> None:
    flow.write_bytes(path, "".join(f"{line}\n" for line in lines).encode("utf-8"), False)


def backup(inv: m.Inventory, stamp: str) -> tuple[Path, list[str]]:
    target = inv.target
    folder = target / f"{BACKUP_PREFIX}{stamp}"
    exclude(target, EXCLUDE_LINES)  # before the first copy, so git never lists the folder
    folder.mkdir()
    files = inv.removals() + inv.replace + inv.foreign + [r for r in m.REWRITTEN + m.DOCS if (target / r).is_file()]
    for rel in files:
        dst = folder / backup_rel(rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source(target, rel), dst)
    index = index_paths(target)
    write_lines(folder / JOURNAL / CREATED,
                sorted({p for p in inv.new + list(m.REWRITTEN) + list(m.DOCS) if not (target / p).exists()}))
    write_lines(folder / JOURNAL / UNTRACKED, [p for p in inv.removals() if p not in index and not p.startswith(".git/")])
    return folder, files


def remove(inv: m.Inventory, folder: Path) -> tuple[list[str], list[str], int]:
    """Deletes the remove list; a file the surface will not delete moves into the backup folder instead."""
    moved, failed, parents = [], [], set()
    for rel in inv.removals():
        src = source(inv.target, rel)
        try:
            try:
                src.unlink()
            except PermissionError:
                os.chmod(src, stat.S_IWRITE)  # a read-only file on Windows
                src.unlink()
        except OSError:
            try:
                os.replace(src, folder / backup_rel(rel))  # its copy is already there
                moved.append(rel)
            except OSError as exc:
                failed.append(f"{rel} ({exc.strerror or exc})")
                continue
        if not rel.startswith(".git/"):
            parents.update(p for p in src.parents if inv.target in p.parents)
    pruned = 0
    for d in sorted(parents, key=lambda p: len(p.parts), reverse=True):
        try:
            d.rmdir()  # only a folder the removal left empty
            pruned += 1
        except OSError:
            pass
    return moved, failed, pruned


def overlay_and_version(inv: m.Inventory) -> list[str]:
    """Replaces each 5.x Flow section by heading with the 6.0 block; the FLOW:PRESERVE region rides along verbatim."""
    done = []
    for name, o in inv.overlays.items():
        path = inv.target / name
        raw = path.read_bytes()
        block = (flow.CORE / flow.OVERLAY[name]).read_bytes()
        if o.crlf:
            block = block.replace(b"\n", b"\r\n")  # the file's own line endings (autocrlf checkouts)
        if o.preserve:
            block = block[:block.index(m.P_BEGIN)] + o.preserve + block[block.index(m.P_END):]
        flow.write_bytes(path, raw[:o.start] + block + raw[o.end:], False)
        done.append(f"{name}: the '{o.heading}' section ({o.end_lf - o.start_lf:,} bytes) replaced by the 6.0 block"
                    + (f", FLOW:PRESERVE ({o.preserve_lf():,} bytes) carried verbatim" if o.preserve else ""))
    if inv.version_is_flow:
        flow.write_bytes(inv.target / "VERSION", (flow.CORE / "VERSION").read_bytes(), False)
        done.append(f"VERSION: {inv.version} -> {(flow.CORE / 'VERSION').read_text(encoding='utf-8').strip()}")
    return done


def install_and_carry(inv: m.Inventory) -> list[str]:
    """Runs milestone 1's install with the 5.x records read before the removal; install carries the project's rows."""
    target = inv.target
    # Every 5.x Flow path goes in, those without a sha256 as an empty set: install reads the keys as Flow-owned
    # when it sorts the baseline's rows into Flow's and the project's.
    rc = flow.install(target, inv.providers, {p: {sha} if sha else set() for p, sha in inv.recorded.items()})
    if rc != 0:
        raise m.Abort(f"install exited {rc} (its report above); the backup folder holds every file")
    plan = flow.planned_files(inv.providers)
    manifest = json.loads((target / flow.MANIFEST).read_text(encoding="utf-8"))
    recorded = {e["path"]: e["sha256"] for e in manifest["files"]}
    wrong = [p for p in inv.replace + inv.new if p in plan and not (
        p in recorded and (target / p).is_file() and flow.same_content((target / p).read_bytes(), recorded[p]))]
    if m.BASELINE in plan and recorded.get(m.BASELINE) != flow.sha256(flow.with_rows(plan[m.BASELINE], inv.rows)):
        wrong.append(f"{m.BASELINE} (not the core's rows plus the {len(inv.rows)} the dry run named)")
    if wrong:
        raise m.Abort(f"after install {len(wrong)} core paths do not hold the core's bytes: {', '.join(wrong[:10])}")
    done = [f"install: the {len(inv.replace)} replace and {len([p for p in inv.new if p in plan])} new files hold "
            f"the core's bytes; {flow.MANIFEST} says {manifest['flow_version']}"]
    rows = flow.baseline_rows((target / m.BASELINE).read_bytes()) if (target / m.BASELINE).is_file() else {}
    stale = [p for p in rows if not (target / p).exists()]
    done.append(f"carry-over: {m.BASELINE} is the core's plus {len(inv.rows)} project rows"
                + (f" ({', '.join(inv.rows)})" if inv.rows else "")
                + (f"; rows naming files the tree does not carry: {', '.join(stale)}" if stale else "")
                + f"; {flow.MANIFEST} records its sha256; local overrides left in place: "
                f"{len(inv.keep.get('local overrides', []))}")
    hooks = m.hooks_dir(target)
    same = [h for h in m.GIT_HOOKS if (hooks / h).is_file()
            and (hooks / h).read_bytes() == (flow.CORE / "hooks/git" / h).read_bytes()]
    if len(same) != len(m.GIT_HOOKS):
        raise m.Abort(f"git hooks not byte-identical to the core's: {', '.join(sorted(set(m.GIT_HOOKS) - set(same)))}")
    done.append(f"git hooks: {', '.join(same)} in .git/hooks/ byte-identical to the core's")
    return done


def migration_report(inv: m.Inventory, stamp: str, folder: Path, backed: int, moved: list[str]) -> list[str]:
    core = (flow.CORE / "VERSION").read_text(encoding="utf-8").strip()
    when = dt.datetime.strptime(stamp, "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%MZ")
    groups = "; ".join(f"{g} {len(inv.remove[g])}" for g in m.GROUPS)
    never = "; ".join(f"{k} {len(v)}" for k, v in inv.never.items())
    keep = "; ".join(f"{k}: {', '.join(v) if len(v) <= 12 else len(v)}" for k, v in inv.keep.items())
    refs = "; ".join(f"{rel} ({', '.join(found)})" for rel, found in inv.consumers.items()) or "none"
    lines = [
        "## Migration report",
        f"- {when} Fusebase Flow {inv.version} -> {core} by `flow.py migrate --apply --go-ahead` "
        f"(providers: {', '.join(sorted(inv.providers))})",
        f"- pre-migration commit: {inv.head} ({inv.branch}); rollback: `git checkout {inv.head[:8]}`",
        f"- backup folder: {folder.name}/ ({backed} files, excluded in .git/info/exclude; delete it once the "
        "migration is accepted)" + (f"; {len(moved)} files moved into it, deletion refused" if moved else ""),
        f"- remove: {len(inv.removals())} ({groups})",
        f"- left in place (named like Flow 5.x files, bytes not Flow's; copied to the backup folder): "
        f"{', '.join(inv.foreign) or 'none'}",
        f"- replace: {len(inv.replace)} ({len(inv.identical)} already identical); new: {len(inv.new)}; rewritten: "
        f"{', '.join(list(inv.overlays) + (['VERSION'] if inv.version_is_flow else []))}; {flow.ATTRIBUTES}: the Flow "
        "line-ending block; .gitignore unchanged",
        f"- never touch: {never}; {m.CLI_VENDOR} {inv.vendor[0]} listed, {inv.vendor[1]} present",
        f"- keep: {keep}",
        "- changed-by-both: 0",
        f"- consumer references ({len(inv.consumers)}): {refs}",
        f"- history mentions under {', '.join(m.HISTORY_DIRS)}/: {len(inv.history)} files, kept as written",
        f"- hidden by .gitignore: {', '.join(inv.hidden) or 'none'}",
        f"- hook wiring (left as is): {inv.wiring}",
        "- not run: check-cli-flow-conflicts.sh and the health check (neither is in the 6.0 core yet)",
    ]
    return lines


def documents(inv: m.Inventory, report: list[str]) -> list[str]:
    """Creates the four documents from the core's templates when absent; the report leads the ledger."""
    created = []
    for rel in m.DOCS:
        dest = inv.target / rel
        if not dest.exists():
            template = (flow.CORE / "templates" / Path(rel).name).read_bytes()
            flow.write_bytes(dest, template.replace(b"\r\n", b"\n"), False)  # generated: LF, whatever the checkout
            created.append(Path(rel).name)
    ledger = inv.target / "docs/flow/ledger.md"
    text = ledger.read_text(encoding="utf-8")
    head, sep, rest = text.partition("\n") if text.startswith("status:") else ("", "", text)
    block = "\n".join(report) + "\n"
    flow.write_bytes(ledger, (head + sep + "\n" + block + ("\n" if not rest.startswith("\n") else "") + rest)
                     .encode("utf-8"), False)
    return [f"documents: {', '.join(created) or 'none'} created from the core's templates in docs/flow/; "
            f"the migration report ({len(report) - 1} lines) leads ledger.md; backlog.md has no items"]


def apply(inv: m.Inventory) -> int:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    folder, files = backup(inv, stamp)
    copied = len(inv.removals()) + len(inv.replace) + len(inv.foreign)
    say(f"backup: {folder.name}/ holds {len(files)} files: remove {len(inv.removals())} + replace "
        f"{len(inv.replace)} + left in place {len(inv.foreign)} + {len(files) - copied} rewritten in place; "
        "listed in .git/info/exclude")
    moved, failed, pruned = remove(inv, folder)
    say(f"removed: {len(inv.removals()) - len(moved) - len(failed)} files deleted, {pruned} folders the removal "
        "left empty pruned")
    if moved:
        say(f"moved into {folder.name}/ because this surface refused the deletion: {len(moved)} files "
            "(delete the folder once the migration is accepted)")
    if failed:
        say(f"STOPPED: {len(failed)} files could be neither deleted nor moved:")
        for line in failed:
            say(f"  {line}")
        return stopped_part_way(inv.target, folder)
    for line in overlay_and_version(inv):
        say(line)
    try:
        for line in install_and_carry(inv):
            say(line)
    except m.Abort as exc:
        say(f"STOPPED: {exc}")
        return stopped_part_way(inv.target, folder)
    for line in documents(inv, migration_report(inv, stamp, folder, len(files), moved)):
        say(line)
    complete(inv, folder)
    return commit(inv, folder)


def complete(inv: m.Inventory, folder: Path) -> None:
    """Records the migration commit's paths and message in the journal: from here the migration is complete."""
    target = inv.target
    index = index_paths(target)
    paths = [p for p in inv.removals() if p in index] + inv.replace + inv.new + list(m.REWRITTEN) + list(m.DOCS)
    write_lines(folder / JOURNAL / STAGE, sorted({p for p in paths if p in index or (target / p).is_file()}))
    core = (flow.CORE / "VERSION").read_text(encoding="utf-8").strip()
    flow.write_bytes(folder / JOURNAL / MESSAGE, (
        f"chore(flow): {inv.task} migrate Fusebase Flow {inv.version} to {core}\n\n"
        f"flow.py migrate --apply --go-ahead: remove {len(inv.removals())}, replace {len(inv.replace)}, "
        f"new {len(inv.new)}; the migration report leads docs/flow/ledger.md.\n"
        f"Backup: {folder.name}/ (excluded). Rollback: git checkout {inv.head[:8]}.\n").encode("utf-8"), False)


def bash(target: Path, *args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, FF_BOOTSTRAP_TTL_MIN="30")
    return subprocess.run([shutil.which("bash") or "bash", *args], cwd=target, env=env,
                          capture_output=True, text=True, timeout=600)


def stage_args(target: Path, folder: Path) -> list[str]:
    stage = (folder / JOURNAL / STAGE).relative_to(target).as_posix()
    return ["--literal-pathspecs", "add", "-f", f"--pathspec-from-file={stage}"]


def commit(inv: m.Inventory, folder: Path) -> int:
    """Stages the migration by name, mints the single-use approval, commits through the hooks, consumes."""
    target = inv.target
    paths = (folder / JOURNAL / STAGE).read_text(encoding="utf-8").splitlines()
    add = m.git(target, *stage_args(target, folder))
    if add.returncode:
        say(f"STOPPED: git add exited {add.returncode}: {add.stderr.decode('utf-8', 'replace').strip()}")
        return stopped_part_way(target, folder)
    staged = [p for p in m.git(target, "diff", "--cached", "--name-only", "-z").stdout.decode("utf-8").split("\0") if p]
    stray = sorted(set(staged) - set(paths))
    if stray:
        say(f"STOPPED: staged paths outside the migration: {', '.join(stray[:10])}; nothing committed")
        return 1
    say(f"staged by name: {len(staged)} paths" + (f" ({len(inv.hidden)} hidden by .gitignore)" if inv.hidden else ""))
    message = (folder / JOURNAL / MESSAGE).read_text(encoding="utf-8")
    mint = bash(target, "hooks/local/write-bootstrap-approval.sh", "--slug", SLUG)
    say(f"approval: {(mint.stdout + mint.stderr).strip()}")
    if mint.returncode:
        say("STOPPED: the approval was not minted; nothing committed")
        for line in finish_steps(target, folder):
            say(line)
        return 1
    say(f"committing through the hooks: {message.splitlines()[0]}")
    sys.stdout.flush()
    try:
        done = subprocess.run(["git", "commit", "-q", "-F", "-"], cwd=target, input=message.encode("utf-8"),
                              timeout=3600)
        failed = f"the commit did not pass (exit {done.returncode}; the hook output is above)" if done.returncode else ""
    except subprocess.TimeoutExpired:
        failed = "the commit did not finish within 3600 s"
    if failed:
        # The approval stays until the commit passes or its TTL ends (owner, 2026-10-17): consumed only on success.
        found, expires = approval(target)
        say(f"STOPPED: {failed}. The migration is applied and staged; HEAD is still {inv.head[:8]}, the backup "
            "folder holds every file" + (f", and the approval {found.name} stays until {expires}" if found else ""))
        for line in finish_steps(target, folder):
            say(line)
        return 1
    used = bash(target, "hooks/local/write-bootstrap-approval.sh", "--consume", "--slug", SLUG)
    say(f"approval: {(used.stdout + used.stderr).strip()}")
    left = sorted(p.name for p in (target / "state/approvals").glob("*") if p.name != ".gitkeep")
    say(f"state/approvals/: {', '.join(left) if left else 'empty'}")
    say(f"committed: {m.git(target, 'log', '-1', '--format=%h %s').stdout.decode('utf-8').strip()}")
    return 0


def approval(target: Path) -> tuple[Path | None, str]:
    """The migration's approval artifact in state/approvals/ and its expiry ("" when absent or unreadable)."""
    for p in sorted((target / "state/approvals").glob(f"protected_path_edit-{SLUG}-*.json")):
        try:
            return p, str(json.loads(p.read_text(encoding="utf-8")).get("expires_at") or "")
        except (OSError, ValueError, AttributeError):
            return p, ""
    return None, ""


def finish_steps(target: Path, folder: Path) -> list[str]:
    """The by-hand end of a complete migration: stage, commit (minting first when no approval is left), consume."""
    subject = (folder / JOURNAL / MESSAGE).read_text(encoding="utf-8").splitlines()[0]
    found, expires = approval(target)
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = ["finish it by hand, once the cause is fixed; stage the migration by name (a no-op when it is staged):",
             "  $ git " + " ".join(stage_args(target, folder))]
    commit_line = f'  $ git commit -m "{subject}"'
    if found and expires > now:
        lines += [f"  commit; the approval {found.name} holds until {expires}:", commit_line,
                  f"  after {expires}, or if the staged paths changed, mint a fresh approval, then commit again:",
                  f"  $ {MINT}"]
    else:
        lines += ["  mint the single-use approval (none is left, or its TTL has passed), then commit:",
                  f"  $ {MINT}", commit_line]
    return lines + ["  once the commit has passed, consume the approval:", f"  $ {CONSUME}"]


def rollback_steps(target: Path, folder: Path | None) -> list[str]:
    """Restores the pre-migration tree from HEAD and the backup folder."""
    lines = ["  $ git reset -q", "  $ git checkout -- ."]
    if folder is None:
        return lines + ["  (no .flow-migrate-* folder: the untracked files the removal deleted and the old "
                        ".git/hooks cannot be restored from it)"]
    rel = folder.relative_to(target).as_posix()
    if (folder / JOURNAL / CREATED).is_file():
        lines.append(f'  $ while IFS= read -r p; do rm -f -- "$p"; rmdir -p -- "$(dirname -- "$p")" 2>/dev/null; '
                     f"done < {rel}/{JOURNAL}/{CREATED}; true")
    if (folder / JOURNAL / UNTRACKED).is_file() and (folder / JOURNAL / UNTRACKED).stat().st_size:
        lines.append(f'  $ while IFS= read -r p; do mkdir -p -- "$(dirname -- "$p")" && cp -p -- "{rel}/$p" "$p"; '
                     f"done < {rel}/{JOURNAL}/{UNTRACKED}")
    hooks = m.hooks_dir(target)
    where = hooks.relative_to(target).as_posix() if target in hooks.parents else hooks.as_posix()
    for old in sorted((folder / ".git-hooks").glob("*")):
        lines.append(f"  $ cp -p -- {rel}/.git-hooks/{old.name} {where}/{old.name}")
    return lines


def stopped_part_way(target: Path, folder: Path | None) -> int:
    say("the apply stopped part-way: do not commit this tree. Roll it back to the pre-migration commit "
        "(this discards every tracked change since the apply began), fix the cause, then run the migration again:")
    for line in rollback_steps(target, folder):
        say(line)
    return 1


def resume(target: Path) -> int:
    """A tree where the 5.x manifest is gone but HEAD still carries it: an apply that did not end in its commit."""
    folders = sorted(p for p in target.glob(f"{BACKUP_PREFIX}*") if p.is_dir())
    folder = folders[-1] if folders else None
    if folder and (folder / JOURNAL / STAGE).is_file() and (folder / JOURNAL / MESSAGE).is_file():
        say(f"STOPPED: the migration is applied but not committed (HEAD still carries Flow 5.x; "
            f"{folder.name}/{JOURNAL}/{STAGE} lists the paths of the migration commit)")
        for line in finish_steps(target, folder):
            say(line)
        return 1
    say(f"STOPPED: an apply stopped part-way: {m.MC_MANIFEST} is gone from the tree, HEAD still carries it"
        + ("" if (target / flow.MANIFEST).is_file() else f", and there is no {flow.MANIFEST}")
        + (f"; backup folder {folder.name}/" if folder else "; no backup folder"))
    return stopped_part_way(target, folder)
