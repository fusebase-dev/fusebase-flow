# Spec — healthcheck-baseline-and-custom-flag-hardening

**Status:** DONE — shipped **v3.30.1** (deploy hash `70b32e2`, tag `v3.30.1`, release https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.30.1). Deployed 2026-06-30. All gate + probe + ticket smoke PASS: preflight 0/0; run-tests 182/182; test-cli-flow-recovery 31/0; check-module-size --all exit 0; mirror 0 drift (4 health-check skill copies byte-identical); plugin==VERSION==3.30.1; GEMINI.md=v3.30.1; README badge 3.30.1; the 5 FR-07 surfaces UNCHANGED (only the FLOW_RULES version-attestation line moved); FR-01..FR-27 + 32 skills unchanged; advisory-only invariant intact (verdict ENUM + exit codes unchanged); clean-room code grep `headroom`=0. Ticket smoke (real merge + real reporter, test-cli-0259-compat.sh 30/0): receipt written (3 CLI hooks, excludes stop.py) + durable across a no-op; dropped baselined hook → CLI_STOP_BASELINE_DRIFT advisory, HEALTHY, exit 0; deleted receipt → CLI_STOP_UNVERIFIED advisory, exit 0; pristine sha==provenance not flagged, drifted flagged; NO input forces exit-1.
**Created:** 2026-06-30
**Baseline:** FuseBase Flow v3.30.0
**Source:** The two non-blocking follow-ups filed by the FuseBase adversarial review of `cli-0.25.9-vendor-refresh` (v3.30.0): `docs/backlog/healthcheck-diff-source-hardening` (MED) + `docs/backlog/cli-custom-at-risk-overflag` (LOW). Operator: finalize both + ship under a new version.
**Lane:** Full (health-check tooling + updater + tests; **advisory-only — no new exit-1 path**).
**Design review:** Codex 2026-06-30 → **RESCOPE** (M+L both confirmed; LOW repro'd live — `cli_custom_at_risk:1` on pristine `app-dev-practices`, sha == manifest). Folded: **the whole M fix is ADVISORY-ONLY — no `SHARED_MERGE_DRIFT`/exit-1 for a missing CLI Stop hook.** Rationale: the merge is provably preserve-only, so a "missing" hook is never a Flow-merge fault (it's a non-Flow/operator edit) — classifying it exit-1 would be a permanent false positive. **D1 = updater-written receipt** `state/audit/cli-stop-baseline.json` (NOT persisting `.pre-flow-merge` — `post-fusebase-update.sh:259` overwrites it before every merge, so persistence alone still loses it; NEVER an on-disk `.claude/hooks/` fallback). **This REPLACES the v3.30.0 exit-1 path** (`check-cli-flow-conflicts.sh:397-398`) with advisory findings. D1–D5 locked below.

## Problem (proven, with code refs)

### M (MED) — diff-source is ephemeral → silent non-detection
v3.30.0 made `check-cli-flow-conflicts.sh` diff-frame `SHARED_MERGE_DRIFT`: flag a CLI Stop hook only if it was wired in the pre-merge backup `.claude/settings.json.pre-flow-merge` and is missing now (`check-cli-flow-conflicts.sh:377-385`). But:
- `post-fusebase-update.sh:259` writes the backup before merging; **`:267` `rm -f`s it on the no-op ("already up to date") path**, and `:273-274` deletes it on merge-failure. So after the steady state (merge once, then subsequent no-op updates) **the backup is gone**.
- When the backup is absent, the reporter sets `missing_cli_hooks=[]` and falls through to `OK` (`:379` guard, `:399-400`) — **silently**. A genuinely-dropped CLI Stop hook is not flagged and there is no signal that verification was skipped.
- This is a deliberate no-false-positive trade-off (the merge is preserve-only, so Flow itself never drops a hook), but the backlog asks: a durable baseline so a real drop is caught, **absence degrades to an explicit advisory (never silent)**, and **without** re-introducing the on-disk-but-unwired false positive (flagging `run-typecheck-apps.js`, which 0.25.9 ships unwired).

### L (LOW) — `CLI_CUSTOM_AT_RISK` over-flags CLI-shipped CUSTOM blocks
`scan_custom_skill_block` (`check-cli-flow-conflicts.sh:142-151`) emits the advisory for ANY CUSTOM:SKILL block in a CLI-owned skill — including a **pristine CLI-shipped** block (e.g. `app-dev-practices`), which re-vendor simply overwrites with the identical CLI copy (nothing at risk). Advisory-only (no verdict/exit impact), but noisy. It should fire only when the file has **drifted from provenance** (operator-modified content that a CLI refresh would clobber).

