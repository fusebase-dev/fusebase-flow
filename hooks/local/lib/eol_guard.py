#!/usr/bin/env python3
"""Fusebase Flow — stamp-time byte-compliance guard (S3a).

A manifest is a pure function of covered-file BYTES. Nothing checked those bytes were the
canonical LF form before attesting them, so a worktree holding CRLF under an `eol=lf` pin
produced a manifest of bytes that never ship: the stamper and the verifier both read the
same wrong local copy and AGREED, and only a clean checkout disagreed. Four occurrences in
two days in this repository; `policies/module-size-baseline.txt` reddened CI twice.

CONTRACT — guard, not warning: on a violation the caller emits the diagnostic, returns
NON-ZERO, and does **NOT** write the manifest. A warning that still writes a knowingly
non-canonical attestation is observability; the wrong baseline still gets created.

ATTRIBUTE RESOLUTION: `git check-attr -z --stdin eol` — git's own resolver, one batched
process, so .gitattributes precedence (repo, subdirectory, per-pattern unset) is git's
answer and never a re-implementation of it. Only paths whose attribute RESOLVES to `lf`
are examined.

SCOPE LIMIT (deliberate): this closes the proven CRLF-under-`eol=lf` subclass and nothing
else. It does NOT settle `stamper-hashes-worktree-not-artifact` (hashing committed bytes
vs worktree bytes), which stays open because that trade gives up local-tamper detection,
and it is not a check for filters, smudge, or case-folding.

DEGRADES OPEN, LOUDLY: no git, no repo, or a check-attr that fails => the attribute cannot
be resolved, so nothing is claimed. The caller stamps and the reason is printed. A guard
that skips SILENTLY would be the original defect wearing a different hat.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

#: Callers use this as their process exit code so a refusal is distinguishable from a
#: verify verdict (0 MATCH / 1 DRIFT / 4 ABSENT) — it is the manifest-family BROKEN code.
REFUSED_RC = 2

_CHUNK = 65536


def _plain(root: Path) -> str:
    r"""Windows extended-length form (\\?\C:\…) back to the plain path: `git -C` does not
    accept the prefixed form, and the stampers resolve their root to it."""
    s = str(root)
    if s.startswith("\\\\?\\UNC\\"):
        return "\\\\" + s[8:]
    if s.startswith("\\\\?\\"):
        return s[4:]
    return s


def _resolved_lf(root: Path, rels: list[str]) -> tuple[list[str] | None, str]:
    """(paths whose `eol` attribute resolves to lf, reason-if-unresolvable)."""
    if not rels:
        return [], ""
    try:
        proc = subprocess.run(
            ["git", "-C", _plain(root), "check-attr", "-z", "--stdin", "eol"],
            input="\0".join(rels).encode("utf-8") + b"\0",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except (OSError, ValueError) as exc:
        return None, f"git unavailable ({exc.__class__.__name__})"
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", "replace").strip().splitlines()
        return None, (detail[0] if detail else f"git check-attr exit {proc.returncode}")
    fields = proc.stdout.decode("utf-8", "replace").split("\0")
    out = []
    # -z output is a flat NUL-separated stream of (path, attr, value) triplets.
    for i in range(0, len(fields) - 2, 3):
        if fields[i + 1] == "eol" and fields[i + 2] == "lf":
            out.append(fields[i])
    return out, ""


def _has_crlf(path: Path) -> bool:
    try:
        with path.open("rb") as fh:
            tail = b""   # last byte of the previous chunk: a CR/LF pair can straddle the seam
            while True:
                chunk = fh.read(_CHUNK)
                if not chunk:
                    return False
                if b"\r\n" in tail + chunk:
                    return True
                tail = chunk[-1:]
    except OSError:
        return False


def offenders(root: Path, rels: list[str]) -> tuple[list[str], str]:
    """(covered paths holding CRLF contrary to their resolved `eol=lf`, reason-if-skipped)."""
    pinned, reason = _resolved_lf(root, rels)
    if pinned is None:
        return [], reason
    return sorted(p for p in pinned if _has_crlf(root / p)), ""


def enforce(root: Path, rels: list[str], tool: str) -> int:
    """0 = write the manifest. REFUSED_RC = refuse; the caller must not write anything."""
    bad, reason = offenders(root, rels)
    if reason:
        print(f"[{tool}] eol guard NOT VERIFIED — canonical line endings could not be "
              f"resolved ({reason}); stamping the worktree bytes as-is.", file=sys.stderr)
        return 0
    if not bad:
        return 0
    print(f"[{tool}] REFUSING TO STAMP: {len(bad)} covered file(s) hold CRLF bytes contrary "
          f"to .gitattributes (resolved eol=lf).", file=sys.stderr)
    for p in bad:
        print(f"  CRLF: {p}", file=sys.stderr)
    print(f"[{tool}] The manifest was NOT written. A manifest built from these bytes attests "
          f"content that never ships: a clean checkout gets LF, so CI reads DRIFT while every "
          f"local stamp+verify agrees with itself.", file=sys.stderr)
    print(f"[{tool}] Normalize, then re-stamp:", file=sys.stderr)
    print(f"  git add --renormalize -- {' '.join(bad[:8])}"
          + (" …" if len(bad) > 8 else ""), file=sys.stderr)
    return REFUSED_RC


def _main(argv: list[str]) -> int:
    """Standalone check (no stamping): --root <dir> --manifest hook-layer|managed-content."""
    root = Path(".").resolve()
    which = "managed-content"
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--root":
            root = Path(args.pop(0)).resolve()
        elif a == "--manifest":
            which = args.pop(0)
        else:
            print(f"[eol-guard] unknown argument: {a}", file=sys.stderr)
            return REFUSED_RC
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    if which == "hook-layer":
        import hook_manifest as m
        rels = m.collect_assets(root)
    elif which == "managed-content":
        import managed_content_manifest as m
        rels = m.collect_paths(root)
    else:
        print(f"[eol-guard] unknown manifest: {which}", file=sys.stderr)
        return REFUSED_RC
    rc = enforce(root, rels, "eol-guard")
    if rc == 0:
        print(f"[eol-guard] {which}: {len(rels)} covered path(s) satisfy their eol pin.")
    return rc


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
