# Pre-commit trusted-tool contract

Status: `DRAFT`  
Change tier: `Full`  
Decision lock: `A2 LOCKED; B1 REOPENED - operator decision required` (`decisions.md`)
Implementation authorization: `T1/S2d + T2/S2b only; S2c DO-NOT-BUILD`

## Problem

- `hooks/git/pre-commit:20-24` conflates unusable Git in repository context with genuine outside-repository execution and exits 0 for both, skipping FR-12 section 2 and FR-07 section 3.
- `hooks/git/pre-commit:87` accepts a resolved primary `python3` without the >=3.10 probe applied to fallback interpreters.
- The rejected S2c/B1 protocol detects only a naive zero-exit stub under a same-principal model while adding four producer/consumer seams, temp lifecycle, concurrency handling, and possible helper bootstrap complexity.

## Clarify summary

| Item | Result |
|---|---|
| A2 | `LOCKED`; implement in T2. |
| B1 / S2c | `REOPENED - operator decision required`; excluded from implementation. |
| S2d | Implement in T1 without making `python3 -S -c` a consumer requirement. |
| Lane / docs | Full / Tier 4: security-kernel behavior, compatibility matrix, and independent release gates justify the existing artifact pack. |

## North-star alignment

Mechanism-first and low-friction: T1/T2 close concrete fail-open/fault-detection gaps without adding an ordinary-consumer approval step; S2c is withheld because its modeled benefit does not justify its mechanism cost (`docs/north-star.md:18,31-34`).

## Scope

| Slice | Required behavior |
|---|---|
| T1 / S2d | Probe resolved primary `python3` for >=3.10 using bounded `-S -c`; preserve existing `-S <file>`-compatible wrappers through a bounded file-script fallback; retain attributable failure stderr. |
| T2 / S2b / A2 | Classify repository context independently before permitting root-query skip; repository evidence plus unavailable/unusable Git blocks; proven no-context execution skips. |
| Proof | Each task lands targeted compatibility + structured mutation proof, then passes a full local and exact-SHA hosted gate before the next task starts. |

## Out of scope

- S2c/B1 verdict artifacts, nonces, control IDs, helper bootstrap, or any producer/consumer completion protocol.
- Authenticating Git/Python, pinning binaries, remote/signature trust roots, or changing the same-principal threat model.
- Edits to `.github/**`, `policies/**`, deploy/release behavior, or unrelated hook behavior.

## S2d compatibility contract

| Context | Expected outcome |
|---|---|
| Real CPython >=3.10 | `python3 -S -c` succeeds; existing controls run. |
| Real CPython <3.10 | Attributable BLOCK before sections 2/3. |
| CI-provisioned Windows shim (`.github/workflows/fusebase-flow-verify.yml:92-104`) | Existing shim behavior remains GREEN without workflow edits. |
| Wrapper supports existing `-S <file>` but rejects/mishandles `-c` | Bounded `-S -c` failure is retained as diagnostic evidence; bounded trusted file-script fallback proves version and existing controls run. |
| Primary probe and fallback fail, return malformed data, or time out | Attributable BLOCK includes probe/fallback rc or timeout plus bounded stderr; stderr is not discarded. |

`python3 -S -c` support is NOT a consumer requirement. Required consumer behavior remains Python >=3.10 plus the existing `python3 -S <file>` control interface. Budget: <=10 seconds per attempt and <=20 seconds total; output capture is bounded to prevent diagnostic flooding.

## A2 search termination contract

- Search starts at the physical invocation directory and ascends strict parents; inspect each candidate once.
- Stop before a matching `GIT_CEILING_DIRECTORIES` entry, at filesystem/mount change unless `GIT_DISCOVERY_ACROSS_FILESYSTEM` enables crossing, and at drive root or UNC share root.
- Filesystem/mount identity, lstat, permission, or network-stat failure makes classification indeterminate and BLOCKS; it never proves outside-repository execution.
- A strict-parent ascent plus terminal roots/ceilings is the termination proof; no retry loop or unbounded network wait is permitted.

## A2 compatibility matrix

