# Handoff - v4.16.0 tagged, gate RED, nothing published

**Source/tag:** `a62e362b070c02b51950d7573b2533bd67603643` / `v4.16.0` (annotated `0df42475ca042875e5d92e0fb32f22008f7eb00d`). **Status:** BLOCKED-AT-release-gate. [Run `34438811255`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34438811255): `verify-windows-msys` SUCCESS 682/682, `verify-linux` FAILURE 681/682, `verify-gate` FAILURE, `publish` SKIPPED. No GitHub Release exists for `v4.16.0`. Published latest is still [v4.15.3](https://github.com/fusebase-dev/fusebase-flow/releases/tag/v4.15.3). `v4.16.0` is an immutable unpublished tagged tree; its fingerprint row is in `docs/release-fingerprints.md`.

## The one failing predicate

| Field | Value |
|---|---|
| Row | `hop-log-truth s1-missing-python3-reports-untouched-not-unknown` |
| Owner | `hooks/tests/test-hop-log-truthfulness.sh:307-333` (D1) |
| Observed (Linux) | recovery exited **127**, channel state `unknown`, trailer rendered "cannot say" |
| Expected | rc 2, state `unavailable`, trailer says settings were not touched |
| Platform | Linux only. Windows/MSYS passed the same row; local MSYS was 682/682 at `1555e79`. |
| Production implicated? | **No evidence either way.** The row never reached `post-fusebase-update.sh`'s python3-less branch on Linux, so it neither confirms nor refutes the documented rc 2. |

**Root cause.** `path_without_python3()` (`:307-315`) enumerates `$PATH` and drops every directory containing `python3`. On Linux `python3` and the shell/coreutils share `/usr/bin`, so pruning removes `bash`, `grep`, `sed` and friends too and the subshell dies `command not found` (127) before the script runs. `hooks/tests/lib/minimal-path-fixture.sh:18-20` carries the tripwire this violates verbatim: *"never enumerate, mirror, symlink or copy PATH directories (AC7). python3 and git share /usr/bin on Linux."* Same failure class as T67 (`docs/problem-catalog/ci-linux-msys-test-divergence/problem.md`), whose fix was that shared fixture.

**Fix shape (not built).** Drive D1 through `mpf_build` / `MPF_PATH` from `hooks/tests/lib/minimal-path-fixture.sh` instead of ad-hoc PATH pruning — resolve tools by name and re-expose absolute-exec shims, so `bash` survives and only the interpreter is unreachable. Test-only change; `hooks/local/post-fusebase-update.sh` is not implicated.

## What is already done and must NOT be redone

| Item | State |
|---|---|
| Four version carriers at 4.16.0 | committed `a62e362` |
| Derived attestation strings (10 surfaces) | committed `a62e362` |
| CHANGELOG 4.16.0 + `docs/release-notes/v4.16.0.md` | committed `a62e362` |
| Both audit manifests restamped (hook layer, then managed content) | committed `a62e362` |
| Health-skill overlay recovery snapshot refreshed from canonical | committed `a62e362`; preflight 1 warn -> 0 |
| `v4.16.0` fingerprint row | this commit, labeled unpublished tagged tree |

## Next cut

A code fix requires a NEW version and tag (`PUBLISHING.md` § Tagging). **Never move, delete or re-point `v4.16.0`.** Re-running run `34438811255` is not permitted: the failure is a source defect, not a transient environment fault. The successor cut repeats the full ceremony at the new version, including its own post-tag fingerprint row.

## Open, unchanged from the E8/E9 ticket

- Event-level wiring intent declined this cycle; schema-1 intent still authorizes the whole `claude_settings` surface.
- The recovery outcome channel is exclusive against consumer bytes, not against executable descendants of recovery (`hooks/local/lib/recovery-outcome.sh`).
- `signal-reap launch-window-signal-still-reaps` is red pre-existing (shown red identically at `24cbff3`); it is not in the essential release profile.
- `docs/specs/hop-log-truthfulness-and-publisher-scope/` is untracked in this repository and was not committed by the release.
