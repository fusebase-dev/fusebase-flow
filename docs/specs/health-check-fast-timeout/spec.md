# Spec — health-check-fast-timeout

**Status:** DONE (shipped v3.24.0, 2026-06-15; 4 Codex review rounds → SHIP)
**Created:** 2026-06-14
**Baseline:** FuseBase Flow v3.23.1
**Deploy hash:** a3d41fa (a3d41fabd95b57612400fb99a0d6e34767b3cbff) — tag v3.24.0; release https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.24.0
**Source:** real consumer install (Windows/schannel-impaired) — `fusebase-flow-health-check.sh` did not return within 2 minutes during install; reproduced in the maintenance session. Backlog: `docs/backlog/health-check-fast-timeout/`.
**Design review:** Codex 2026-06-14 → **BUILD-WITH-CHANGES**; biggest risk = **false-HEALTHY when a critical check doesn't run.** All findings folded (new `PARTIAL_UNVERIFIED` verdict; bound `check-cli-flow-conflicts` too; fix the pre-existing run-tests rc-masking; split `--fast`/`--no-upstream`; `gtimeout` fallback; SLO-budgeted timeouts).

## Problem (grounded in the script)
`hooks/local/fusebase-flow-health-check.sh` (633 lines) can exceed two minutes and **appear to hang** during installs. Unbounded, verdict-affecting operations:
1. **Network git fetch — line 465:** `git fetch origin --tags >/dev/null 2>&1 || true` (Section 2 upstream comparison; runs when `.fusebase-flow-source/.git` exists). `|| true` prevents failure, not a *hang* on a network-impaired host.
2. **`preflight.sh` — line 363** and **`run-tests.sh` — line 371** sub-invocations (BROKEN-determining; `run-tests` is slow regardless of network).
3. **`check-cli-flow-conflicts.sh` — line 411** (drift/BROKEN-determining; does repeated full-tree `root.rglob("*")` scans — slow in large repos). **Missed by the first draft; added per design review.**

`timeout(1)` confirmed available in Git-Bash (`/usr/bin/timeout`); macOS commonly has `gtimeout` not `timeout`.

## The core risk (design-review blocker) → the fix
Bounding/skipping these checks naively creates a **false HEALTHY**: today an empty `LOCAL_BROKEN` ⇒ HEALTHY/exit 0, and `run-tests` is read via `|| true` (so a harness *crash* with no `FAIL:` line already reads OK). A timed-out or skipped **critical** check must therefore be **distinct from "ran clean."** This ticket **intentionally changes verdict semantics** to add an "unverified" state.

### Verdict / exit-code contract (LOCKED)
| Condition | Verdict | Exit |
|---|---|---|
| All **critical** checks ran and passed; no drift/broken/deferred | `HEALTHY` | 0 |
| Real drift detected | `CLI_LAYER_DRIFT` / `FLOW_LAYER_DRIFT` / `SHARED_MERGE_DRIFT` | 1 |
| A **completed** critical check fails, **or** a sub-script rc≠0 with no parsable result (harness crash) | `BROKEN` | 2 |
| Only operator-authored exception artifacts remain | `EXCEPTION_IN_EFFECT` | 3 |
| A critical check was **skipped / timed out / unavailable** AND nothing completed proves BROKEN | **`PARTIAL_UNVERIFIED`** (new) | **4** |

- **Critical checks** (must run to claim full health): `preflight`, hook tests (`run-tests`), CLI/Flow conflict reporter (`check-cli-flow-conflicts`).
- **Optional check:** upstream comparison (`git fetch` + version diff) — may be unavailable **without** forcing exit 4, but the verdict text MUST say "upstream not verified".
- **Never exit 0 when a critical check did not run.**

