# Pre-commit trusted-tool contract

Status: `DRAFT`  
Change tier: `Full`  
Decision lock: `LOCKED — A2 + B1` (`decisions.md`)  
Implementation authorization: `GRANTED`

## Problem

- `hooks/git/pre-commit:20-24` conflates unusable Git inside repository context with genuine outside-repository execution and exits 0 for both, skipping FR-12 §2 and FR-07 §3.
- `hooks/git/pre-commit:213,316,503,678` accepts process status 0 without positive evidence that the named Python control completed.
- `hooks/git/pre-commit:87` accepts a resolved `python3` without the ≥3.10 probe already applied to fallback interpreters.

## Clarify summary

The operator supplied the compatibility set, mutation-proof contract, protected-path procedure, residual-threat boundary, and locked A2/B1. No implementation choice remains open.

## North-star alignment

On-vision: the change strengthens the fail-closed safety kernel through executable mechanisms while adding no ordinary-consumer workflow gate (`docs/north-star.md:18,31-34`).

## In scope

| Slice | Required behavior |
|---|---|
| S2d | Apply the same Python ≥3.10 probe to a resolved primary `python3`; refuse it with the existing attributable BLOCK diagnostic when unsupported. |
| S2b / A2 | Before allowing the root-query skip, classify repository context independently: upward `.git` directory or file evidence, explicit `GIT_DIR` / `GIT_WORK_TREE` context, and bare-repository evidence. Repository evidence plus unavailable/unusable Git blocks; no evidence preserves exit 0. |
| S2c / B1 | For each Python control, shell creates a fresh per-invocation nonce; the wrapper writes the exact control ID plus nonce only at successful completion; shell requires exact content in addition to rc=0 and removes the artifact. |
| Proof | Add direct contract tests and one mutation discriminator per new control, following `hooks/tests/test-pre-commit-interpreter-mutation.sh`. |

Control IDs are fixed: `ffpc-s2-head-extract`, `ffpc-s2-secret-scan`, `ffpc-s3-head-extract`, `ffpc-s3-protected-path`.

## Out of scope

- Authenticating Git, Python, `.git` evidence, verdict artifacts, or workspace state.
- Adding a remote/signature trust root, pinning interpreter binaries, or changing the threat model.
- Weakening, replacing, or bypassing any existing FR-07/FR-12 mitigation.
- Deploy, release, policy, workflow-trigger, or unrelated hook behavior changes.

## Compatibility contract

- Normal repositories, nested working directories, linked worktrees, and submodules must reach the existing controls when Git works; `.git` file evidence is equal to `.git` directory evidence.
- Explicit `GIT_DIR` / `GIT_WORK_TREE` invocation must retain working behavior and must block, not skip, when that declared context exists but Git is unusable.
- A bare repository with functioning Git retains its current non-blocking no-worktree behavior; bare evidence plus broken Git blocks.
- A genuine outside-repository invocation with no repository evidence retains the current diagnostic and exit 0.

## Invariants

- Preserve environment sanitization at `hooks/git/pre-commit:28-45`, `PYTHONSAFEPATH=1`, `-S` on every Python invocation, controlled `PYTHONPATH`, file-script control wrappers, shell-side `git ls-tree` sentinels, and trusted-HEAD extraction.
- Verdict artifacts are per-control, exact-match, non-reusable, removed on success and failure, and never treated as authentication.
- `hooks/git/pre-commit` is 731 lines at plan time: 69 lines remain below the FR-25 ceiling of 800. If projected above 800, extract the post-control verdict protocol to `hooks/git/lib/pre-commit-verdict.sh`, materialized from committed HEAD before use; keep pre-Git repository classification inline.
- `hooks/git/**` is FR-07 protected. Every implementation commit touching it uses a sanctioned approval writer, a normal verified commit, and approval consumption. `--no-verify` is forbidden.

## Acceptance criteria

- **AC1:** A resolved `python3` reporting Python <3.10 or failing the version probe is refused before §2/§3 with the existing attributable BLOCK diagnostic; supported `python3`, `python`, and `py -3` paths still work.
- **AC2:** From a normal repository with `.git` evidence, unavailable Git, nonzero root discovery, an empty/bogus root, or an unusable returned root blocks nonzero with a repository-context/Git diagnostic.
- **AC3:** From a directory with no repository evidence and no explicit Git context, the same unavailable/broken Git condition still prints the outside-repository skip and exits 0.
- **AC4:** Contract rows pass for normal repos, nested directories, linked worktrees, submodules, explicit `GIT_DIR` / `GIT_WORK_TREE`, and functioning bare repos; `.git` directory and file forms are tested separately.
- **AC5:** Each fixed verdict ID blocks with an attributable message when its targeted Python process exits 0 but creates no verdict artifact.
- **AC6:** Each verdict site accepts only its exact ID plus its fresh shell-issued nonce; wrong ID, stale/wrong nonce, or a prior artifact blocks, and artifacts are absent after every success/failure path.
- **AC7:** The S2d, S2b, and four-site S2c controls each have a mutation discriminator: unique target; unmutated baseline GREEN; mutant fails exactly its named row; all prerequisite/control rows identical; unmutated negative control makes the harness reject the mutant claim.
- **AC8:** Tests mechanically confirm all invariants above remain present and operative, including `-S` and controlled `PYTHONPATH` at all four verdict sites and the version probe.
- **AC9:** No new comment, diagnostic, test name, or documentation calls A2/B1 authentication, a trust root, tamper-proofing, or proof of executable identity.
- **AC10:** `bash -n`, targeted contract/mutation tests, the full hook suite, runner-parity checks, preflight, and the module-size gate pass without modifying production files during mutation tests.
- **AC11:** Three ordered commits implement T1 → T2 → T3; each contains its control and discriminator, cites its T-number, uses/consumes FR-07 approval, and does not stage or modify unrelated `docs/wasted-code/`.
- **AC12:** `fusebase-flow-verify` is manually run by `workflow_dispatch` on the final SHA; `verify-linux`, `verify-windows-msys`, and `verify-gate` are GREEN for that SHA. The workflow retains no `push` or `pull_request` trigger, so a push runs nothing.

## Risks

| Risk | Required containment |
|---|---|
| Consumer incompatibility | AC3-AC4 matrix is blocking, not advisory. |
| Theatre tests | AC7 mutation evidence is mandatory per control; aggregate GREEN alone is insufficient. |
| Size growth | Enforce the 800-line ceiling and named verdict-protocol extraction seam. |
| Protected-path bypass | Sanctioned approval + normal commit + consumption only; never `--no-verify`. |

## Residual risk

An attacker who controls `PATH` can still supply a smart Git or Python shim that returns plausible repository/version results, inspects arguments, scripts, environment, nonce, and temp paths, and fabricates the expected unsigned verdict. A same-principal attacker can also alter local `.git` or workspace evidence. A2 detects repository-context Git faults and B1 detects non-cooperating/incomplete controls; neither authenticates Git or Python. Future comments, messages, and docs must not claim otherwise.
