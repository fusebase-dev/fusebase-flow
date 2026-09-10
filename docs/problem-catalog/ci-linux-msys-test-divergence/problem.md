# Problem: tests that pass on one release platform fail on the other — six distinct env-divergence pitfalls

**Slug:** `ci-linux-msys-test-divergence`
**Filed:** 2026-07-09
**Severity:** high
**Status:** resolved per pitfall; pitfall 2 RECURRED in a new carrier (v4.16.0), and its ratchet GATES the tagged two-platform run from v4.16.2
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
| 5 | v4.16.0 (2026-09-10): `FF_RELEASE=1` profile on the tagged SHA `a62e362` | `verify-windows-msys` 682/682, `verify-linux` **681/682** — 1 FAIL, pitfall 7 |
| 6 | same tree in an `ubuntu:24.04` container (`apt` python3 at `/usr/bin`), `bash hooks/tests/test-hop-log-truthfulness.sh` | 17/18 — reproduced `rc 127` locally in ~40 s, no CI round-trip |

Reproduces: 3/3 on CI (deterministic per platform). **Reproduce locally without CI:** clone the repo INSIDE an `ubuntu:24.04` container (`git clone /src /work`, never a bind-mounted dirty worktree), `git config core.fileMode false`, `chmod +x`, then run the workflow's steps in order — this reproduced pitfall 5 in ~50 s, versus a CI round-trip whose logs need auth.

## Root cause — six environment-specific assumptions one platform can mask

