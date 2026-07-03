# Problem: `$(git ls-tree …)` command substitution inside the hook intermittently HANGS under MSYS/Git-Bash

**Slug:** `msys-git-command-substitution-hang`
**Filed:** 2026-07-03
**Severity:** medium
**Status:** resolved
**Filed by:** PO per FR-15 (reliability lesson; operator requested records)

## Symptom

A `$(git ls-tree …)` command substitution inside the pre-commit hook intermittently HANGS under MSYS/Git-Bash — a Windows-native git grandchild holds the captured pipe open past exit, so the substitution never returns (rc=124 when bounded). Source of gate-timeout flakiness.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Run the hook's `$(git ls-tree)` sentinel loop under MSYS repeatedly | intermittent hang; a native git grandchild holds the pipe |
| 2 | Bound the run | rc=124 (timeout) |
| 3 | Convert to file-redirect (`git … > tmpfile`), re-run | completes cleanly |

Reproduces: intermittent (~non-deterministic; MSYS pipe-inheritance dependent — see FR-10). Sibling of `run-tests-never-completes-msys`.

## Root cause

Under MSYS/Git-Bash, a Windows-native git grandchild can inherit and hold open the pipe that backs a `$(...)` command substitution. The shell waits for EOF on that pipe, which never arrives while the grandchild lives, so the substitution hangs even though the direct child exited.

## Why it matters

- Intermittent gate/deploy timeouts that look like a slow host but are actually a stuck pipe.
- Erodes trust in the harness: a real GREEN run can false-INCONCLUSIVE.

## Mitigation / workaround

Capture git output via FILE REDIRECT instead of command substitution:

1. `git … > tmpfile` (the pattern the hook already uses for its prep extractor).
2. Read the file; no pipe stays open for a grandchild to inherit (T32).

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `180f4a1` (release v3.30.5) · tag v3.30.5 · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- A hook/script uses `$(git …)` command substitution AND runs under MSYS/Git-Bash
- Intermittent rc=124 / hang in a git-reading loop on Windows
- File path `hooks/git/pre-commit` sentinel/enumeration loops

## Guardrail (the lesson)

Under MSYS, capture git output via FILE REDIRECT (`git … > tmpfile`), not `$(...)` command substitution — a native git grandchild can hold the substitution pipe open past exit and hang the shell.

## Related

- `docs/problem-catalog/run-tests-never-completes-msys/problem.md` — the sibling (same MSYS pipe-inheritance class)
- `docs/problem-catalog/cwd-on-syspath-under-dash-S/problem.md` — shipped in the same commit (T32)

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