## In scope
- **A — `run_with_timeout` helper:** detect `timeout` → `gtimeout`; wrap with `-k <grace>`; treat rc **124** as timeout; **preserve the wrapped command's own rc** otherwise (don't squash). For `git fetch` also set `GIT_TERMINAL_PROMPT=0` (+ low-speed config) so it fails fast, not on a prompt.
- **B — bound all 4 slow ops:** the git fetch (line 465) + the 3 sub-invocations (preflight 363, run-tests 371, check-cli-flow-conflicts 411). Network fetch timeout → optional "upstream not verified (fetch timed out)" note. A critical-check timeout → `LOCAL_UNVERIFIED` → `PARTIAL_UNVERIFIED`/exit 4 (never 0).
- **C — add `LOCAL_UNVERIFIED` tracking + the `PARTIAL_UNVERIFIED` verdict + exit 4** per the contract.
- **D — fix the pre-existing run-tests rc-masking:** rc≠0 with no parsable `FAIL:` (harness crashed before reporting) ⇒ `BROKEN` (not OK). Observed `FAIL:` before a timeout ⇒ `BROKEN`; timeout with no observed `FAIL:` ⇒ `UNVERIFIED`.
- **E — flags:** `--no-upstream` = full local health, may exit 0 (upstream is optional). `--fast` = skips hook tests (and upstream) for a quick verdict — keeps `preflight` + local inventory + conflict reporter — but is **explicitly partial: exit 4, never 0**, and prints "fast mode — not a full health verdict."
- **F — SLO-budgeted defaults** (env-overridable): fetch ~10–15s, preflight ~20–30s, conflict reporter ~20–30s, hook tests ~45–60s. Document the worst-case full-run bound. Consider optimizing the conflict reporter's `root.rglob("*")` to scan only target dirs (perf, optional).
- **G — `timeout`-missing default:** if neither `timeout` nor `gtimeout` exists, **skip the bounded-only slow ops and return `PARTIAL_UNVERIFIED`** (do NOT run unbounded by default); allow opt-in unbounded via an explicit env var.