1. **Shallow checkout breaks `HEAD~1`.** `actions/checkout` defaults to `fetch-depth: 1` (one commit). `test-po-investigate.sh` runs `git diff HEAD~1 HEAD` → `HEAD~1` doesn't exist → git **rc=128** (×5 cases). Local full clones always have `HEAD~1`. **Fix: `fetch-depth: 0` in the checkout step.**
2. **A PATH-dir mask removes git on Linux.** `test-bootstrap-exception.sh` masked `python3` by dropping every PATH dir that contains a python. On `ubuntu-latest` `git` and `python3` **share `/usr/bin`**, so dropping it also removed `git` → the hook's initial `git rev-parse --show-toplevel` guard treated the run as outside a git repo, printed its skip warning, and **exited 0 there** (the test mis-tested, not a real fail-open); it never reached the §3 `git diff --cached` logic. On MSYS git/python live in separate dirs, so the mask kept git → the hook reached its real warn → passed. **Fix: a git-preserving mask (symlink a curated bin excluding only python) + a precondition asserting git survives.**
3. **`chmod +x` dirties the working tree.** 32 of the hook `.sh` files are committed `100644` (Windows contributors can't reliably set exec bits). CI's "Make scripts executable" step `chmod +x` flips them to `755` → git sees a mode change → the "Working-tree clean check" fails. **Fix: `git config core.fileMode false` in the workflow** (scripts are always invoked via `bash`, so the exec bit is functionally irrelevant).
4. **A new health-check critical needs a manifest in test fixtures.** After v4.2.0 replaced the hook-tests critical with the hook-layer manifest verify, `test-cli-flow-recovery.sh`'s fixtures (which run the main health engine expecting HEALTHY) lacked `verify-hook-manifest.sh` + a manifest → the critical returned **UNVERIFIED → PARTIAL_UNVERIFIED** where HEALTHY was expected. **Fix: copy the stamp/verify scripts + stamp a fresh manifest in each fixture before the health-engine call.**

5. **A synthetic fixture built without `.gitattributes` + `core.autocrlf=true` ships CRLF `.sh`; only MSYS bash tolerates CR.** (v4.7.0 release run, 2026-07-29 — `test-upgrade-conflict-classification.sh` §7 `t29c-classification-eol-stable-under-autocrlf-true`.) The case clones a fixture upstream with `git -c core.autocrlf=true clone` to prove the classifier is EOL-stable. The fixture is a bare `git init` repo with **no `.gitattributes`**, so `hooks/local/bootstrap-upgrade.sh` copied into it lands **CRLF** on checkout. Git-for-Windows bash strips the trailing CR and runs the script; **Linux bash does not** — `line 48: $'\r': command not found`, `line 49: set: pipefail: invalid option name` → the engine never ran → `[no base synthesis]` → FAIL. The **shipped** product is unaffected: the real `.gitattributes` pins `*.sh text eol=lf`, so a real consumer's autocrlf=true clone gets LF scripts. **Fix (test, not code): give the fixture the same `*.sh text eol=lf` pin the product ships.** Scripts land LF and run; `workflows/wf.md` (unpinned) still lands CRLF, so the assertion keeps its teeth.

6. **Native Windows Python emits CRLF on a typed multi-line surface list.** (v4.15.0 release repair, 2026-09-07.) `post-fusebase-update.sh` compared each `ffhc_hwi_surfaces` line byte-for-byte. Native Python emitted `claude_settings\r\ngit_hooks\r\n`; Bash `read` retained the terminal CR, so automatic recovery missed `claude_settings` while accepting the last `git_hooks` value after command substitution removed its final newline. **Fix: remove exactly one terminal CR at the typed-output boundary before exact membership comparison; LF/CRLF positives and prefix/suffix negatives preserve the allowlist.**

7. **Pitfall 2 recurred in a NEW carrier — a PATH-dir mask that removes the shell itself.** (v4.16.0 tagged gate, 2026-09-10.) `hooks/tests/test-hop-log-truthfulness.sh:307-333` (slice D1) built its python3-less PATH with `path_without_python3()`: enumerate `$PATH`, drop every dir holding `python3`. On `ubuntu-latest` that dir is `/usr/bin`, which also holds `bash`, `grep` and `sed` — so `bash hooks/local/post-fusebase-update.sh` died **rc 127** before the script's first line. Observed `rc 127` / state `unknown` / "cannot say"; expected `rc 2` / `unavailable` / settings-not-touched. Worse than a red row: **the row had never exercised the python3-less branch on Linux at all**, so the documented `rc 2` behaviour was neither confirmed nor refuted there — a caller reporting an outcome it never observed, which is the exact defect class the S1 suite exists to close. **Fix: route D1 through `mpf_build`/`MPF_PATH` (`hooks/tests/lib/minimal-path-fixture.sh`), which resolves tools BY NAME and re-exposes absolute-exec shims, plus an explicit `rc 127 => the child never started` anti-vacuity assertion.** Production was NOT defective: under the corrected fixture the recovery reaches `post-fusebase-update.sh:245-248` and publishes `settings=unavailable detail=recovery aborted before its settings step (python3 is unavailable for recovery plan validation); .claude/settings.json was not touched (rc 2)`.

### Why the existing tripwire did not prevent pitfall 7

| Control that existed | Scope | Why it missed |
|---|---|---|
| `minimal-path-fixture.sh:18-20` TRIPWIRE naming this exact hazard ("python3 and git share /usr/bin on Linux") | comment inside the fixture file | Read only by someone already editing the fixture; D1's author never opened it. |
| `test-minimal-path-fixture.sh` §1 `fixture-no-path-enumeration-loop` | greps **`$FIXTURE` only** | A mechanical guard aimed at the one file that was already correct. It could not see a suite next door re-inventing the pruning it forbids. |
| `cli-flow-recovery-direct.sh` `ffcf_t14_preflight` — already drives the same python3-less abort correctly via `mpf_build` | different suite | A correct sibling is not a constraint on a new one. |
| Two-platform release gate | tagged SHA | Caught it, but only AFTER `v4.16.0` was tagged and immutable. |

**What would have caught it before a tagged cut:** a source-level check binding the AC7 rule to the fixture's *callers*, not just the fixture. Shipped in v4.16.1 as `test-minimal-path-fixture.sh` §1b `callers-no-unreviewed-path-enumeration` — scan `hooks/tests/**.sh` for `for X in $PATH`, compare against a reviewed allowlist, red on any new site. It is a grep over source, so its verdict is identical on MSYS and Linux and needs no platform to reproduce. Verified non-vacuous: reverting D1 to the enumerating version makes the row FAIL naming both files.

**The control now gates (v4.16.2), stated exactly — overstating a guard is this entry's own defect class.** `minimal-path-fixture` is in `FF_RELEASE_TAGS`, so `test-minimal-path-fixture.sh` (the §1b caller ratchet included) runs on `verify-linux` AND `verify-windows-msys` for every tagged SHA: a new `for X in $PATH` site is red on the run that blocks publication, not only when someone chooses `FF_FULL=1`. Cost is ~21 s for 18 rows on MSYS, the slower leg. Guardrail 8 is the reason that release exists.

**What it still does not do.** The tag stays OUT of `FF_FAST_TAGS` (local default) and out of `fusebase-flow-maintainer.yml`'s `FF_ONLY` list, so the earliest AUTOMATIC red is the tagged gate — pre-tag it fires only under `FF_FULL=1` or `FF_ONLY=minimal-path-fixture`. That is later than the commit that introduces a new site, and earlier than a published release.

## Why it matters

- A test can be **green locally and red on CI** (pitfalls 1/3) — or worse, **silently mis-test** (pitfall 2: it looked like it exercised the python3-absent path but actually removed git), giving false confidence.
- Adding a health-check critical (pitfall 4) silently breaks every test fixture that drives the engine.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | v4.2.0 CI green-up: `fetch-depth: 0` (`fe62d34`), git-preserving mask (`8378265`), `core.fileMode false` (`34409e1`), fixture manifest stamp (`ffe879e`). First fully-green CI run in repo history: `34409e1`. |
| Shipped | v4.7.0 release-run green-up (pitfall 5): fixture `*.sh text eol=lf` pin (`8d3c007`). Reproduced in an `ubuntu:24.04` container cloning the repo at HEAD and mirroring every workflow step: RED 662/663 before, GREEN 663/663 after, all 8 remaining CI steps rc=0. |
| Verified locally | T61 v4.15.0 release repair (pitfall 6): one-CR normalization at the exact typed-output boundary, with LF/CRLF positive and prefix/suffix negative controls. Publication is reserved for v4.15.1. |
| Shipped | v4.16.1 (pitfall 7): D1 routed through `mpf_build`/`MPF_PATH` plus an `rc 127` anti-vacuity assertion; `test-minimal-path-fixture.sh` §1b caller ratchet; a surviving-toolchain guard on the one remaining reviewed enumerator (`test-cli-version-gate.sh` `path_without_fusebase`). Reproduced RED 17/18 and proved GREEN 18/18 in `ubuntu:24.04` with `/usr/bin/python3`. |
| Published | `v4.16.1` (`3515ce6`, 2026-09-10): both legs 682/682 across 31 phases, `verify-gate` and `publish` green — [run `34441536913`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34441536913). The D1 row now passes on Linux by reaching its subject, not by avoiding it. |
| Shipped | v4.16.2: `minimal-path-fixture` joins `FF_RELEASE_TAGS` (32-tag allowlist; `test-ff-only.sh` size assertion 31 -> 32), so the caller ratchet is selected by the tagged two-platform gate instead of only by an explicit local choice. Audited for platform assumptions in the same change per the trigger below: 18/18 in `ubuntu:24.04` with `/usr/bin/python3`, 18/18 on MSYS. |
| Published | `v4.16.2` (`46d1125`, 2026-09-10): both legs **700/700 across 32 phases** — `verify-linux` 2.9 min, `verify-windows-msys` 20.4 min, `verify-gate` and `publish` green — [run `34444312839`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34444312839). The caller ratchet's 18 rows are inside that total on both platforms, which is what "gates" means here. |
| Tagged, NOT published | v4.16.3 (`022b011`): four phases join `FF_RELEASE_TAGS` (36-tag allowlist; `test-ff-only.sh` size assertion 32 -> 36) — `cli-rendered`, `recovery-hint`, `stamp-eol-guard`, `cli-flow-recovery-selectors`. Audited per the trigger below BEFORE tagging: all four green in `ubuntu:24.04` with row counts identical to MSYS (7/6/18/11), and green on MSYS. `preboundary-consumed` was measured (204 s MSYS, 13 engine hops) and DECLINED on cost, not promoted blind. The audit surfaced one latent portability defect it did not have to fix: `test-recovery-owned-bootstrap.py` spawns `python`, not `python3`, so `cli-flow-recovery`'s T34 group is red in a container that has only `python3` (GitHub's runners provide both via `setup-python`, which is why the already-gated parent phase has never reddened CI). |
| Outcome | The `v4.16.3` tagged gate went RED for an unrelated reason: `secret-scan-staged`, a pre-existing profile member untouched by the release, hit its 1800 s bound on `verify-windows-msys` (98 s on the green v4.16.2 run of the same code). `verify-linux` 3.2 min green; the four promoted phases cost 4 s / 5 s / 1 s / 32 s there, so the platform audit above held. Recorded under `msys-git-command-substitution-hang`; the tag stays immutable and unmoved. |

