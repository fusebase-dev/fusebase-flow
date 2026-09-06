#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


SCHEMA = 2
CONTEXT_ENV = "FUSEBASE_FLOW_VALIDATOR_CONTEXT"
ENV_NAMES = {
    "CI",
    "HOME",
    "JAVA_HOME",
    "LANG",
    "NODE_ENV",
    "NODE_OPTIONS",
    "PATH",
    "PATHEXT",
    "PYTHONHASHSEED",
    "RUSTFLAGS",
    "VIRTUAL_ENV",
}
ENV_PREFIXES = (
    "CARGO_",
    "FUSEBASE_FLOW_",
    "GIT_CONFIG_",
    "GO",
    "LC_",
    "NPM_CONFIG_",
    "PNPM_",
    "YARN_",
)
CONFIG_NAMES = {
    ".eslintrc",
    ".eslintrc.js",
    ".eslintrc.json",
    "eslint.config.js",
    "eslint.config.mjs",
    "eslint.config.cjs",
    "pyproject.toml",
    "ruff.toml",
    "setup.cfg",
    "tox.ini",
    "tsconfig.json",
    "package.json",
}
LOCK_NAMES = {
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "bun.lock",
    "bun.lockb",
    "poetry.lock",
    "uv.lock",
    "Pipfile.lock",
    "requirements.txt",
    "Cargo.lock",
    "go.sum",
}


def run_git(root: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", *args], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", "replace").strip())
    return result.stdout


def canonical_root(raw: str) -> Path:
    root = Path(raw).resolve()
    if not (root / ".git").exists():
        raise RuntimeError(f"not a git worktree: {root}")
    return root


def auth_root(repo: Path) -> Path:
    home = Path.home().resolve()
    base = home / ("AppData/Local" if os.name == "nt" else ".local/state")
    target = (base / "fusebase-flow" / "validator-evidence").resolve()
    try:
        target.relative_to(repo)
    except ValueError:
        return target
    raise RuntimeError("validator authority resolves inside the repository")


def repo_id(root: Path) -> str:
    return hashlib.sha256(str(root).encode("utf-8")).hexdigest()


def paths(root: Path) -> tuple[Path, Path, Path]:
    base = auth_root(root)
    rid = repo_id(root)
    return base / "authority.key", base / "receipts" / f"{rid}.json", base / "pending" / f"{rid}.json"


def ensure_key(path: Path) -> bytes:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "wb") as handle:
            handle.write(secrets.token_bytes(32))
    data = path.read_bytes()
    if len(data) != 32:
        raise RuntimeError("validator authority key has invalid length")
    if os.name != "nt" and stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise RuntimeError("validator authority key permissions are too broad")
    return data


def existing_key(path: Path) -> bytes:
    if not path.is_file():
        raise RuntimeError("validator authority key is unavailable")
    return ensure_key(path)


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def path_record(path: Path, label: str, seen: set[Path] | None = None) -> dict[str, Any]:
    seen = set() if seen is None else seen
    try:
        meta = path.lstat()
    except FileNotFoundError:
        return {"path": label, "kind": "missing"}
    mode = stat.S_IMODE(meta.st_mode)
    if path.is_symlink():
        resolved = path.resolve(strict=True)
        if resolved in seen:
            raise RuntimeError(f"validator input symlink cycle: {label}")
        return {
            "path": label,
            "kind": "symlink",
            "mode": mode,
            "target": os.readlink(path),
            "resolved": path_record(resolved, str(resolved), seen),
        }
    if path.is_file():
        return {
            "path": label,
            "kind": "file",
            "mode": mode,
            "size": meta.st_size,
            "sha256": digest_file(path),
        }
    if path.is_dir():
        resolved = path.resolve(strict=True)
        if resolved in seen:
            raise RuntimeError(f"validator input directory cycle: {label}")
        entries = []
        try:
            children = sorted(path.iterdir(), key=lambda item: item.name)
        except OSError as exc:
            raise RuntimeError(f"validator input unreadable: {label}: {exc}") from exc
        for child in children:
            entries.append(path_record(child, f"{label}/{child.name}", seen | {resolved}))
        return {"path": label, "kind": "directory", "mode": mode, "entries": entries}
    raise RuntimeError(f"validator input has unsupported type: {label}")


def file_record(root: Path, rel: str) -> dict[str, Any]:
    return path_record(root / rel, rel)


