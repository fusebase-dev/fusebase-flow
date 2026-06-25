# Implement handoff — upgrade-baseline-bootstrap-hop (v3.25.1 hotfix)

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.25.0 → fixing toward **v3.25.1** (PATCH). Self-attest FR-01..FR-26, IM section. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-13 (preflight per commit), FR-25 (<800).

**Lane:** Full (upgrade engine — a bug strands every consumer). Stop at gate; do NOT bump VERSION or push (deploy is a separate phase).

## The bug (Codex adversarial review of v3.25.0, BLOCKER — verified)
v3.25.0's U3 baseline merge-preserve (the W2 data-loss fix) **does not protect the first upgrade that adopts v3.25.x.** Two confirmed gaps:

1. **`upgrade.sh` sources the merge lib too early + from the wrong tree.** [upgrade.sh:91-92] sources `$ROOT/hooks/local/lib/merge-module-size-baseline.sh` at the TOP of `main()` — *before* Step 1 refreshes `hooks/`. If the LOCAL lib isn't present yet (a pre-v3.25 install, or a bootstrap that didn't stage it), `merge_module_size_baseline` is never defined, so the Step 1a guard at [upgrade.sh:268] (`command -v merge_module_size_baseline`) is false → **merge silently skipped** → `policies/module-size-baseline.txt` left clobbered by the wholesale `policies/` copy.
2. **`bootstrap-upgrade.sh` doesn't stage `hooks/local/lib/`.** Its `ENGINE_SCRIPTS` array [bootstrap-upgrade.sh:92-100] stages the engine scripts but NOT the `lib/` dir the new engine sources. So even the recommended bootstrap path runs the new `upgrade.sh` with the merge function undefined → same clobber.

(The naive path — a v3.21–v3.24 consumer running their *installed* old `upgrade.sh` — has no merge code at all; that path is only fixable by routing them through `bootstrap-upgrade.sh`, hence the docs task.)

**Consequence:** the exact W2 friction recurs for existing consumers (incl. the two who reported it) on their v3.25.x adoption upgrade. Recoverable (the `policies.pre-upgrade-<ts>/` backup exists) but silent.

## Tasks (one commit each; stop at gate)

### P1 — `bootstrap-upgrade.sh`: stage `hooks/local/lib/`
Add the engine's sourced lib dir to bootstrap staging so the new `upgrade.sh` finds its libs BEFORE handoff. Copy `hooks/local/lib/*.sh` from `$SOURCE_CLONE` (back up an existing local `hooks/local/lib/` to `.pre-bootstrap-<ts>` first, consistent with the script's backup convention). Keep it general (stage the whole `lib/` dir, not just the one file — future libs too). Update the script's header comment (the "What it does" list) to mention `hooks/local/lib/`. `bash -n` clean.

### P2 — `upgrade.sh`: make the merge-lib load robust (the real fix)
The merge MUST run even if the local lib wasn't present at the top of `main()`. Source the AUTHORITATIVE (target-version) lib from the SOURCE clone, and/or re-source after Step 1 refreshes `hooks/`. Concretely:
- Prefer sourcing the merge lib from `$SOURCE_CLONE/hooks/local/lib/merge-module-size-baseline.sh` (guaranteed to be the target version) — fall back to the local `$ROOT/...` path. Do this such that `merge_module_size_baseline` is defined by the time Step 1a runs.
- Belt-and-suspenders: right before the Step 1a guard ([upgrade.sh:268]), if `command -v merge_module_size_baseline` is still false, attempt the source again from `$SOURCE_CLONE` (now definitely present) and, failing that, print a LOUD warning that the baseline was NOT merge-preserved + the exact recovery (restore from `policies/module-size-baseline.txt.pre-upgrade-<ts>` or the `policies.pre-upgrade-<ts>/` dir). Never silently skip.
- Keep the existing behavior identical for the steady-state (v3.25.0→later) path (local lib present). Do NOT change the LOCKED merge rule itself. FR-25 <800 (upgrade.sh is near ceiling — check; extract only if needed, prefer a minimal in-place change).

### P3 — docs (U8-adjacent): pre-v3.25 adoption uses bootstrap
README / upgrade docs (wherever the "Upgrading an installed overlay" guidance lives — grep for `bootstrap-upgrade` and the upgrade section): add a clear note that **pre-v3.25 installs should run `bash hooks/local/bootstrap-upgrade.sh -- --auto-yes` for the v3.25.x hop** (it stages the new engine + libs first, so the baseline merge-preserve actually runs). State that running the old installed `upgrade.sh` directly cannot run the new merge logic (it ships inside the version you're upgrading TO), and that a clobbered baseline is recoverable from the `.pre-upgrade-<ts>` backup.

### P4 — integration test (the proof; RED-then-GREEN)
New `hooks/tests/test-bootstrap-baseline-hop.sh`: simulate the adoption hop end-to-end in a temp tree —
- a consumer tree with a `policies/module-size-baseline.txt` carrying a PROJECT row (a path NOT in upstream's baseline);
- a `.fusebase-flow-source/` (or `--source` dir) = the current repo (the v3.25.x target, which HAS `hooks/local/lib/`);
- run the bootstrap → upgrade chain (or the minimal equivalent that reproduces the staging gap);
- ASSERT: the project row SURVIVES and `check-module-size.sh --all` passes.
Prove it FAILS against the pre-fix bootstrap (i.e. without P1/P2) and PASSES after. Add it to `run-tests.sh`. Use loud setup asserts (avoid the false-green class from the last round — a missing file / silent exit-0 must fail the test).

## Worker-undisturbed (FR-07)
Zero diff to: FLOW_RULES.md FR rule rows; the 3 deploy policies' rule semantics; `ratchet-governance.yml`. These edits are to `upgrade.sh` / `bootstrap-upgrade.sh` / docs / tests only — none are FR-07-protected. Do NOT touch the LOCKED merge rule in `merge-module-size-baseline.sh` (only how/when it's sourced).

## Gate (stop here; produce the gate report; HALT)
preflight 0/0 · run-tests PASS (+ the new P4 test) · check-module-size --all exit 0 · mirror 0 drift · `bash -n` on both changed scripts · FR-25 all <800 · internal/+repo-polish untracked. Do NOT run the 27-min recovery-sim (targeted P4 test is the proof); if you want extra assurance, the recovery-sim is the strongest guard but optional here. Do NOT bump VERSION / push.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ P2 merge runs on the bootstrap/adoption hop (not just steady-state)  ☐ P4 FAILS pre-fix, PASSES post-fix
☐ FR-25 <800  ☐ check-module-size --all exit 0  ☐ commit cites the task
```

## Notes
- This is the follow-up the Codex adversarial review of v3.25.0 demanded. After the gate, a Codex re-review runs, then a v3.25.1 deploy.
- The fix's spirit: the baseline merge must be driven by the TARGET-version lib (from the source clone), because the running engine may predate it. That single insight (source the lib from `$SOURCE_CLONE`) is the core of P2.