## Recurrence triggers (so future sessions recognize this)

- A test uses `git diff HEAD~1` / `git log -2` / any history depth ≥ 2 → will fail on a shallow CI checkout (`rc=128`, "unknown revision HEAD~1").
- A test masks a tool by dropping PATH dirs → on Linux the target shares a dir with git/coreutils, so the mask collaterally removes them.
- **rc 127 from a child the test spawned under a constructed PATH** → the subject never started, so the row's assertions describe the fixture, not the product. Never read a downstream `unknown`/default state as behaviour while rc is 127.
- **A suite is ADDED to `FF_RELEASE_TAGS`** → rows that until then only ran on the maintainer's MSYS box now run on Linux for the first time. Audit the new phases for platform assumptions in the SAME change (v4.16.0's only additions were `hop-log-truth` and `n4-parity-scope`; `hop-log-truth` carried pitfall 7. v4.16.2 added `minimal-path-fixture`, audited green on Linux in the same change); v4.16.3 added four, all audited green on Linux in the same change).
- **A test spawns `python` rather than `python3`** → green on MSYS and on hosted runners that provision both, red in a bare `ubuntu:24.04` container. Prefer `python3`, or resolve the interpreter by variable; never conclude from a bare-container `FileNotFoundError: 'python'` that the hosted Linux leg is red.
- `git status --porcelain` dirty on CI with a list of `.sh` files as `M` (mode-only) → committed `100644` + `chmod +x`.
- A newly-added health-check critical → test fixtures that run the engine now return UNVERIFIED/BROKEN.
- A test builds a synthetic git repo (`git init` + `git add`) and later checks it out with `core.autocrlf=true` (or `git archive` on such a tree) → any `.sh`/executable in that fixture lands CRLF and dies on Linux bash with `$'\r': command not found` / `set: pipefail: invalid option name`. Synthetic fixtures do NOT inherit the repo's `.gitattributes`.
- A native program emits a typed multi-line allowlist into Bash → remove one terminal CR at the read boundary before exact comparison; never replace the typed allowlist with substring matching.
- General signal: "the suite is green on Windows but red on CI" / "it passed locally."

