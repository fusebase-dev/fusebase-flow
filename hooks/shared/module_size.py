#!/usr/bin/env python3
"""Fusebase Flow — FR-25 module-size ratchet.

Checks gated source files against policies/module-size.yml. Ratchet semantics:
an over-ceiling file not in the committed baseline is a violation; a baselined
file may shrink or hold but not grow while over the ceiling. No baseline file
=> warn-only (adoption-safe). See flow-skills/module-size-discipline/SKILL.md.

Modes: --staged (pre-commit) | --worktree (vs HEAD) | --all | --write-baseline [path]
(--write-baseline with a path re-keys ONE row — no global amnesty.)
Exit: 1 = violations under enforcement=block (and baseline present); else 0.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

POLICY_REL = "policies/module-size.yml"


def _git(args: list[str], binary: bool = False):
    proc = subprocess.run(["git"] + args, capture_output=True)
    if proc.returncode != 0:
        return None
    return proc.stdout if binary else proc.stdout.decode("utf-8", errors="replace")


def _glob_to_regex(pat: str) -> re.Pattern:
    pat = pat.replace("\\", "/").lstrip("/")
    out, i, n = [], 0, len(pat)
    while i < n:
        c = pat[i]
        if c == "*":
            if pat[i : i + 3] == "**/":
                out.append("(?:.*/)?")
                i += 3
            elif pat[i : i + 2] == "**":
                out.append(".*")
                i += 2
            else:
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def _matches(path: str, regexes: list[re.Pattern]) -> bool:
    return any(r.match(path) for r in regexes)


# Local override is ADDITIVE-ONLY on these keys. enforcement/ceiling/baseline_file
# stay committed-policy only — a gitignored file that could flip block->warn or
# blank the globs would be a silent, review-invisible kill switch for the gate.
LOCAL_OVERRIDE_ADDITIVE = ("exempt_globs", "source_globs")


def _load_policy(root: Path) -> dict | None:
    try:
        import yaml
    except ImportError:
        print("[module-size] PyYAML missing; skipping FR-25 check (pip install -r hooks/requirements.txt)", file=sys.stderr)
        return None
    policy_path = root / POLICY_REL
    if not policy_path.is_file():
        return None
    policy = yaml.safe_load(policy_path.read_text(encoding="utf-8")) or {}
    local_rel = policy.get("local_override_file") or ""
    local_path = root / local_rel if local_rel else None
    if local_path and local_path.is_file():
        local = yaml.safe_load(local_path.read_text(encoding="utf-8")) or {}
        applied, ignored = [], []
        for k, v in local.items():
            if k in LOCAL_OVERRIDE_ADDITIVE and isinstance(v, list):
                policy[k] = list(policy.get(k) or []) + v
                applied.append(k)
            else:
                ignored.append(k)
        note = f"[module-size] local override active ({local_rel}): additive {applied if applied else '[]'}"
        if ignored:
            note += f"; IGNORED non-overridable keys {ignored} (enforcement/ceiling/baseline_file are committed-policy only)"
        print(note, file=sys.stderr)
    return policy


def _read_baseline(path: Path) -> dict[str, int] | None:
    if not path.is_file():
        return None
    baseline: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(" ", 1)
        if len(parts) == 2 and parts[0].isdigit():
            baseline[parts[1]] = int(parts[0])
    return baseline


def _line_count(root: Path, path: str, staged: bool) -> int | None:
    if staged:
        blob = _git(["-C", str(root), "show", f":{path}"], binary=True)
        if blob is None:
            return None
        return len(blob.decode("utf-8", errors="replace").splitlines())
    f = root / path
    if not f.is_file():
        return None
    return len(f.read_text(encoding="utf-8", errors="replace").splitlines())


def _candidate_files(root: Path, mode: str) -> list[str]:
    # quotepath=off: octal-escaped non-ASCII names would silently miss the globs.
    if mode == "staged":
        out = _git(["-C", str(root), "-c", "core.quotepath=off", "diff", "--cached", "--name-only", "--diff-filter=ACM"])
    elif mode == "worktree":
        out = _git(["-C", str(root), "-c", "core.quotepath=off", "diff", "--name-only", "--diff-filter=ACM", "HEAD"])
    else:  # all / write-baseline
        out = _git(["-C", str(root), "-c", "core.quotepath=off", "ls-files"])
    return [p for p in (out or "").splitlines() if p.strip()]


KNOWN_ARGS = ("--staged", "--worktree", "--all", "--write-baseline")


def main(argv: list[str]) -> int:
    mode = "staged"
    flags = [a for a in argv if a.startswith("-")]
    bare = [a for a in argv if not a.startswith("-")]
    for arg in flags:
        if arg not in KNOWN_ARGS:
            print(f"[module-size] unknown argument: {arg} (expected one of {', '.join(KNOWN_ARGS)})", file=sys.stderr)
            return 2
        mode = "write_baseline" if arg == "--write-baseline" else arg.lstrip("-")
    target = None
    if bare:
        if mode != "write_baseline" or len(bare) > 1:
            print(f"[module-size] unexpected argument(s): {' '.join(bare)} (a single path is only valid after --write-baseline)", file=sys.stderr)
            return 2
        target = bare[0].replace("\\", "/")
    top = _git(["rev-parse", "--show-toplevel"])
    if not top:
        print("[module-size] not in a git repo; skipping", file=sys.stderr)
        return 0
    root = Path(top.strip())

    policy = _load_policy(root)
    if policy is None:
        # Missing policy/PyYAML degrades open: local guardrail, not a security boundary.
        return 0

    ceiling = int(policy.get("ceiling") or 800)
    enforcement = str(policy.get("enforcement") or "block")
    source_res = [_glob_to_regex(g) for g in (policy.get("source_globs") or [])]
    exempt_res = [_glob_to_regex(g) for g in (policy.get("exempt_globs") or [])]
    baseline_rel = str(policy.get("baseline_file") or "policies/module-size-baseline.txt")
    baseline_path = root / baseline_rel

    scan_mode = "all" if mode == "write_baseline" else mode
    staged = scan_mode == "staged"
    gated: list[tuple[str, int]] = []
    for path in _candidate_files(root, scan_mode):
        norm = path.replace("\\", "/")
        if not _matches(norm, source_res) or _matches(norm, exempt_res):
            continue
        lines = _line_count(root, norm, staged)
        if lines is not None:
            gated.append((norm, lines))

    if mode == "write_baseline":
        header = (
            "# FR-25 module-size baseline — over-ceiling files frozen at current size.\n"
            "# Regenerate (operator-run): bash hooks/local/check-module-size.sh --write-baseline\n"
            "# Re-key ONE file (no global amnesty): ... --write-baseline <path>\n"
        )
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        if target:
            # Single-file re-key (rename remedy / targeted refresh). Full regen
            # grandfathers EVERY current violation — keep refreshes targeted.
            existing = _read_baseline(baseline_path) or {}
            lines = _line_count(root, target, staged=False)
            if lines is None:
                existing.pop(target, None)
                action = "row removed (file absent)"
            elif lines > ceiling:
                existing[target] = lines
                action = f"frozen at {lines}"
            else:
                existing.pop(target, None)
                action = f"row removed ({lines} <= ceiling {ceiling})"
            body = "\n".join(f"{n} {p}" for p, n in sorted(existing.items()))
            baseline_path.write_text(header + (body + "\n" if body else ""), encoding="utf-8")
            print(f"[module-size] baseline re-keyed: {target} — {action} ({baseline_rel})")
            return 0
        rows = sorted((p, n) for p, n in gated if n > ceiling)
        body = "\n".join(f"{n} {p}" for p, n in rows)
        baseline_path.write_text(header + (body + "\n" if body else ""), encoding="utf-8")
        print(f"[module-size] baseline written: {baseline_rel} ({len(rows)} over-ceiling file(s), ceiling {ceiling})")
        return 0

    baseline = _read_baseline(baseline_path)
    warn_only = baseline is None or enforcement == "warn"

    violations: list[str] = []
    for path, lines in gated:
        if lines <= ceiling:
            continue
        allowed = (baseline or {}).get(path)
        if allowed is not None and lines <= allowed:
            continue
        if allowed is None:
            violations.append(f"{path}: {lines} lines > ceiling {ceiling} (not in baseline)")
        else:
            violations.append(f"{path}: {lines} lines > baseline {allowed} (ceiling {ceiling}) — over-ceiling files may not grow")

    if not violations:
        return 0

    tag = "WARN" if warn_only else "BLOCK"
    print(f"[module-size] {tag} — FR-25 module-size ratchet ({mode}):", file=sys.stderr)
    for v in violations:
        print(f"  {v}", file=sys.stderr)
    print(
        "  Remedy: extract the addition into a new module along a responsibility seam\n"
        "  (extraction is in-scope for the current task, not scope creep; not a\n"
        "  mechanical utilsN split), or get an operator exemption\n"
        "  (policies/module-size.yml exempt_globs, or operator-run --write-baseline).",
        file=sys.stderr,
    )
    if baseline is None:
        print(
            f"  Note: no baseline at {baseline_rel} — warn-only. Activate the ratchet with:\n"
            "    bash hooks/local/check-module-size.sh --write-baseline   (then commit the baseline)",
            file=sys.stderr,
        )
    return 0 if warn_only else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
