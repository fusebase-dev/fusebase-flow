# Active handoff — v4.7.0 unpublished; M17 answered the (b), both platforms green, round-6 review returns 3 × (a)

**Updated:** 2026-08-02 (rev 4 — M17 locked; 5 commits landed; Windows 742/742 + Linux 739/739; review 6 = NO-SHIP, three **(a)**, zero **(b)**) · **Branch:** `fix/msys-v3307-hardening` · **HEAD:** `d432961` · **VERSION:** 4.7.0
**Stopped by the operator's rail, not by a contract defect.** The threat-model question is CLOSED (M17). Nothing here needs a decision.

## State — nothing shipped, nothing to undo

| | |
|---|---|
| `origin/main` | `85b97dd` — untouched, CI green |
| Tag `v4.7.0` | `b11c60d` — **not** moved; no GitHub Release (404) |
| Local | `d432961`, tracked tree clean, 56 commits unpushed |
| Gate at `d432961` | Windows unscoped **742/742 PASS, 0 FAIL**; Linux `ubuntu:24.04` **739/739 PASS, 0 FAIL**, every CI step rc 0 |
| Platform delta | 742 vs 739 = 4 MSYS-only cases minus 1 Linux-only case, all in `msys-tree-cleanup`. Verified by name-set diff, not assumed |
| FR-07 | empty diff `c77b139..d432961` on `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` |
| Locked files | empty diff: M2 hashers, M3 `run-with-timeout.sh`, `.gitattributes`, `templates/**` |
| Release prerequisites | all four version carriers 4.7.0, README badge 4.7.0, `sync-version-strings.sh` empty diff — verified, unused |
| Operator DP.6 | never consumed — the authorization was conditioned on a SHIP verdict |

## What landed — 5 commits, all green

`b6adbbc` T1 wording under M17 · `f38a3cf` T2 symlink refusal (**RED on Linux first**: 3/3 classes returned rc 0 and confirmed the repair at `b6adbbc`) · `ccc59cb` T3 runnable `RECOVER:` advice (**RED on Windows first**: no RECOVER line existed) · `138fa10` T4 write-order wording · `d432961` T5 backlog `repair-trust-root-outside-workspace`

T4's test is labelled **COVERAGE**, not a discriminator — the behaviour already held; the contract wording was the defect. That label is honest and the review agreed.

## Round-6 review: NO-SHIP, three (a), zero (b)

`c:/tmp/ffrev8/review.md`. The contract is right; **two sentences and one line of shell** are wrong. Each verified first-hand, not relayed.

| # | Defect | Where | Class |
|---|---|---|---|
| 1 | `--source` is interpolated into the emitted `RECOVER:` line **unquoted** — a source path containing a space produces a command that does not run (this repo's own directory name contains two). Introduced by T3 | `bootstrap-upgrade.sh:317` `src=" --source $SRC_OVERRIDE"` | **(a)** |
| 2 | "the only write that may precede the bind is the staging clone" is still false: every route materializes and populates a temp `ff-source-*` tree under `$TMPDIR` first (`bootstrap-upgrade.sh:455` → `materialize-managed-source.sh:202`), before the bind at `:480`. The TRUE invariant is narrower and provable: **no pre-existing consumer file is touched before the bind**; writes that precede it only CREATE new locations (the temp canonical tree, removed on exit; `.fusebase-flow-source/` when absent) | `decisions.md` M13/M16, `v4.7.0.md:105`, `bootstrap-upgrade.sh:464` — and 3h-10's claim must be narrowed to what it measures | **(a)** |
| 3 | M16's anchor table still calls a plain-source `cp -R` result an "immutable snapshot". It is writable and preserves symlinks (`materialize-managed-source.sh:87`) | `decisions.md:308` | **(a)** |

Non-blocking, recorded not fixed: hardlinks / bind mounts / Windows junctions are outside the symlink control (and outside M17's model); `comment-policy.yml`'s `trust_critical_globs` is empty while several multi-line tripwires remain.

## The next pass is small and needs no decision

1. Quote the emitted source path (`--source '<path>'`, or `printf %q`); add a 3h-9 fixture whose source directory name **contains a space**, and capture the status without `eval` masking it.
2. Replace the "only write" sentence in M13, M16, `v4.7.0.md` and the `bootstrap-upgrade.sh:464` tripwire with the true invariant above; rename/re-scope 3h-10 to "no pre-existing consumer file changes across a repair that had to clone" — which is exactly what its hash snapshot measures.
3. Delete or qualify "immutable snapshot" in M16's anchor row.

Then: unscoped Windows + Linux container, ONE review, DP.1 mint, release sequence below. **The operator must re-authorize** — no DP.6 phrase survives a NO-SHIP.

## Release sequence, unchanged, for when the verdict is SHIP

Restamp both manifests → unscoped Windows + Linux `ubuntu:24.04` → one review → DP.1 mint → `git push origin HEAD:refs/heads/main` → `git push origin :refs/tags/v4.7.0` → re-tag → `git push origin v4.7.0` → watch verify+publish via the public REST API (`gh` is not installed) → FR-14 single docs commit. Publish is `needs: verify`, so a red suite cannot release.

## Constraints (unchanged, all still binding)

Never `--no-verify`. FR-07 protected = `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` only. Locked: M2 byte-exact hashers, M3 tempfile capture, `.gitattributes`, `templates/**`, the FR-06 deny. `bootstrap-upgrade.sh` is at **799/800** lines — the next edit must shrink before it grows. Linux parity is mandatory before any release claim. Before diagnosing a timing FAIL, run `ps -W | grep run-tests`. The unscoped Windows suite needs **>40 min**; bound any wrapper at ≥5400s. `run-tests.sh:342` still misnames the running phase during a bounded wait (`cli-flow-recovery` appears as `upgrade-repair`).

## Reproducing the gate

Linux: `docker build -t ff-gate:24.04` from `ubuntu:24.04` + `git python3 python3-pip`, then clone `/src` INSIDE the container and run the CI step list (`c:/tmp/ffgate/linux-full.sh`). A container without PyYAML produces ~20 false FAILs — that was an environment defect this session, not a code defect.

## Filed, deferred

`docs/backlog/`: `repair-trust-root-outside-workspace` (**new** — M17's rejected option (b)) · `command-gate-shell-evasion` · `approval-single-use-consumption` · `approval-binding-omits-head` · `rm-rule-pattern-single-space-gap` · `provenance-and-single-seam-guarantees`.
Reviews: `c:/tmp/ffrev8/review.md` (round 6) · `docs/tmp/handoff/2026-08-02-m16-review.md` (round 5) · `c:/tmp/ffrev7/r*.md`; earlier rounds in `docs/tmp/handoff/2026-07-2[89]-*`, `2026-07-3[01]-*`.
