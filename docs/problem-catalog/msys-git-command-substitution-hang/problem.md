# Problem: `$(git ls-tree …)` command substitution inside the hook intermittently HANGS under MSYS/Git-Bash

**Slug:** `msys-git-command-substitution-hang`
**Filed:** 2026-07-03
**Severity:** medium
**Status:** resolved for the converted call site; class RECURRED 2026-09-10 in `secret-scan-staged` on the `v4.16.3` tagged gate (see Reproduction step 4)
**Filed by:** PO per FR-15 (reliability lesson; operator requested records)

## Symptom

A `$(git ls-tree …)` command substitution inside the pre-commit hook intermittently HANGS under MSYS/Git-Bash — a Windows-native git grandchild holds the captured pipe open past exit, so the substitution never returns (rc=124 when bounded). Source of gate-timeout flakiness.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Run the hook's `$(git ls-tree)` sentinel loop under MSYS repeatedly | intermittent hang; a native git grandchild holds the pipe |
| 2 | Bound the run | rc=124 (timeout) |
| 3 | Convert to file-redirect (`git … > tmpfile`), re-run | completes cleanly |
| 4 | `v4.16.3` tagged gate (2026-09-10), `verify-windows-msys` on `022b011` | `secret-scan-staged` hit its 1800 s bound (rc 124) after 17 of 39 rows, in the T31 block that runs the REAL `hooks/git/pre-commit` inside a throwaway repo. Same phase, same code, 98 s on the green `v4.16.2` run. `verify-gate` red, `publish` skipped, tag left immutable and unmoved. [run `34506385370`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34506385370) |

Reproduces: intermittent (~non-deterministic; MSYS pipe-inheritance dependent — see FR-10). Sibling of `run-tests-never-completes-msys`.

**Status qualifier (2026-09-10).** `resolved` covers the ONE call site that was converted to a file redirect. It does not mean the class is gone from the hook: step 4 above is a hosted-runner recurrence in a phase whose inputs were untouched by the release that observed it, and it cost a release. `secret-scan-staged` is a required release-profile phase with no headroom analysis (backlog `gate-bounds-lack-headroom`); a bound it clears at 98 s and misses at >1800 s is not a bound, it is a coin flip. Diagnose the T31 dispatch before treating a rerun as evidence.

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
