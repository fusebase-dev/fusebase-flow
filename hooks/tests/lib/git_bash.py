"""Locate the bash a Python test should spawn: Git Bash on Windows, PATH bash elsewhere."""
from __future__ import annotations

import os
import shutil
from pathlib import Path

# TRIPWIRE: System32\bash.exe and WindowsApps\bash.exe are WSL launchers, never Git Bash.
_WSL_LAUNCHERS = ("\\windows\\system32\\", "\\windowsapps\\")


def candidates() -> list[Path]:
    found: list[Path] = []
    configured = os.environ.get("FUSEBASE_FLOW_BASH")
    if configured:
        found.append(Path(configured))
    if os.name != "nt":
        path_bash = shutil.which("bash")
        if path_bash:
            found.append(Path(path_bash))
        return found
    git = shutil.which("git")
    if git:
        for start in dict.fromkeys((Path(git), Path(git).resolve())):
            for ancestor in list(start.parents)[:4]:
                found += [ancestor / "bin" / "bash.exe", ancestor / "usr" / "bin" / "bash.exe"]
    path_bash = shutil.which("bash")
    if path_bash and not any(marker in path_bash.lower() for marker in _WSL_LAUNCHERS):
        found.append(Path(path_bash))
    local = os.environ.get("LOCALAPPDATA")
    for base in (os.environ.get("ProgramW6432"), os.environ.get("ProgramFiles"),
                 os.path.join(local, "Programs") if local else None):
        if base:
            found += [Path(base) / "Git" / "bin" / "bash.exe", Path(base) / "Git" / "usr" / "bin" / "bash.exe"]
    return list(dict.fromkeys(found))


def bash_executable(default: str | None = None) -> str:
    tried = candidates()
    for candidate in tried:
        if candidate.is_file():
            return str(candidate)
    if default is not None:
        return default
    raise RuntimeError("Git Bash is unavailable; tried: " + "; ".join(map(str, tried))
                       + f" (git on PATH: {shutil.which('git')})")
