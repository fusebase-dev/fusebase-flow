# wire-hooks-skips-occupied-pretooluse

**Status:** FIXED on `fix/wire-hooks-add-beside-preserve` (T1 `36d0f2e`, T2 `c5a2b36`, T3 `effe38c`) — NOT yet released
**Filed:** 2026-08-25 · **Fixed:** 2026-08-25
**Found:** while filing consumer proposal E5. **Not reported by the consumer** — their mint-then-trim procedure keeps upstream's PreToolUse object, which happens to route around it.
**Severity:** high — silent loss of tool-time FR-06/07/12 enforcement, with a health-check recovery that could not converge
**One-liner:** `--wire-hooks` never added Flow's handler to a `.claude/settings.json` whose lifecycle-event array was already non-empty (measured on ALL FIVE non-Stop events), exited 0 anyway, and recorded the wiring-intent marker on that rc — so the tree recorded INTENT while enforcement was absent and the health check's own recovery command was the one that produced the state.

## Release action REQUIRED (open — PO/release call, not done here)

`docs/release-notes/v4.14.0.md:6-9` and `CHANGELOG.md` § [4.14.0] direct **every exposed consumer** at `bash hooks/local/post-fusebase-update.sh --wire-hooks` as the E6 security remediation. For a consumer holding a consumer-authored PreToolUse block that command silently did not wire enforcement. Two corrections belong in the next release note:

| Carrier | Stale claim | Correction |
|---|---|---|
| `docs/release-notes/v4.14.0.md:60` | "Existing install, runs `--wire-hooks` → Matcher widened in place" | True only when a Flow block already exists. Consumer-only array → nothing widened, nothing added |
| `CHANGELOG.md` § [4.14.0] + `docs/release-notes/v4.14.0.md:6-9` | "Existing installs stay exposed until they re-merge" | A consumer who DID re-merge could still be exposed pre-fix; they must re-run `--wire-hooks` on the fixed release and confirm `grep -c hooks/handlers/pre_tool_use.py .claude/settings.json` ≥ 1 |

Published tags are immutable — the correction goes in the NEXT release note, not by rewriting v4.14.0.

## What shipped

| # | Change | Where |
|---|---|---|
| A | Add-beside-preserve for every non-Stop event: array occupied and no Flow block → APPEND Flow's block; consumer blocks never dropped, reordered or rewritten | `settings-json-merge.py` `_flow_handler_present` + `merge_settings` |
| A2 | Non-array `hooks.<event>` warned + skipped, never coerced and never allowed to abort the merge (which would take the other events' wiring down with it) | `settings-json-merge.py` `merge_settings` |
| B | Intent recorded iff the tree ACHIEVED the wiring (`ffhc_hwi_wired` says the canonical handler is in `.claude/settings.json` NOW); merge rc 0 is necessary, not sufficient | `hook-wiring-intent.sh` `ffhc_hwi_record_wiring` |
| B2 | Caller captures the recorder's rc, WARNS on "merge succeeded, handler absent", and no longer claims `recorded Flow hook-wiring intent` for a marker it did not write | `post-fusebase-update.sh` Step 5 |

**Appended, never merged into the consumer's chain.** Appending Flow's command into the consumer's block would inherit that block's matcher — measured `Bash|Edit|Write` — and re-open E6: PowerShell never reaches `pre_tool_use.py`, so FR-06 denies and FR-12 approvals do not apply to it. Flow's block carries `DEFAULT_EVENT_MATCHERS` unchanged.

## Open questions from the filing — all three answered

| Question | Answer |
|---|---|
| Where in the array is Flow's block appended | END. Never reorders a consumer block; `A5` deep-equals `after[:len(before)] == before` |
| Does the appended block get the full E6 matcher | YES — `make_event_block()`, the same block a fresh install gets (`A6`) |
| Is a tree already in the bad state repaired, or does it need an explicit path | REPAIRED by the next ordinary `--wire-hooks`; the presence check runs on every merge. No new flag, no migration |

## Scope: FIVE events, not one

Measured, `settings-json-merge.py` at `fc39ef6`, consumer-only array per event:

| Event | Flow handler after merge (pre-fix) |
|---|---|
| SessionStart | 0 — GAP |
| UserPromptSubmit | 0 — GAP |
| **PreToolUse** | **0 — GAP** (the security-relevant one) |
| PostToolUse | 0 — GAP |
| PreCompact | 0 — GAP |
| Stop | 1 — the only event with an add-beside path |

## Evidence

`hooks/tests/test-wire-hooks-add-beside.sh` (tag `wire-hooks-beside`, 35 rows, 8s).

| Run | Result |
|---|---|
| RED at `fc39ef6` (pre-fix) | 20/35 PASS, 15 FAIL |
| GREEN at `effe38c` | 35/35 PASS |

The oracle is the CONTROL SET: `A1` key-absent, `A2` `[]`, `A3` consumer+flow all wired BEFORE the fix, so only `A4` consumer-only separates fixed from pre-fix. `C1` is the real end-to-end (`post-fusebase-update.sh --wire-hooks`, then the real health arm) and carries the convergence row: the health check must not report ENFORCEMENT STRIPPED on a tree `--wire-hooks` just succeeded on. `C2` proves the fail-closed direction with a stub merge that exits 0 without wiring.

## Why (B) was needed even with (A)

`post-fusebase-update.sh:380-383` already carried a protection saying intent is recorded *"ONLY on a merge that actually succeeded… so a failed or aborted merge never leaves an intent the health check would then report as stripped enforcement."* It was real and did not cover this: the merge **succeeded** — it applied seven other changes. Success was measured as **exit 0**, not as **achieved the thing**. `(B)` is the fail-closed backstop for whatever `(A)` misses, and for any future event whose wiring silently no-ops.

**Other exit-code-not-outcome recorders found while building (B)** — reported, deliberately NOT fixed here:

| Site | Shape | Blast radius |
|---|---|---|
| `post-fusebase-update.sh` Step 5b (`:412-430`) | `GH_RC -eq 0` + no "custom … detected" string → `ACTIONS_TAKEN+=("(re)installed Flow git fallback hooks")`; never asserts `.git/hooks/pre-commit` is present, executable and Flow's | LOWER — a transient report line, not a durable marker a later health check reads back as an accusation. No non-convergent loop |
| `bootstrap-upgrade.sh:502-516` `REPAIR_RC` | already ACHIEVED-state keyed (`ff_boot_repair_verify` re-verifies the manifest layers) | none — correct as-is |
| `settings-json-merge.py` `write_baseline` | derives `cli_stop_hooks` from the merged CONTENT | none — correct as-is |

## Reuse

`enforcement-only-hook-wiring` **ask 1** (`--record-wiring-intent`, record-only, iff the canonical handler is present) is the SAME predicate. It is now built and callable: `ffhc_hwi_wired <root>` (0 wired · 1 absent · 2 no settings.json), composed by `ffhc_hwi_record_wiring`. Ask 1 becomes a flag that calls the existing predicate — no new detection logic.

## Related

- `docs/backlog/enforcement-only-hook-wiring/README.md` — ask 1 unblocked by this fix; ask 4 still needs its own design
- `docs/problem-catalog/live-enforcement-inertness/problem.md` — the class
- `hooks/tests/test-wire-hooks-add-beside.sh` · `hooks/tests/test-hook-wiring-intent.sh`
