#!/usr/bin/env python3
"""Fusebase Flow — managed-content manifest: what upstream actually shipped.

The upgrade engine could tell that a managed directory DIFFERED from upstream, but not
whether UPSTREAM changed it or the CONSUMER did — so it overwrote consumer edits. This
module records a sha256 per managed path at install/upgrade time (the "base"), and
classifies base x local x upstream into the ten states of decision K9.

CANONICAL LIST HOME (decision K14): MANAGED_DIRS / MANAGED_FILES below are the single
definition of "managed". hooks/local/upgrade.sh populates its arrays from `list-managed`
instead of declaring them inline — two definitions would eventually disagree about what
"managed" means, which is a silent correctness hole in the classifier.

Byte-stable stamp (mirrors hook_manifest.py): the manifest is a pure function of the
covered file bytes + VERSION. NO timestamps — the stamp date is git history, and CI
freshness-gates it with `stamp && git diff --exit-code`.

Exit codes: verify 0 MATCH / 1 DRIFT / 2 BROKEN / 4 ABSENT (same contract as
hook_manifest.py; 3 stays reserved for the health engine's EXCEPTION_IN_EFFECT).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

MANIFEST_REL = "audit/managed-content-manifest.json"
SCHEMA_VERSION = 1

# TRIPWIRE (decision K14): these two lists ARE the definition of "managed content" for
# both the manifest and the upgrade engine. upgrade.sh reads them via `list-managed`;
# never re-declare them in shell. Adding a tree here puts it under classification and
# under the CI freshness gate at the same time — which is the point.
# TRIPWIRE: `.claude-plugin/` and `.codex-plugin/` are PUBLISHER-ONLY and must stay absent —
# listing them would let an upgrade clobber a consumer's own plugin manifest. Version parity is
# preflight §8's job (docs/install-fusebase-cli-project.md).
MANAGED_DIRS = (
    "flow-skills", "agents", "workflows", "policies", "templates", "hooks",
)
MANAGED_FILES = (
    "FLOW_RULES.md",
    "FLOW_RULES_HISTORY.md",
    "audit/hook-layer-manifest.json",
    # K13b: the base manifest travels with the upgrade and is installed LAST, so the next
    # upgrade classifies against what THIS one actually delivered.
    MANIFEST_REL,
)

# Never part of the managed set: operator overrides that upgrade deliberately preserves,
# build noise, and the transient backup twins upgrade/bootstrap drop.
_EXCLUDED_DIR_NAMES = {"__pycache__", ".git", "node_modules"}
_EXCLUDED_SUFFIXES = (".pyc", ".pyo")
_BACKUP_MARKERS = (".pre-upgrade-", ".pre-bootstrap-", ".pre-refresh-")


def _excluded(rel: str) -> bool:
    name = rel.rsplit("/", 1)[-1]
    if any(part in _EXCLUDED_DIR_NAMES for part in rel.split("/")):
        return True
    if rel.endswith(_EXCLUDED_SUFFIXES):
        return True
    if any(marker in name for marker in _BACKUP_MARKERS):
        return True
    # `*.local.*` are operator overrides; upgrade never overwrites them, so upstream has
    # no opinion about their content and they must never classify as consumer-divergent.
    return ".local." in name


def _rel(root: Path, p: Path) -> str:
    return str(p.relative_to(root)).replace("\\", "/")


def _resolve_root(root: Path) -> Path:
    r"""Windows extended-length form so >MAX_PATH files stat normally (hook_manifest.py
    does the same; a silently-dropped file would be a coverage hole, not an error)."""
    p = Path(root).resolve()
    s = str(p)
    if os.name == "nt" and not s.startswith("\\\\?\\"):
        s = ("\\\\?\\UNC\\" + s[2:]) if s.startswith("\\\\") else "\\\\?\\" + s
        p = Path(s)
    return p


def collect_paths(root: Path) -> list[str]:
    """Every managed FILE that exists under `root`, repo-relative POSIX, sorted."""
    root = _resolve_root(root)
    out: set[str] = set()
    for d in MANAGED_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for f in base.rglob("*"):
            if not f.is_file():
                continue
            rel = _rel(root, f)
            if not _excluded(rel):
                out.add(rel)
    for f in MANAGED_FILES:
        if (root / f).is_file() and not _excluded(f):
            out.add(f)
    return sorted(out)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _flow_version(root: Path) -> str:
    vf = root / "VERSION"
    return vf.read_text(encoding="utf-8").strip() if vf.is_file() else ""


def _self_hash(schema_version, flow_version, assets: list) -> str:
    payload = json.dumps(
        {"schema_version": schema_version, "flow_version": flow_version, "assets": assets},
        sort_keys=True, separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_manifest(root: Path) -> dict:
    root = _resolve_root(root)
    flow_version = _flow_version(root)
    # TRIPWIRE: the manifest must never hash ITSELF — a self-referential entry can never
    # settle (stamping changes the file, which changes its own hash). It stays in
    # MANAGED_FILES so the upgrade engine still COPIES it; it is excluded here only.
    assets = [{"path": rel, "sha256": sha256_of(root / rel)}
              for rel in collect_paths(root) if rel != MANIFEST_REL]
    return {
        "schema_version": SCHEMA_VERSION,
        "flow_version": flow_version,
        "description": (
            "Content-hash manifest of Fusebase Flow-managed content (the trees + files "
            "hooks/local/upgrade.sh refreshes). Recorded at install/upgrade so the NEXT "
            "upgrade can tell an upstream change from a consumer edit (decision K9). "
            "Byte-stable: NO timestamps. Regenerate with "
            "hooks/local/stamp-managed-content-manifest.sh; membership resolved by "
            "managed_content_manifest.py::collect_paths."
        ),
        "asset_count": len(assets),
        "assets": assets,
        "manifest_self_sha256": _self_hash(SCHEMA_VERSION, flow_version, assets),
    }


def _eol_enforce(root: Path, rels: list[str], tool: str) -> int:
    """S3a guard, loaded lazily and degrading OPEN when it is not installed.

    TRIPWIRE: imported HERE, never at module scope. This module is the verifier the
    bootstrap source boundary runs under `python3 -I`, and -I drops the script's own
    directory from sys.path — a top-level `import eol_guard` would break that verdict.

    TRIPWIRE: a guard that cannot be LOADED must never fail the stamp. See the same tripwire
    in hook_manifest.py for the failure it caused. The net is optional; the manifest is not.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import eol_guard
    except Exception as exc:
        print(f"[{tool}] eol guard NOT VERIFIED — eol_guard.py is not loadable beside "
              f"{Path(__file__).name} ({exc.__class__.__name__}); stamping the worktree "
              f"bytes as-is.", file=sys.stderr)
        return 0
    return eol_guard.enforce(root, rels, tool)


