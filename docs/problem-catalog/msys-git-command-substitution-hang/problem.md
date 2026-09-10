# Problem: a command substitution that captures a git process tree HANGS under MSYS/Git-Bash

**Slug:** `msys-git-command-substitution-hang`
**Filed:** 2026-07-03
**Severity:** high (cost the `v4.16.3` release)
**Status:** class CLOSED on the gated surface at v4.16.4 (27 → 0 sites, mechanically gated); 230 sites remain OUTSIDE the gate — see § Scope of the fix
**Filed by:** PO per FR-15; reopened and re-scoped 2026-09-10 after the v4.16.3 recurrence

## Symptom

A `$(...)` command substitution whose command reaches git never returns under MSYS/Git-Bash: a
Windows-native descendant inherits the write end of the pipe backing the substitution and holds it
past the direct child's exit, so the shell waits for an EOF that never arrives. Presents as an
intermittent gate/deploy timeout (rc 124 when bounded), not as a failed assertion.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Run a `$(git ls-tree …)` sentinel loop under MSYS repeatedly | intermittent hang; a native git grandchild holds the pipe |
| 2 | Bound the run | rc=124 (timeout) |
| 3 | Convert to a file redirect (`git … > tmpfile`), re-run | completes cleanly |
| 4 | `v4.16.3` tagged gate (2026-09-10), `verify-windows-msys` on `022b011` | `secret-scan-staged` hit its 1800 s bound (rc 124) after 17 of 39 rows, between the `release-gate-self-test` row and the first T31 row — the block that builds a throwaway repo through `D="$(ph_repo)"` and captures the REAL `hooks/git/pre-commit` through `"$( ( cd … && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"`. Same phase, same code, 98 s on the green `v4.16.2` run. `verify-gate` red, `publish` skipped. [run `34506385370`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34506385370) |
| 5 | **Deterministic mechanism reproduction (v4.16.4)** — `hooks/tests/test-git-capture-guard.sh` row `retained-writer-blocks-a-command-substitution`: a script that leaves ONE descendant holding its inherited handles and then exits 3 | the enclosing `$( … )` is still open when a 10 s bound kills it, although the direct child exited. The same fault through the tempfile capture returns rc 3 in ~1 s with diagnostics intact |

Step 5 reproduces the MECHANISM deterministically. The v4.16.3 TIMING did not reproduce:
100 isolated iterations of that exact block plus a full-phase run on an MSYS host (bash 5.3.15,
git 2.55.0.windows.2) completed 39/39, worst capture 21.9 s. Which specific descendant retained the
handle on the hosted runner is UNPROVEN; the class of the capture is not.

## Root cause

A `$(...)` substitution is backed by a pipe the shell reads until EOF. EOF arrives only when EVERY
write handle is closed. Under MSYS a Windows-native process spawned somewhere below the substitution
(git, or python spawned by a hook, or anything they spawn) inherits that handle, so the direct
child's exit does not produce EOF. The shell blocks with no CPU use and no output — invisible to any
check that looks for a failed assertion, and detectable only as an outer timeout.

## Scope of the fix (the part the 2026-07-03 entry got wrong)

**"Resolved" in 2026-07-03 meant ONE converted call site and a regression grep for that site's exact
spelling.** It did not mean the class was gone, and the guard could not have said otherwise: it
matched a literal string, so any new capture — a different git subcommand, a wrapper function, a
whole-hook capture — passed it silently. That is how a phase whose inputs no release had touched
took down `v4.16.3`.

Closing it requires all four, not the first:

1. convert every capture on the surface, not the one that failed;
2. a control that rejects a NEW capture **by shell syntax**, since a wrapper function hides the
   pattern from any grep;
3. a bound at the OPERATION, so a block that does slip through is named where it happens;
4. an honest count of what is still unconverted.