## Out of scope
- Drift-detection signatures themselves (we add `UNVERIFIED`, we don't change what counts as CLI/FLOW/SHARED drift).
- `test-cli-flow-recovery.sh` per-fixture clone slowness (separate test-harness follow-up).
- FR rule rows / deploy policies / `ratchet-governance.yml` — untouched.

## Decisions (H1–H5, revised per design review — LOCKED)
| # | Decision | Change from draft |
|---|---|---|
| H1 | **Per-op `run_with_timeout`** on ALL verdict-affecting slow ops — incl. `check-cli-flow-conflicts` (not just the 3 first-named). | Added the missed conflict reporter. |
| H2 | **SLO-budgeted timeouts** (env-overridable), not arbitrary large values; document worst-case bound. | Was 15+60+60 (>2min); re-budgeted. |
| H3 | **Split `--no-upstream` (exit 0 OK) from `--fast` (exit 4, never 0)**; both keep preflight. | `--fast` was conflated; now explicitly partial. |
| H4 | **Timeout/skip of a CRITICAL check ⇒ `PARTIAL_UNVERIFIED`/exit 4** (new state); only the upstream comparison may be "unavailable" without exit 4. Never exit 0 when a critical check didn't run. | Was "unavailable, not drift" — corrected (that was the false-HEALTHY blocker). |
| H5 | **`timeout`-missing ⇒ skip bounded slow ops + `PARTIAL_UNVERIFIED`** (detect `gtimeout` first); opt-in unbounded via env only. | Was "run unbounded + note" — would hang; corrected. |
| H6 (new) | **Preserve sub-script rc** — rc≠0 + no parsable result ⇒ `BROKEN` (fixes a pre-existing false-HEALTHY where a `run-tests` crash read OK via `|| true`). | New, from design review. |

## Acceptance criteria
- **AC1** `.fusebase-flow-source/.git` present + network unreachable ⇒ engine returns within ~(fetch-timeout + slack), reports "upstream not verified (fetch timed out)", and **upstream alone does NOT force exit 4** (it's optional) — **no hang.** (Test: stub `git`/unreachable origin.)
- **AC2** A **critical** check (preflight/run-tests/conflict) that times out or is skipped ⇒ `PARTIAL_UNVERIFIED` **exit 4**, never 0; the report names which check is unverified.
- **AC3** Full run, network reachable, all checks pass ⇒ **same `HEALTHY`/exit 0** as today (no regression to drift detection or the in-sync/behind paths).
- **AC4 (false-HEALTHY guards)** (a) a real preflight failure still ⇒ `BROKEN`/2 even with timeouts in place; (b) a `run-tests` harness crash (rc≠0, no `FAIL:`) ⇒ `BROKEN`/2 (H6), not HEALTHY; (c) `--fast` HEALTHY-looking output ⇒ **exit 4**, not 0.
- **AC5** `--no-upstream` ⇒ full local verdict, may exit 0; `--fast` ⇒ exit 4 + "not a full verdict"; both run preflight.
- **AC6** `timeout`/`gtimeout` both absent ⇒ engine still returns (no crash, no hang) with `PARTIAL_UNVERIFIED` (or opt-in unbounded via env).
- **AC7** Standard gate: preflight 0/0; run-tests PASS; recovery-sim PASS (+ new fixtures: fetch-timeout-not-hang; critical-timeout→exit4; harness-crash→BROKEN; fast-mode→exit4; timeout-missing→partial); health HEALTHY; mirror drift 0; plugin valid; `internal/`+`repo-polish` untracked.
- **AC8** Docs: `--fast`/`--no-upstream` + timeout env knobs + the new exit-4 `PARTIAL_UNVERIFIED` in the `fusebase-flow-health-check` skill + README; CHANGELOG + release notes + version bump. Update any caller/recovery flow that keys off exit codes to handle exit 4.

## Tasks (rough — firm at planning)
- **Ta** `run_with_timeout` helper (timeout/gtimeout detect, `-k`, rc preservation, 124=timeout, GIT_TERMINAL_PROMPT=0) (A,H1,H5).
- **Tb** Add `LOCAL_UNVERIFIED` + `PARTIAL_UNVERIFIED`/exit 4 + the locked contract (C,H4).
- **Tc** Wrap the 4 slow ops; upstream→optional note, criticals→UNVERIFIED on timeout (B).
- **Td** Fix run-tests rc handling (rc≠0+no FAIL ⇒ BROKEN; partial FAIL ⇒ BROKEN; timeout-no-FAIL ⇒ UNVERIFIED) (D,H6).
- **Te** `--no-upstream` (exit 0 OK) + `--fast` (exit 4) flags (E,H3).
- **Tf** SLO-budgeted defaults + env knobs; optional conflict-reporter glob optimization (F,H2).
- **Tg** Tests (AC1–AC6 fixtures) + update exit-code-aware callers (AC7/AC8).
- **Th** Docs + CHANGELOG + release notes + version bump; mirror if overlay copy exists.
- Gate → deploy.

### Implemented tasks (T1–T12 → SHA, shipped v3.24.0)
| T | Maps to | SHA | Description |
|---|---|---|---|
| T1 | Ta | 73afb1e | run_with_timeout helper lib + source it in health-check engine |
| T2 | Tb | e88dd0a | LOCAL_UNVERIFIED tracking + PARTIAL_UNVERIFIED verdict + exit 4 |
| T3 | Tc | 92b8ead | bound all 4 slow ops; criticals→UNVERIFIED, upstream→note-only |
| T4 | Td | db68b20 | fix run-tests rc-masking (H6) — harness crash ⇒ BROKEN |
| T5 | Te | 758638c | --no-upstream (exit 0 OK) and --fast (exit 4, never 0) flags |
| T6 | Tf | c2cf8f0 | document worst-case bound + scope conflict-reporter glob scan |
| T7 | Tg | 902232c | tests for AC1–AC6 + AC8 caller note + test-driven hardening |
| T8 | Th | 139689c | health-check fast-timeout docs + v3.24.0 bump (AC8) |
| T9 | — | de6c53f | treat rc 137 as timeout-induced in run_with_timeout (Codex B2) |
| T10 | — | 1670896 | require a non-empty PASS line for hook-tests OK (Codex A1) |
| T11 | — | 3628f41 | reword unverified-block to not assert PARTIAL_UNVERIFIED (Codex B1) |
| T12 | — | 6fd2f9d | extract HT health-check-timeout fixtures to own test file (Codex A2) |

Post-gate Codex hardening (round-2/round-3, not T-numbered): ebafd41 (validate PASS counts — round-2 A1), 9294b08 (close two residual PASS-classifier spoofs — round-3 A1+A2). Step-0 threat-model note (round-4): c4252a8. Release-date set: a3d41fa.

## Notes
- One engine script + tests + docs. FR-25: currently 633 lines; the additions (helper + UNVERIFIED + flags) may approach 800 — extract the timeout helper / verdict logic along a clean seam if so.
- **New exit code 4 is a contract change** — sweep for any consumer/recovery script or hook that branches on the health-check exit code and teach it exit 4 = partial/unverified (not failure, not full health).
