# Active handoff — v4.7.0 release, blocked on one fail-open

**Updated:** 2026-07-30 · **Branch:** `fix/msys-v3307-hardening` · **HEAD:** `f77c49e` · **VERSION:** 4.7.0
**Operator authorization on file:** DP.6 phrase `approve deploy now` given 2026-07-30 for the `v4.7.0` tag re-point. **Still valid — do not re-ask.** It authorizes releasing a verified-good candidate; the candidate is not yet one.

## State

| | |
|---|---|
| `origin/main` | `85b97dd` — CI green, untouched |
| Local | ~24 commits ahead, unpushed |
| Tag `v4.7.0` | `664503b`; **no GitHub Release** (API 404, verified) |
| Linux gate | 703/703 PASS at `d0a980d` |
| Windows gate | all assertion-level PASS; non-passes have a named external cause (concurrent suite, pid 634763 from `paperclip+hermes-v1`, `ps` evidence) |

## The one blocker

Full detail: `docs/tmp/handoff/2026-07-30-release-review-findings.md`.

**A verifier-only GIT source installs unverified bytes after reporting VERIFIED.**

1. `bootstrap-upgrade.sh:200` archives committed objects → temp tree; embedded verification returns `MATCH`.
2. Engine is pre-boundary → `:417-431` switches `ENGINE_SRC` to `$SOURCE_CLONE/hooks/local/upgrade.sh` (**the mutable worktree**) and deletes the verified tree.
3. `:437` execs it; that legacy engine copies from `.fusebase-flow-source` (`hooks/tests/lib/upgrade-fixtures.sh:53`), not the verified snapshot.

A source whose *committed* objects are clean but whose *worktree* is tampered therefore passes verification and installs tampered bytes. Same class as F2/M11 — re-entered through the fix that unstranded B3. The existing negative control is plain-only (`test-upgrade-source-boundary.sh:444`), so the git shape is uncovered.

### Two smaller items from the same review

- **Matrix waiver premise is insufficient.** The B/H+ WAIVE claims shapes B/C collapse onto A with a trusted installed helper. True for the *verdict*, false for the *complete route* — the consumed-tree split above is exactly the difference. Re-disposition those cells.
- **Temp-tree leak.** A boundary-aware engine with no materializer takes `upgrade.sh:229-231`'s warning-only path without arming cleanup. Not the published shape; low priority.

## Recommended fix

Make the **verified tree the consumed tree**, or refuse the combination:

1. *(preferred)* If the engine is pre-boundary, do **not** claim `VERIFIED` — route that source through `UNVERIFIED_LEGACY_SOURCE` with the state named, since the bytes actually installed were never verified.
2. Or point the legacy engine's `.fusebase-flow-source` at the verified tree so it consumes what was proven.

Do **not** merely keep the temp tree alive — the engine reads `.fusebase-flow-source` by name, so survival alone does not make it consume verified bytes.

**Required test:** a **git** verifier-only source with clean committed objects and a tampered worktree. Must fail against `f77c49e`. Then re-run both platform gates and repeat the review.

## Already CLOSED — do not re-touch

R1, R2, R4, R5 and all MINORs from the implementation review; B1 and B2 from the re-review. Each verified at HEAD by an independent pass.

## Constraints that keep biting

- **Linux parity is mandatory** before any release claim (`docs/problem-catalog/ci-linux-msys-test-divergence/problem.md`). A green MSYS run alone has now been wrong twice.
- **A timing FAIL on this host is usually a competing suite.** Check `ps -W | grep run-tests` before diagnosing a design flaw — that mistake was made once in this chain.
- Never `--no-verify`. FR-07 protected: `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` only.
- M2 (byte-exact hashers), M3 (tempfile capture), `.gitattributes` — locked, empty-diff required.

## Deferred, filed

`docs/backlog/`: `command-gate-shell-evasion` (F7 parser), `approval-single-use-consumption`, `approval-binding-omits-head`, `rm-rule-pattern-single-space-gap`, `provenance-and-single-seam-guarantees`.
One-liner: `hooks/tests/run-tests.sh:342` — `run_exitcode_phase` never sets `FFHC_HEARTBEAT_LABEL`, so a stuck phase is misnamed during an FR-27 hang.

## Release sequence once green

Restamp both manifests → full unscoped Windows + Linux container → repeat the review → `git push origin :refs/tags/v4.7.0` → re-tag at the green commit → `git push origin v4.7.0`. The release workflow publishes only if verify passes. Permission rules for all three pushes are already in `.claude/settings.local.json`.

Release notes must carry: the moved-tag notice (`git fetch --force --tags origin`), the F7 known limitation with `git commit -F` as the sanctioned path, and that downgrading from 4.7.0 restores the replayable gate.