| Surface | Capture sites before | After | Gated |
|---|---|---|---|
| `hooks/git/pre-commit` | 3 | 0 | yes |
| `hooks/tests/test-secret-scan-staged.sh` | 23 (1 direct, 17 via `new_repo`/`ph_repo`/`t32_red_repo`, 5 whole-hook) | 0 | yes |
| `hooks/tests/run-tests.sh` | 1 | 0 | yes |
| `hooks/git/commit-msg`, `hooks/local/lib/run-with-timeout.sh`, `hooks/tests/lib/orphan-reap.sh` | 0 | 0 | yes |
| other `hooks/tests/*.sh` | 185 | 185 | **no** |
| `hooks/local/**` operator tooling | 43 | 43 | **no** |
| `install.sh`, `docs/backlog/**` | 2 | 2 | **no** |

**230 sites are deliberately outside the gate.** Gated = what runs on every commit plus the release
harness that executes it; those are the paths where a block costs a release. The remaining 230 can
still burn a phase bound on a hosted MSYS runner — the exposure is REDUCED, not removed. Converting
them is a separate outcome; the count above is the checklist. Adding a file to
`FF_GIT_CAPTURE_GATED` in `hooks/local/check-git-capture.sh` is a one-line change.

**Historical hooks cannot be converted.** `555b897:hooks/git/pre-commit` (4 sites) and
`41a8c6d:hooks/git/pre-commit` (5 sites) are executed as RED baselines by `secret-scan-staged`.
They are immutable git objects. They are instead invoked through the bounded `run_hook`, so a block
inside one is killed at its own deadline and reaped.

## Mitigation / workaround

Capture git output via a FILE REDIRECT and read it with a shell builtin:

1. `git … > "$CAP" 2>/dev/null` — rc from `$?`, no pipe exists for a descendant to inherit.
2. `IFS= read -r VAR < "$CAP"` (single line) or `"$(<"$CAP")"` (whole file) — both are builtins.
3. Wrapper functions must SET a global, never `echo` a value the caller captures: `D="$(mk_repo)"`
   is the same hazard even though no `git` is visible at the call site.
4. Invoking a hook or any deep process tree: `ffhc_run_bounded SECS …` (tempfile capture, watchdog
   outside the capture, recorded owned-tree reap).

## Permanent fix

| Status | Detail |
|---|---|
| Partial | `180f4a1` (v3.30.5, 2026-07-03) — one call site converted; the guard matched its spelling only |
| Shipped | v4.16.4 — 27 → 0 sites on the gated surface; `hooks/local/check-git-capture.sh` + `hooks/local/lib/git-capture-scan.py` reject the class by shell syntax; `git-capture-guard` runs in the essential release profile with mutation and fault-injection rows |

## Detection — at cause, not at the wall

| Control | Fires | Where |
|---|---|---|
| `git-capture-guard` static gate | at authoring/CI, the moment a capture reaching git is introduced — direct, backtick, wrapper function, transitive, or whole-hook | `hooks/local/check-git-capture.sh`, essential release profile |
| Owner-side operation bound | ~180 s at the named hook run instead of 1800 s at the phase wall; prints the operation and the repo, and reaps the owned tree | `run_hook` in `hooks/tests/test-secret-scan-staged.sh` |
| Timeout ≠ block | a killed hook exits nonzero; `hook_blocked()` refuses to read that as "the control worked" | same file |

The 1800 s phase bound and the 30 s heartbeat observe the PHASE. They report that something hung,
never what. They are a backstop, not the control.

## Related

- `docs/problem-catalog/run-tests-never-completes-msys/problem.md` — sibling (same pipe-inheritance class)
- `docs/problem-catalog/ci-linux-msys-test-divergence/problem.md` — why MSYS is a required leg
- `docs/backlog/gate-bounds-lack-headroom/` — the phase bounds still have no measured headroom

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed; one call site converted, marked resolved | v3.30.5 (`180f4a1`) |
| 2026-09-10 | RECURRED on the `v4.16.3` tagged gate; release lost, tag left unpublished | run `34506385370` |
| 2026-09-10 | class closed on the gated surface, mechanically gated, mechanism reproduced by fault injection | v4.16.4 |
