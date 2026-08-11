# Active handoff

Mode: run-ledger  (autonomous run, operator stepped out)
**Updated:** 2026-08-11T21:05Z
**Branch:** `fix/trusted-tool-contract` (T1+T2); `fix/msys-v3307-hardening` merged and released
**HEAD at write time:** `9a83c51`
**Default branch:** `main` at `20fd707` — **v4.8.0 PUBLISHED** (tag `v4.8.0`, release run `31459937396` attempt 2)

## v4.8.0 shipped — and what publishing it cost

Four blockers + eight MAJORs. Two consumer-visible behaviour changes are in `CHANGELOG.md` §[4.8.0]
and `docs/release-notes/v4.8.0.md`: a missing Python 3.10+ now REFUSES a commit with staged
changes, and the shipped verify workflow no longer runs on push/PR.

**Do not re-derive the release procedure — `PUBLISHING.md:257` has three steps, not one.** Bumping
the four version carriers is insufficient; you must also run `hooks/local/sync-version-strings.sh`
AND restamp BOTH audit manifests (`flow_version` is embedded in each). Skipping steps 2-3 leaves the
attestation surfaces at the old version, the health engine returns `PARTIAL_UPGRADE`, and
`cli-flow-recovery U17` fails — 907/908, one row, whole gate. Cost two CI cycles.

Also: `sync-version-strings.sh` edits `FLOW_RULES.md`, an FR-07 protected path, so the release
itself requires minting and consuming a bootstrap approval.

## S2b + S2d done on `fix/trusted-tool-contract` — NOT merged

| SHA | Content |
|---|---|
| `d5abf3d` | T1/S2d — a resolved `python3` must prove >=3.10. Bounded `-S -c` probe with file-script fallback, so `-c` support is NOT a new consumer requirement |
| `facae26` | T2/S2b — broken git in repository context now BLOCKS; genuine outside-repo `exit 0` preserved |
| `9a83c51` | manifest stamp for the four new test files |

Gates: local `1006/1006 PASS` (artifact `2026-08-11T20:54:20Z`, 77 rows for these phases) · hosted
run `31520333589` GREEN on `verify-linux` + `verify-windows-msys` + `verify-gate` for `9a83c51`.

**`wip-t2-falsified` (`83d0d09`) — DO NOT REVIVE.** It accepted any dir with `objects/`+`refs/`+a
well-formed `HEAD` as a bare repo without requiring `bare = true`, so it REFUSED commits in
directories that are not repositories. Measured: 33/34 vs 34/34. That is the outcome the governing
review ranked worst — newly blocking a commit that works today.

`hooks/git/pre-commit` is at **799/800**. Further inline growth needs the prior helper task the plan
names; it must not be compressed.

**Open:** AC9 says "human/reviewer" semantic check. An independent AI reviewer passed it; no human
has read the diff. Operator's reading to settle. Also `docs/specs/pre-commit-trusted-tool-contract/`
still reads DRAFT/PENDING — the FR-14 docs flip is a Deploy-phase action.

## Process lesson that cost the most this run

**A 0-byte agent transcript is NOT proof of death.** An `ai-developer` ran 107 minutes with its
transcript at 0 bytes; it was declared dead, a successor was spawned, and two writers then shared
one tree — voiding three full-suite runs, producing a bundled commit, and causing a `G15` failure
misdiagnosed as a fixture defect (it was contamination; 33/33 green once quiet). Check live child
processes and new untracked files, never transcript size. A fourth run died to an orphan-cleanup
filter that matched the cleaner's own run by age.
**Authoritative roadmap:** `docs/specs/msys-hardening-roadmap/roadmap.md` — owns S0..S14 slice scheduling
**Governing review:** `docs/specs/backlog-triage-execution/plan-review-2.md` — `WRONG-APPROACH` on B1
**Superseded state:** `docs/tmp/handoff/archive/2026-08-07-restart-186ba38.md`
(sha256 `c4ac658dda263c74caced5015a7a09c5cfe2bed6e22a982dbb15810eddc1e5e4`)

## B1 IS ANSWERED — the estimate was wrong by ~6x. No architecture change is needed.

Run `31431353353`, `windows-latest`, SHA `c753d130`, committed defaults, unscoped.

| | |
|---|---|
| **Full Windows suite wall** | **15m17s** (46 phases; per-phase sum 15m06s — no unaccounted gap) |
| Committed CI wall | 60 min → **~4x headroom** |
| Superseded estimate | ~88m35s |
| Result | 889/893 PASS, 4 FAIL |

**Root cause of the bad estimate: the dev host was never representative.** `cli-flow-recovery`
took **1107s locally vs 82s on the hosted runner — 13.5x faster**. Every projection built on local
timings inherited that error.

**Decision: no per-platform tier, no sharding, no ceiling change. Close B1 as no-action.** The
whole gate-speed workstream was solving a problem that did not exist. Do not reopen it without a
fresh hosted-runner measurement — a local timing is not evidence for a CI bound.

