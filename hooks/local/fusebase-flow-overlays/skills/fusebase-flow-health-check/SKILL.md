---
name: fusebase-flow-health-check
description: Use when the operator asks "is Fusebase Flow healthy", "check Fusebase Flow", "did fusebase update break anything", "Fusebase Flow status", "restore Fusebase Flow", or asks whether Fusebase CLI and Fusebase Flow agent files conflict. Runs the read-only health engine, reports layer verdicts (`HEALTHY`, `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT`, `EXCEPTION_IN_EFFECT`, `BROKEN`), and offers Flow recovery only when the drift is Flow-owned or shared-merge. For CLI-owned drift, instruct the operator to run the current FuseBase CLI refresh/update first, then Flow recovery.
source_inspiration: original (operator-maintained recovery infrastructure)
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: low - diagnosis phase is read-only; recovery phase executes hooks/local/post-fusebase-update.sh only after explicit operator affirmative reply in chat
invocation: automatic (description match) - also via /fusebase-health slash command
expected_outputs:
  - Health check report printed to chat
  - Layer verdict and next action
  - Recovery offer only for FLOW_LAYER_DRIFT or SHARED_MERGE_DRIFT
  - CLI-first guidance for CLI_LAYER_DRIFT
related_workflows:
  - hooks/local/fusebase-flow-health-check.sh
  - hooks/local/check-cli-flow-conflicts.sh
  - hooks/local/post-fusebase-update.sh
hook_dependencies:
  - none
---

# Fusebase Flow Health Check

## Purpose

Verify the local Fusebase Flow overlay and the shared FuseBase CLI / Flow agent surfaces without writing to the repository. The health engine now separates failures by ownership layer:

| Verdict | Meaning | Recovery posture |
|---|---|---|
| `HEALTHY` | CLI-owned, Flow-owned, and shared-merge surfaces look intact AND every critical check ran clean. | No action. |
| `CLI_LAYER_DRIFT` | CLI-owned assets are **missing** or structurally damaged. | Do not run Flow recovery first. Run the current FuseBase CLI refresh/update, then Flow recovery. |
| `SHARED_MERGE_DRIFT` | Shared files are missing Flow overlay/merge additions. | Offer Flow recovery. |
| `FLOW_LAYER_DRIFT` | Flow-owned mirrors or overlay files are missing/drifted. | Offer Flow recovery. |
| `EXCEPTION_IN_EFFECT` | Drift is covered by active approval/deferral artifacts. | Do not run recovery automatically. Surface the artifact. |
| `BROKEN` | A completed critical check failed, or a sub-script crashed (rc≠0 with no parsable result). | Do not offer recovery; inspect the broken item first. |
| `PARTIAL_UNVERIFIED` | A **critical** check (preflight, hook tests, conflict reporter) was skipped / timed out / unavailable, and nothing that ran proves drift or breakage. **Not full health, not a failure** — the run is simply incomplete. | Re-run on a host with more time/CPU, raise the relevant `FFHC_*_TIMEOUT` knob, or run the named check directly. Don't treat as healthy. |

### Bounded execution + flags (v3.24.0+)

The slow, verdict-affecting operations (preflight, hook tests, conflict reporter, the upstream `git fetch`) are bounded so a network-impaired or large-repo host can't make the read-only diagnostic appear to hang. A timed-out/skipped **critical** check ⇒ `PARTIAL_UNVERIFIED` (never a false `HEALTHY`). The upstream comparison is **optional** — its fetch timing out is a "upstream not verified" note only and never forces exit 4.

| Flag | Effect | Exit |
|---|---|---|
| (none) | Full local + upstream verdict. | 0 only if every critical ran clean |
| `--no-upstream` | Skip the optional upstream comparison (full **local** verdict). | 0 OK |
| `--fast` | Skip the slow hook tests (and upstream); keeps preflight + inventory + conflict reporter. **Explicitly partial.** | **4, never 0** (prints "fast mode — not a full health verdict") |

Env knobs (seconds; defaults in parentheses): `FFHC_FETCH_TIMEOUT` (15), `FFHC_PREFLIGHT_TIMEOUT` (30), `FFHC_CONFLICT_TIMEOUT` (30), `FFHC_TESTS_TIMEOUT` (60). If neither `timeout` nor `gtimeout` exists, the bounded ops are **skipped** ⇒ `PARTIAL_UNVERIFIED` (install coreutils, or opt into unbounded runs with `FFHC_ALLOW_UNBOUNDED=1`). Worst-case bounded full run ≈ 155s.

### Advisory signals (informational — never change the verdict or exit code)

The conflict reporter (`check-cli-flow-conflicts.sh`) also emits advisory findings for vendored CLI-owned assets. These are **info-only**: they do NOT flip the verdict away from `HEALTHY` and do NOT change the exit code. Restoration of CLI-owned content always stays with the FuseBase CLI; Flow only diagnoses.

