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
from pathlib import Path

MANIFEST_REL = "audit/managed-content-manifest.json"
SCHEMA_VERSION = 1

# TRIPWIRE (decision K14): these two lists ARE the definition of "managed content" for
# both the manifest and the upgrade engine. upgrade.sh reads them via `list-managed`;
# never re-declare them in shell. Adding a tree here puts it under classification and
# under the CI freshness gate at the same time — which is the point.
# PUBLISHER-ONLY, deliberately absent: `.claude-plugin/` and `.codex-plugin/`. Those manifests
# describe THIS repository as a distributable plugin — they carry the name `fusebase-flow`,
# Flow's own VERSION, and paths relative to Flow's root. docs/install-fusebase-cli-project.md
# states they are never copied into a consumer project; listing them here contradicted that by
# putting them in the set the upgrade engine owns and overwrites, so an upgrade could clobber a
# consumer's own (Fusebase CLI-generated) `.codex-plugin/plugin.json`. Their version parity is
# enforced by preflight §8 instead, which is publisher-side.
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

# GENERATED-UNMANAGED target-repository state: written by the consumer's own upgrade run,
# never shipped as source content. TRIPWIRE: this exclusion must survive any later addition to
# MANAGED_FILES — a managed INSTALLED_FROM would be copied FROM the source tree, so every
# consumer would inherit the publisher's provenance and their own would be overwritten.
GENERATED_UNMANAGED = ("INSTALLED_FROM",)

# Never part of the managed set: operator overrides that upgrade deliberately preserves,
# build noise, and the transient backup twins upgrade/bootstrap drop.
_EXCLUDED_DIR_NAMES = {"__pycache__", ".git", "node_modules"}
_EXCLUDED_SUFFIXES = (".pyc", ".pyo")
_BACKUP_MARKERS = (".pre-upgrade-", ".pre-bootstrap-", ".pre-refresh-")


def _excluded(rel: str) -> bool:
    name = rel.rsplit("/", 1)[-1]
    if rel in GENERATED_UNMANAGED:
        return True
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


def stamp(root: Path, out_rel: str = MANIFEST_REL) -> int:
    root = _resolve_root(root)
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


def classify(base_manifest: Path | None, local_root: Path, upstream_root: Path) -> list[dict]:
    """The K9 truth table over base B x local L x upstream U, one row per managed path.

    B is the manifest recorded by the consumer's LAST install/upgrade (what upstream shipped
    them), NOT the incoming tree. Passing the incoming tree as the base would declare every
    consumer edit `current` or `consumer-only` against the wrong reference (K13 option B).
    """
    base = load_manifest(base_manifest) if base_manifest else None
    local_root = _resolve_root(local_root)
    upstream_root = _resolve_root(upstream_root)

    local = {p: sha256_of(local_root / p) for p in collect_paths(local_root)}
    upstream = {p: sha256_of(upstream_root / p) for p in collect_paths(upstream_root)}

    rows: list[dict] = []
    # TRIPWIRE (K13b): the base manifest is NOT classifiable content — it is never in its
    # own asset list, so it would always land on `unknown-base` and pollute every report.
    # It is replaced wholesale by the base refresh that build_plan appends last.
    candidates = (set(local) | set(upstream) | set(base or {})) - {MANIFEST_REL}
    for path in sorted(candidates):
        b = (base or {}).get(path)
        loc = local.get(path)
        up = upstream.get(path)
        rows.append({"path": path, "classification": _classify_one(b, loc, up),
                     "in_base": b is not None, "in_local": loc is not None,
                     "in_upstream": up is not None})
    return rows


def _classify_one(b: str | None, loc: str | None, up: str | None) -> str:
    """One cell of the K9 table. Row numbers below are that table's rows."""
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
        return "upstream-deleted-clean" if loc == b else "upstream-deleted-dirty"
    if loc == b:
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
    # BASE REFRESH, ALWAYS LAST (decision K13b). The new base is the SOURCE tree's
    # manifest — "what upstream shipped you this time" — so the NEXT upgrade classifies
    # against reality instead of calling every 4.7.0 file consumer-divergent. Appending it
    # last matters: if it landed first, a mid-run failure would leave a base claiming
    # content that was never written.
    if not abort:
        plan.append(("copy", MANIFEST_REL))
    return plan, abort


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
                        choices=["stamp", "verify", "classify", "plan", "list-managed"])
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
    # rc 9 = ABORT (changed-by-both needs a human). Distinct from 1/2/4 so the shell can
    # tell "stop, nothing written" from a verify verdict.
    return 9 if abort else 0


if __name__ == "__main__":
    raise SystemExit(main())
