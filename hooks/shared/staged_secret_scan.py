"""Fusebase Flow — staged-diff secret scan helper (pre-commit step 2).

Extracts ONLY added (`+`) content lines from a `git diff --cached -U0` blob and
feeds them to secret_scanner.scan(). Removed (`-`) content is leaving the repo,
and the diff's own `@@`/`+++`/`---` header lines are not committed content, so
neither is scanned. The scanner's designed-token inputs (secret-patterns.yml,
its local override, hooks/tests/fixtures/) are path-excluded at the `git diff`
level — see DELIBERATE GAP below.

decision D-A1 (docs/specs/secret-scan-and-msys-liveness-fix/spec.md).
scan() semantics are NOT touched here (fixtures 10/11 call scan() directly).

DELIBERATE GAP (D-A1): a real secret added to one of the three excluded
designed-token files is NOT caught by THIS commit scan. The exclusion is a
data-as-code scope decision — those files exist to hold fake example tokens that
otherwise self-trip the scanner. PreToolUse/UserPromptSubmit still scan freely.

KNOWN LIMITATION + the excluded-file gap are documented operator-side in
docs/compatibility.md § Secret-scan scope (PreToolUse self-trips when an agent
writes full secret-patterns.yml content; legitimate path = stage + commit).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# Designed-token inputs excluded from the staged content scan (D-A1). A `git diff`
# pathspec exclude is exact: the two policy files by path, the fixtures by prefix.
_EXCLUDE_PATHSPECS = [
    ":(exclude)policies/secret-patterns.yml",
    ":(exclude)policies/secret-patterns.local.yml",
    ":(exclude)hooks/tests/fixtures/",
]


def added_lines(diff_text: str) -> str:
    """Join the added-content lines of a unified diff, leading `+` stripped.

    Drops file headers (`+++`/`---`), hunk headers (`@@`), and every removed
    (`-`) line. Returns the added content as one newline-joined blob.
    """
    out: list[str] = []
    # Split on "\n" ONLY — NOT str.splitlines(), which ALSO breaks on Unicode/control line
    # separators (U+2028/U+2029/U+0085 NEL, \v, \f, FS/GS/RS) that git does NOT treat as line
    # boundaries. `git diff -U0` emits one physical `+` line even when its content contains
    # those bytes; splitlines() would split it and orphan the tail from its leading "+", so a
    # secret after such a byte is dropped from the scan (a bypass — flips deny->allow). Only
    # git's own "\n" delimits diff lines here.
    for line in diff_text.split("\n"):
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("@@"):
            continue
        if line.startswith("+"):
            out.append(line[1:])
    return "\n".join(out)


def staged_added_text(root: Path) -> str:
    """Return the added-content blob of the staged diff, designed-token files excluded."""
    cmd = [
        "git", "diff", "--cached", "-U0", "--",
        ".", *_EXCLUDE_PATHSPECS,
    ]
    # Force UTF-8: git emits UTF-8 diff content, but `text=True` alone decodes with
    # locale.getpreferredencoding() — cp1252 on Windows — which raises UnicodeDecodeError
    # on any byte undefined there (0x81/0x8D/0x8F/0x90/0x9D; e.g. U+2510 box-drawing corner,
    # whose UTF-8 e2 94 90 carries the undefined 0x90 — this comment stays ASCII on purpose).
    # On that failure subprocess.run's reader thread dies and leaves proc.stdout None, so the
    # scan crashes the commit (or fails open) instead of scanning. errors="replace" degrades
    # non-UTF-8 bytes to U+FFFD without masking ASCII secret tokens; `or ""` guards a None
    # stdout from any other subprocess failure.
    proc = subprocess.run(
        cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=str(root)
    )
    # FAIL-CLOSED (mirrors staged_change_paths, T27/#4): a nonzero git rc means we could not
    # reliably read the staged diff. Do NOT return an empty blob — that would silently PASS
    # the scan (fail-open). Raise; the pre-commit's §2 wrapper catches it and BLOCKS. rc0 with
    # empty stdout is the LEGITIMATE no-staged-content case and returns "" normally.
    if proc.returncode != 0:
        raise RuntimeError(
            f"staged_added_text: git diff --cached failed rc={proc.returncode} "
            "(refusing to scan an unverifiable staged diff — FR-12 fail-closed)"
        )
    return added_lines(proc.stdout or "")


def _restore_site_packages() -> None:
    """Re-add site-packages to sys.path WITHOUT importing sitecustomize/usercustomize.

    TRIPWIRE (T29): the pre-commit now invokes this helper under `python3 -S` so a
    working-tree/untracked sitecustomize.py cannot run an `os._exit(0)` at startup and
    silently disable §2. But `-S` also drops site-packages, and this scanner's imports
    reach PyYAML (secret_scanner -> policy_loader -> yaml). Add the site-packages dirs
    back via site.getsitepackages()/getusersitepackages() — these only RETURN paths;
    they do NOT run site.main(), so the startup-file import stays disabled.

    T32 (DEFENSE-IN-DEPTH #2): PREPEND site-packages (insert) rather than append, so the
    REAL PyYAML always wins over any working-tree `yaml.py`/`yaml/` shadow that might still
    sit later on sys.path — closing the discriminating-`yaml.py`-shim vector even if a
    CWD-like entry ever survived. Ordering invariant: site-packages go AFTER any leading
    trusted import dir the caller already inserted at sys.path[0] (the SEC_IMPORT_DIR /
    FR07_IMPORT_DIR seed), never ahead of it — so [trusted_dir, site-packages, stdlib] is
    preserved and the prepend never shadows the trusted temp dir's OWN modules. We insert at
    a running index that STARTS AFTER sys.path[0] to keep that first trusted entry in place.
    """
    import site
    try:
        candidates = list(site.getsitepackages())
    except Exception:
        candidates = []
    try:
        user = site.getusersitepackages()
        if user:
            candidates.append(user)
    except Exception:
        pass
    # Insert just after the leading trusted import dir (sys.path[0]), preserving it as first.
    insert_at = 1 if sys.path else 0
    for p in candidates:
        if p and p not in sys.path:
            sys.path.insert(insert_at, p)
            insert_at += 1


def main() -> int:
    root = Path.cwd()
    sys.path.insert(0, str(root / "hooks"))
    _restore_site_packages()
    try:
        from shared.secret_scanner import block_decision, scan
    except Exception:
        return 0
    matches = scan(staged_added_text(root), tool_context="git_pre_commit")
    if matches and block_decision(matches) == "deny":
        print(
            "[fusebase-flow:pre-commit] BLOCK — secret pattern in staged added lines:",
            file=sys.stderr,
        )
        for m in matches:
            print(f"  {m.pattern_id} ({m.confidence}) — redacted", file=sys.stderr)
        print(
            "Per FR-12: rotate the credential, then `git reset HEAD -- <file>` to unstage. "
            "Do NOT whitelist the value to get past this.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
