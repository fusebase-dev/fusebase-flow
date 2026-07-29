# Problem: tests that pass on MSYS-local FAIL on Linux CI (and the composed suite hid it) — five distinct env-divergence pitfalls

**Slug:** `ci-linux-msys-test-divergence`
**Filed:** 2026-07-09
**Severity:** high
**Status:** resolved
**Filed by:** operator (per FR-15, during the v4.2.0 CI green-up)

## Symptom

Once the composed suite finally ran fully green on the MSYS box (`396/396`), the SAME suite failed on Linux CI (`ubuntu-latest`) with **four distinct failures in tests that pass locally** — and because the suite had never reached these steps on CI before (every prior run died at step 7, see [[ci-red-invisible-no-release-gate]]), the failures had been invisible. Fixing them was iterative: each fix exposed the next (a later step that had never run).

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | `run-tests.sh` on MSYS-local | 396/396 PASS |
| 2 | same suite on `ubuntu-latest` CI | 7 FAIL across 3 tests, then (after fixing those) 1 FAIL at the working-tree-clean step |
| 3 | v4.7.0 (2026-07-29): suite on MSYS-local | 665/666, 0 FAIL |
| 4 | same suite, `ubuntu:24.04` container, fresh `git clone` of the repo (not a bind-mounted worktree) | 662/663 — 1 FAIL, pitfall 5 |

Reproduces: 3/3 on CI (deterministic per platform). **Reproduce locally without CI:** clone the repo INSIDE an `ubuntu:24.04` container (`git clone /src /work`, never a bind-mounted dirty worktree), `git config core.fileMode false`, `chmod +x`, then run the workflow's steps in order — this reproduced pitfall 5 in ~50 s, versus a CI round-trip whose logs need auth.

## Root cause — five env-specific assumptions MSYS-local runs mask