| Advisory finding | Meaning | What to do |
|---|---|---|
| `CLI_SNAPSHOT_STALE` | A **present** CLI-owned asset's sha256 differs from the bundled provenance in `audit/cli-vendor-manifest.json` (a newer or locally-modified copy). Distinct from `MISSING`, which still escalates to `CLI_LAYER_DRIFT`. | Expected after a `fusebase update`. If intentional, re-stamp provenance with `bash hooks/local/stamp-cli-provenance.sh`. Freshness is advisory only (`source_cli_version` is the `unknown` sentinel — UNVERIFIABLE_LOCALLY). |
| `CLI_CUSTOM_AT_RISK` | A CLI-owned skill carries a `<!-- CUSTOM:SKILL:BEGIN -->…END` block **AND** the file has drifted from bundled provenance (sha256 ≠ manifest). A pristine CLI-shipped block (sha == provenance) is NOT flagged; provenance-unavailable keeps the conservative flag. | Back up the CUSTOM block before the next `fusebase update` / CLI refresh. |
| `CLI_STOP_UNVERIFIED` | A Flow-merged project (`stop.py` wired) has no CLI Stop baseline receipt (`state/audit/cli-stop-baseline.json`), so CLI Stop preservation cannot be verified. Never fires on a no-`stop.py` / never-wired project. | Run `bash hooks/local/post-fusebase-update.sh --wire-hooks` to establish (or refresh) the baseline. |
| `CLI_STOP_BASELINE_DRIFT` | A CLI Stop hook recorded in the receipt at the last Flow update is no longer in the current Stop chain. The preserve-only merge never drops a hook, so this reflects a non-Flow/operator edit — **advisory, never `SHARED_MERGE_DRIFT`/exit-1**. | If intentional, re-run `bash hooks/local/post-fusebase-update.sh --wire-hooks` to re-baseline. |

## Procedure

1. Confirm the engine exists:

   ```bash
   test -f hooks/local/fusebase-flow-health-check.sh
   ```

2. Run the read-only engine:

   ```bash
   bash hooks/local/fusebase-flow-health-check.sh
   ```

3. Optionally run the no-write ownership report for more detail:

   ```bash
   bash hooks/local/check-cli-flow-conflicts.sh
   ```

   This report also surfaces the advisory findings `CLI_SNAPSHOT_STALE` (a present CLI asset differs from the bundled provenance sha256), `CLI_CUSTOM_AT_RISK` (a *drifted* CLI skill carries a `CUSTOM:SKILL` block), `CLI_STOP_UNVERIFIED` (a Flow-merged project with no `state/audit/cli-stop-baseline.json` receipt), and `CLI_STOP_BASELINE_DRIFT` (a baselined CLI Stop hook is gone). All are informational only — they do not change the verdict or exit code. Provenance lives in `audit/cli-vendor-manifest.json` (re-stamp: `bash hooks/local/stamp-cli-provenance.sh`); the Stop receipt is written by `bash hooks/local/post-fusebase-update.sh --wire-hooks`.

4. Interpret exit code:

   | Exit | Verdicts |
   |---:|---|
   | 0 | `HEALTHY` (every critical check ran clean) |
   | 1 | `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT` |
   | 2 | `BROKEN` |
   | 3 | `EXCEPTION_IN_EFFECT` |
   | 4 | `PARTIAL_UNVERIFIED` (a critical check did not run — partial/unverified; **not** full health, **not** a hard failure) |

   **Callers that branch on the exit code must treat 4 as partial/unverified** — re-run or raise a timeout knob; never read it as healthy and never hard-fail a pipeline on it without distinguishing it from drift/breakage.

5. If verdict is `FLOW_LAYER_DRIFT` or `SHARED_MERGE_DRIFT`, ask in chat before writing:

   > Run Flow recovery now? Reply `yes`, `run it`, `fix it`, or `proceed` and I will execute `bash hooks/local/post-fusebase-update.sh`, then re-run the health check.

6. If the operator already gave an affirmative in the same turn, that counts as confirmation for this recovery action. Execute:

   ```bash
   bash hooks/local/post-fusebase-update.sh
   bash hooks/local/fusebase-flow-health-check.sh
   ```

7. If verdict is `CLI_LAYER_DRIFT`, do not run Flow recovery as the first step. Say:

   > CLI-owned files need the current FuseBase CLI to restore them. Run the current FuseBase CLI refresh/update for this project first, then run `bash hooks/local/post-fusebase-update.sh`.

## Recovery Boundary

`post-fusebase-update.sh` restores only Flow-owned assets and shared Flow additions:

- Flow skills into `.claude/skills/` and `.agents/skills/`
- Flow agents into `.claude/agents/` and `.codex/agents/`
- Flow overlay blocks in `AGENTS.md` and `CLAUDE.md`
- Flow lifecycle hooks merged into `.claude/settings.json`
- `fusebase-flow-health-check` skill mirrors
- `.claude/commands/fusebase-health.md`

It does not patch or restore `.claude/hooks/**`, FuseBase CLI provider skills, MCP configs, `fusebase.json`, `skills-lock.json`, or active `.codex/config.toml` content. Those are CLI-owned or project-owned surfaces.

The advisory signals (`CLI_SNAPSHOT_STALE`, `CLI_CUSTOM_AT_RISK`, `CLI_STOP_UNVERIFIED`, `CLI_STOP_BASELINE_DRIFT`) never trigger Flow recovery: a present-but-changed CLI asset is the CLI's to manage, a `CUSTOM:SKILL` block is a user edit Flow must not clobber, and a missing/unverified CLI Stop hook is a non-Flow edit (the preserve-only merge never drops one). Flow only reports them so the operator can act (re-stamp provenance, back up CUSTOM blocks, or re-run `--wire-hooks` to re-baseline the Stop receipt).

## Output Shape

Report:

- Verdict
- Layer that drifted
- Concrete next action
- Whether recovery was offered, declined, or executed
- Re-check result when recovery runs

Keep chat output brief and concrete. Do not paste the full engine transcript unless the operator asks.
