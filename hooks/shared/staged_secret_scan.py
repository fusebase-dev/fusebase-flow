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
    for line in diff_text.splitlines():
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
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=str(root))
    return added_lines(proc.stdout)


def _restore_site_packages() -> None:
    """Re-add site-packages to sys.path WITHOUT importing sitecustomize/usercustomize.

    TRIPWIRE (T29): the pre-commit now invokes this helper under `python3 -S` so a
    working-tree/untracked sitecustomize.py cannot run an `os._exit(0)` at startup and
    silently disable §2. But `-S` also drops site-packages, and this scanner's imports
    reach PyYAML (secret_scanner -> policy_loader -> yaml). Add the site-packages dirs
    back via site.getsitepackages()/getusersitepackages() — these only RETURN paths;
    they do NOT run site.main(), so the startup-file import stays disabled.
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
    for p in candidates:
        if p and p not in sys.path:
            sys.path.append(p)


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