def stamp(root: Path, out_rel: str = MANIFEST_REL) -> int:
    root = _resolve_root(root)
    # S3a: refuse BEFORE any write. The proven case is policies/module-size-baseline.txt —
    # hashed CRLF, shipped LF, reddened CI twice, invisible locally because the stamper and
    # the verifier read the same wrong bytes and agreed.
    rc = _eol_enforce(root, collect_paths(root), "managed-content")
    if rc:
        return rc
    doc = build_manifest(root)
    out_path = root / out_rel
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(doc, indent=2) + "\n")
    print(f"[managed-content] wrote {out_rel} ({doc['asset_count']} asset(s); "
          f"flow_version={doc['flow_version']})")
    return 0


def load_manifest(path: Path) -> dict[str, str] | None:
    """{repo-relative path: sha256} from a manifest file, or None if unusable."""
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
        return {a["path"]: a["sha256"] for a in doc["assets"]}
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None


def verify(root: Path, as_json: bool) -> int:
    root = _resolve_root(root)
    manifest_path = root / MANIFEST_REL
    if not manifest_path.is_file():
        result = {"verdict": "ABSENT", "reason": "manifest absent", "files": []}
        return _emit_verify(result, as_json, 4)
    try:
        doc = json.loads(manifest_path.read_text(encoding="utf-8"))
        listed = {a["path"]: a["sha256"] for a in doc["assets"]}
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return _emit_verify({"verdict": "BROKEN", "reason": "unparseable manifest",
                             "files": []}, as_json, 2)
    expected_self = doc.get("manifest_self_sha256")
    actual_self = _self_hash(doc.get("schema_version"), doc.get("flow_version", ""),
                             doc["assets"])
    if not expected_self or expected_self != actual_self:
        return _emit_verify({"verdict": "BROKEN", "reason": "manifest self-hash mismatch",
                             "files": []}, as_json, 2)

    files = []
    present = {p for p in collect_paths(root) if p != MANIFEST_REL}
    for path, sha in listed.items():
        fp = root / path
        if not fp.is_file():
            files.append({"path": path, "status": "missing"})
        elif sha256_of(fp) != sha:
            files.append({"path": path, "status": "modified"})
    for path in sorted(present - set(listed)):
        files.append({"path": path, "status": "extra"})
    verdict = "MATCH" if not files else "DRIFT"
    return _emit_verify({"verdict": verdict, "listed": len(listed), "files": files},
                        as_json, 0 if verdict == "MATCH" else 1)


