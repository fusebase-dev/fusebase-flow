#!/usr/bin/env python3
from __future__ import annotations

import argparse
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
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


SCHEMA = 1
GIT_TIMEOUT = 15
REGULAR_GIT_MODES = {"100644", "100755"}
MANIFEST_ROW = re.compile(r"^(.+?)  ([0-9a-f]{64})$")


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


@dataclass(frozen=True)
class PlanRow:
    source_raw: str
    source_rel: str | None
    target_rel: str
    manifest_rel: str | None


@dataclass(frozen=True)
class TreeEntry:
    mode: str
    kind: str
    oid: str


@dataclass(frozen=True)
class BootstrapProof:
    head: str
    source_hash: str
    target_hash: str


@dataclass(frozen=True)
class PreparedRow:
    row: PlanRow
    source: Path | None
    target: Path | None
    status: str
    detail: str
    proof: BootstrapProof | None


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


def parse_plan(root: Path, plan: Path, surface: str) -> list[PlanRow]:
    rows = []
    for raw in plan.read_text(encoding="utf-8").splitlines():
        if not raw:
            continue
        source_raw, target_rel = raw.split("\t", 1)
        source_rel = None
        try:
            source_rel = lexical_path(root, source_raw).relative_to(root).as_posix()
        except RuntimeError:
            pass
        manifest_rel = expected_mapping(source_rel, target_rel, surface) if source_rel else None
        rows.append(PlanRow(source_raw, source_rel, target_rel, manifest_rel))
    return rows


def classify(
    source: Path, target: Path, row: PlanRow, targets: dict, baseline: Baseline,
) -> tuple[str, str, BootstrapProof | None]:
    source_hash = digest(source)
    if target.is_symlink():
        return "unowned-collision", "target is a symlink", None
    if not target.exists():
        return "missing-and-authorized", source_hash, None
    if not target.is_file():
        return "unowned-collision", "target is not a regular file", None
    target_hash = digest(target)
    if target_hash == source_hash:
        return "current", source_hash, None
    prior = targets.get(row.target_rel)
    if isinstance(prior, dict) and prior.get("sha256") == target_hash:
        return "owned-repair", source_hash, None
    try:
        proof = baseline.prove(row, source_hash, target_hash)
        return "owned-repair", source_hash, proof
    except RuntimeError as exc:
        return "unowned-collision", str(exc), None


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


def apply(root: Path, plan: Path, result: Path, surface: str) -> int:
    receipt_path = root / "state/audit/recovery-owned-targets.json"
    receipt = load_receipt(receipt_path)
    targets = receipt["targets"]
    plan_rows = parse_plan(root, plan, surface)
    baseline = Baseline(root, plan_rows)
    prepared = []
    for row in plan_rows:
        try:
            source = safe_source(root, row.source_raw)
            target = safe_target(root, row.target_rel)
            status, detail, proof = classify(source, target, row, targets, baseline)
            prepared.append(PreparedRow(row, source, target, status, detail, proof))
        except Exception as exc:
            prepared.append(PreparedRow(row, None, None, "unsafe", str(exc), None))
    head_error = ""
    if any(item.proof for item in prepared):
        try:
            baseline.revalidate_head()
        except Exception as exc:
            head_error = str(exc)
    rows = []
    partial = False
    for item in prepared:
        row = item.row
        try:
            if item.source is None or item.target is None:
                raise RuntimeError(item.detail)
            source, target = item.source, item.target
            status, detail, proof = item.status, item.detail, item.proof
            backup = ""
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
                copy_atomic(source, target)
            if status in {"current", "missing-and-authorized", "owned-repair"}:
                owned = {"sha256": digest(target), "surface": surface}
                if targets.get(row.target_rel) != owned:
                    targets[row.target_rel] = owned
                    atomic_json_if_changed(receipt_path, receipt)
            else:
                partial = True
            rows.append((status, row.target_rel, detail, backup))
        except Exception as exc:
            partial = True
            rows.append(("unsafe", row.target_rel, str(exc), ""))
    result.write_text("".join("\t".join(item) + "\n" for item in rows), encoding="utf-8")
    return 1 if partial else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--surface", required=True)
    args = parser.parse_args()
    root = native_path(args.root).resolve()
    try:
        return apply(root, native_path(args.plan), native_path(args.result), args.surface)
    except Exception as exc:
        print(f"[recovery-owned-write] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
