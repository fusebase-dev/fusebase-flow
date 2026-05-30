# Spec — provider-skill-drift-guards

**Status:** DONE
**Created:** 2026-05-29
**Linked decisions:** B1..B8
**Promoted from:** external adoption feedback (v3.1 provider-skill drift-risk audit, 2026-05-29)
**Deploy hash:** N/A — framework/template change, no production deploy
**Closure:** T10..T16 shipped (b35afa4..abb0e11) and pushed to origin; gate T17 green; post-implement review verdict CLEAN_TO_FLIP (0 blockers, 6 findings refuted, 1 nit TEST-4 deferred). Released as VERSION 3.2.0.

## Problem

The CLI edition VENDORS a second copy of FuseBase CLI-owned assets (19 provider skills + their `references/`, 2 CLI app-agents, 4 CLI quality hooks) inside the Flow template. Those vendored copies are written by two independent tools — `fusebase update` (live CLI bundle) and the frozen Flow snapshot — with no provenance, no freshness signal, and no content-drift detection. The recovery model already protects CLI assets from being overwritten *by Flow recovery* (mirror scope is canonical-only; manifest marks CLI skills `flow_write_mode:"never"`; `post-fusebase-update.sh` excludes CLI paths — all verified holding). The residual gaps are: vendored assets carry no provenance/version stamp; the conflict reporter checks **existence, not drift**; the two-writer overwrite hazard (incl. `CUSTOM:SKILL` blocks) is undetected and the broad documented install copy clobbers CLI-owned assets; CLI app-agents are owned by a fragile `app-*.md` wildcard; and the Windows-fragile jq/bash Stop hooks are wired while the Windows-hardened node hook sits idle.

## Why now

External evaluator audited commit `3c9c00a` (VERSION 3.1) for adoption into a live Fusebase Apps project that manages provider skills via `fusebase update`, and found drift-on-arrival already occurring. All claims were independently verified against the code (workflow `w53s6vemy`, 8 grounded verdicts + completeness critic). Closing these before broader adoption prevents silent staleness and data-loss on install.

## In scope

- Provenance manifest + freshness signal for all vendored CLI-owned assets (skills, agents, hooks).
- Drift-aware conflict reporter (content hash vs provenance) + `CUSTOM:SKILL` at-risk scan.
- Pin CLI app-agents by explicit `known_names` (retire the `app-*.md` wildcard).
- Consolidate Stop hooks onto the Windows-hardened node hooks; retire jq/bash duplicates.
- Make the documented install copy non-clobbering for CLI-owned assets; document the two-writer hazard.
- Doc-accuracy fixes (FR-19 straggler; `run-typecheck-features.js` → `run-typecheck-apps.js`).
- Version bump + changelog + release notes + README health/recovery refresh.

## Out of scope