def _emit_verify(result: dict, as_json: bool, rc: int) -> int:
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"[managed-content] verify: {result['verdict']} "
              f"(listed={result.get('listed', 0)} drifted={len(result.get('files', []))})")
        for f in result.get("files", [])[:50]:
            print(f"  {f['status']}: {f['path']}")
        if result.get("reason"):
            print(f"  reason: {result['reason']}")
    return rc


# Classification-only line-ending proof: docs/backlog/stamper-hashes-worktree-not-artifact/.
# TRIPWIRE: never reach this from verify() or a stamper — integrity comparison stays exact bytes.
_TIMEOUT = 30
_CONVERSION_ATTRIBUTES = {"filter", "ident", "working-tree-encoding"}
# Only this conversion vocabulary crosses into the scratch checkout; an unlisted value drops its path.
_EOL_ATTRS = (("text", {"set": "text", "unset": "-text", "auto": "text=auto"}),
              ("eol", {"unset": "-eol", "lf": "eol=lf", "crlf": "eol=crlf"}))
_AUTOCRLF = {None: "true", "true": "true", "yes": "true", "on": "true", "1": "true",
             "input": "input", "": "false", "false": "false", "no": "false", "off": "false",
             "0": "false"}
_EOL_CONFIG = {"native": "native", "lf": "lf", "crlf": "crlf"}


def _crlf(text: bytes) -> bytes:
    return text.replace(b"\n", b"\r\n")


def _lf_text(local: bytes) -> bytes | None:
    """The unique C (no CR, no NUL, >= 1 LF) with `local` in {C, R(C)}, else None."""
    lf = local.replace(b"\r\n", b"\n")
    bad = b"\0" in lf or b"\r" in lf or b"\n" not in lf
    return None if bad or local not in (lf, _crlf(lf)) else lf


def _safe_rel(root: Path, rel: str) -> bool:
    parts = rel.split("/")
    if rel != rel.strip() or any(p in ("", ".", "..") for p in parts) \
            or any(ord(ch) < 0x20 or ch in "\x7f\\" for ch in rel):
        return False
    try:
        rel.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return not any(root.joinpath(*parts[:n + 1]).is_symlink() for n in range(len(parts)))


def _git(cwd: list[str], args: list[str], stdin: bytes | None = None,
         rcs: tuple[int, ...] = (0,), env: dict[str, str] | None = None) -> bytes:
    feed = {"input": stdin} if stdin is not None else {"stdin": subprocess.DEVNULL}
    done = subprocess.run(["git", *cwd, *args], capture_output=True, env=env, timeout=_TIMEOUT, **feed)
    if done.returncode not in rcs:
        raise ValueError(f"git {args[0]} rc={done.returncode}")
    return done.stdout


def _blobs(cwd: list[str], oids: list[str]) -> dict[str, bytes]:
    out = _git(cwd, ["cat-file", "--batch"], "".join(o + "\n" for o in oids).encode("ascii"))
    pos, blobs = 0, {}
    for oid in oids:
        end = out.index(b"\n", pos)
        head = out[pos:end].split()
        size = int(head[2]) if len(head) == 3 and head[2].isdigit() else -1
        if size < 0 or head[0].decode("ascii") != oid or head[1] != b"blob" \
                or out[end + 1 + size:end + 2 + size] != b"\n":
            raise ValueError(f"unexpected cat-file record for {oid}")
        blobs[oid], pos = out[end + 1:end + 1 + size], end + 2 + size
    if pos != len(out):
        raise ValueError("trailing cat-file output")
    return blobs


