# Pre-commit trusted-tool contract verification gate

Status: `PENDING - STOP AT EACH TASK GATE`
Decision basis: `A2 LOCKED; B1 REOPENED` (`decisions.md`)
Implementation scope: `T1/S2d + T2/S2b only`
Deploy/release/smoke: `OUT OF SCOPE; deterministic hook proof only`

## Entry conditions

- T1 and T2 are two serial, independently releasable commits; each message cites its T-number and contains its control plus discriminator.
- T2 does not start until T1 targeted, full-suite, exact-SHA hosted, FR-07, and semantic gates are GREEN.
- S2c/B1 verdict code, helper code, nonces, artifacts, or tests are absent.
- Planned paths only are changed; pre-existing `?? docs/wasted-code/` remains untouched/untracked.

## Per-task release gates

| ID | SHA | Required proof | Pass condition |
|---|---|---|---|
| P1 | T1 | S2d contract + structured mutation record | Every S2d row GREEN; mutation satisfies the full observable contract below. |
| P2 | T1 | `bash -n`, preflight, full hook suite, subprocess parity, module-size `--all`, production integrity | All GREEN; report totals; hook <=800 lines. |
| P3 | T1 | `workflow_dispatch` exact-SHA run | `verify-linux`, `verify-windows-msys`, `verify-gate` GREEN on T1 SHA; actual provisioned shim exercised. |
| P4 | T2 | Complete A2 matrix + structured mutation record | Every A2 row returns its defined outcome; mutation satisfies the full observable contract below. |
| P5 | T2 | P2 full gate repeated; T1 targeted regression repeated | All GREEN on T2 SHA; report totals; hook <=800 lines. |
| P6 | T2 | `workflow_dispatch` exact-SHA run | All three jobs GREEN on T2 SHA. |
| P7 | Each | Mitigation inventory | Environment scrub, `PYTHONSAFEPATH=1`, `-S`, controlled `PYTHONPATH`, file-script controls, shell sentinels, and trusted-HEAD extraction remain present and exercised. |
| P8 | Each | FR-07 + worktree audit | Named paths staged before mint; bootstrap approval unstaged; normal commit; consumed/inactive; no unrelated change. |
| P9 | Each | Human/reviewer semantic review | `AC9` passes by meaning, not vocabulary grep. |

Aggregate GREEN at T2 cannot substitute for missing T1 proof. Failure at P1-P3/P7-P9 is `BLOCKED-AT-T1-release`; failure at P4-P9 is `BLOCKED-AT-T2-release`.

## Mutation evidence contract

Each mutation record is predeclared before execution.

| Field | Required value |
|---|---|
| ID / unique target | Stable anchor, expected occurrence count=1, named compatibility row. |
| Expected observable | Exact expected delta for rc, stdout/stderr, artifact state, timeout class, and side effects. |
| Baseline snapshot | Structured rc; exact stdout/stderr after only declared nondeterminism normalization; artifact manifest with path/type/size/content hash; elapsed/timeout class; tracked-hook hash; index/worktree state; temp residue. |
| Mutant snapshot | Same structure; only the predeclared target observables may differ. |
| Comparator | Compares fields above, not reduced `row=PASS|FAIL`; undeclared diagnostic, artifact, timing-class, or side-effect change fails proof. |
| Negative control | Unmutated copy presented as mutant is rejected. |
| Production integrity | Tracked hook byte-identical before/after harness; mutation occurs only in temporary copies. |

Missing structured fields or a row-status-only comparison is `BLOCKED-AT-mutation-proof`.

## S2d compatibility rows

| ID | Context | Expected outcome |
|---|---|---|
| PY1 | Real CPython >=3.10 | `-S -c` probe succeeds; controls run. |
| PY2 | Real CPython <3.10 | Attributable BLOCK before sections 2/3. |
| PY3 | CI Windows shim (`fusebase-flow-verify.yml:92-104`) | Hosted Windows job GREEN without workflow edit. |
| PY4 | Wrapper rejects/mishandles `-c`, supports `-S <file>` | Bounded file-script fallback proves >=3.10; controls run; `-S -c` is not required. |
| PY5 | Probe/fallback error, malformed output, or timeout | Attributable BLOCK includes bounded stderr and rc/timeout; <=10 seconds each, <=20 seconds total. |
| PY6 | Supported `python` and `py -3` fallbacks | Existing behavior retained. |
| PY7 | Empty staged set | Early no-op rc=0; no Python probe, temp residue, or control side effect. |

