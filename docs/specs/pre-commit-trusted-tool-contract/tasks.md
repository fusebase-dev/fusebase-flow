# Pre-commit trusted-tool contract tasks

Status: `READY`  
Decision dependency: `A2 + B1 LOCKED` (`decisions.md`)  
Execution order: `T1 → T2 → T3 → verification gate`  
Commit rule: one task = one commit; no task may be split or combined.

## Shared execution contract

- Before T1, record `git status --short`; preserve the pre-existing `?? docs/wasted-code/` entry and every unrelated change.
- Before and after each task, count `hooks/git/pre-commit`. Baseline is 731; ceiling is 800. If projected above 800, use the extraction seam in `spec.md#invariants` before adding more inline logic.
- For each T1/T2/T3 commit touching `hooks/git/pre-commit`, mint a single-use FR-07 approval with `hooks/local/write-bootstrap-approval.sh` or `hooks/local/approve-local.sh --path hooks/git/pre-commit ...`; stage only named task paths and the approval artifact; commit normally; consume the approval using the sanctioned writer flow and prove it is no longer active.
- `--no-verify`, `git add .`, and `git add -A` are forbidden. Mutation harnesses operate only on temporary copies and byte-compare the production hook afterward.
- Every discriminator follows `hooks/tests/test-pre-commit-interpreter-mutation.sh`: unique target, baseline GREEN, exact named-row mutant RED, identical controls, and rejected unmutated negative control.
- Each commit message cites its T-number. Stop after T3 for `verification-gate.md`; do not deploy or release.

## T1 — S2d primary-python3 version symmetry

Depends on: none  
Commit: `T1 refuse unsupported primary python3`

Targets:

- `hooks/git/pre-commit`
- `hooks/tests/test-pre-commit-python3-version-contract.sh` (new)
- `hooks/tests/test-pre-commit-python3-version-mutation.sh` (new)
- `hooks/tests/run-tests.sh` (register new tests)

Work:

- Probe a resolved `python3` with the same ≥3.10 predicate used for `python` / `py -3`; use startup-minimal `-S` and fail closed through the existing diagnostic.
- Preserve supported-primary and both fallback paths; do not describe the probe as interpreter authentication.
- Contract rows cover supported primary, below-floor primary, probe-error primary, supported fallbacks, and attributable terminal refusal.
- Mutation discriminator has one unique primary-probe target and named row `python3-below-floor-blocks`; require baseline GREEN, exact one-row mutant RED, identical controls, and rejected unmutated negative control.

Acceptance: `AC1, AC7-AC11`.

## T2 — S2b A2 Git fail-closed classifier

Depends on: T1 SHA recorded  
Commit: `T2 fail closed on broken git in repository context`

Targets:

- `hooks/git/pre-commit`
- `hooks/tests/test-pre-commit-git-context-contract.sh` (new)
- `hooks/tests/test-pre-commit-git-context-mutation.sh` (new)
- `hooks/tests/run-tests.sh` (register new tests)

Work:

- Add bounded shell-side context classification before permitting the root-query skip: upward `.git` directory/file, explicit `GIT_DIR` / `GIT_WORK_TREE`, and bare-layout evidence.
- Block repository evidence plus missing/unusable Git, empty/bogus root, or unusable returned root with an attributable diagnostic; preserve genuine outside-repo exit 0 and functioning bare no-worktree behavior.
- Parameterized contract rows cover normal/nested repos, both `.git` forms, linked worktree, submodule, explicit environment, bare repo, broken Git, and outside-repo regression.
- Mutation discriminator has one unique fail-closed target and named row `repo-evidence-broken-git-blocks`; require the full baseline/exact-row/identical-controls/negative-control contract.

Acceptance: `AC2-AC4, AC7-AC12`.

## T3 — S2c B1 per-control positive verdict

Depends on: T2 SHA recorded  
Commit: `T3 require per-control positive verdicts`

Targets:

- `hooks/git/pre-commit`
- `hooks/tests/test-pre-commit-verdict-contract.sh` (new)
- `hooks/tests/test-pre-commit-verdict-mutation.sh` (new, four-case parameterized discriminator)
- `hooks/tests/run-tests.sh` (register new tests)

Work:

- Add one reusable shell verdict protocol and instrument the four fixed IDs from `spec.md`: shell-issued fresh nonce, producer write only at successful completion, exact shell match plus rc=0, and cleanup on every path.
- Keep environment scrubbing, `PYTHONSAFEPATH=1`, `-S`, controlled `PYTHONPATH`, file scripts, `git ls-tree` sentinels, and trusted-HEAD extraction unchanged and operative.
- Contract rows independently substitute a targeted rc=0/no-artifact control at each site; add wrong-ID, stale/wrong-nonce, cross-control reuse, successive-nonce freshness, and cleanup rows.
- For each of the four sites, mutate one unique shell requirement independently. Each mutant must fail exactly its site row (`verdict-s2-head-extract`, `verdict-s2-secret-scan`, `verdict-s3-head-extract`, `verdict-s3-protected-path`), leave all controls identical, and be rejected when an unmutated copy is supplied as the mutant.

Acceptance: `AC5-AC12`.

## Gate handoff

After T3, provide the three SHAs, approval mint/consumption evidence, pre/post line counts, targeted and full-suite results, six discriminator records (S2d, S2b, four S2c), mitigation inventory, and exact-SHA dual-platform workflow URLs. No implementation claim is accepted from aggregate GREEN without the named mutation evidence.
