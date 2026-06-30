# Spec — cli-0.25.9-vendor-refresh

**Status:** DONE — shipped **v3.30.0** (deploy hash `25bdd59`, tag `v3.30.0`, release https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.30.0). Deployed 2026-06-29 (UTC 2026-06-30). All gate + probe + real-CLI ticket smoke PASS: run-tests 164/164; check-module-size --all exit 0; mirror 0 drift; plugin==VERSION==3.30.0; GEMINI.md=v3.30.0; README badge 3.30.0; 5 FR-07 surfaces UNCHANGED; cli-vendor-manifest fresh; merge appends stop.py once + 0 run-typecheck-apps.js + preserves the 3 CLI hooks + enabledMcpjsonServers + idempotent; health-check HEALTHY (shared_merge_drift:0, cli_snapshot_stale:0) on the real extracted 0.25.9 CLI settings; settings.json.example wired to the 0.25.9 set; 20 CLI-provider skills; manifest re-stamp 0-diff; headroom=0. 2 follow-ups filed to backlog (1 MED + 1 LOW, neither blocking).

**Status (historical):** LOCKED — design review folded (RESCOPE). Target **v3.30.0**.
**Created:** 2026-06-29
**Baseline:** FuseBase Flow v3.29.0
**Source:** Operator compatibility check against `fusebase-apps-cli` **0.25.9** (zip provided). Flow v3.29.0 RUNS with 0.25.9 (structurally compatible — same AGENTS.md/CLAUDE.md/.claude/{skills,agents,hooks}/settings.json conventions; restore never clobbers CLI assets), but its vendored CLI snapshot and CLI-Stop-hook model are STALE, producing real warts. All findings below were PROVEN against the extracted 0.25.9 tree + a fixture run of the conflict reporter.
**Design review:** Codex 2026-06-29 → **RESCOPE** (diagnosis + all 4 facts confirmed). Folded: **D1 = option C** (preserve-only merge + DIFF-framed health-check — flag only a CLI hook that Flow's merge actually DROPPED vs the pre-merge `.claude/settings.json` Stop chain; use `.claude/hooks/` only to classify an already-wired command as a CLI hook; never invent hooks from static names; never remove an existing hook → keeps older-CLI projects that still wire `run-typecheck-apps.js` safe). **D2 = full re-vendor** (manifest-only would certify stale content). **D3 = v3.30.0** (MINOR — hook-merge behavior change + new vendored skill). Two HIGH additions I missed: **(H1)** `.claude/settings.json.example` still wires `run-typecheck-apps.js` + calls the `*-on-stop.sh` hooks deprecated — contradicts 0.25.9, MUST update; **(H2)** `app-api-contract-testing` is FLAG-GATED upstream (CLI `copy-template.ts` gates it behind `cross-app-api-calls-analysis`) — add it to `flag_gated_skills` (not only `known_names`), else false `CLI_LAYER_DRIFT` when the flag is off. Plus **(M)** existing `hooks/tests/test-cli-flow-recovery.sh` encodes the OLD model (asserts run-typecheck-apps.js preservation + `*-on-stop.sh` deprecated) → must update; **(L)** extra stale refs (`audit/README.md`, `stamp-cli-provenance.sh` comments, README hook/count). D1–D4 locked below.

## Problem (proven)
Root cause: Flow HARDCODES the CLI's Stop-hook set as `[run-typecheck-apps.js, quality-check-apps.js]` in **two** places — `hooks/local/check-cli-flow-conflicts.sh` (`expected_cli_markers`, ~L338) and `hooks/local/fusebase-flow-overlays/settings-json-merge.py` (`CLI_STOP_HOOKS`, ~L64). This predates 0.25.9, which **replaced the wired `run-typecheck-apps.js` with `run-typecheck-on-stop.sh`** and added `run-lint-on-stop.sh`. 0.25.9 wires exactly `[run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js]` and wires `run-typecheck-apps.js` **0 times** (confirmed). Consequences:

1. **Health-check false positive (proven).** On a 0.25.9 project with Flow's `stop.py` + the CLI's actual 3 hooks, `check-cli-flow-conflicts.sh` returns **`SHARED_MERGE_DRIFT` → "CLI Stop hooks not preserved: run-typecheck-apps.js"** — a phantom (0.25.9 doesn't wire that hook).
2. **Restore re-injects a deprecated hook (proven).** `settings-json-merge.py` deep-merge PRESERVES the CLI's 3 hooks + `enabledMcpjsonServers` (✅ safe, never clobbers) but **re-adds `run-typecheck-apps.js`** → typecheck runs TWICE on Stop (`run-typecheck-apps.js` + `run-typecheck-on-stop.sh`). Wasteful; also masks #1 in the default `--wire-hooks` flow (consistently stale together).
3. **Vendored snapshot stale (advisory).** CLI 0.25.9 has **20** provider skills (new `app-api-contract-testing`; none removed/renamed), **4** `.claude/hooks` (new `run-lint-on-stop.sh`, `run-typecheck-on-stop.sh`), and changed skill CONTENT (e.g. `fusebase-cli`, `app-dev-practices`). Flow vendors 19 skills + 2 hooks with frozen sha256 → `CLI_SNAPSHOT_STALE` advisory; `app-api-contract-testing` absent from `known_names` (health-check unaware — benign).

Nothing is BROKEN; Flow v3.29.0 installs/works on 0.25.9. This refresh removes the noise + the redundant typecheck + the false positive, and future-proofs the model.

## In scope (D1 = option C; full re-vendor; + the 2 HIGH additions)
- **B (load-bearing) — de-stale the CLI-Stop-hook model via the DIFF framing (D1c).**
  - `settings-json-merge.py`: make it **preserve-only** for CLI Stop hooks — append `stop.py` (once, idempotent) + preserve every existing Stop hook; **stop RE-INJECTING `run-typecheck-apps.js`** (remove it from the auto-inject `CLI_STOP_HOOKS`, or gate re-inject to "already wired"). Never remove an existing hook (so an older-CLI project that still wires `run-typecheck-apps.js` keeps it).
  - `check-cli-flow-conflicts.sh`: replace the hardcoded `expected_cli_markers` with the DIFF check — flag `SHARED_MERGE_DRIFT` only if Flow's merge DROPPED a CLI Stop command that was wired in the pre-merge `.claude/settings.json` (source = the project's actual settings, NOT static names; use `.claude/hooks/` only to classify an already-wired command as CLI-owned). No false positive on 0.25.9's 3-hook set; still flags a genuinely-dropped hook.
- **H1 — `.claude/settings.json.example`.** Update its Stop chain to 0.25.9's wired set (`run-lint-on-stop.sh`, `run-typecheck-on-stop.sh`, `quality-check-apps.js`) + Flow `stop.py`, and fix the comments that call the `*-on-stop.sh` hooks deprecated. (This file is also what `settings-json-merge.py` auto-discovers Flow's events from — keep `stop.py` discoverable as the `hooks/handlers/` command.)
- **A (freshness) — full re-vendor to 0.25.9.** Re-copy 0.25.9's CLI-owned assets over Flow's vendored copies: 20 provider skills (+ `references/`), 4 `.claude/hooks`, 2 app-agents → `.claude/skills`, `.agents/skills`, `.claude/hooks`, `.claude/agents`, `.codex/agents`. Re-run `stamp-cli-provenance.sh` → fresh `cli-vendor-manifest.json`.
- **H2 — flag-gate the new skill.** Add `app-api-contract-testing` to BOTH `known_names` (`.claude` + `.agents` entries) AND `flag_gated_skills: {"app-api-contract-testing": ["cross-app-api-calls-analysis"]}` in `agent-surface-ownership.json` (verify the flag name against the CLI's `copy-template.ts`), so absence-when-flag-off is benign, not `CLI_LAYER_DRIFT`. Bump the CLI-skill count 19→20 in the AGENTS/overlay catalog.
- **C — docs.** `docs/compatibility.md` (19→20, 0.25.9 wired-hook set, `38=19x2`→`40=20x2`, version ref), `docs/source-map.md` (CLI-provider count), `README.md` ("19 provider skills" → 20 + hook/count sections), `docs/fusebase-cli-edition.md` (CLI Stop-hook description), `audit/README.md` (count), `stamp-cli-provenance.sh` comments. (Historical release notes stay historical.)
- **D — tests.** (a) NEW `0.25.9-shaped` fixture: conflict reporter does NOT emit `SHARED_MERGE_DRIFT` for the CLI's 3-hook set + Flow `stop.py` (RED-then-GREEN), and DOES still flag a genuinely-dropped CLI hook; (b) `settings-json-merge.py` on a 0.25.9 settings: NO `run-typecheck-apps.js` added, preserves the 3 hooks + `enabledMcpjsonServers`, appends `stop.py` once, idempotent; (c) re-vendor freshness — vendored sha == manifest, `app-api-contract-testing` flag-gated benign when flag off; (d) **UPDATE `hooks/tests/test-cli-flow-recovery.sh`** — replace the old assertions (run-typecheck-apps.js preservation, `*-on-stop.sh` deprecated/non-reinjected) with the 0.25.9 model. No-regression: 26 health-check timeout tests + non-FuseBase/0-present benign behavior unchanged; FFHC API + read-only-no-`fusebase`-calls guarantee intact.

## Out of scope
- Changing CLI behavior; Codex-plugin packaging (separate parked ticket).
- Making the health-check invoke the `fusebase` CLI (stays read-only, no CLI calls — preserve that guarantee).

## Constraints (FR-07 / clean-room)
- No diff to FLOW_RULES FR rows / the 3 deploy-policy rule semantics / ratchet-governance.yml.
- Editable: `check-cli-flow-conflicts.sh`, `settings-json-merge.py`, `agent-surface-ownership.json`, `cli-vendor-manifest.json` (via `stamp-cli-provenance.sh`), the vendored CLI assets (CLI-owned, re-vendoring is the point), docs.
- **Clean-room:** re-vendored CLI provider assets stay CLI-owned (NOT canonical Flow clean-room) — same boundary `docs/source-map.md` already documents; do not assert the Flow clean-room attestation over them. They're first-party FuseBase CLI content.
- Do NOT break the `ffhc_*` API or the health-check verdict/exit contract (PARTIAL_UNVERIFIED, exit codes).

## Decisions (LOCKED — design review folded)
- **D1 = option C** (diff-framed, version-agnostic): merge is **preserve-only** (append `stop.py`, keep every existing Stop hook, never re-inject `run-typecheck-apps.js` from a static name, never remove); health-check flags `SHARED_MERGE_DRIFT` only when Flow's merge DROPPED a CLI Stop command that was in the **pre-merge `.claude/settings.json`** Stop chain (`.claude/hooks/` used only to classify an already-wired command). Keeps older-CLI projects (still wiring `run-typecheck-apps.js`) safe; no false positive on 0.25.9.
- **D2 = full re-vendor** of all 0.25.9 CLI-owned assets + provenance restamp (manifest-only would certify stale content). CLI-owned boundary stays explicit (not canonical Flow clean-room).
- **D3 = v3.30.0** (MINOR — hook-merge behavior change + new vendored skill).
- **D4 = safe as scoped:** do NOT alter the FFHC API or the health-check verdict/exit contract; do NOT call `fusebase`; preserve `run-typecheck-apps.js` when already wired (older projects).

## Acceptance criteria
- **AC1 (B)** Conflict reporter: on the 0.25.9 wired set + Flow `stop.py`, verdict is NOT `SHARED_MERGE_DRIFT`/no false "not preserved"; a previously-wired CLI hook that Flow's merge actually dropped IS still flagged (the genuine case preserved). RED-then-GREEN.
- **AC2 (B)** `settings-json-merge.py` on a 0.25.9 settings.json: does NOT add `run-typecheck-apps.js`; preserves the 3 CLI hooks + `enabledMcpjsonServers`; appends `stop.py` exactly once; idempotent (2nd run byte-identical).
- **AC3 (A)** `cli-vendor-manifest.json` fresh (sha matches vendored files); `app-api-contract-testing` in `known_names` (both surfaces); CLI-skill count 19→20 everywhere it's asserted; `check_provenance` clean (no `CLI_SNAPSHOT_STALE` against the refreshed snapshot).
- **AC3b (H2 flag-gate)** `app-api-contract-testing` in `flag_gated_skills` (flag `cross-app-api-calls-analysis`, verified vs CLI `copy-template.ts`); a fixture with the flag OFF + skill absent → benign INFO, NOT `CLI_LAYER_DRIFT`.
- **AC3c (H1 example)** `.claude/settings.json.example` wires 0.25.9's Stop set (`run-lint-on-stop.sh`, `run-typecheck-on-stop.sh`, `quality-check-apps.js`) + `stop.py`; no `run-typecheck-apps.js`; no "deprecated" comment on the `*-on-stop.sh` hooks; `stop.py` still discoverable by `settings-json-merge.py`.
- **AC3d (test model)** `hooks/tests/test-cli-flow-recovery.sh` old assertions (run-typecheck-apps.js preservation / `*-on-stop.sh` deprecated) replaced with the 0.25.9 model; suite green.
- **AC4 (C)** docs updated (compatibility.md/source-map/README/cli-edition) to 0.25.9 reality.
- **AC5 (no-regression)** 26 health-check timeout tests pass; conflict reporter on a non-FuseBase / 0-present project still benign (no false drift); FFHC API + read-only guarantee intact.
- **AC6 (gate)** preflight 0/0; run-tests PASS incl. new tests; check-module-size --all exit 0; mirror 0 drift; FR-07 clean; clean-room boundary intact (CLI assets not under Flow attestation).

## Tasks (finalize post-design-review)
- **T1 (B)** de-stale `check-cli-flow-conflicts.sh` + `settings-json-merge.py` per D1.
- **T2 (A)** re-vendor 0.25.9 assets + `stamp-cli-provenance.sh` + `known_names`/count updates per D2.
- **T3 (C)** docs.
- **T4 (D)** fixture tests (AC1/AC2/AC3) + no-regression (AC5) + wire into run-tests; re-mirror if needed.

## Risks
- **Auto-discovery over/under-including** CLI hooks → mis-flag or mis-merge: pin the discovery source precisely (D1); the diff-based "did the merge drop a hook" framing (D1c) is the most version-agnostic.
- **Re-vendor pulling in unexpected CLI content** (e.g. a skill that references something Flow can't satisfy): re-vendor is byte-copy of CLI-owned text only; no execution; clean-room boundary preserved.
- **Regressing older-CLI projects** (still wiring run-typecheck-apps.js): the merge must keep preserving it if already present (never remove) — only stop ADDING it; the health-check must not flag a genuinely-dropped hook as fine. AC1/AC5 guard this.