def _checkout_equals_local(cwd: list[str], repo: dict[str, str], same: list[str],
                           pending: dict[str, tuple[bytes, bytes]]) -> set[str]:
    """Paths where git's own checkout of C reproduces the local bytes exactly.

    TRIPWIRE: consumer attributes and config are read ONCE here and carried on as DATA; the
    scratch repository the checkout runs in reads neither, so a consumer filter driver can
    never be NAMED in the converting process, let alone executed, whatever lands mid-run."""
    fields = _git(cwd, ["check-attr", "--all", "-z", "--stdin"],
                  "".join(repo[rel] + "\0" for rel in same).encode("utf-8")).split(b"\0")
    carried: dict[str, dict[str, str]] = {}
    for i in range(0, len(fields) - 2, 3):
        path, name, value = (f.decode("utf-8", "surrogateescape") for f in fields[i:i + 3])
        carried.setdefault(path, {})[name] = value
    specs: dict[str, str] = {}
    for rel in same:
        at = carried.get(repo[rel], {})
        words = [t.get(at[n]) for n, t in _EOL_ATTRS if n in at]
        # TRIPWIRE: conversion attributes block on PRESENCE, never on value (recovery-owned-write.py).
        if not _CONVERSION_ATTRIBUTES & set(at) and None not in words:
            specs[rel] = " ".join(words)
    if not specs:
        return set()
    # TRIPWIRE: --null, and split on NUL. A config VALUE may contain a newline, so a line-split
    # record boundary is forgeable: one core.eol can mint a second core.autocrlf setting.
    records = _git(cwd, ["config", "--null", "--get-regexp", r"^core\.(autocrlf|eol)$"],
                   rcs=(0, 1)).decode("utf-8", "surrogateescape").split("\0")
    if records.pop():
        raise ValueError("unterminated git config record")
    cfg: dict[str, str | None] = {"core.autocrlf": "false", "core.eol": "native"}
    for rec in records:
        key, sep, value = rec.partition("\n")     # no newline => valueless, git's implicit true
        cfg[key] = value.lower() if sep else None
    config = ["-c", "core.autocrlf=" + _AUTOCRLF[cfg["core.autocrlf"]],
              "-c", "core.eol=" + _EOL_CONFIG[cfg["core.eol"]]]
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_CONFIG_SYSTEM=os.devnull, GIT_ATTR_NOSYSTEM="1")
    matched, order = set(), sorted(specs)
    with tempfile.TemporaryDirectory() as scratch:
        box = Path(scratch)
        _git([], ["init", "-q", "--template=", str(box)], env=env)
        (box / ".git/info").mkdir(parents=True, exist_ok=True)
        (box / ".git/info/attributes").write_bytes(
            "".join(f"p/{n} {specs[r]}\n" for n, r in enumerate(order) if specs[r]).encode("utf-8"))
        (box / "p").mkdir()
        for n, rel in enumerate(order):
            (box / "p" / str(n)).write_bytes(pending[rel][1])
        box_cwd = ["-C", str(box), "-c", f"core.attributesFile={(box / 'none').as_posix()}", *config]
        _git(box_cwd, ["add", "--", "p"], env=env)
        _git(box_cwd, ["checkout-index", "-a", "--prefix=out/"], env=env)
        for n, rel in enumerate(order):
            written = (box / "out" / "p" / str(n)).read_bytes()
            if written not in (pending[rel][1], _crlf(pending[rel][1])):
                raise ValueError(f"checkout of {rel} is neither the LF nor the CRLF form")
            if written == pending[rel][0]:
                matched.add(rel)
    return matched


def _git_confirm(git_root: Path, pending: dict[str, tuple[bytes, bytes]]) -> set[str]:
    lines = _git(["-C", str(git_root)], ["rev-parse", "--show-cdup", "--show-prefix",
                                         "--verify", "HEAD^{commit}"]).decode("utf-8").split("\n")
    # TRIPWIRE: refuse, never trim - a newline in a directory name shifts these positional fields.
    if len(lines) != 4 or lines[3] or len(lines[2]) not in (40, 64) \
            or any(ch not in "0123456789abcdef" for ch in lines[2]):
        raise ValueError("git rev-parse did not return exactly cdup, prefix and a commit")
    cdup, prefix, head = lines[:3]
    cwd = ["-C", str(git_root)] + (["-C", cdup] if cdup else [])
    repo = {rel: prefix + rel for rel in pending}
    wanted = {path: rel for rel, path in repo.items()}
    tops = sorted({prefix + rel.split("/", 1)[0] for rel in pending})
    listing = _git(["--literal-pathspecs", *cwd], ["ls-tree", "-rz", "--full-tree", head, "--", *tops])
    oids: dict[str, str] = {}
    for raw in listing.split(b"\0"):
        if not raw:
            continue
        meta, path = raw.split(b"\t", 1)
        mode, kind, oid = meta.split()
        rel = wanted.get(path.decode("utf-8", "surrogateescape"))
        if rel is not None and mode in (b"100644", b"100755") and kind == b"blob":
            oids[rel] = oid.decode("ascii")
    blobs = _blobs(cwd, sorted(set(oids.values()))) if oids else {}
    same = sorted(rel for rel, oid in oids.items() if blobs[oid] == pending[rel][1])
    return _checkout_equals_local(cwd, repo, same, pending) if same else set()


