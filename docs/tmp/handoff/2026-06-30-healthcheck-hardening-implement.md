# Implement handoff — healthcheck-baseline-and-custom-flag-hardening

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.30.0. Self-attest FR-01..FR-27 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07, FR-13, FR-22 (comments), FR-25, **FR-27 (liveness — bound/poll any long run, never bare)**. **Synchronous; stop at gate; do NOT bump VERSION/push/deploy.**

## COMMENT POLICY (FR-22) — any code you write
```
ONLY tripwire + retrieval-pointer comments. Remove WHAT-restating/recorded-elsewhere/changelog. Don't match density upward. Keep pointers.
```
At done emit `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-27 (stop at Amendment log).
2. `docs/specs/healthcheck-baseline-and-custom-flag-hardening/spec.md` — LOCKED (D1 receipt, D2 advisory-only/no exit-1, D3 CLI_STOP_UNVERIFIED, D4 sha-gate, D5 v3.30.1). Authoritative.
3. The files you change: `hooks/local/check-cli-flow-conflicts.sh` (the embedded Python: `scan_custom_skill_block` ~L142, the Stop-hook diff ~L366-401, the advisory filters ~L601/631/666), `hooks/local/fusebase-flow-overlays/settings-json-merge.py`, `hooks/local/post-fusebase-update.sh` (~L259-275), `hooks/tests/test-cli-0259-compat.sh`, run-tests wiring.
4. Confirm `state/audit/` exists + is gitignored except `.gitkeep`.

## Scope — one commit per task. ADVISORY-ONLY: no new exit-1 path; verdict ENUM + exit codes (0/1/2) unchanged.

- **T1 (M) — durable receipt writer + advisory reporter.**
  - **Writer:** `settings-json-merge.py` gains a `--baseline-out PATH` mode: after computing the merge, write `{"schema":1,"cli_stop_hooks":[<basenames of Stop commands naming a file under .claude/hooks/>],"written_by":"post-fusebase-update --wire-hooks"}` to PATH (a CLI-owned Stop hook = a Stop command whose command string names a file under `.claude/hooks/`; exclude `stop.py` which is under `hooks/handlers/`). `post-fusebase-update.sh --wire-hooks` invokes it so `state/audit/cli-stop-baseline.json` is written on BOTH the real-merge path (`:269`) AND the no-op "already wired" path (`:266`) — durable + self-refreshing. Do NOT persist `.pre-flow-merge` (it stays only the merge-failure restore at `:273`).
  - **Reporter (`check-cli-flow-conflicts.sh`):** STOP reading `.claude/settings.json.pre-flow-merge`; read `state/audit/cli-stop-baseline.json` (relative to `root`). REMOVE the `:397-398` `DRIFT`/`SHARED_MERGE_DRIFT` path. New behavior when `has_flow_stop` is true:
    - receipt absent → advisory **`CLI_STOP_UNVERIFIED`** ("cannot verify CLI Stop preservation; run `bash hooks/local/post-fusebase-update.sh --wire-hooks` to establish a baseline").
    - receipt present + a `cli_stop_hooks` entry NOT found in the current Stop chain (reuse `stop_commands_in_settings`/`cli_hook_markers_in`) → advisory **`CLI_STOP_BASELINE_DRIFT`** ("a CLI Stop hook wired at last Flow update is gone; re-run the updater to re-baseline if intentional").
    - else OK.
  - Both new statuses are **advisory** — wire them into the SAME filter posture as `CLI_SNAPSHOT_STALE`/`CLI_CUSTOM_AT_RISK`: excluded from `cli_drift`/`shared_merge_drift`, do NOT change the verdict, and the `verdict=="HEALTHY"` exit-0 branch (~L666) still exits 0 but surfaces them in the summary counts. The health-check stays READ-ONLY (writer is the updater only; never call `fusebase`).
- **T2 (L) — sha-gate `CLI_CUSTOM_AT_RISK`.** In `scan_custom_skill_block` (~L142): only `add(...)` when the file's sha256 ≠ the bundled provenance for that `rel_path` (reuse `PROVENANCE`/`sha256_of`/`check_provenance` machinery). sha == provenance → CLI-shipped block → skip. Provenance unavailable for that file (`not PROVENANCE_AVAILABLE` or no entry) → keep the conservative flag.
- **T3 (tests).** Extend `hooks/tests/test-cli-0259-compat.sh` (or a new suite): AC-M1 (receipt written on real-merge AND no-op; survives a 2nd no-op — RED-then-GREEN vs current `rm -f`), AC-M2 (receipt + dropped CLI hook → `CLI_STOP_BASELINE_DRIFT`, verdict HEALTHY, **exit 0**; 0.25.9 `run-typecheck-apps.js`-unwired stays benign), AC-M3 (`has_flow_stop`+no receipt → `CLI_STOP_UNVERIFIED`, exit 0; no-stop.py → no finding), AC-M4 (**UPDATE** the existing "still-flags-dropped → SHARED_MERGE_DRIFT" assertion to the advisory model; no exit-1 from a missing CLI hook anywhere), AC-L1 (pristine sha==provenance+CUSTOM → not flagged; drifted sha≠provenance+CUSTOM → flagged; provenance-absent → conservative flag). Wire into run-tests.sh. **No-regression:** 164+ tests, the 26 timeout tests, FFHC verdict enum + exit codes intact. Genuine RED-then-GREEN, loud asserts, no false-green.
- **T4 (code-adjacent doc, only if one exists).** If a doc enumerates the health-check finding/verdict list (e.g. in `hooks/local/` README or `docs/`), add the two advisory findings. Release notes + spec/backlog→DONE are the DEPLOY FR-14 commit — do NOT write them here.

## FR-07 / hard rules
No diff to FLOW_RULES FR rows / the 3 deploy-policy rule semantics / ratchet-governance.yml. The two new findings are ADVISORY — verdict ENUM + exit codes (0/1/2, PARTIAL_UNVERIFIED) UNCHANGED; no new exit-1 path. Health-check stays READ-ONLY (writer = updater/merge only; never call `fusebase`). Don't change the `ffhc_*` API. Re-vendored CLI assets stay CLI-owned. Do NOT bump VERSION/push/deploy.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ FR-22 comments  ☐ FR-25 <ceiling  ☐ advisory-only (no new exit-1; verdict enum + exit codes intact)  ☐ health-check read-only/no-fusebase-calls
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet UNCHANGED  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n check-cli-flow-conflicts.sh post-fusebase-update.sh` + `python -m py_compile settings-json-merge.py` + `python -c "import ast; ast.parse(open(...).read())"` for the embedded reporter if extractable · run-tests PASS incl. new + updated tests + the 26 timeout tests · check-module-size --all exit 0 · mirror 0 drift · FR-07 clean · confirm a HEALTHY-with-advisory fixture exits 0. Emit the FR-22 marker. Produce the gate report; HALT. A FuseBase adversarial review runs after the gate.

## Return
Gate report: per-task SHAs (T1–T4), AC evidence (M1 receipt durable across no-op RED-then-GREEN; M2 dropped-hook→advisory exit 0; M3 no-receipt→CLI_STOP_UNVERIFIED exit 0; M4 no exit-1 from missing CLI hook + updated assertion; L1 sha-gate), no-regression (164+ / 26-timeout, verdict enum + exit codes intact), gate numbers, FR-07 + read-only + advisory-only confirmation.