## In scope (D1 = receipt; ALL advisory; LOW = sha-gate)
- **M — durable updater-written baseline + advisory-only detection.**
  - **Writer (`settings-json-merge.py` + `post-fusebase-update.sh --wire-hooks`):** the merge gains a `--baseline-out PATH` mode (or a small helper) that writes the CLI-owned Stop commands it preserved to `state/audit/cli-stop-baseline.json` (a command is CLI-owned iff it names a file under `.claude/hooks/` — same rule the reporter uses; the writer single-sources the list so the reporter just reads it). `post-fusebase-update.sh --wire-hooks` invokes it on **every** wire-hooks run — after a real merge AND on the no-op ("already wired") path — so the receipt is durable and self-refreshing (re-running the updater re-baselines → the clear/escape path). Do NOT persist `.pre-flow-merge` (it's overwritten at `:259`); `.pre-flow-merge` stays only the merge-failure restore source.
  - **Reporter (`check-cli-flow-conflicts.sh`) — stop reading `.pre-flow-merge`; read the receipt; ALL advisory:**
    - `has_flow_stop` true + **no receipt** → advisory **`CLI_STOP_UNVERIFIED`** ("cannot verify CLI Stop preservation; re-run `post-fusebase-update.sh --wire-hooks` to establish a baseline"). Never fires on a no-stop.py project.
    - receipt present + a baselined CLI Stop command **missing now** → advisory **`CLI_STOP_BASELINE_DRIFT`** ("a CLI Stop hook wired at last Flow update is gone; re-run the updater to re-baseline if intentional"). **NOT `SHARED_MERGE_DRIFT`, NOT exit-1.**
    - else OK.
  - This **REPLACES** the v3.30.0 `:397-398` `DRIFT`/`SHARED_MERGE_DRIFT` path. Both new findings are advisory (same posture as `CLI_SNAPSHOT_STALE`): they do NOT change the verdict enum or exit codes — a project with only these stays HEALTHY/exit 0. **The merge's preserve-only correctness stays guarded by the merge's own idempotency/older-CLI tests** (unchanged) — removing the exit-1 path does not weaken merge verification, it stops miscategorizing non-merge edits as a merge fault.
  - **The health-check stays READ-ONLY** (reads the receipt; never writes it; never calls `fusebase`). The writer is the updater/merge only.
- **L — gate `CLI_CUSTOM_AT_RISK` on provenance drift.** In `scan_custom_skill_block`, only flag when the CLI-owned skill file's sha256 ≠ the bundled provenance (operator content at risk). sha == provenance → CLI-shipped block → skip. Provenance unavailable for that file → keep the conservative flag (preserve the genuine signal). Advisory-only contract unchanged. **(D4)**
- **Docs.** Release notes; flip both backlog READMEs → DONE. No FR / skill changes.
- **Tests.** M: receipt written + durable across a no-op update (AC-M1); receipt present + dropped CLI hook → advisory `CLI_STOP_BASELINE_DRIFT` **exit 0** (AC-M2), and the 0.25.9 `run-typecheck-apps.js`-on-disk-unwired case stays benign (no false positive); `has_flow_stop` + no receipt → advisory `CLI_STOP_UNVERIFIED`, never silent, exit 0 (AC-M3). **UPDATE the v3.30.0 `test-cli-0259-compat.sh` assertion** that expected `SHARED_MERGE_DRIFT` for a dropped hook → now the advisory model. L: pristine CLI file (sha==provenance)+CUSTOM block → NOT flagged; drifted (sha≠provenance)+CUSTOM block → STILL flagged (AC-L1). No-regression: 164+ tests, the 26 timeout tests, FFHC verdict enum + exit codes intact.

## Out of scope
- Re-policing operator-deliberate hook removals as a hard verdict (see D2 — needs a re-baseline escape hatch if we flag them).
- Changing the merge's preserve-only behavior or the FFHC verdict set / exit codes.
- Calling the `fusebase` CLI from the health-check.

## Decisions (LOCKED — design review folded)
- **D1 = updater-written receipt** at `state/audit/cli-stop-baseline.json` (`state/audit/*` already gitignored except `.gitkeep`). Writer = `settings-json-merge.py --baseline-out` invoked by `post-fusebase-update.sh --wire-hooks` after merge AND no-op. NOT persisted `.pre-flow-merge` (overwritten at `:259`). NEVER an on-disk `.claude/hooks/` fallback (would re-introduce the `run-typecheck-apps.js` false positive).
- **D2 = advisory-only; NO `SHARED_MERGE_DRIFT`/exit-1 for a missing CLI Stop hook.** Preserve-only merge ⇒ a missing hook is never a merge fault. Replace the v3.30.0 `:397-398` exit-1 path with advisory `CLI_STOP_BASELINE_DRIFT`. Re-baseline escape hatch = re-run `post-fusebase-update.sh --wire-hooks` (re-writes the receipt) — so a deliberate operator change is never a permanent false positive.
- **D3 = `CLI_STOP_UNVERIFIED` advisory-only** (no verdict/exit change; same posture as `CLI_SNAPSHOT_STALE`), fires ONLY when `has_flow_stop` is true and the receipt is absent; cleared by running the updater.
- **D4 = LOW gate confirmed:** sha≠provenance ⇒ flag; sha==provenance ⇒ skip; provenance-unavailable-for-that-file ⇒ conservative flag. (A genuine operator CUSTOM block cannot hash-identically to provenance unless the operator re-stamped after editing — an explicit acceptance of that baseline.)
- **D5 = PATCH `v3.30.1`** (hardening the v3.30.0 health-check; advisory-only, no verdict/exit-contract change).

## Acceptance criteria
- **AC-M1** The receipt `state/audit/cli-stop-baseline.json` is written by `post-fusebase-update.sh --wire-hooks` on BOTH the real-merge and no-op paths, and **survives a subsequent no-op run** (the v3.30.0 `rm -f`-on-no-op blind spot is closed). RED-then-GREEN vs current code.
- **AC-M2** Receipt present + a baselined CLI Stop hook missing now → advisory **`CLI_STOP_BASELINE_DRIFT`**, verdict stays HEALTHY, **exit 0** (NOT `SHARED_MERGE_DRIFT`/exit-1); the 0.25.9 `run-typecheck-apps.js`-on-disk-unwired case stays benign. Re-running the updater clears it.
- **AC-M3** `has_flow_stop` true + receipt absent → advisory **`CLI_STOP_UNVERIFIED`** (never silent), verdict HEALTHY, **exit 0**. No-stop.py / never-wired project → no finding (no nag).
- **AC-M4** The v3.30.0 exit-1 `:397-398` path is gone — no `SHARED_MERGE_DRIFT` can arise from a missing CLI Stop hook; the `test-cli-0259-compat.sh` "still-flags-dropped" assertion is updated to the advisory model.
- **AC-L1** Pristine CLI skill (sha==provenance) with a CUSTOM block → NOT flagged. Drifted CLI skill (sha≠provenance) with a CUSTOM block → STILL flagged. Provenance-unavailable-for-that-file → conservative flag. Advisory-only contract unchanged.
- **AC-NR (no-regression)** run-tests (164+) PASS incl. the v3.30.0 diff-framed no-false-positive + the 26 timeout tests; FFHC `ffhc_*` API + verdict ENUM + exit codes (0/1/2, PARTIAL_UNVERIFIED) unchanged (the two new findings are advisory, like `CLI_SNAPSHOT_STALE`); health-check stays read-only / no `fusebase` calls.
- **AC-gate** preflight 0/0; check-module-size --all exit 0; mirror 0 drift; FR-07 clean; clean-room boundary intact.

## Tasks (finalize post-design-review)
- **T1 (M)** durable baseline writer (updater/merge) + reporter diff against it + `CLI_STOP_UNVERIFIED` advisory per D1/D2/D3.
- **T2 (L)** gate `scan_custom_skill_block` on provenance drift per D4.
- **T3 (tests)** AC-M1/M2/M3 + AC-L1 + no-regression; wire into run-tests.sh.
- **T4 (docs)** release notes; backlog READMEs → DONE.

## Risks
- **Operator-edit false positive** (D2): persisting a baseline can flag a deliberate operator removal — mitigate with categorization + a re-baseline path.
- **Stale baseline** mis-representing the current CLI set after a CLI re-init — bound by refreshing the baseline on each merge run.
- **Advisory noise** from `CLI_STOP_UNVERIFIED` on every backup-less project — gate strictly on `has_flow_stop` so only Flow-merged projects that lost their baseline are nudged.
- **FR-07 / read-only**: the writer must be the updater/merge, never the health-check; verdict/exit contract must stay intact (advisory additions only).