def _eol_proven(local_root: Path, git_root: Path, base: dict[str, str],
                local: dict[str, str], paths: list[str]) -> set[str]:
    """Paths whose local bytes equal their base only through git's own checkout conversion.
    Needs C = the pinned HEAD regular-file blob, B in {H(C), H(R(C))}, L in {C, R(C)}, no
    conversion attribute, and git's checkout of C == L. Missing evidence proves nothing."""
    pending: dict[str, tuple[bytes, bytes]] = {}
    for rel in paths:
        try:
            data = (local_root / rel).read_bytes() if _safe_rel(local_root, rel) else None
        except OSError:
            data = None
        lf = _lf_text(data) if data is not None else None
        # TRIPWIRE: the installed manifest digest is the anchor, never consumer HEAD - a consumer
        # can commit an edit without changing the installed base.
        if lf is None or hashlib.sha256(data).hexdigest() != local[rel] or base[rel] not in (
                hashlib.sha256(lf).hexdigest(), hashlib.sha256(_crlf(lf)).hexdigest()):
            continue
        pending[rel] = (data, lf)
    if not pending:
        return set()
    try:
        proven = _git_confirm(git_root, pending)
        # TRIPWIRE: the proof is NOT atomic. An edit landing WHILE git ran must not inherit the
        # verdict, so local bytes and path safety are re-proved AFTER the evidence, not only before.
        return {rel for rel in proven if _safe_rel(local_root, rel)
                and (local_root / rel).read_bytes() == pending[rel][0]}
    except Exception:
        # TRIPWIRE: any failure means NO exception (the pre-proof verdict), never a classifier crash.
        return set()


def classify(base_manifest: Path | None, local_root: Path, upstream_root: Path) -> list[dict]:
    """The K9 truth table over base B x local L x upstream U, one row per managed path.

    B is the manifest recorded by the consumer's LAST install/upgrade (what upstream shipped
    them), NOT the incoming tree. Passing the incoming tree as the base would declare every
    consumer edit `current` or `consumer-only` against the wrong reference (K13 option B).
    L == B may also hold through `_eol_proven`; B and the manifest are never rewritten here.
    """
    base = load_manifest(base_manifest) if base_manifest else None
    git_root = Path(local_root).resolve()
    local_root = _resolve_root(local_root)
    upstream_root = _resolve_root(upstream_root)

    local = {p: sha256_of(local_root / p) for p in collect_paths(local_root)}
    upstream = {p: sha256_of(upstream_root / p) for p in collect_paths(upstream_root)}

    rows: list[dict] = []
    # TRIPWIRE (K13b): the base manifest is NOT classifiable content — it is never in its
    # own asset list, so it would always land on `unknown-base` and pollute every report.
    # It is replaced wholesale by the base refresh that build_plan appends last.
    candidates = (set(local) | set(upstream) | set(base or {})) - {MANIFEST_REL}
    mismatched = sorted(p for p in candidates if base and p in base and p in local
                        and local[p] != base[p] and local[p] != upstream.get(p))
    proven = _eol_proven(local_root, git_root, base, local, mismatched) if mismatched else set()
    for path in sorted(candidates):
        b = (base or {}).get(path)
        loc = local.get(path)
        up = upstream.get(path)
        matches_base = loc is not None and (loc == b or path in proven)
        rows.append({"path": path, "classification": _classify_one(b, loc, up, matches_base),
                     "in_base": b is not None, "in_local": loc is not None,
                     "in_upstream": up is not None, "eol_proven": path in proven})
    return rows


def _classify_one(b: str | None, loc: str | None, up: str | None,
                  local_matches_base: bool | None = None) -> str:
    """One cell of the K9 table. Row numbers below are that table's rows."""
    if local_matches_base is None:
        local_matches_base = loc is not None and loc == b
    if loc is not None and up is not None and loc == up:
        return "current"                                          # row 1
    if b is None:
        if loc is not None and up is None:
            return "consumer-added"                               # row 7
        if loc is None and up is not None:
            return "upstream-added"                               # row 8
        return "unknown-base"                                     # row 10
    if loc is None:
        # Base had it, local does not. Upstream still ships it -> the consumer deleted it.
        return "consumer-deleted" if up is not None else "current"  # row 9 / both gone
    if up is None:
        # Upstream dropped it. Clean iff the consumer never touched it (row 5 vs row 6).
        return "upstream-deleted-clean" if local_matches_base else "upstream-deleted-dirty"
    if local_matches_base:
        return "upstream-only"                                    # row 2
    if up == b:
        return "consumer-only"                                    # row 3
    return "changed-by-both"                                      # row 4


#: K9's action columns. `auto_overwrite` False means --auto-yes must PRESERVE.
CLASSIFICATIONS = {
    "current":                 {"auto_overwrite": False, "report": False, "abort": False},
    "upstream-only":           {"auto_overwrite": True,  "report": False, "abort": False},
    "consumer-only":           {"auto_overwrite": False, "report": True,  "abort": False},
    "changed-by-both":         {"auto_overwrite": False, "report": True,  "abort": True},
    "upstream-deleted-clean":  {"auto_overwrite": True,  "report": False, "abort": False},
    "upstream-deleted-dirty":  {"auto_overwrite": False, "report": True,  "abort": False},
    "consumer-added":          {"auto_overwrite": False, "report": False, "abort": False},
    "upstream-added":          {"auto_overwrite": True,  "report": False, "abort": False},
    "consumer-deleted":        {"auto_overwrite": False, "report": True,  "abort": False},
    "unknown-base":            {"auto_overwrite": False, "report": True,  "abort": False},
}


