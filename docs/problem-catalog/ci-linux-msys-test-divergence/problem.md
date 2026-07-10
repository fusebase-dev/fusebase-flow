# Problem: tests that pass on MSYS-local FAIL on Linux CI (and the composed suite hid it) — four distinct env-divergence pitfalls

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

Reproduces: 3/3 on CI (deterministic per platform).

## Root cause — four env-specific assumptions MSYS-local runs mask

1. **Shallow checkout breaks `HEAD~1`.** `actions/checkout` defaults to `fetch-depth: 1` (one commit). `test-po-investigate.sh` runs `git diff HEAD~1 HEAD` → `HEAD~1` doesn't exist → git **rc=128** (×5 cases). Local full clones always have `HEAD~1`. **Fix: `fetch-depth: 0` in the checkout step.**
2. **A PATH-dir mask removes git on Linux.** `test-bootstrap-exception.sh` masked `python3` by dropping every PATH dir that contains a python. On `ubuntu-latest` `git` and `python3` **share `/usr/bin`**, so dropping it also removed `git` → the hook's initial `git rev-parse --show-toplevel` guard treated the run as outside a git repo, printed its skip warning, and **exited 0 there** (the test mis-tested, not a real fail-open); it never reached the §3 `git diff --cached` logic. On MSYS git/python live in separate dirs, so the mask kept git → the hook reached its real warn → passed. **Fix: a git-preserving mask (symlink a curated bin excluding only python) + a precondition asserting git survives.**
3. **`chmod +x` dirties the working tree.** 32 of the hook `.sh` files are committed `100644` (Windows contributors can't reliably set exec bits). CI's "Make scripts executable" step `chmod +x` flips them to `755` → git sees a mode change → the "Working-tree clean check" fails. **Fix: `git config core.fileMode false` in the workflow** (scripts are always invoked via `bash`, so the exec bit is functionally irrelevant).
4. **A new health-check critical needs a manifest in test fixtures.** After v4.2.0 replaced the hook-tests critical with the hook-layer manifest verify, `test-cli-flow-recovery.sh`'s fixtures (which run the main health engine expecting HEALTHY) lacked `verify-hook-manifest.sh` + a manifest → the critical returned **UNVERIFIED → PARTIAL_UNVERIFIED** where HEALTHY was expected. **Fix: copy the stamp/verify scripts + stamp a fresh manifest in each fixture before the health-engine call.**

## Why it matters

- A test can be **green locally and red on CI** (pitfalls 1/3) — or worse, **silently mis-test** (pitfall 2: it looked like it exercised the python3-absent path but actually removed git), giving false confidence.
- Adding a health-check critical (pitfall 4) silently breaks every test fixture that drives the engine.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v4.2.0 CI green-up: `fetch-depth: 0` (`fe62d34`), git-preserving mask (`8378265`), `core.fileMode false` (`34409e1`), fixture manifest stamp (`ffe879e`). First fully-green CI run in repo history: `34409e1`. |

## Recurrence triggers (so future sessions recognize this)

- A test uses `git diff HEAD~1` / `git log -2` / any history depth ≥ 2 → will fail on a shallow CI checkout (`rc=128`, "unknown revision HEAD~1").
- A test masks a tool by dropping PATH dirs → on Linux the target shares a dir with git/coreutils, so the mask collaterally removes them.
- `git status --porcelain` dirty on CI with a list of `.sh` files as `M` (mode-only) → committed `100644` + `chmod +x`.
- A newly-added health-check critical → test fixtures that run the engine now return UNVERIFIED/BROKEN.
- General signal: "the suite is green on Windows but red on CI" / "it passed locally."

## Guardrail (the lesson)

**MSYS-local and Linux-CI hide DIFFERENT failures — a green local run is not a green CI run.** Concretely: (1) any history-dependent test needs `fetch-depth ≥ 2`; (2) never mask a tool by dropping PATH dirs — symlink a curated bin and ASSERT the tools you meant to keep still resolve; (3) commit scripts executable OR set `core.fileMode false` in CI; (4) when you add a health-check critical, update every fixture that drives the engine; (5) run the FULL composed suite on BOTH platforms (or gate on CI) before trusting green — the release gate ([[ci-red-invisible-no-release-gate]]) now enforces the CI half.

## Related

- [[ci-red-invisible-no-release-gate]] — why these were invisible for ~3 releases.
- `.github/workflows/fusebase-flow-verify.yml` — `fetch-depth: 0` + `core.fileMode false`.
- `hooks/tests/{test-po-investigate.sh, test-bootstrap-exception.sh, test-cli-flow-recovery.sh}` — the fixed tests.
