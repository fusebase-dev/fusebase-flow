# consumer-post-upgrade-gate-hook

**Status:** filed, NOT built — a new extension point is a new contract, and it gets its own premise review first
**Filed:** 2026-08-25
**Source:** paperclip+hermes-v1 escalation E2 (`2026-08-20-E2-consumer-post-upgrade-hook.md`)
**One-liner:** one documented `hooks/local/post-upgrade-gate.local.sh`, run by the SOURCE engine after the per-file apply loop and before it reports success, so a consumer maintaining its own enforcement can assert FATALLY that its controls survived the hop.

## The gap is real — re-confirmed against v4.14.0, not taken on their word

| Their claim | Verdict here |
|---|---|
| The sanctioned adoption route ends in `exec` of the SOURCE engine | **CONFIRMED.** `hooks/local/bootstrap-upgrade.sh:750` is the file's last statement: `exec bash "$ENGINE_SRC" …`. Their `:714-750` citation against `4.12.0+1` maps unchanged onto v4.14.0. |
| So nothing the consumer installed can run after the hop | **CONFIRMED.** `hooks/local/upgrade.sh` prints next steps and ends `UPGRADE_FINISHED=1; trap - INT TERM ERR; exit 0` (`:815-818`). There is no post-apply seam. Both `upgrade.sh` and `post-fusebase-update.sh` are managed paths the engine refreshes, and the INSTALLED engine is never invoked, so a consumer edit to either is not a seam either. |
| `*.local.*` is already the "consumer-owned, never refreshed" convention | **CONFIRMED.** `upgrade.sh:18,306,789` state it — `hooks/local/*.local.*` survives the hop. The proposed filename needs no new convention. |

## Why the consumer needs it

A consumer maintaining ANY local enforcement — a PreToolUse veto, a composed security gate, a manifest re-stamp recipe — has no seam in which to assert *"after this hop my controls are still live"* except by hand, after the engine already exited 0. Measured twice on their side: `2026-07-29` C2 (the four-layer gate) and `2026-08-04` (FR-12 left fail-open by an installed-engine hop, live until rolled back). A `--auto-yes` run that exits 0 while a consumer gate would have failed is a silent regression.

They explicitly do NOT ask for I4/I5-style patching of `upgrade.sh` to keep a seam alive — their reviewer and ours both refuted decomposing the engine for that reason.

## Why it is NOT being built now

1. **A new extension point is a new contract.** The last three tickets in this chain each turned on a premise review run BEFORE any code (E1 → WRONG-LAYER/NO-BUILD; E6 → built; E7 → built). This one's contract questions are open and none is small:
   - Does a non-zero gate make the engine report FAILED **after** the tree is already upgraded? That is a "files changed AND the run failed" terminal state Flow has never shipped. The proposal accepts it (the `.pre-upgrade-<ts>` backup exists, `upgrade.sh:27,528`) — but accepting it is a decision, not a detail.
   - Ordering: before or after the manifest re-stamp, the pre-commit reinstall, and the recovery-hint block?
   - Its own liveness bound (FR-27): a consumer gate that hangs hangs the upgrade. `hooks/local/lib/bounded-run.sh` exists; wiring it is part of the contract, not an afterthought.
   - Skipped under `--dry-run` only, or under every non-applying mode?
   - It executes consumer-authored code inside Flow's own upgrade path. That is a deliberate change to the M17 same-principal threat model, and it must be stated, not inherited.
2. **`upgrade.sh` is 821/800 lines and the decomposition debt is already assigned.** `upgrade-sh-at-module-ceiling` ruled that the next change touching `upgrade.sh` must decompose it FIRST — prerequisite, not cleanup. This ticket cannot be built without paying that, and that is a feature: it forces the seam question to be answered structurally rather than as patch #N.
3. **Not urgent.** Their interim procedure — a manually-run composed gate (`hooks/local/check-post-upgrade-gate.local.sh`) after every hop — works and is disclosed.

## Shape if commissioned (their three asks, in substance)

1. ONE hook point: `hooks/local/post-upgrade-gate.local.sh` if present, executed by the SOURCE engine after the per-file apply loop and before it reports success. Non-zero ⇒ engine reports FAILED (exit 1) and prints the gate's output. It does NOT roll back. It does NOT run under `--dry-run`.
2. Runs with the NEW bytes on disk and with `FF_UPGRADE_FROM=<old VERSION>` / `FF_UPGRADE_TO=<new VERSION>` in the environment, so a consumer gate can key on the hop.
3. One line in the release notes' adoption section naming the hook point, so consumers stop inventing post-hop ceremonies.

## Acceptance sketch (to be refined at spec)

1. AC1 — with no `post-upgrade-gate.local.sh` present, an upgrade run is byte-identical in behaviour to today's.
2. AC2 — a gate exiting non-zero makes the engine exit 1 and print the gate's stdout+stderr; applied files stay applied and the message says so plainly.
3. AC3 — `--dry-run` never executes the gate.
4. AC4 — the gate is bounded (FR-27); a hanging gate is killed and reported, never left to hang the upgrade.
5. AC5 — `FF_UPGRADE_FROM` / `FF_UPGRADE_TO` are set to the real versions, proven by a test gate that echoes them.

## Out of scope

- Rolling back an applied hop on gate failure.
- Any `upgrade.sh` decomposition beyond what `upgrade-sh-at-module-ceiling` already requires.
- A hook point in the INSTALLED engine — the whole point is that the installed engine never runs.

## Risks / unknowns

- Executing consumer code inside the upgrade path changes the threat model M17 locked.
- "Reports FAILED after applying" is a new terminal state; it can train the re-run-until-green habit `release-gate-flaky-job-probe` documents.
- Ordinary-consumer demand is **UNVERIFIED** — both consumers driving this chain run their own overlays (`docs/north-star.md`).

## Related

- `docs/backlog/upgrade-sh-at-module-ceiling/README.md` — the decomposition prerequisite that gates this
- `docs/problem-catalog/live-enforcement-inertness/problem.md` — enforcement wired but inert; the class this gate would catch
- `hooks/local/bootstrap-upgrade.sh:750` · `hooks/local/upgrade.sh:815-818` · `hooks/local/lib/bounded-run.sh`
- Their prior filings `2026-07-30` / `2026-08-04`; `docs/release-notes/v4.7.0.md` § adoption