#: Attended-mode default decision per conflict class (decision K9's "Attended" column).
ATTENDED_DEFAULTS = {
    "consumer-only": "keep",
    "changed-by-both": "abort",
    "upstream-deleted-dirty": "keep",
    "consumer-deleted": "keep",          # leave absent
    "unknown-base": "keep",
}
#: Groups that are safe to collapse to a count in the report (AC15).
_SAFE_GROUPS = ("current", "upstream-only", "upstream-added",
                "upstream-deleted-clean", "consumer-added")


def build_plan(rows: list[dict], *, auto_yes: bool,
               decisions: dict[str, str] | None = None) -> tuple[list[tuple[str, str]], bool]:
    """(ordered [(op, path)], abort) where op is copy | delete | skip.

    `auto_yes` applies K9's unattended column verbatim: the four protected classes are
    PRESERVED, and `changed-by-both` ABORTS. Attended runs pass `decisions` (per class:
    keep | overwrite | abort) collected by the shell, defaulting to ATTENDED_DEFAULTS.
    """
    decisions = decisions or {}
    plan: list[tuple[str, str]] = []
    abort = False
    for row in rows:
        cls = row["classification"]
        cfg = CLASSIFICATIONS.get(cls, {"auto_overwrite": False, "abort": False})
        if auto_yes:
            choice = "overwrite" if cfg["auto_overwrite"] else "keep"
            if cfg["abort"]:
                abort = True
        else:
            choice = decisions.get(cls, ATTENDED_DEFAULTS.get(
                cls, "overwrite" if cfg["auto_overwrite"] else "keep"))
            if choice == "abort":
                abort = True
        if choice == "overwrite":
            # Upstream dropped the file -> the "overwrite" action is a DELETE.
            op = "delete" if not row["in_upstream"] else "copy"
        else:
            op = "skip"
        plan.append((op, row["path"]))
    # BASE REFRESH, ALWAYS LAST (decision K13b): the new base is the SOURCE tree's manifest,
    # so the NEXT upgrade classifies against reality. Order is load-bearing — landing it
    # first would let a mid-run failure leave a base claiming content that was never written.
    if not abort:
        plan.append(("copy", MANIFEST_REL))
    return plan, abort


def unclassified_preserved(rows: list[dict], plan: list[tuple[str, str]]) -> list[str]:
    """Paths this run PRESERVED because it could not classify them (decision N6-D1).

    `unknown-base` (K9 row 10) is the only class meaning "no historical base entry existed
    for this path", and only a `skip` op means the run left the local bytes alone. Both
    halves are required: an attended run may choose `overwrite` for `unknown-base`, and that
    path IS then delivered, so the base has earned the right to record it.

    TRIPWIRE — the scope is exactly this intersection. `consumer-only` is EARNED (upstream
    did not change the file, so upstream's manifest entry equals the old base's) and must
    stay recorded. Widening this to "everything preserved" would strip legitimate entries
    and re-manufacture the missing-base state N6 exists to kill.
    """
    skipped = {path for op, path in plan if op == "skip"}
    return [r["path"] for r in rows
            if r["classification"] == "unknown-base" and r["path"] in skipped]