| Context | Expected outcome |
|---|---|
| Normal repo / nested directory | Working Git reaches controls; unavailable/unusable Git BLOCKS. |
| Invocation inside `.git/`; working Git returns no `--show-toplevel` | Distinct repository/no-worktree rc=0 outcome; never the outside-repo skip. |
| Linked worktree / submodule (`.git` file) | Working Git reaches controls; broken Git BLOCKS. |
| Valid explicit `GIT_DIR` / `GIT_WORK_TREE` | Existing working behavior; broken Git BLOCKS. |
| Stale explicit `GIT_DIR` / `GIT_WORK_TREE` | Attributable BLOCK; stale declarations never authorize skip. |
| Valid `core.worktree` separate-git-dir layout | Working Git reaches controls; independently found valid context plus broken Git BLOCKS. |
| `.git` symlink: valid / dangling / inaccessible | Valid reaches controls; dangling or inaccessible is indeterminate repository evidence and BLOCKS. |
| `.git` only above `GIT_CEILING_DIRECTORIES` | Search stops before ceiling; no other evidence yields outside-repo skip. |
| `.git` across mount boundary | Default stops and skips if no nearer evidence; enabled `GIT_DISCOVERY_ACROSS_FILESYSTEM` crosses, then works/BLOCKS by Git usability. |
| Windows UNC/share root | Search terminates at share root; valid evidence works/BLOCKS by Git usability; no evidence skips. |
| Windows network stat failure | Bounded attributable BLOCK, never outside-repo skip or hang. |
| False bare-layout lookalike | Does not qualify as bare evidence and receives outside-repo skip when no other context exists. |
| Functioning bare repo | Distinct no-worktree rc=0 outcome; broken Git with complete bare evidence BLOCKS. |
| Genuine outside repo, no evidence | Existing diagnostic and rc=0 for working, unavailable, or unusable Git. |
| First adoption / unborn HEAD | Staged content is checked against the existing empty-base behavior; no HEAD-dependent bypass or fatal lookup. |
| Empty staged set | Existing early no-op rc=0; no Python probe, temp residue, or control side effect. |

## Invariants

- Preserve environment sanitization, `PYTHONSAFEPATH=1`, `-S` on every Python invocation, controlled `PYTHONPATH`, file-script controls, shell `git ls-tree` sentinels, and trusted-HEAD extraction.
- `hooks/git/pre-commit` is 731 lines at HEAD `e1b43f9`; inline headroom is 69 lines below the 800-line ceiling. T1/T2 stay inline and <=800. If that cannot be met, STOP and return to Product Owner for a prior independently releasable helper task; no same-commit committed-HEAD helper contingency.
- FR-07 flow per task: stage named code/test paths; then mint with `hooks/local/write-bootstrap-approval.sh`; keep the gitignored artifact unstaged; commit normally; run `--consume`; verify inactive. Never use `approve-local.sh` for `fusebase_flow_internals` or `--no-verify`.

## Acceptance criteria

- **AC1:** All S2d compatibility rows pass; real CPython and the CI-provisioned shim are covered, and `python3 -S -c` is not a consumer requirement.
- **AC2:** Each S2d attempt obeys the 10-second/20-second budgets; BLOCK diagnostics preserve bounded stderr plus rc/timeout attribution.
- **AC3:** Repository evidence plus missing, nonzero, empty/bogus-root, or unusable-root Git BLOCKS; proven outside-repo execution preserves rc=0.
- **AC4:** A2 implements the explicit ceiling, mount, root/share-root, stat-failure, and bounded termination rules.
- **AC5:** Every A2 compatibility-matrix row has a named test and the exact expected outcome above, including distinct inside-`.git` and functioning-bare no-worktree outcomes.
- **AC6:** First-adoption/unborn-HEAD and empty-staged-set rows preserve their security-sensitive existing behavior.
- **AC7:** Before each mutation, the harness declares the target and expected observable delta. Baseline-versus-mutant proof compares structured rc, stdout/stderr diagnostic text, artifact manifest/content state, timeout class/budget, tracked-hook hash, index/worktree state, and temp side effects - not `row=PASS|FAIL` alone; all undeclared observables remain identical and an unmutated negative control is rejected.
- **AC8:** Mechanical and runtime checks prove all invariants remain operative; final hook size is <=800 with no helper added by T1/T2.
- **AC9:** A mandatory human/reviewer semantic check confirms no text overclaims tool identity or unforgeability. Vocabulary scanning is non-authoritative only: it misses `genuine interpreter`, `verified binary`, `identity assurance`, and `cannot be forged`, and false-positives on explicit disclaimers.
- **AC10:** T1 and T2 are independently releasable commits; each passes its targeted compatibility/mutation proof, full local suite, and exact-SHA Linux + Windows MSYS hosted gate before the next task/release claim.
- **AC11:** Each task follows the exact FR-07 stage -> mint -> normal commit -> consume -> inactive sequence; the approval artifact is never staged and unrelated `docs/wasted-code/` remains untouched.
- **AC12:** `fusebase-flow-verify` is dispatched on each task SHA; `verify-linux`, `verify-windows-msys`, and `verify-gate` are GREEN on that SHA, with no workflow trigger or file edit.

## Residual risk

A same-principal attacker controlling `PATH` can still return plausible Git/Python results or alter workspace evidence. T1 is version/interface fault detection; A2 is repository-context/Git fault detection. Neither authenticates an executable or creates a trust root.
