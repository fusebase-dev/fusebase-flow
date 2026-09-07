#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import namedtuple
from contextlib import contextmanager
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path, PurePosixPath

if os.name == "nt":
    import msvcrt
else:
    import fcntl


SCHEMA = 1
GIT_TIMEOUT = 15
REGULAR_GIT_MODES = {"100644", "100755"}
MANIFEST_ROW = re.compile(r"^(.+?)  ([0-9a-f]{64})$")
SUPPORTED_SURFACES = {"skill", "agent", "health-skill", "command"}
SURFACE_MANIFESTS = {
    "skill": "audit/skill-mirror-manifest.txt",
    "agent": "audit/agent-mirror-manifest.txt",
}


def native_path(raw: str) -> Path:
    if os.name == "nt" and raw.startswith("/"):
        converted = subprocess.run(
            ["cygpath", "-m", raw], check=True, text=True, capture_output=True,
            timeout=GIT_TIMEOUT,
        ).stdout.strip()
        return Path(converted)
    return Path(raw)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def bytes_digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def encoded_json(value: dict) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8")


def atomic_bytes(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp = Path(raw)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def atomic_json_if_changed(path: Path, value: dict) -> None:
    encoded = encoded_json(value)
    if path.is_file() and path.read_bytes() == encoded:
        return
    atomic_bytes(path, encoded)


def load_receipt(path: Path) -> dict:
    if not path.exists():
        return {"schema": SCHEMA, "targets": {}}
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("schema") != SCHEMA or not isinstance(value.get("targets"), dict):
        raise RuntimeError("owned-target receipt has invalid schema")
    return value


def lexical_path(root: Path, raw: str) -> Path:
    candidate = native_path(raw)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = Path(os.path.abspath(candidate))
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"source escapes repository: {raw}") from exc
    return candidate


def reject_symlinks(root: Path, path: Path, label: str) -> None:
    current = root
    for part in path.relative_to(root).parts:
        current = current / part
        if current.is_symlink():
            raise RuntimeError(f"{label} or ancestor is a symlink: {path.relative_to(root).as_posix()}")


def safe_source(root: Path, raw: str) -> Path:
    source = lexical_path(root, raw)
    reject_symlinks(root, source, "source")
    if not source.is_file():
        raise RuntimeError("source is missing or not a regular file")
    return source


def safe_target(root: Path, rel: str) -> Path:
    relative = PurePosixPath(rel)
    if relative.is_absolute() or rel != relative.as_posix() or ".." in relative.parts:
        raise RuntimeError(f"invalid target path: {rel}")
    candidate = root.joinpath(*relative.parts)
    reject_symlinks(root, candidate, "target")
    return candidate


def expected_mapping(source_rel: str, target_rel: str, surface: str) -> str | None:
    source = PurePosixPath(source_rel).parts
    target = PurePosixPath(target_rel).parts
    if surface == "skill" and len(source) in {3, 4} and source[0] == "flow-skills":
        suffix = source[2:]
        if suffix != ("SKILL.md",) and not (
            len(suffix) == 2 and suffix[0] == "references"
        ):
            return None
        if len(target) == len(source) + 1 and target[:2] in {
            (".agents", "skills"), (".claude", "skills")
        } and target[2] == source[1] and target[3:] == suffix:
            return "audit/skill-mirror-manifest.txt"
    if surface == "agent" and len(source) == 3 and source[0] == "agents" \
            and source[2] == "AGENT.md":
        if len(target) == 3 and target[:2] in {
            (".claude", "agents"), (".codex", "agents")
        } and target[2] == f"{source[1]}.md":
            return "audit/agent-mirror-manifest.txt"
    return None


PlanRow = namedtuple(
    "PlanRow", ("source_raw", "source_rel", "target_rel", "manifest_rel"),
)
TreeEntry = namedtuple("TreeEntry", ("mode", "kind", "oid"))
BootstrapProof = namedtuple("BootstrapProof", ("head", "source_hash", "target_hash"))
PreparedRow = namedtuple(
    "PreparedRow", ("row", "source", "target", "status", "detail", "proof", "state"),
)
ClassifiedState = namedtuple("ClassifiedState", ("source_hash", "target_kind", "target_hash"))