def prune_base(manifest_path: Path, omit: set[str],
               prior_base: str = "", prior_version: str = "") -> int:
    """Drop `omit` entries from a written base manifest and RE-SEAL it (decision N6-D1).

    WHY (N6): build_plan appends the base refresh as a wholesale copy of the SOURCE tree's
    manifest — "what upstream shipped you this time" (K13b). That claim is true only for
    paths the run actually applied. For a path preserved as `unknown-base` it records
    UPSTREAM's bytes as the CONSUMER's history, so the next run reads L != B, U == B and
    reports `consumer-only` — "YOU changed these" — for a file the consumer never touched;
    one release later it is `changed-by-both` and the upgrade aborts. Measured against the
    v4.12.0 engine on hooks/local/control.sh.

    A missing entry re-classifies as `unknown-base`: preserved AND REPORTED every run, K9's
    designed safe residue. A false entry is silent and permanent. That asymmetry is the
    decision; see docs/specs/half-apply-self-seals/decisions.md N6-D1.

    TRIPWIRE — asset_count and manifest_self_sha256 MUST be recomputed here. `verify` checks
    the self-hash before anything else and returns BROKEN on a mismatch, which would make
    every downstream integrity check useless. Pruned paths then report `extra` instead of
    `modified`; both are DRIFT.
    """
    try:
        doc = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
        assets = [a for a in doc["assets"] if a["path"] not in omit]
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return 2
    pruned = len(doc["assets"]) - len(assets)
    if not pruned and not prior_base:
        return 0
    if pruned:
        doc["assets"] = assets
        doc["asset_count"] = len(assets)
        doc["manifest_self_sha256"] = _self_hash(
            doc.get("schema_version"), doc.get("flow_version", ""), assets)
    if prior_base:
        # DECISION N6-D2 — the forward-only half. A poisoned base and a healthy one are
        # locally INDISTINGUISHABLE: both are present, self-consistent, and byte-identical to
        # a published upstream manifest, because K13b installs the source tree's manifest as
        # the new base after EVERY successful upgrade. The one fact that separates them is
        # whether a base existed BEFORE the run that wrote this one, and nothing in the tree
        # recorded it. This records it.
        #
        # TRIPWIRE — ADDITIVE ONLY, and it must stay that way. `_self_hash` covers
        # schema_version + flow_version + assets, so a new TOP-LEVEL key is invisible to
        # `verify`. Never move provenance inside `assets` and never fold it into the
        # self-hash: older engines read this file and must keep parsing it.
        #
        # TRIPWIRE — this reaches ZERO already-affected installs, by construction: their base
        # was written by an engine that predates this code. They are reached out-of-band by
        # docs/ADVISORY-2026-08-20-missing-base-upgrade.md. Do not let anything claim
        # otherwise.
        doc["base_provenance"] = {
            "prior_base": prior_base,
            "prior_version": prior_version,
            "preserved_unclassified": len(omit),
        }
    with Path(manifest_path).open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(doc, indent=2) + "\n")
    return 0


def render_report(rows: list[dict], *, auto_yes: bool, backup_suffix: str,
                  resume_command: str, aborting: bool = False) -> str:
    """The AC15 conflict report.

    Safe groups collapse to a count; every path that needs a human decision is listed in
    full and NEVER elided behind "N files" — being told only that "some files differed"
    was the consumer's actual complaint. Backup dir named; exact resume command last.
    """
    by_class: dict[str, list[str]] = {}
    for row in rows:
        by_class.setdefault(row["classification"], []).append(row["path"])

    out: list[str] = ["", "[upgrade] Managed-content classification:"]
    for cls in _SAFE_GROUPS:
        paths = by_class.get(cls)
        if paths:
            out.append(f"  {cls:<24} {len(paths):>4} file(s)")
    eol_only = sum(1 for row in rows if row.get("eol_proven"))
    if eol_only:
        out.append(f"  {'(line endings only)':<24} {eol_only:>4} file(s) matched the recorded base "
                   f"through git's own checkout conversion")

    needs_decision = [c for c, cfg in CLASSIFICATIONS.items() if cfg["report"]]
    conflicts = {c: by_class[c] for c in needs_decision if by_class.get(c)}
    if not conflicts:
        out.append("  (no consumer divergence — every managed path was safe to refresh)")
    for cls, paths in conflicts.items():
        verb = {
            "consumer-only": "YOU changed these; upstream did not — PRESERVED",
            "changed-by-both": "BOTH changed these — cannot be merged automatically",
            "upstream-deleted-dirty": "upstream removed these but YOU changed them — PRESERVED",
            "consumer-deleted": "YOU deleted these; upstream still ships them — LEFT ABSENT",
            "unknown-base": "no recorded base for these — PRESERVED (cannot tell who changed them)",
        }.get(cls, cls)
        out.append("")
        out.append(f"  {cls} ({len(paths)}) — {verb}:")
        out.extend(f"    - {p}" for p in paths)

    out.append("")
    out.append(f"[upgrade] Backups of every touched directory: *.pre-upgrade-{backup_suffix}")
    if aborting:
        out.append("[upgrade] ABORTED: 'changed-by-both' paths need a human decision and")
        out.append("          --auto-yes must not guess. NOTHING was written.")
        out.append("          Reconcile the files listed above (or take upstream's copy from")
        out.append(f"          the source clone), then resume with:")
    else:
        out.append("[upgrade] Resume / re-run with:")
    out.append(f"    {resume_command}")
    return "\n".join(out)