- **Reference-over-copy / de-vendoring** (feedback's preferred Issue [4] fix) — rejected per decision **B1**; preserves offline/template UX. Vendoring stays, gated behind provenance + freshness.
- Restoring CLI-owned content from the Flow snapshot — remains CLI-owned; Flow diagnoses only (CLI-first/Flow-second model, unchanged).
- Comparing the bundled snapshot against the *live* CLI bundle (UNVERIFIABLE_LOCALLY; freshness is advisory only).
- Issue [5] (HEALTHY masking) — verified safe, dropped (explicit positive marker at `fusebase-flow-health-check.sh:185`).

## Acceptance criteria

1. **AC1** — A read-only provenance manifest (`audit/cli-vendor-manifest.json`) lists every vendored CLI-owned asset (19 provider skills incl. `references/`, 2 app-agents ×2 providers, 4 hooks) with: source-CLI version (or `unknown` sentinel), bundling date, and per-file sha256. A generator script regenerates it deterministically. (B2)
2. **AC2** — `check-cli-flow-conflicts.sh` hashes each present CLI asset against the manifest and reports a present-but-changed asset as an advisory `CLI_SNAPSHOT_STALE` (info, non-failing) — distinct from `MISSING` → `CLI_LAYER_DRIFT`. Restoration still deferred to the CLI. (B3)
3. **AC3** — The reporter scans CLI-owned skill files for `<!-- CUSTOM:SKILL:BEGIN -->…END` blocks and lists any found as "at-risk on next refresh". (B3)
4. **AC4** — CLI app-agents are pinned by explicit `known_names` (e.g. `app-architect`, `app-create-checker`) in `agent-surface-ownership.json` for BOTH `.claude/agents` and `.codex/agents`; the checker iterates that list (no `glob("app-*.md")`); a hypothetical Flow agent named `app-*` is attributed flow-owned, not cli-owned. (B4)
5. **AC5** — `.claude/settings.json.example` wires only node Stop hooks (Windows CVE-2024-27980 `shell:win32` patch active); the jq/bash duplicates (`run-typecheck-on-stop.sh`, `run-lint-on-stop.sh`) are removed or marked deprecated and unwired; no wired Stop hook hard-depends on `jq`/bash. (B5)
6. **AC6** — The documented install copy steps (`docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`) do NOT overwrite existing CLI-owned assets (copy-if-absent / explicit exclusion; no unconditional `-Force` over CLI paths); the two-writer hazard is documented in `docs/fusebase-cli-edition.md`. (B6)
7. **AC7** — `docs/install-existing-project.md:250` reads `FR-01..FR-19`; no shipped/tracked doc references the nonexistent `run-typecheck-features.js` (corrected to `run-typecheck-apps.js`). (B7)
8. **AC8** — `VERSION` = `3.2.0`; `CHANGELOG.md` + `docs/release-notes/v3.2.md` document the drift-guard changes; README "Health check & recovery" reflects the new reporter behavior + provenance. (B8)
9. **AC9** — Full gate green and **no regression of the verified baseline protections**: `preflight.sh` 0/0; `run-tests.sh` PASS; `test-cli-flow-recovery.sh` PASS (updated for new reporter behavior); `check-cli-flow-conflicts.sh` and `fusebase-flow-health-check.sh` report expected verdicts; mirror-skills/agents scope unchanged (canonical-only); manifest `flow_write_mode:"never"` for CLI skills intact.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths | none (no downstream worker paths; template repo) |
| Mixed-fleet considerations | N/A — edition template; changes are additive guards |
| Migration approach | no migration; additive manifest + checker logic + doc edits |
| Auth model | N/A — no auth surface touched |
| Quality bar | new provenance generator + drift/CUSTOM tests added to `test-cli-flow-recovery.sh`; preflight/CI extended |

## Backend changes

N/A (no application backend). Framework asset + tooling changes only — see tasks.

## Risks

- **Checker change breaks existing fixtures** → T11/T14 update `test-cli-flow-recovery.sh` in the same commit (FR-13). Mitigation: keep `CLI_SNAPSHOT_STALE` advisory (non-failing) so HEALTHY/verdict semantics for missing-vs-stale stay distinct.
- **Provenance "source CLI version" is unknowable locally** → record `unknown` sentinel + bundling date + sha; freshness is advisory only, never blocks. (UNVERIFIABLE_LOCALLY documented.)
- **Hook consolidation removes a hook a downstream wired** → `settings.json.example` is an example (not active); document the swap in CHANGELOG/release notes. Keep deprecated `.sh` files one release with a deprecation header rather than hard-deleting, unless redundant with `quality-check-apps.js`.
- **Install copy edit could under-copy** → use copy-if-absent for CLI-owned paths only; Flow-owned paths still copy normally.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | Issue [4] direction: reference-over-copy vs vendoring+guards? | 2026-05-29 — operator delegated; **vendoring + guards** (B1) |
| Q-B | Execution path? | 2026-05-29 — PO drafts spec/decisions/tasks/gate/handoff; AI Developer executes T10–T17, stop at gate |
| Q-C | Issue [5]? | 2026-05-29 — verified safe, dropped |

## Related

- `docs/specs/provider-skill-drift-guards/decisions.md`
- `docs/specs/provider-skill-drift-guards/tasks.md`
- `docs/specs/provider-skill-drift-guards/verification-gate.md`
- `docs/handoff/2026-05-29-provider-skill-drift-guards-implement.md`
- Verification source: workflow `w53s6vemy` (8 verdicts + completeness critic)
- Builds on: `docs/specs/cli-first-flow-second-recovery/` (CLI-first/Flow-second baseline)
