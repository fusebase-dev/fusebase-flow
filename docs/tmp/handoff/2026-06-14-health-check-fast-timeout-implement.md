# Implement handoff — health-check-fast-timeout

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.23.1. Self-attest (FR-01..FR-26), IM.1..IM.18.
Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-13 (preflight per commit), FR-22 (comments), FR-25 (module<800).

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-26 (stop at Amendment log)
2. `docs/specs/health-check-fast-timeout/spec.md` — **LOCKED plan** (the verdict/exit contract, decisions H1–H6, AC1–AC8, tasks Ta–Th). Authoritative.
3. The engine you're changing: `hooks/local/fusebase-flow-health-check.sh` (633 lines) — read it fully. Note the slow ops at lines 363 (preflight), 371 (run-tests), 411 (check-cli-flow-conflicts), 465 (git fetch).
4. What it invokes: `hooks/local/preflight.sh`, `hooks/tests/run-tests.sh`, `hooks/local/check-cli-flow-conflicts.sh`.
5. `flow-skills/role-discipline/references/ai-developer.md`; `flow-skills/fusebase-flow-health-check/SKILL.md` (docs to update, AC8).

## Scope = Tasks Ta–Th (stop at gate)
Implement exactly the spec's LOCKED contract. The non-negotiable correctness core (do NOT get this wrong):
- **New `PARTIAL_UNVERIFIED` verdict + exit code 4** + a `LOCAL_UNVERIFIED` tracking array.
- **Exit 0 ONLY when all CRITICAL checks (preflight, run-tests, check-cli-flow-conflicts) actually ran and passed.** A timed-out/skipped critical check ⇒ `PARTIAL_UNVERIFIED`/exit 4 — **NEVER HEALTHY/0.**
- **Upstream comparison is OPTIONAL** — its `git fetch` timing out ⇒ a "upstream not verified (fetch timed out)" note only, NOT exit 4.
- **Fix the pre-existing run-tests rc-masking (H6):** rc≠0 with no parsable `FAIL:` (harness crash) ⇒ `BROKEN`/2 (today it reads OK via `|| true`). Observed `FAIL:` ⇒ BROKEN; timeout-no-FAIL ⇒ UNVERIFIED.
- **`run_with_timeout` helper:** detect `timeout` → `gtimeout`; `-k` grace; rc 124 = timeout; **preserve the wrapped command's own rc otherwise** (don't squash); `GIT_TERMINAL_PROMPT=0` for the fetch. If neither timeout binary exists ⇒ skip bounded slow ops + `PARTIAL_UNVERIFIED` (opt-in unbounded via env only). 
- **Flags:** `--no-upstream` (full local, exit 0 OK) vs `--fast` (skips hook tests → **exit 4**, never 0, prints "not a full verdict"); both keep preflight.
- **SLO-budgeted timeouts**, env-overridable (fetch ~10–15s, preflight ~20–30s, conflict ~20–30s, tests ~45–60s).

## Tests (Te — required)
Add fixtures (recovery-sim/health test layer): AC1 fetch-timeout→bounded+note (not hang); AC2 critical-timeout→exit 4; AC4a real-preflight-fail→BROKEN even with timeouts; AC4b run-tests harness-crash (rc≠0, no FAIL)→BROKEN; AC4c `--fast`→exit 4; AC6 timeout-missing→partial. Don't rely on real network — stub `git`/sub-scripts.

## Worker-undisturbed (FR-07)
Zero diff to: FLOW_RULES.md FR rule rows; the 3 deploy policies; `ratchet-governance.yml`. Bounded-additive: `hooks/local/fusebase-flow-health-check.sh`, tests, the health-check skill docs, README/CHANGELOG/release-notes. **AC8 contract sweep:** grep for any script/hook that branches on the health-check exit code and teach it **exit 4 = partial/unverified** (not failure, not full health) — do NOT leave a caller treating 4 as success or hard-fail incorrectly.

## FR-25
Engine is 633 lines; the additions may approach 800 — if so, extract the `run_with_timeout` helper / verdict logic along a clean seam (e.g. a sourced `hooks/local/lib/` file), not a mechanical split.

## Stop at gate
Per FR-05, stop after Te (gate). Produce the gate report (`templates/gate-report.md`; fields per `policies/gate-contracts.yml: gate_report`), then HALT. Do NOT push, do NOT deploy, do NOT bump version.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ exit 0 only when all critical checks ran clean (no false-HEALTHY)  ☐ FR-25 <800  ☐ commit cites the task
```

## Notes
- This is the diagnostic operators trust for recovery — the verdict/exit contract correctness is the whole point. The Codex design review's blocker was false-HEALTHY; AC4 guards it. A second Codex review runs after the gate.
