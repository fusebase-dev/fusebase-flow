#!/usr/bin/env python3
"""Fusebase Flow — FR-25 module-size ratchet.

Checks gated source files against policies/module-size.yml. Ratchet semantics:
a baselined file may shrink or hold but not grow while over the ceiling; a NEW
over-ceiling file (one crossing the ceiling in this change) is a violation. In a
change gate (--staged/--worktree) a PRE-EXISTING over-ceiling file not in the
baseline may be touched or shrunk (the refactor path) but not grown — the adoption
grace, so turning FR-25 on for a repo with pre-existing monoliths does not hard-block
the first touch. --all (audit) still reports every over-ceiling not-baselined file.
No baseline file => warn-only. See flow-skills/module-size-discipline/SKILL.md.

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
DEFAULT_BASELINE_REL = "policies/module-size-baseline.txt"


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


def _head_line_count(root: Path, path: str) -> int | None:
    # Line count at HEAD (the pre-change baseline for a change gate). None => the
    # path did not exist at HEAD (a newly added file). Used by the delta-aware
    # ratchet so a pre-existing over-ceiling file may be touched/shrunk (a refactor)
    # without blocking, while NEW over-ceiling files and GROWTH still block.
    blob = _git(["-C", str(root), "show", f"HEAD:{path}"], binary=True)
    if blob is None:
        return None
    return len(blob.decode("utf-8", errors="replace").splitlines())


def _candidate_files(root: Path, mode: str) -> list[str]:
    # quotepath=off: octal-escaped non-ASCII names would silently miss the globs.
    # --no-renames: a rename is otherwise classified R and dropped by --diff-filter=ACM,
    # so a RENAMED-and-grown monolith would escape the delta gate entirely. With
    # --no-renames git reports the move as delete+add, surfacing the destination as an
    # Added path -> the delta branch sees prev=None -> BLOCK (matches path_policy's -M
    # enumerator intent: a moved over-ceiling file is re-gated at its new path).
    if mode == "staged":
        out = _git(["-C", str(root), "-c", "core.quotepath=off", "diff", "--cached", "--no-renames", "--name-only", "--diff-filter=ACMT"])
    elif mode == "worktree":
        out = _git(["-C", str(root), "-c", "core.quotepath=off", "diff", "--no-renames", "--name-only", "--diff-filter=ACMT", "HEAD"])
    else:  # all / write-baseline
        out = _git(["-C", str(root), "-c", "core.quotepath=off", "ls-files"])
    return [p for p in (out or "").splitlines() if p.strip()]


def _head_baseline_rel(root: Path) -> str:
    # The WRITE target for --write-baseline is derived from the HEAD-committed policy,
    # never the worktree copy. policies/module-size.yml is FR-07 protected, but the
    # tool-time hook does not gate a plain Bash edit of the *worktree* file; deriving the
    # write target from the worktree would let an uncommitted `baseline_file:` redirect
    # steer --write-baseline to create a stray file (or, pre-v4.3.1, clobber one) at an
    # arbitrary path. HEAD-derivation pins the target to what is actually committed and
    # review-visible. The wrapper (check-module-size.sh) does NOT reparse the policy — it
    # consumes the resolved path this engine PRINTS (the `[module-size] baseline-path:`
    # marker), so the two cannot disagree. Any committed value that is not a plain
    # repo-relative path — absolute (POSIX or Windows-drive), UNC, Windows drive-relative
    # (`C:foo`), or repo-escaping (`..`) — falls back to the default (belt-and-suspenders
    # atop the fact that a committed policy already passed FR-07 review). A legitimate
    # relocation of baseline_file is a protected-policy edit that must be committed first.
    try:
        import yaml
    except ImportError:
        return DEFAULT_BASELINE_REL
    blob = _git(["-C", str(root), "show", "HEAD:" + POLICY_REL])
    if not blob:
        return DEFAULT_BASELINE_REL
    try:
        data = yaml.safe_load(blob)
    except Exception:
        return DEFAULT_BASELINE_REL
    if not isinstance(data, dict):            # non-mapping YAML (scalar/list) -> default
        return DEFAULT_BASELINE_REL
    bf = data.get("baseline_file")
    if not isinstance(bf, str) or not bf.strip():
        return DEFAULT_BASELINE_REL
    rel = bf.strip().replace("\\", "/")
    # Reject anything that isn't a plain repo-relative path, on EITHER platform's rules
    # (a Windows drive-relative `C:foo` is not caught by POSIX containment alone).
    import ntpath
    import posixpath
    if posixpath.isabs(rel) or ntpath.isabs(rel) or ntpath.splitdrive(rel)[0]:
        return DEFAULT_BASELINE_REL
    try:
        (root / rel).resolve().relative_to(root.resolve())
    except (ValueError, OSError, RuntimeError):
        return DEFAULT_BASELINE_REL   # repo-escaping / unresolvable -> refuse, use default
    return rel


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
        if mode == "write_baseline":
            # FAIL CLOSED for the WRITE path: --write-baseline stages a protected baseline
            # and the wrapper mints an FR-07 approval for it. If the policy can't be loaded
            # (worktree policy deleted, or PyYAML missing) the engine would otherwise no-op
            # (return 0) and leave whatever baseline is on disk — a pre-edited/attacker
            # amnesty — for the wrapper to stage and mint. Refuse so the wrapper (which
            # exits on any nonzero rc) never stages/mints an un-regenerated baseline.
            print("[module-size] refusing --write-baseline: policy policies/module-size.yml "
                  "could not be loaded (missing, or PyYAML unavailable). Adoption mints a "
                  "protected-path approval and must not proceed without a loadable committed "
                  "policy.", file=sys.stderr)
            return 2
        # Non-write modes degrade open: local guardrail, not a security boundary.
        return 0

    ceiling = int(policy.get("ceiling") or 800)
    enforcement = str(policy.get("enforcement") or "block")
    source_res = [_glob_to_regex(g) for g in (policy.get("source_globs") or [])]
    exempt_res = [_glob_to_regex(g) for g in (policy.get("exempt_globs") or [])]
    baseline_rel = str(policy.get("baseline_file") or DEFAULT_BASELINE_REL)
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
        # Pin the write target to the HEAD-committed policy, not the worktree copy: an
        # uncommitted `baseline_file:` redirect must not steer where --write-baseline
        # writes (it would otherwise create a stray file at an arbitrary path, or — before
        # the clobber guard below — overwrite one). This also keeps the write target in
        # lockstep with check-module-size.sh, which HEAD-derives baseline_file for its
        # staged-baseline scope check.
        baseline_rel = _head_baseline_rel(root)
        baseline_path = root / baseline_rel
        header = (
            "# FR-25 module-size baseline — over-ceiling files frozen at current size.\n"
            "# Regenerate (agent runs on the operator's go-ahead): bash hooks/local/check-module-size.sh --write-baseline\n"
            "# Re-key ONE file (no global amnesty): ... --write-baseline <path>\n"
        )
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        # Second layer atop the HEAD-derivation above: refuse to CLOBBER a non-baseline
        # file. Even a HEAD-committed baseline_file could, in principle, name an existing
        # tracked file; overwriting it with baseline text would be a DoS. A legitimate
        # baseline is either absent (first write) or already starts with this header;
        # anything else is refused, fail-closed.
        if baseline_path.is_file():
            head = baseline_path.read_text(encoding="utf-8", errors="replace").lstrip()
            if not head.startswith("# FR-25 module-size baseline"):
                print(f"[module-size] refusing to overwrite {baseline_rel}: it is not a module-size "
                      f"baseline — policy baseline_file may be misconfigured or redirected. Fix "
                      f"policies/module-size.yml.", file=sys.stderr)
                return 2
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
            # Machine-parseable marker: the wrapper (check-module-size.sh) consumes THIS
            # to learn where the baseline actually landed — it never reparses the policy,
            # so the wrapper's staged/mint target can't diverge from the engine's write.
            print(f"[module-size] baseline-path: {baseline_rel}")
            print(f"[module-size] baseline re-keyed: {target} — {action} ({baseline_rel})")
            return 0
        rows = sorted((p, n) for p, n in gated if n > ceiling)
        body = "\n".join(f"{n} {p}" for p, n in rows)
        baseline_path.write_text(header + (body + "\n" if body else ""), encoding="utf-8")
        print(f"[module-size] baseline-path: {baseline_rel}")   # wrapper consumes this (see re-key note)
        print(f"[module-size] baseline written: {baseline_rel} ({len(rows)} over-ceiling file(s), ceiling {ceiling})")
        return 0

    baseline = _read_baseline(baseline_path)
    warn_only = baseline is None or enforcement == "warn"
    # A change gate (pre-commit --staged / vs-HEAD --worktree) is delta-aware for
    # un-adopted files; --all is an absolute audit (no HEAD delta to compare).
    delta_gate = mode in ("staged", "worktree")

    violations: list[str] = []
    for path, lines in gated:
        if lines <= ceiling:
            continue
        allowed = (baseline or {}).get(path)
        if allowed is not None:
            # Baselined: may hold or shrink, never grow while over the ceiling.
            if lines <= allowed:
                continue
            violations.append(f"{path}: {lines} lines > baseline {allowed} (ceiling {ceiling}) — over-ceiling files may not grow")
            continue
        # Not in baseline. In a change gate, a PRE-EXISTING over-ceiling file (already
        # over the ceiling at HEAD) may be touched or shrunk (the refactor path) — only
        # a file that NEWLY crosses the ceiling, or GROWS while already over it, is a
        # violation. This is the adoption grace: an upgrade that turns FR-25 on for a
        # repo with pre-existing monoliths does not hard-block the first touch. In
        # --all (audit) any over-ceiling not-baselined file is still reported.
        if delta_gate:
            prev = _head_line_count(root, path)
            if prev is not None and prev > ceiling:
                if lines <= prev:
                    continue  # pre-existing monolith, not growing -> allow the touch
                violations.append(f"{path}: {lines} lines > previous {prev} (ceiling {ceiling}) — a pre-existing over-ceiling file may be touched or shrunk but not grown; extract the addition, or adopt+freeze it (--write-baseline)")
                continue
        violations.append(f"{path}: {lines} lines > ceiling {ceiling} (not in baseline)")

    if not violations:
        return 0

    tag = "WARN" if warn_only else "BLOCK"
    print(f"[module-size] {tag} — FR-25 module-size ratchet ({mode}):", file=sys.stderr)
    for v in violations:
        print(f"  {v}", file=sys.stderr)
    print(
        "  Remedy: extract the addition into a new module along a responsibility seam\n"
        "  (extraction is in-scope for the current task, not scope creep; not a\n"
        "  mechanical utilsN split). A PRE-EXISTING over-ceiling file may be touched or\n"
        "  shrunk without blocking — only NEW over-ceiling files and GROWTH block.\n"
        "  To adopt+freeze the current over-ceiling files (grandfather them): this is the\n"
        "  operator's decision to make (not the agent's own, to dodge a block). Once the\n"
        "  operator OKs adoption in chat, the AGENT runs the following on their behalf —\n"
        "  the operator types no command:\n"
        "    bash hooks/local/check-module-size.sh --write-baseline\n"
        f"  {baseline_rel} is an FR-07 protected path — --write-baseline auto-mints a scoped,\n"
        "  single-use approval; the agent then commits the baseline and consumes it (the\n"
        "  sanctioned FR-07 path; NOT --no-verify). Or add an exempt glob to policies/module-size.yml.",
        file=sys.stderr,
    )
    if baseline is None:
        print(
            f"  Note: no baseline at {baseline_rel} — currently warn-only. --write-baseline\n"
            "  (agent-run on the operator's go-ahead) activates the ratchet (freezes current\n"
            "  over-ceiling files at their size).",
            file=sys.stderr,
        )
    return 0 if warn_only else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