## A2 compatibility rows

| ID | Context | Expected outcome |
|---|---|---|
| G1 | Normal repo / nested directory | Working Git reaches controls; unavailable/unusable Git BLOCKS. |
| G2 | Invocation inside `.git/`; no top-level | Distinct repository/no-worktree rc=0; not outside-repo skip. |
| G3 | Linked worktree / submodule `.git` file | Working Git reaches controls; broken Git BLOCKS. |
| G4 | Valid explicit `GIT_DIR` / `GIT_WORK_TREE` | Existing working behavior; broken Git BLOCKS. |
| G5 | Stale explicit `GIT_DIR` / `GIT_WORK_TREE` | Attributable BLOCK. |
| G6 | Valid separate git dir + `core.worktree` | Working Git reaches controls; valid context + broken Git BLOCKS. |
| G7 | `.git` symlink valid / dangling / inaccessible | Valid works; dangling/inaccessible BLOCK as indeterminate evidence. |
| G8 | `.git` only above `GIT_CEILING_DIRECTORIES` | Stop before ceiling; no other evidence => outside-repo skip. |
| G9 | `.git` across filesystem/mount boundary | Default stop/skip; enabled `GIT_DISCOVERY_ACROSS_FILESYSTEM` crosses then works/BLOCKS by Git usability. |
| G10 | Windows UNC/share root | Terminate at share root; evidence works/BLOCKS by Git usability; no evidence skips. |
| G11 | Windows network stat failure | Bounded attributable BLOCK; no skip/hang. |
| G12 | False bare-layout lookalike | Not bare evidence; no other context => outside-repo skip. |
| G13 | Functioning bare repository | Distinct no-worktree rc=0; complete bare evidence + broken Git BLOCKS. |
| G14 | Genuine outside repo, no evidence | Existing outside-repo diagnostic and rc=0 even with unavailable/unusable Git. |
| G15 | First adoption / unborn HEAD | Staged content checked against empty base; no HEAD bypass/fatal lookup. |
| G16 | Empty staged set | Early no-op rc=0; no temp or control side effect. |

Search proof for G8-G11: physical strict-parent ascent; each candidate once; stop before ceiling, at disallowed mount crossing, drive root, or UNC share root; stat/permission/network failure BLOCKS; no retry loop or unbounded wait.

## Claim-boundary gate

Mandatory human/reviewer question: does any new comment, diagnostic, test name, or doc imply executable identity, authenticity, or unforgeability beyond the same-principal model? Reviewer records `PASS` plus inspected files and rationale. A vocabulary scan is supplemental/non-authoritative: it misses `genuine interpreter`, `verified binary`, `identity assurance`, and `cannot be forged`, and false-positives on explicit disclaimers.

## Exact-SHA hosted gate

1. Dispatch `.github/workflows/fusebase-flow-verify.yml` separately on T1 and T2 SHA.
2. Record run URL, requested SHA, checked-out SHA, and three job results for each.
3. Cancelled, skipped, timed-out, different-SHA, or final-SHA-only evidence fails independent releasability.
4. Confirm no `.github/**` diff and triggers remain `workflow_dispatch` / `workflow_call` only.

## Gate report

```text
T1_sha: <sha>
T1_targeted_mutation: <P1 structured record>
T1_full_suite: <P2 totals>
T1_hosted: <P3 url/sha/linux/windows/gate>
T2_sha: <sha>
T2_targeted_mutation: <P4 structured record>
T2_full_suite: <P5 totals + T1 regression>
T2_hosted: <P6 url/sha/linux/windows/gate>
compatibility: <PY1-PY7; G1-G16>
invariants: <P7; line_count before=731 after=<n> ceiling=800 helper=absent>
fr07_worktree: <P8 per task; approval_staged=no; inactive=yes>
semantic_review: <P9 reviewer/files/rationale>
verdict: PASS | BLOCKED-AT-<probe>
```

## Rollback

Revert T2 alone to return to the independently verified T1 state; revert T1 only if its behavior must also be removed. Each revert touching protected paths uses a new stage -> bootstrap-mint -> normal-commit -> consume -> inactive FR-07 sequence and repeats its own targeted/full/hosted gate. Never reset, discard checkout, force push, or use `--no-verify`.