1. **Shallow checkout breaks `HEAD~1`.** `actions/checkout` defaults to `fetch-depth: 1` (one commit). `test-po-investigate.sh` runs `git diff HEAD~1 HEAD` → `HEAD~1` doesn't exist → git **rc=128** (×5 cases). Local full clones always have `HEAD~1`. **Fix: `fetch-depth: 0` in the checkout step.**
2. **A PATH-dir mask removes git on Linux.** `test-bootstrap-exception.sh` masked `python3` by dropping every PATH dir that contains a python. On `ubuntu-latest` `git` and `python3` **share `/usr/bin`**, so dropping it also removed `git` → the hook's initial `git rev-parse --show-toplevel` guard treated the run as outside a git repo, printed its skip warning, and **exited 0 there** (the test mis-tested, not a real fail-open); it never reached the §3 `git diff --cached` logic. On MSYS git/python live in separate dirs, so the mask kept git → the hook reached its real warn → passed. **Fix: a git-preserving mask (symlink a curated bin excluding only python) + a precondition asserting git survives.**
3. **`chmod +x` dirties the working tree.** 32 of the hook `.sh` files are committed `100644` (Windows contributors can't reliably set exec bits). CI's "Make scripts executable" step `chmod +x` flips them to `755` → git sees a mode change → the "Working-tree clean check" fails. **Fix: `git config core.fileMode false` in the workflow** (scripts are always invoked via `bash`, so the exec bit is functionally irrelevant).
4. **A new health-check critical needs a manifest in test fixtures.** After v4.2.0 replaced the hook-tests critical with the hook-layer manifest verify, `test-cli-flow-recovery.sh`'s fixtures (which run the main health engine expecting HEALTHY) lacked `verify-hook-manifest.sh` + a manifest → the critical returned **UNVERIFIED → PARTIAL_UNVERIFIED** where HEALTHY was expected. **Fix: copy the stamp/verify scripts + stamp a fresh manifest in each fixture before the health-engine call.**

5. **A synthetic fixture built without `.gitattributes` + `core.autocrlf=true` ships CRLF `.sh`; only MSYS bash tolerates CR.** (v4.7.0 release run, 2026-07-29 — `test-upgrade-conflict-classification.sh` §7 `t29c-classification-eol-stable-under-autocrlf-true`.) The case clones a fixture upstream with `git -c core.autocrlf=true clone` to prove the classifier is EOL-stable. The fixture is a bare `git init` repo with **no `.gitattributes`**, so `hooks/local/bootstrap-upgrade.sh` copied into it lands **CRLF** on checkout. Git-for-Windows bash strips the trailing CR and runs the script; **Linux bash does not** — `line 48: $'\r': command not found`, `line 49: set: pipefail: invalid option name` → the engine never ran → `[no base synthesis]` → FAIL. The **shipped** product is unaffected: the real `.gitattributes` pins `*.sh text eol=lf`, so a real consumer's autocrlf=true clone gets LF scripts. **Fix (test, not code): give the fixture the same `*.sh text eol=lf` pin the product ships.** Scripts land LF and run; `workflows/wf.md` (unpinned) still lands CRLF, so the assertion keeps its teeth.

## Why it matters

- A test can be **green locally and red on CI** (pitfalls 1/3) — or worse, **silently mis-test** (pitfall 2: it looked like it exercised the python3-absent path but actually removed git), giving false confidence.
- Adding a health-check critical (pitfall 4) silently breaks every test fixture that drives the engine.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v4.2.0 CI green-up: `fetch-depth: 0` (`fe62d34`), git-preserving mask (`8378265`), `core.fileMode false` (`34409e1`), fixture manifest stamp (`ffe879e`). First fully-green CI run in repo history: `34409e1`. |
| Shipped | v4.7.0 release-run green-up (pitfall 5): fixture `*.sh text eol=lf` pin (`8d3c007`). Reproduced in an `ubuntu:24.04` container cloning the repo at HEAD and mirroring every workflow step: RED 662/663 before, GREEN 663/663 after, all 8 remaining CI steps rc=0. |

## Recurrence triggers (so future sessions recognize this)

- A test uses `git diff HEAD~1` / `git log -2` / any history depth ≥ 2 → will fail on a shallow CI checkout (`rc=128`, "unknown revision HEAD~1").
- A test masks a tool by dropping PATH dirs → on Linux the target shares a dir with git/coreutils, so the mask collaterally removes them.
- `git status --porcelain` dirty on CI with a list of `.sh` files as `M` (mode-only) → committed `100644` + `chmod +x`.
- A newly-added health-check critical → test fixtures that run the engine now return UNVERIFIED/BROKEN.
- A test builds a synthetic git repo (`git init` + `git add`) and later checks it out with `core.autocrlf=true` (or `git archive` on such a tree) → any `.sh`/executable in that fixture lands CRLF and dies on Linux bash with `$'\r': command not found` / `set: pipefail: invalid option name`. Synthetic fixtures do NOT inherit the repo's `.gitattributes`.
- General signal: "the suite is green on Windows but red on CI" / "it passed locally."

## Guardrail (the lesson)

**MSYS-local and Linux-CI hide DIFFERENT failures — a green local run is not a green CI run.** Concretely: (1) any history-dependent test needs `fetch-depth ≥ 2`; (2) never mask a tool by dropping PATH dirs — symlink a curated bin and ASSERT the tools you meant to keep still resolve; (3) commit scripts executable OR set `core.fileMode false` in CI; (4) when you add a health-check critical, update every fixture that drives the engine; (5) a synthetic fixture inherits NONE of the repo's `.gitattributes` — if the test executes a script from it under `core.autocrlf=true`, pin `*.sh text eol=lf` in the fixture (MSYS bash tolerates CR, Linux bash does not); (6) run the FULL composed suite on BOTH platforms (or gate on CI) before trusting green — the release gate ([[ci-red-invisible-no-release-gate]]) now enforces the CI half.

## Related

- [[ci-red-invisible-no-release-gate]] — why these were invisible for ~3 releases.
- `.github/workflows/fusebase-flow-verify.yml` — `fetch-depth: 0` + `core.fileMode false`.
- `hooks/tests/{test-po-investigate.sh, test-bootstrap-exception.sh, test-cli-flow-recovery.sh}` — the fixed tests (pitfalls 1/2/4).
- `hooks/tests/test-upgrade-conflict-classification.sh` §7 — the fixed test (pitfall 5); `.gitattributes` — the shipped `*.sh text eol=lf` pin the fixture now mirrors.