def source_identity(root: Path) -> tuple[str, list[str]]:
    raw = run_git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    rels = sorted({item.decode("utf-8", "surrogateescape") for item in raw.split(b"\0") if item})
    digest = hashlib.sha256()
    for rel in rels:
        encoded = json.dumps(file_record(root, rel), sort_keys=True, separators=(",", ":"))
        digest.update(encoded.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
    return digest.hexdigest(), rels


def selected_files(root: Path, rels: list[str], names: set[str]) -> dict[str, str]:
    found: dict[str, str] = {}
    for rel in rels:
        if Path(rel).name in names and (root / rel).is_file():
            found[rel] = digest_file(root / rel)
    return found


def effective_path() -> str:
    return os.environ.get("FFVE_ORIGINAL_PATH", os.environ.get("PATH", ""))


def validator_context() -> dict[str, list[str]]:
    raw = os.environ.get(CONTEXT_ENV, "")
    if not raw:
        return {"inputs": [], "dependencies": [], "environment": [], "toolchains": []}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid {CONTEXT_ENV}: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError(f"invalid {CONTEXT_ENV}: expected object")
    allowed = {"inputs", "dependencies", "environment", "toolchains"}
    if set(parsed) - allowed:
        raise RuntimeError(f"invalid {CONTEXT_ENV}: unknown keys")
    result: dict[str, list[str]] = {}
    for key in sorted(allowed):
        values = parsed.get(key, [])
        if not isinstance(values, list) or any(not isinstance(item, str) or not item for item in values):
            raise RuntimeError(f"invalid {CONTEXT_ENV}: {key} must be nonempty strings")
        if len(values) != len(set(values)):
            raise RuntimeError(f"invalid {CONTEXT_ENV}: duplicate {key}")
        result[key] = sorted(values)
    return result


def environment_identity(extra_names: list[str]) -> dict[str, str | None]:
    result: dict[str, str | None] = {}
    for key, value in os.environ.items():
        upper = key.upper()
        if upper not in ENV_NAMES and not upper.startswith(ENV_PREFIXES) and key not in extra_names:
            continue
        result[key] = effective_path() if upper == "PATH" else value
    for key in extra_names:
        result.setdefault(key, None)
    return dict(sorted(result.items()))


def resolve_tool(token: str, root: Path) -> Path | None:
    candidate = Path(token)
    if not candidate.is_absolute():
        repo_candidate = root / candidate
        if repo_candidate.is_file():
            candidate = repo_candidate
    if candidate.is_file():
        return candidate.resolve()
    resolved = shutil.which(token, path=effective_path())
    return Path(resolved).resolve() if resolved else None


def shebang_layers(path: Path, root: Path) -> list[dict[str, Any]]:
    try:
        with path.open("rb") as handle:
            first = handle.readline(4096)
    except OSError as exc:
        raise RuntimeError(f"validator tool unreadable: {path}: {exc}") from exc
    if not first.startswith(b"#!"):
        return []
    try:
        words = shlex.split(first[2:].decode("utf-8").strip(), posix=True)
    except (UnicodeDecodeError, ValueError) as exc:
        raise RuntimeError(f"validator tool has ambiguous shebang: {path}") from exc
    layers = []
    for token in words:
        resolved = resolve_tool(token, root)
        if resolved:
            layers.append(path_record(resolved, str(resolved)))
    return layers


def command_toolchain(command: str, root: Path, declared: list[str]) -> list[dict[str, Any]]:
    try:
        words = shlex.split(command, posix=os.name != "nt")
    except ValueError as exc:
        raise RuntimeError(f"validator command is ambiguous: {command}") from exc
    if not words:
        raise RuntimeError("validator command is empty")
    candidates = [words[0], *declared]
    candidates.extend(word for word in words[1:] if resolve_tool(word, root))
    layers: list[dict[str, Any]] = []
    seen: set[Path] = set()
    for token in candidates:
        resolved = resolve_tool(token, root)
        if not resolved:
            raise RuntimeError(f"validator tool cannot be resolved: {token}")
        if resolved in seen:
            continue
        seen.add(resolved)
        record = path_record(resolved, str(resolved))
        layers.append({"token": token, "record": record})
        for shebang in shebang_layers(resolved, root):
            shebang_path = Path(str(shebang["path"]))
            if shebang_path not in seen:
                seen.add(shebang_path)
                layers.append({"token": "#!", "record": shebang})
    return layers


def declared_files(root: Path, values: list[str]) -> list[dict[str, Any]]:
    records = []
    for value in values:
        path = Path(value)
        if not path.is_absolute():
            path = root / path
        records.append(path_record(path, value))
    return records


def identity(root: Path, lint: str, typecheck: str) -> dict[str, Any]:
    source, rels = source_identity(root)
    context = validator_context()
    index = hashlib.sha256(run_git(root, "ls-files", "--stage", "-z")).hexdigest()
    head = run_git(root, "rev-parse", "HEAD").decode().strip()
    commands = {"lint": lint, "typecheck": typecheck}
    return {
        "root": str(root),
        "head": head,
        "commands": commands,
        "environment": environment_identity(context["environment"]),
        "source": source,
        "index": index,
        "configs": selected_files(root, rels, CONFIG_NAMES),
        "dependencies": selected_files(root, rels, LOCK_NAMES),
        "declared_inputs": declared_files(root, context["inputs"]),
        "declared_dependencies": declared_files(root, context["dependencies"]),
        "toolchains": {
            name: command_toolchain(value, root, context["toolchains"])
            for name, value in commands.items()
            if value
        },
    }


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temp.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")), encoding="utf-8")
    os.replace(temp, path)


def signature(key: bytes, evidence: dict[str, Any]) -> str:
    body = json.dumps(evidence, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hmac.new(key, body, hashlib.sha256).hexdigest()


def invalidate(root: Path) -> None:
    _, receipt, pending = paths(root)
    for path in (receipt, pending):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def begin(root: Path, lint: str, typecheck: str) -> str:
    key_path, receipt, pending = paths(root)
    ensure_key(key_path)
    invalidate(root)
    token = secrets.token_hex(24)
    atomic_json(
        pending,
        {"schema": SCHEMA, "token": token, "identity": identity(root, lint, typecheck)},
    )
    if receipt.exists():
        raise RuntimeError("stale validator receipt survived invalidation")
    return token


def finish(root: Path, token: str) -> Path:
    key_path, receipt, pending = paths(root)
    key = existing_key(key_path)
    saved = json.loads(pending.read_text(encoding="utf-8"))
    if saved.get("schema") != SCHEMA or not hmac.compare_digest(str(saved.get("token", "")), token):
        raise RuntimeError("validator pending token mismatch")
    original = saved["identity"]
    current = identity(root, original["commands"]["lint"], original["commands"]["typecheck"])
    confirm = identity(root, original["commands"]["lint"], original["commands"]["typecheck"])
    if original != current or current != confirm:
        invalidate(root)
        raise RuntimeError("validator-visible state changed during validation")
    evidence = {"schema": SCHEMA, "result": "success", "identity": current, "created_at": int(time.time())}
    atomic_json(receipt, {"evidence": evidence, "signature": signature(key, evidence)})
    pending.unlink(missing_ok=True)
    return receipt


def verify(root: Path, lint: str, typecheck: str) -> bool:
    key_path, receipt, _ = paths(root)
    key = existing_key(key_path)
    envelope = json.loads(receipt.read_text(encoding="utf-8"))
    evidence = envelope.get("evidence")
    supplied = str(envelope.get("signature", ""))
    if not isinstance(evidence, dict) or not hmac.compare_digest(supplied, signature(key, evidence)):
        return False
    if evidence.get("schema") != SCHEMA or evidence.get("result") != "success":
        return False
    current = identity(root, lint, typecheck)
    confirm = identity(root, lint, typecheck)
    return current == confirm == evidence.get("identity")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("begin", "finish", "verify", "invalidate", "path"))
    parser.add_argument("--root", required=True)
    parser.add_argument("--lint", default="")
    parser.add_argument("--typecheck", default="")
    parser.add_argument("--token", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = canonical_root(args.root)
        if args.action == "begin":
            print(begin(root, args.lint, args.typecheck))
        elif args.action == "finish":
            print(finish(root, args.token))
        elif args.action == "verify":
            return 0 if verify(root, args.lint, args.typecheck) else 3
        elif args.action == "invalidate":
            invalidate(root)
        else:
            print(paths(root)[1])
        return 0
    except Exception as exc:
        print(f"[validator-evidence] unavailable: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