def _git_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip()).resolve()
    except Exception:
        return Path.cwd().resolve()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="managed_content_manifest.py")
    parser.add_argument("command",
                        choices=["stamp", "verify", "classify", "plan", "list-managed",
                                 "prune-base"])
    parser.add_argument("--root", default=None)
    parser.add_argument("--out", default=MANIFEST_REL, help="stamp: manifest destination")
    parser.add_argument("--base", default=None, help="classify: base manifest path")
    parser.add_argument("--upstream", default=None, help="classify: upstream tree root")
    parser.add_argument("--dirs", action="store_true", help="list-managed: dirs only")
    parser.add_argument("--files", action="store_true", help="list-managed: files only")
    parser.add_argument("--auto-yes", action="store_true", help="plan: unattended K9 column")
    parser.add_argument("--decisions", default="",
                        help="plan: attended choices, e.g. consumer-only=keep,changed-by-both=abort")
    parser.add_argument("--plan-file", default=None, help="plan: write the TSV apply plan here")
    parser.add_argument("--manifest", default=None, help="prune-base: manifest to re-seal")
    parser.add_argument("--omit-file", default=None,
                        help="prune-base: newline-separated paths to drop from the manifest")
    parser.add_argument("--prior-base", default="",
                        help="prune-base: present|synthesized|absent — what the run started from")
    parser.add_argument("--prior-version", default="",
                        help="prune-base: the VERSION the tree held before this run")
    parser.add_argument("--report-file", default=None, help="plan: write the AC15 report here")
    parser.add_argument("--backup-suffix", default="<TS>", help="plan: report the backup stamp")
    parser.add_argument("--resume-command", default="bash hooks/local/upgrade.sh",
                        help="plan: exact command printed last in the report")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve() if args.root else _git_root()

    if args.command == "list-managed":
        if args.dirs:
            print("\n".join(MANAGED_DIRS))
        elif args.files:
            print("\n".join(MANAGED_FILES))
        else:
            for d in MANAGED_DIRS:
                print(f"dir\t{d}")
            for f in MANAGED_FILES:
                print(f"file\t{f}")
        return 0
    if args.command == "stamp":
        return stamp(root, args.out)
    if args.command == "verify":
        return verify(root, args.json)
    if args.command == "prune-base":
        if not args.manifest or not args.omit_file:
            print("[managed-content] prune-base requires --manifest and --omit-file",
                  file=sys.stderr)
            return 2
        try:
            omit = {ln.strip() for ln in
                    Path(args.omit_file).read_text(encoding="utf-8").splitlines() if ln.strip()}
        except OSError:
            return 0
        return prune_base(Path(args.manifest), omit,
                          prior_base=args.prior_base, prior_version=args.prior_version)

    if not args.upstream:
        print(f"[managed-content] {args.command} requires --upstream <tree>", file=sys.stderr)
        return 2
    base = Path(args.base) if args.base else None
    if base is not None and not base.is_file():
        base = None                     # no recorded base -> K9 row 10 (unknown-base)
    rows = classify(base, root, Path(args.upstream))

    if args.command == "classify":
        if args.json:
            print(json.dumps(rows, indent=2))
        else:
            for r in rows:
                print(f"{r['classification']}\t{r['path']}")
        return 0

    decisions = {}
    for item in (args.decisions or "").split(","):
        if "=" in item:
            k, v = item.split("=", 1)
            decisions[k.strip()] = v.strip()
    plan, abort = build_plan(rows, auto_yes=args.auto_yes, decisions=decisions)
    report = render_report(rows, auto_yes=args.auto_yes, backup_suffix=args.backup_suffix,
                           resume_command=args.resume_command, aborting=abort)
    if args.report_file:
        Path(args.report_file).write_text(report + "\n", encoding="utf-8", newline="\n")
    else:
        print(report)
    if args.plan_file and not abort:
        Path(args.plan_file).write_text(
            "".join(f"{op}\t{path}\n" for op, path in plan), encoding="utf-8", newline="\n")
        # N6-D1 sidecar, NOT a plan column. TRIPWIRE: the plan's TSV shape is FROZEN —
        # hooks/local/upgrade.sh reads it with `read -r op path`, and the engine consuming
        # this plan is the consumer's INSTALLED one while the module is the SOURCE's
        # (upgrade.sh:312), so a third field would be swallowed into $path by every older
        # engine. A sidecar is invisible to them: they simply do not prune, which is
        # exactly today's behaviour.
        Path(args.plan_file + ".unclassified").write_text(
            "".join(p + "\n" for p in unclassified_preserved(rows, plan)),
            encoding="utf-8", newline="\n")
    # rc 9 = ABORT (changed-by-both needs a human). Distinct from 1/2/4 so the shell can
    # tell "stop, nothing written" from a verify verdict.
    return 9 if abort else 0


if __name__ == "__main__":
    raise SystemExit(main())
