# Active handoff — **v4.7.1 SHIPPED**. Nothing pending on this ticket.

**Updated:** 2026-08-05 (rev 7 — released) · **Deploy hash:** `3ae1feb` · **Release:** <https://github.com/fusebase-dev/fusebase-flow/releases/tag/v4.7.1>
Ticket `m19-recovery-hint-honesty` is **DONE**. This file exists only so the next session does not re-derive the shipped state. **No forward action is pending here** — the next ticket starts from a clean `main`.

## Shipped state

| | |
|---|---|
| `origin/main` | `cbda87e` → `3ae1feb` (14 commits, fast-forward) |
| Tag `v4.7.1` | **new** annotated tag at `3ae1feb`. `v4.7.0` untouched (`bad4d92`, published 2026-08-04T00:57:45Z) |
| GitHub Release | **published** 2026-08-05T05:30:48Z, not draft, not prerelease, target `main` |
| CI `fusebase-flow-verify` `30978106861` | **success** — 15/15 steps |
| CI `fusebase-flow-release` `30978179823` | **success** (`publish` is `needs: verify`, so a red suite cannot release) |
| Local gate — Linux `ubuntu:24.04` | **746/746 PASS**, 0 non-PASS, every CI-mirrored step rc 0 (`FAILED_STEPS=0`), 3.5 min |
| Local gate — Windows unscoped | **718/721 PASS**, 0 assertion failures. Three watchdog crossings — see below |
| FR-07 | empty diff `cbda87e..3ae1feb` on `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, `hooks/git/**` |
| Locked files | empty diff: M2 hashers, M3 `run-with-timeout.sh`, `.gitattributes`, `parked/` |
| Approval | `state/approvals/production_deploy-m19-recovery-hint-honesty-20260805.json` (repo-bound, command-bound to the `main` push) |

## What shipped — the M19 residual

M19 corrected the recovery hint's prose but left the same continuity claim alive in two other carriers. This release removes them and fixes the tests that failed to catch them.

| Task | Commit | Change |
|---|---|---|
| T1 | `d9856fc` | Deleted `# re-run; completes remaining steps` from the printed block and the sibling sentence from the `main()` header. Commands unchanged; nothing hedged — a qualification would restate the paragraph above it |
| T2 | `9bfba78` | Four assertion names made to agree with their predicates; one shared `CONTINUITY_RE` family now covers both carriers |
| T3 | `c6ebf68` | Release notes: per-assertion RED/PASS table; the control corrected from "the sixth" to **assertion 4** |
| T4 | `e67671a` | Manifest restamp (T1/T2 files) |
| T5 | `961d9f8` | Three review corrections, all class (a) text-only |
| T6 | `5696d8f` | Manifest restamp (T5 rename) |

**Discriminator.** Against `02d14f7`'s `upgrade.sh` the old test is 6/6 green; the widened test is 4/6, catching exactly `completes remaining steps` and the header's `also finishes the remaining steps`. Verified against `5b5578f`: 5 RED, assertion 4 the sole control.

The residual comment was inherited **verbatim** from pre-M19 `5b5578f` — M19 rewrote the prose above it and left the comment untouched. Defect class for the whole ticket: **a claim wider than the thing it describes**, which recurred inside the fix for it (T5).

## Windows gate — three ratified watchdog crossings, stated as they were

The Windows run was **not clean**. `718/721`, three non-PASS:

| Phase | Bound | Actual | Over by | Verdict |
|---|---|---|---|---|
| `cli-flow-recovery` | 900s | 903s | 0.3% | INCONCLUSIVE — previously ratified (D9) |
| `bootstrap-exception` | 600s | 602s | 0.3% | FAIL 124 — **ratified 2026-08-05** |
| `upgrade-repair-managed` | 600s | 603s | 0.5% | FAIL 124 — **ratified 2026-08-05** |

All three exited **124** (the watchdog, not an assertion); **zero assertions failed** anywhere; `bootstrap-exception` passed at **577s** on this same code in an earlier run; Linux was 746/746 on the identical commit. The operator moved the line deliberately and filed the underlying defect as `docs/backlog/gate-bounds-lack-headroom/README.md` (`3ae1feb`) rather than waiving the finding.

**Do not record this gate as clean.** The bar was "the ratified `cli-flow-recovery` INCONCLUSIVE as the only non-PASS"; the release proceeded on an explicit ratification of two further crossings, not on meeting that bar.

## Review

One Codex round over `02d14f7..e67671a`: **NO-SHIP, 3 findings, every one class (a) and text-only, zero class (b)** → fixed exactly those in T5 and released without a further round, per the standing authorization. Findings: #2/#6 named the general absence of continuity claims while testing one finite regex family; #4 claimed all recovery commands present but never anchors `fusebase-flow-health-check.sh`; the notes located all six assertions inside `print_recovery_hint` when #6 reads the header. #4 was **renamed rather than strengthened** — strengthening its predicate would have been class (b).

## Harness lessons (cost real time this cycle)

| Trap | Reality |
|---|---|
| `ps -W \| grep run-tests` | **Cannot work** — `ps -W` prints only exe paths, never script args. Detect competing suites via Win32 `CommandLine` (`Get-CimInstance Win32_Process`) |
| Linux container venv | A venv breaks `python3 -S` + `getsitepackages()` and manufactures **33 false FAILs**. CI installs flat — use `pip install --break-system-packages` on Ubuntu 24.04 |
| Mirror-drift step | Reset `audit/` first, or the two manifest-stamp steps above it get attributed to the mirrors |
| Manifest freshness | Any `hooks/**` edit restales both manifests; CI catches it, the local suite does not (`local-gate-misses-manifest-freshness`) |
| `MSYS_NO_PATHCONV=1` | Required for `docker run`, or MSYS rewrites `/gate.sh` into `C:/Program Files/Git/gate.sh` |

## Filed, deferred

New this cycle: `docs/backlog/gate-bounds-lack-headroom/README.md` — bounds are liveness backstops, not performance assertions; they need deliberate headroom (2–3×) against a *loaded-host* worst case.

Still parked: `compat-approval-surfacing` (needs a designed carrier table; M19 residual now closed out of it) · `self-granting-health-deferral` · `repair-trust-root-outside-workspace` · `command-gate-shell-evasion` · `approval-single-use-consumption` · `local-gate-misses-manifest-freshness`.