## Guardrail (the lesson)

**MSYS-local and Linux-CI hide DIFFERENT failures — a green local run is not a green CI run.** Concretely: (1) any history-dependent test needs `fetch-depth ≥ 2`; (2) never mask a tool by dropping PATH dirs — symlink a curated bin and ASSERT the tools you meant to keep still resolve; (3) commit scripts executable OR set `core.fileMode false` in CI; (4) when you add a health-check critical, update every fixture that drives the engine; (5) a synthetic fixture inherits NONE of the repo's `.gitattributes` — if the test executes a script from it under `core.autocrlf=true`, pin `*.sh text eol=lf` in the fixture (MSYS bash tolerates CR, Linux bash does not); (6) normalize one terminal CR before exact typed-output comparisons; (7) run the FULL composed suite on BOTH platforms (or gate on CI) before trusting green — the release gate ([[ci-red-invisible-no-release-gate]]) now enforces the CI half; (8) **a rule that lives only inside the file it protects is a comment, not a control** — when a correct tool already exists (`mpf_build`), the guard must bind every CALLER by source scan, or the next author re-invents the banned construction in a file the guard never reads.

## Related

- [[ci-red-invisible-no-release-gate]] — why these were invisible for ~3 releases.
- `.github/workflows/fusebase-flow-verify.yml` — `fetch-depth: 0` + `core.fileMode false`.
- `hooks/tests/{test-po-investigate.sh, test-bootstrap-exception.sh, test-cli-flow-recovery.sh}` — the fixed tests (pitfalls 1/2/4).
- `hooks/tests/test-upgrade-conflict-classification.sh` §7 — the fixed test (pitfall 5); `.gitattributes` — the shipped `*.sh text eol=lf` pin the fixture now mirrors.
- `hooks/tests/lib/minimal-path-fixture.sh` — the one sanctioned interpreter-less PATH constructor; `hooks/tests/test-minimal-path-fixture.sh` §1b — the caller ratchet; `hooks/tests/test-hop-log-truthfulness.sh` D1 — the fixed row (pitfall 7).
- [[undecided-contract-drives-repeat-defects]] — same shape: a fix landed in one carrier and the contract was never bound across the caller family.
