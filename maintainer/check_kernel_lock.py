"""Fail when a kernel file's committed bytes differ from maintainer/kernel.lock.

The kernel started as 5.x's bytes (release/6.0 at 17b796d3); the lock's header names each authorized
change and each kernel fix since. Hashes are taken from the committed blob (git cat-file), so a CRLF checkout on Windows
does not read as a change. A kernel change lands on core only (the owner's decision of 2026-10-24: 5.x is frozen at
v5.11) and updates the lock in the same commit.
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
