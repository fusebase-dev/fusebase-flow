# Suite state at handoff — corrects `efd89e1`

`efd89e1`'s message records `upgrade-boundary`, `preboundary-consumed`, `upgrade-repair` and
`n5-delivery` as "STILL IN FLIGHT and unreported". Two of them reported **after** that commit
was written, and one of them **FAILED**. This file supersedes that line; the commit stands
otherwise.

## Measured

| Phase | Result |
|---|---|
| `upgrade-classify` | 12 PASS / **3 FAIL** (the three named in `efd89e1`) |
| `upgrade-boundary` | 22 PASS / **1 FAIL** — **not** in `efd89e1`, see below |
| `preboundary-consumed` | 18 PASS / 0 FAIL |
| `upgrade-repair` | **never reported** — the run was killed mid-phase |
| `n5-delivery` | not reached in this run (6/6 standalone, `c:/tmp/n5-oracle4.txt`) |

The run was killed at `upgrade-repair` (540s/1800s), so it produced no summary line. Nothing
here is a full-gate result.

## The fourth regression — FOUR open, not three

```
FAIL: upgrade-boundary ac1-incoming-U-materialized-from-objects-forced-LF
  [PINNED .jsonl installed with CRLF — the engine copied the staging WORKTREE,
   not the git object (F2)]
  [UNPINNED file installed with CRLF — incoming U inherited the consumer's
   core.autocrlf instead of forcing false (M1)]
  [managed-content manifest does NOT verify MATCH after the upgrade]
```

**Rank this with `ac25`, not with `t29c`.** It asserts the **M1 source boundary**: incoming
upstream content must be materialized from **git objects with LF forced**, never copied from
the staging worktree. That contract is what `materialize-managed-source.sh` exists to hold, and
it is the same eol/CRLF family that produced the shipped-bytes defect earlier in this session.

Two candidate causes, and they are not equally cheap:

1. **Fixture** — this phase's tree may not carry `lib/synthesize-base.sh` +
   `lib/upgrade-delivery-guard.sh`, which `upgrade.sh` now sources. Same cause as `t29c`, and
   the same cause already fixed twice here.
2. **Real** — the base-synthesis call was inserted into `upgrade.sh` *before* classification,
   which is upstream of the materialization path. `ffsb_synthesize_base` deliberately runs
   `git archive` with the **consumer's** `core.autocrlf` (decision M1's historical-base rule),
   which is the OPPOSITE of what incoming-U requires. If those two paths now share state or
   ordering, this is a genuine boundary regression.

**Answer (1) before touching anything** — the same discipline `efd89e1` records for `ac25`.

## Reading order for the next session

1. `ac25-aborted-bootstrap-hop-writes-nothing` — abort path may now write; safety property.
2. `ac1-incoming-U-materialized-from-objects-forced-LF` — M1 boundary; the note above.
3. `ac25-source-executed-engine-still-upgrades-end-to-end`.
4. `t29c-classification-eol-stable-under-autocrlf-true` — most likely fixture-only.

`upgrade-repair` is **unknown**, not passing. Re-run it before trusting the branch.

## Housekeeping

The killed run left 5 orphan processes; they were reaped (0 remaining, verified by `ps`). It
also left ~235 `ffhc-*` / `tmp.*` trees under `TMPDIR` — outside the repo, harmless to it, but
worth clearing before timing-sensitive phases run again (`gate-loop-wall-time-saturated-host`).
The repo itself verifies clean: `hook-manifest verify: MATCH (177/177)`.