Raw logs: `windows-measurement` artifact on the run (no `summary.md` — the step that writes it is
downstream of the suite step and did not run; per-phase times come from stderr `took Ns` lines).

## S1 fixture rework invalidates the four-row FIXED claim

**Status: `6ffd8da`'s FIXED claim is invalidated (`VERDICT: WRONG-LAYER`).** `bd47aed` / `800bf36`
asserted the contract at the wrong layer; S1 replaces subtractive PATH masking with causal fixture
and mutation proof.

| Fact | Value |
|---|---|
| Invalidated repair | Deleting `hooks/git/pre-commit:96`'s `exit 1` left both absent-interpreter rows GREEN; stderr and rc came from separate invocations; row 8 staged a PROTECTED path, so `rc != 0` could pass for the wrong reason; the PATH mask was duplicated in two files with an arbitrary 2000-entry cap |
| Superseding work | S1 `msys-test-fixture-rework`: `fcddf10` (T1), `b7d5545` (T2), `06c0b3b` (T3) |
| Root cause | The PATH **masks**, not the assertions — subtractive masking is host-dependent by construction |
| Remedy | ONE additive fixture, `hooks/tests/lib/minimal-path-fixture.sh`: resolves ~26 allowlisted tools to absolute paths, never adds an interpreter, never enumerates/mirrors/symlinks/copies PATH dirs |
| Mutation proof | Deleting `pre-commit:96`'s `exit 1` now flips EXACTLY `8-interpreter-absent-blocks` PASS→FAIL; all control rows are identical; an unmutated copy presented as the mutant is rejected (verdict rc 1); production hook byte-unchanged |
| Critical detail | The mutant still returns **rc 1**, so a bare "named RED" oracle would have passed it; a terminality clause (no post-§1b marker) was required |
| Rows | Changed phases 66 → 101 (+35); `bootstrap-exception` 59 → 56 (3 rows RELOCATED to the new contract test, not lost) |
| Module size | `test-bootstrap-exception.sh` 799 → 740 |
| Local gate | `929/929 PASS`, 0 FAIL — developer evidence only, never release evidence |
| Hosted | **GREEN on exact SHA `1227652`** — run `31451240122`: `verify-linux` + `verify-windows-msys` + `verify-gate` all success (wall 16m24s; suite 2m37s Linux / 15m38s Windows). AC8 satisfied; S1 CLOSED. Pushes do not trigger `fusebase-flow-verify.yml` — hosted verification requires explicit dispatch |
| First dispatch | Run `31450469371` on `06c0b3b` failed BOTH legs at step 12 (managed-content manifest), never at the tests — step 9 passed on both platforms. Fixed by `9585f54`. This is `local-gate-misses-manifest-freshness` (S11) reproducing live: the local suite has no managed-content freshness assertion, CI does, so 929/929 local still reddened CI |
| Side effect | `bootstrap-exception` phase 600–680s → ~95s **on this dev host**. NOT demonstrated on the runner: Windows suite was 13m05s on `06c0b3b` and 15m38s on `1227652` for essentially the same tests — that spread is variance, not signal. Do not cite a hosted speedup without a controlled measurement (`gate-bounds-lack-headroom` / S8) |

## What is real vs. what is still an estimate

| Claim | Status |
|---|---|
| Local fast gate ~5m30s, 116/116 | MEASURED, this host |
| `cli-flow-recovery` 36m42s → 18m27s | MEASURED, this host |
| `signal-reap` 1075s → ~165s | MEASURED, this host |
| Root cause is MSYS **process-spawn count**, not bytes | ESTABLISHED (step 4: 98 files × ~0.6s/spawn) |
| Windows **hosted-runner** full-suite wall | **DID NOT EXIST until run 31431353353** — the ~88m35s figure is an estimate off a loaded dev host |

## Still open after the measurement

**B2 and B4 were re-verified against the shipped files on 2026-08-10 and are CLOSED.** An earlier
revision of this handoff listed them as open; that was stale, not a finding.

**Slice scheduling:** `docs/specs/msys-hardening-roadmap/roadmap.md` owns S0..S14; this ledger
records current finding state only.

| ID | State | Evidence (read, not inferred from commit messages) |
|---|---|---|
| B2 | **CLOSED** | `hooks/local/verify-tag-target.sh` force-fetches the tag from the remote (a non-forced fetch of an existing ref is rejected by git, which would silently compare the stale workspace ref — the exact bypass), peels with `^{commit}` so annotated tags resolve, requires a full 40-hex SHA so a truncated value cannot match, and has no skip knob. Called in `fusebase-flow-release.yml` BEFORE publish and again AFTER (TOCTOU re-assert). Mutation-tested by `test-release-tag-binding.sh`, which strips `refresh_tag_from_remote` from a copy and asserts the moved tag is then wrongly accepted — so the fetch cannot decay into decoration. The residual window is fetch→create and is closable only by a repo-side tag ruleset (`PUBLISHING.md` § Publication paths) |
| B4 | **CLOSED** | `test-run-tests-signal-reap.sh`: discriminators that cannot run call `err()` ("a discriminator that could not run is NOT a pass") which counts into `fail`; `skip()` is restricted to CONTROLS and never enters the exit status. The one surviving `skip` (`never-signals-own-group`) is a labelled `[CONTROL]`. `finish()` also fails when any declared row never reported — "the suite got smaller, not greener" |

