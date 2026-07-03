# Problem: `python3 -S -` (stdin script) leaves CWD on sys.path — a working-tree pathlib.py/yaml.py shadows stdlib inside the trusted wrapper

**Slug:** `cwd-on-syspath-under-dash-S`
**Filed:** 2026-07-03
**Severity:** high
**Status:** resolved
**Filed by:** PO per FR-15 (operator requested lessons "so next time we avoid such problems")

## Symptom

Even after the trusted-HEAD wrapper (T28-T31) ran under `python3 -S`, the wrapper was invoked as `python3 -S -` (reading the script from STDIN). That leaves the current directory (the mutable repo root) on `sys.path[0]`. An UNSTAGED repo-root `pathlib.py` (or a discriminating `yaml.py` shim) shadowed a stdlib/site import INSIDE the otherwise-trusted wrapper and could `os._exit(0)` to force a pass. Verified END-TO-END: a real AWS key committed to HEAD with the hook printing "all checks passed."

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Drop an unstaged repo-root `pathlib.py` that `os._exit(0)`s on import | present in working tree, unstaged |
| 2 | Commit a file containing a real AWS key (via the trusted-HEAD §2 scanner) | hook printed "all checks passed" — RED |
| 3 | Apply T32 (file-script from temp dir), re-run | hook BLOCKS on the AWS key — GREEN |

Reproduces: 3/3 RED→GREEN (independently confirmed by two reviewers — see FR-10)

## Root cause

`-S` disables site-packages but does NOT strip the current working directory from `sys.path`. For stdin (`-`) and `-c` Python, CWD (or `''` resolved to CWD) is prepended to `sys.path`, so the FIRST non-builtin import inside the trusted wrapper could resolve to a mutable working-tree file. The wrapper was trusted; its import path was not.

## Why it matters

- It defeated the entire trusted-HEAD hardening from the inside, via an UNSTAGED file — the highest-severity bypass of the roadmap.
- It was a two-reviewer catch: the ladder's last rung, invisible until adversarial review drove an end-to-end PoC.

## Mitigation / workaround

Run the §2/§3 MAIN checks as trusted FILE SCRIPTS from a fresh `mktemp` dir (T32):

1. Write the wrapper to a temp-dir file → `sys.path[0]` = script dir = temp dir; CWD never added (version-independent).
2. `PYTHONSAFEPATH=1` (3.11+) as belt-and-suspenders.
3. In-script CWD scrub via builtin `nt`/`posix` before the first non-builtin import.
4. PREPEND (not append) real site-packages so genuine PyYAML wins.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `180f4a1` (release v3.30.5) · tag v3.30.5 · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- Any `python3 -S -` / `python3 -S -c` in a hook or enforcement path (stdin/`-c` → CWD on path)
- A trusted wrapper that `import`s stdlib/site (`pathlib`, `yaml`, …) — check its `sys.path[0]`
- File path `hooks/git/pre-commit` uses stdin-piped Python for a security check

## Guardrail (the lesson)

`-S` is NOT enough. For stdin/`-c` Python the CWD is on `sys.path`. Prefer a file-script run from a trusted dir (temp), or scrub `sys.path` before the first non-builtin import; add `PYTHONSAFEPATH=1`; prepend real site-packages.

## Related

- `docs/problem-catalog/mutable-python-load-point/problem.md` — the class this is the tail of
- `docs/problem-catalog/security-check-fail-open-class/problem.md` — the umbrella lesson
- `docs/problem-catalog/msys-git-command-substitution-hang/problem.md` — the reliability fix shipped alongside (T32)

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
