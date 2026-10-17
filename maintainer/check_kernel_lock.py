"""Fail when a kernel file's committed bytes differ from maintainer/kernel.lock.

The kernel is byte-locked to 5.x (release/6.0 at 17b796d3); the lock names its one authorized
change. Hashes are taken from the committed blob (git cat-file), so a CRLF checkout on Windows
does not read as a change. A kernel fix lands on 5.x first, is cherry-picked here, and updates
the lock in the same commit.
"""
import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / "maintainer" / "kernel.lock"


def committed(path: str) -> bytes | None:
    r = subprocess.run(["git", "cat-file", "blob", f"HEAD:{path}"], cwd=ROOT, capture_output=True)
    return None if r.returncode else r.stdout


def main() -> int:
    total = bad = 0
    for line in LOCK.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        want, path = line.split(None, 1)
        total += 1
        data = committed(path)
        if data is None:
            print(f"MISSING {path}")
            bad += 1
        elif (got := hashlib.sha256(data).hexdigest()) != want:
            print(f"CHANGED {path} (lock {want[:12]}, HEAD {got[:12]})")
            bad += 1
    print(f"kernel lock: {total - bad}/{total} files match")
    return 1 if bad or not total else 0


if __name__ == "__main__":
    sys.exit(main())