| ID | State | Evidence / residual |
|---|---|---|
| B3 | **CLOSED** | `hooks/tests/cli-flow-recovery-direct.sh:40,46,69,257` — predicate 32 runs the shipped writer over the production corpus and byte-compares the manifest |
| MAJOR 9 | **CLOSED (deliberate)** | `.github/workflows/fusebase-flow-verify.yml:3,16,21` — `workflow_dispatch` + `workflow_call` only; ordinary pushes/PRs run NO CI by design |
| MAJOR 10 | **CLOSED by `c11d4e2`** | Attribution correction: not closed by the row-16 repair |
| MAJOR 11 | **CLOSED** | `hooks/local/write-bootstrap-approval.sh:113,123,132`; `hooks/local/approve-local.sh:168,218` — both writers emit a populated `paths` array |
| MAJOR 12 | **PARTIAL** | Narrow defect closed in `c11d4e2`; `hooks/local/preflight.sh:42` still silently skips Python checks when Python is absent, so `docs/specs/backlog-triage-execution/plan-review-2.md:69` remains unsatisfied (roadmap S3) |
| MAJOR 7 | **PARTIAL** | 124/137 are labelled TIMED OUT vs `crashed`, but classification is rc-only; a test's own 124/137 is indistinguishable from watchdog action (`hooks/tests/run-tests.sh:299,305`; `hooks/local/lib/run-with-timeout.sh:49,52`) |
| SIGINT | **OPEN (confirmed)** | No `INT` trap; nothing branches on 130 (`hooks/tests/run-tests.sh:219,270,596`) |
| MAJOR 8 / `gate-bounds-lack-headroom` | **OPEN** | Roadmap S8; updated `bootstrap-exception` timing is recorded in the S1 table above |

## Lessons this run — do not re-derive

- **A fixture must contain the mechanism under test.** A TERM trap was measured at 0.9s with a
  `sleep 0.2` loop; the real harness naps on `read -t` over an RW-opened FIFO where bash never
  delivers the trap. That wrong number was then used to override a correct finding.
- **Measure before naming a cost driver.** Two cost claims ("cp -R copies dominate" → 0.3%;
  "13× post-fusebase-update = 65%" → 9 direct calls) were both wrong and both deleted.
- **A scoped run is never release evidence.** A renamed test heading broke
  `test-health-check-timeout.sh:412` and was reported green, because the scoped run excluded that tag.
- **One AI Developer session per branch.** Two collided when a 0-byte transcript was misread as a
  dead spawn. Poll **file mtime and process count**, never transcript size.
- **Raising a bound is two different acts.** Masking a defect with a *phase* bound hides
  information; sizing a *CI job ceiling* to measured work is an honest budget. Applying the lesson
  without re-deriving it produced the least defensible option.

## Standing constraints

- Release evidence is the CI `verify` job — never a local run. `verify-linux` +
  `verify-windows-msys` + the `verify-gate` aggregate on the exact SHA; `publish` needs all three.
- `FF_CLI_RECOVERY_TIMEOUT` and `FF_SKIP_CLI_RECOVERY` are **deleted** (step 7). There is no way
  left to make this gate pass by supplying an environment variable. A bound hit is a FAIL, never
  an INCONCLUSIVE. The CI negative arm fails if either name reappears.
- FR-07 protected: `policies/*.yml`, `hooks/{handlers,shared,git}/**`, `.github/workflows/**`.
  Never `--no-verify`.
- **No release published.** v4.7.0/v4.7.1 remain live and untouched. `main` carries only the
  measurement workflow beyond the v4.7.1 closeout.

## Environment note (2026-08-10)

The repo tree became unwritable after a host restart — `FullControl`, correct ownership, and no
Deny ACEs, yet every write denied. Cause was a **Windows Mandatory Integrity Control** label, not
the DACL. Fix, from an operator shell:

```
icacls "<repo>" /setintegritylevel "(OI)(CI)Medium" /T /C
```

Setting the label itself requires write access, so this cannot be self-applied from the blocked
process — it must come from a shell that still has rights.

`C:\tmp` still carries the same label and remains unwritable; the stale worktree
`C:/tmp/fusebase-flow-v451-release` could not be deleted for that reason (its git reference was
pruned, so it no longer blocks a `main` checkout). The local `main` commit it held, `2620dae`
(v4.5.1 T1 metadata, never pushed, superseded by the shipped v4.5.1), is preserved as branch
`salvage/main-2620dae`.
