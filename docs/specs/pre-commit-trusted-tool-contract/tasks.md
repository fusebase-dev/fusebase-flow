# Pre-commit trusted-tool contract tasks

Status: `READY - T1/T2 ONLY`
Decision dependency: `A2 LOCKED; B1 REOPENED` (`decisions.md`)
Execution order: `T1 -> T1 release gate -> T2 -> T2 release gate -> STOP`
Commit rule: one independently releasable task = one commit; no S2c/T3 work.

## Shared execution contract

- Record `git status --short`; preserve pre-existing `?? docs/wasted-code/` and every unrelated change.
- `hooks/git/pre-commit` is 731 lines at `e1b43f9`, leaving 69 lines below the 800-line ceiling. T1/T2 keep changes inline and final size <=800. If projected above 800, STOP for Product Owner revision and a prior independently releasable helper task; do not bootstrap a helper first added by the same commit.
- Mutation harnesses use temporary copies only. Before each mutation, predeclare target plus expected observable delta; compare structured rc, stdout/stderr, artifact manifest/content, timeout class/budget, production-hook hash, index/worktree state, and temp side effects. `row=PASS|FAIL` alone is insufficient.
- FR-07 sequence for each task: stage only named code/test paths -> mint with `hooks/local/write-bootstrap-approval.sh` after staging -> confirm the gitignored approval artifact is unstaged -> commit normally -> run `write-bootstrap-approval.sh --consume` -> verify approval inactive. `approve-local.sh`, `--no-verify`, `git add .`, and `git add -A` are forbidden.
- A task SHA is not complete and the next task may not start until its targeted proof, full local suite, and exact-SHA Linux + Windows MSYS hosted gate are GREEN.

## T1 - S2d primary-python3 version symmetry

Depends on: none  
Commit: `T1 refuse unsupported primary python3`

Targets:

- `hooks/git/pre-commit`
- `hooks/tests/test-pre-commit-python3-version-contract.sh` (new)
- `hooks/tests/test-pre-commit-python3-version-mutation.sh` (new)
- `hooks/tests/run-tests.sh` (register tests)

Work:

- Attempt a <=10-second `python3 -S -c` >=3.10 probe; total primary/fallback budget <=20 seconds.
- On rejected/mishandled `-c`, use a bounded trusted `-S <file>` version-probe fallback so existing wrappers remain compatible. `python3 -S -c` support does not become a consumer requirement.
- On final BLOCK, retain bounded stderr and rc/timeout attribution in the existing attributable diagnostic; do not discard probe failure output.
- Contract rows: real CPython supported/below-floor/error/timeout; actual CI-provisioned Windows shim contract (`.github/workflows/fusebase-flow-verify.yml:92-104`); `-c`-rejecting but `-S <file>`-working wrapper; both fallbacks; empty staged set; first-adoption/unborn HEAD regression.
- Mutation discriminator: one unique primary-version target and named expected delta; baseline/mutant comparison satisfies `AC7`, including diagnostic/artifact/side-effect state and rejected unmutated negative control.

Acceptance: `AC1-AC2, AC6-AC12`.

### T1 release gate - before T2

1. Targeted T1 contract + structured mutation proof GREEN on the T1 SHA.
2. `bash -n`, preflight, full `hooks/tests/run-tests.sh`, subprocess parity, module-size `--all`, and production-integrity checks GREEN on the T1 SHA.
3. `fusebase-flow-verify` dispatched on the T1 SHA; Linux, Windows MSYS, and verify-gate jobs GREEN on that exact SHA, exercising the provisioned shim without `.github/**` edits.
4. FR-07 approval consumed/inactive; T1 commit and worktree audit recorded.

## T2 - S2b A2 Git fail-closed classifier

Depends on: T1 release gate GREEN and T1 SHA recorded
Commit: `T2 fail closed on broken git in repository context`

Targets:

- `hooks/git/pre-commit`
- `hooks/tests/test-pre-commit-git-context-contract.sh` (new)
- `hooks/tests/test-pre-commit-git-context-mutation.sh` (new)
- `hooks/tests/run-tests.sh` (register tests)

Work:

- Add bounded inline context classification before permitting the root-query skip; implement `spec.md`'s ceiling, mount-boundary, drive/UNC-root, lstat/stat-failure, and strict-parent termination rules.
- Distinguish worktree, inside-`.git` no-worktree, functioning bare no-worktree, indeterminate/BLOCK, and proven outside-repository skip outcomes.
- Parameterize every A2 compatibility row: normal/nested, `.git` file, linked worktree, submodule, valid/stale explicit environment, `core.worktree`, `.git` symlink valid/dangling/inaccessible, ceiling, mount crossing on/off, UNC/share root, Windows network-stat failure, false bare lookalike, functioning bare, outside repo, unborn HEAD, and empty staged set.
- Mutation discriminator: one unique fail-closed classifier target and named expected delta; baseline/mutant comparison satisfies `AC7`, including diagnostic/artifact/side-effect state and rejected unmutated negative control.

Acceptance: `AC3-AC12`.

### T2 release gate - final

1. Targeted T2 matrix + structured mutation proof GREEN on the T2 SHA; all T1 targeted rows remain GREEN.
2. `bash -n`, preflight, full `hooks/tests/run-tests.sh`, subprocess parity, module-size `--all`, and production-integrity checks GREEN on the T2 SHA.
3. `fusebase-flow-verify` dispatched on the T2 SHA; Linux, Windows MSYS, and verify-gate jobs GREEN on that exact SHA.
4. FR-07 approval consumed/inactive; T2 commit and worktree audit recorded.

## Gate handoff

Provide T1/T2 SHAs; per-SHA targeted/full/hosted results; predeclared mutation records; full compatibility outcomes; bounded-probe diagnostics; 731 -> final line count; semantic-review attestation; and FR-07 stage/mint/unstaged/commit/consume/inactive evidence. Stop at `verification-gate.md`; no S2c, deploy, or release work.