def git_run(root: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(root), *args], check=True, capture_output=True,
        timeout=GIT_TIMEOUT,
    )
    return result.stdout


def git_blobs(root: Path, oids: set[str]) -> dict[str, bytes]:
    if not oids:
        return {}
    process = subprocess.Popen(
        ["git", "-C", str(root), "cat-file", "--batch"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    payload = "".join(f"{oid}\n" for oid in sorted(oids)).encode("ascii")
    try:
        stdout, stderr = process.communicate(payload, timeout=GIT_TIMEOUT)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        raise RuntimeError("committed-object batch timed out")
    if process.returncode != 0:
        raise RuntimeError(f"committed-object batch failed: {stderr.decode('utf-8', 'replace').strip()}")
    stream = io.BytesIO(stdout)
    values: dict[str, bytes] = {}
    for requested in sorted(oids):
        header = stream.readline().decode("ascii", "strict").rstrip("\n").split()
        if len(header) != 3 or header[0] != requested or header[1] != "blob":
            raise RuntimeError(f"unreadable committed blob: {requested}")
        size = int(header[2])
        values[requested] = stream.read(size)
        if stream.read(1) != b"\n":
            raise RuntimeError(f"malformed committed-object response: {requested}")
    return values


class Baseline:
    def __init__(self, root: Path, rows: list[PlanRow]):
        self.root = root
        self.head = ""
        self.entries: dict[str, TreeEntry] = {}
        self.blobs: dict[str, bytes] = {}
        self.error = ""
        wanted = {
            item for row in rows if row.manifest_rel
            for item in (row.source_rel, row.target_rel, row.manifest_rel) if item
        }
        if not wanted:
            return
        try:
            self.head = git_run(root, "rev-parse", "--verify", "HEAD^{commit}").decode().strip()
            tree = git_run(root, "ls-tree", "-rz", "--full-tree", self.head)
            for raw in tree.split(b"\0"):
                if not raw:
                    continue
                meta, path_raw = raw.split(b"\t", 1)
                mode, kind, oid = meta.decode("ascii").split()
                path = path_raw.decode("utf-8", "surrogateescape")
                if path in wanted:
                    self.entries[path] = TreeEntry(mode, kind, oid)
            oids = {entry.oid for entry in self.entries.values() if entry.kind == "blob"}
            self.blobs = git_blobs(root, oids)
        except Exception as exc:
            self.error = f"committed baseline unavailable: {exc}"

    def regular_blob(self, rel: str) -> bytes:
        entry = self.entries.get(rel)
        if not entry:
            raise RuntimeError(f"committed baseline missing path: {rel}")
        if entry.kind != "blob" or entry.mode not in REGULAR_GIT_MODES:
            raise RuntimeError(f"committed baseline path is not a regular file: {rel}")
        try:
            return self.blobs[entry.oid]
        except KeyError as exc:
            raise RuntimeError(f"committed baseline blob unreadable: {rel}") from exc

    def manifest_hash(self, manifest_rel: str, target_rel: str) -> str:
        try:
            text = self.regular_blob(manifest_rel).decode("utf-8")
        except UnicodeDecodeError as exc:
            raise RuntimeError(f"committed mirror manifest is not UTF-8: {manifest_rel}") from exc
        matches = []
        for line in text.splitlines():
            parsed = MANIFEST_ROW.fullmatch(line)
            if not parsed or "\t" in parsed.group(1):
                raise RuntimeError(f"committed mirror manifest has a malformed row: {manifest_rel}")
            if parsed.group(1) == target_rel:
                matches.append(parsed.group(2))
        if len(matches) != 1:
            raise RuntimeError(
                f"committed mirror manifest requires exactly one row for {target_rel}; found {len(matches)}"
            )
        return matches[0]

    def prove(self, row: PlanRow, source_hash: str, target_hash: str) -> BootstrapProof:
        if not row.manifest_rel or not row.source_rel:
            raise RuntimeError("target has no authorized canonical mirror mapping")
        if self.error:
            raise RuntimeError(self.error)
        canonical_hash = bytes_digest(self.regular_blob(row.source_rel))
        committed_target_hash = bytes_digest(self.regular_blob(row.target_rel))
        manifest_hash = self.manifest_hash(row.manifest_rel, row.target_rel)
        if len({canonical_hash, committed_target_hash, manifest_hash}) != 1:
            raise RuntimeError("committed canonical, target, and manifest hashes do not agree")
        if target_hash != canonical_hash:
            raise RuntimeError("current target bytes do not match proven committed mirror bytes")
        return BootstrapProof(self.head, source_hash, target_hash)

    def revalidate_head(self) -> None:
        current_head = git_run(self.root, "rev-parse", "--verify", "HEAD^{commit}").decode().strip()
        if current_head != self.head:
            raise RuntimeError("repository HEAD changed after baseline pin")

    def revalidate(self, proof: BootstrapProof, source: Path, target: Path) -> None:
        reject_symlinks(self.root, source, "source")
        reject_symlinks(self.root, target, "target")
        if not source.is_file() or digest(source) != proof.source_hash:
            raise RuntimeError("source changed after ownership classification")
        if not target.is_file() or digest(target) != proof.target_hash:
            raise RuntimeError("target changed after ownership classification")


def make_plan_row(root: Path, source_raw: str, target_rel: str, surface: str) -> PlanRow:
    source_rel = None
    try:
        source_rel = lexical_path(root, source_raw).relative_to(root).as_posix()
    except RuntimeError:
        pass
    manifest_rel = expected_mapping(source_rel, target_rel, surface) if source_rel else None
    return PlanRow(source_raw, source_rel, target_rel, manifest_rel)


def parse_plan(root: Path, plan: Path, surface: str) -> list[PlanRow]:
    rows = []
    for raw in plan.read_text(encoding="utf-8").splitlines():
        if raw:
            rows.append(make_plan_row(root, *raw.split("\t", 1), surface))
    return rows


def _classify(
    source: Path, target: Path, row: PlanRow, targets: dict, baseline: Baseline | None,
) -> tuple[str, str, BootstrapProof | None, ClassifiedState | None]:
    if source.is_symlink() or not source.is_file():
        return "unsafe", "source is missing, non-file, or symlink", None, None
    source_hash = digest(source)
    if target.is_symlink():
        return "unowned-collision", "target is a symlink", None, None
    if not target.exists():
        return "missing-and-authorized", source_hash, None, ClassifiedState(
            source_hash, "missing", None,
        )
    if not target.is_file():
        return "unowned-collision", "target is not a regular file", None, None
    target_hash = digest(target)
    state = ClassifiedState(source_hash, "file", target_hash)
    if target_hash == source_hash:
        return "current", source_hash, None, state
    prior = targets.get(row.target_rel)
    if isinstance(prior, dict) and prior.get("sha256") == target_hash:
        return "owned-repair", source_hash, None, state
    if baseline is None:
        return "unowned-collision", "existing bytes are not proven Flow-owned", None, None
    try:
        proof = baseline.prove(row, source_hash, target_hash)
        return "owned-repair", source_hash, proof, state
    except RuntimeError as exc:
        return "unowned-collision", str(exc), None, None


def classify(source: Path, target: Path, rel: str, targets: dict) -> tuple[str, str]:
    row = PlanRow(str(source), None, rel, None)
    status, detail, _proof, _state = _classify(source, target, row, targets, None)
    return status, detail


def prepare_rows(
    root: Path, rows: list[PlanRow], targets: dict,
) -> tuple[Baseline, list[PreparedRow]]:
    unique = []
    by_target: dict[str, PlanRow] = {}
    for row in rows:
        prior = by_target.get(row.target_rel)
        if prior:
            prior_source = prior.source_rel or prior.source_raw
            row_source = row.source_rel or row.source_raw
            if prior_source != row_source:
                raise RuntimeError(f"conflicting sources for recovery target: {row.target_rel}")
            continue
        by_target[row.target_rel] = row
        unique.append(row)
    prepared = []
    bootstrap = []
    for row in unique:
        try:
            source = safe_source(root, row.source_raw)
            target = safe_target(root, row.target_rel)
            status, detail, proof, state = _classify(source, target, row, targets, None)
            prepared.append(PreparedRow(row, source, target, status, detail, proof, state))
            if status == "unowned-collision" and row.manifest_rel \
                    and detail == "existing bytes are not proven Flow-owned":
                bootstrap.append(len(prepared) - 1)
        except Exception as exc:
            prepared.append(PreparedRow(row, None, None, "unsafe", str(exc), None, None))
    baseline = Baseline(root, [prepared[index].row for index in bootstrap])
    for index in bootstrap:
        item = prepared[index]
        try:
            status, detail, proof, state = _classify(
                item.source, item.target, item.row, targets, baseline,
            )
            prepared[index] = PreparedRow(
                item.row, item.source, item.target, status, detail, proof, state,
            )
        except Exception as exc:
            prepared[index] = PreparedRow(
                item.row, None, None, "unsafe", str(exc), None, None,
            )
    return baseline, prepared


def retained_path(target: Path) -> Path:
    base = target.with_name(f"{target.name}.pre-flow-repair")
    if not base.exists():
        return base
    index = 1
    while base.with_name(f"{base.name}.{index}").exists():
        index += 1
    return base.with_name(f"{base.name}.{index}")


def interrupted(stage: str, rel: str) -> bool:
    requested = os.environ.get("FF_RECOVERY_WRITE_INTERRUPT", "")
    return requested in {stage, f"{stage}:{rel}"}


def copy_atomic(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    temp = Path(raw)
    os.close(fd)
    try:
        shutil.copyfile(source, temp)
        temp.chmod(stat.S_IMODE(source.stat().st_mode))
        os.replace(temp, target)
    finally:
        temp.unlink(missing_ok=True)


def revalidate_prepared(root: Path, item: PreparedRow) -> None:
    if item.source is None or item.target is None or item.state is None:
        raise RuntimeError(item.detail)
    source = safe_source(root, item.row.source_raw)
    target = safe_target(root, item.row.target_rel)
    if source != item.source or target != item.target or digest(source) != item.state.source_hash:
        raise RuntimeError("source changed after ownership classification")
    if item.state.target_kind == "missing":
        if target.exists() or target.is_symlink():
            raise RuntimeError("target changed after ownership classification")
    elif not target.is_file() or digest(target) != item.state.target_hash:
        raise RuntimeError("target changed after ownership classification")


def revalidate_written(root: Path, item: PreparedRow) -> None:
    source = safe_source(root, item.row.source_raw)
    target = safe_target(root, item.row.target_rel)
    if source != item.source or target != item.target or not target.is_file():
        raise RuntimeError("source or target changed during replacement")
    source_hash = digest(source)
    if source_hash != item.state.source_hash or digest(target) != source_hash:
        raise RuntimeError("source or target changed during replacement")


@contextmanager
def recovery_lock(root: Path):
    identity = hashlib.sha256(os.path.normcase(str(root)).encode("utf-8")).hexdigest()
    lock_dir = Path(tempfile.gettempdir()) / "fusebase-flow-recovery-locks"
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock_path = lock_dir / f"{identity}.lock"
    with lock_path.open("a+b", buffering=0) as handle:
        if handle.seek(0, os.SEEK_END) == 0:
            handle.write(b"\0")
            os.fsync(handle.fileno())
        deadline = time.monotonic() + GIT_TIMEOUT
        while True:
            try:
                if os.name == "nt":
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("recovery writer lock timed out")
                time.sleep(0.05)
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == "nt":
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _apply_locked(
    root: Path, plan: Path, result: Path, surface: str, manifest: Path | None = None,
) -> int:
    receipt_path = root / "state/audit/recovery-owned-targets.json"
    receipt = load_receipt(receipt_path)
    targets = receipt["targets"]
    plan_rows = parse_plan(root, plan, surface)
    baseline, prepared = prepare_rows(root, plan_rows, targets)
    head_error = ""
    if any(item.proof for item in prepared):
        try:
            baseline.revalidate_head()
        except Exception as exc:
            head_error = str(exc)
    rows = []
    manifest_rows = []
    partial = False
    for item in prepared:
        row = item.row
        try:
            if item.source is None or item.target is None:
                raise RuntimeError(item.detail)
            source, target = item.source, item.target
            status, detail, proof = item.status, item.detail, item.proof
            backup = ""
            if status in {"current", "missing-and-authorized", "owned-repair"}:
                revalidate_prepared(root, item)
            if status == "owned-repair":
                if proof:
                    if head_error:
                        raise RuntimeError(head_error)
                    baseline.revalidate(proof, source, target)
                backup_path = retained_path(target)
                copy_atomic(target, backup_path)
                backup = backup_path.relative_to(root).as_posix()
                if interrupted("after-retain", row.target_rel):
                    raise RuntimeError("injected interruption after retained original")
            if status in {"missing-and-authorized", "owned-repair"}:
                if interrupted("before-replace", row.target_rel):
                    raise RuntimeError("injected interruption before replace")
                if status == "owned-repair":
                    revalidate_prepared(root, item)
                copy_atomic(source, target)
            if status in {"current", "missing-and-authorized", "owned-repair"}:
                if status != "current":
                    revalidate_written(root, item)
                else:
                    revalidate_prepared(root, item)
                target_hash = digest(target)
                prior = targets.get(row.target_rel)
                stable = isinstance(prior, dict) and prior.get("sha256") == target_hash \
                    and prior.get("surface") in SUPPORTED_SURFACES
                if not stable:
                    owned = {"sha256": target_hash, "surface": surface}
                    targets[row.target_rel] = owned
                    atomic_json_if_changed(receipt_path, receipt)
                if manifest is not None:
                    manifest_rows.append(f"{row.target_rel}  {detail}\n")
            else:
                partial = True
            rows.append((status, row.target_rel, detail, backup))
        except Exception as exc:
            partial = True
            rows.append(("unsafe", row.target_rel, str(exc), ""))
    if manifest is not None:
        encoded = "".join(sorted(manifest_rows, key=lambda row: row.encode("utf-8"))).encode("utf-8")
        if not manifest.is_file() or manifest.read_bytes() != encoded:
            atomic_bytes(manifest, encoded)
    result.write_text("".join("\t".join(item) + "\n" for item in rows), encoding="utf-8")
    return 1 if partial else 0


def apply(
    root: Path, plan: Path, result: Path, surface: str, manifest: Path | None = None,
) -> int:
    with recovery_lock(root):
        return _apply_locked(root, plan, result, surface, manifest)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--surface", required=True)
    parser.add_argument("--manifest")
    args = parser.parse_args()
    root = native_path(args.root).resolve()
    try:
        manifest = None
        if args.manifest:
            expected = SURFACE_MANIFESTS.get(args.surface)
            raw_manifest = native_path(args.manifest)
            if not raw_manifest.is_absolute():
                raw_manifest = root / raw_manifest
            manifest = Path(os.path.abspath(raw_manifest))
            if not expected or manifest != root / expected:
                raise RuntimeError("manifest path is not authorized for surface")
            reject_symlinks(root, manifest, "manifest")
        return apply(
            root, native_path(args.plan), native_path(args.result), args.surface, manifest,
        )
    except Exception as exc:
        print(f"[recovery-owned-write] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
