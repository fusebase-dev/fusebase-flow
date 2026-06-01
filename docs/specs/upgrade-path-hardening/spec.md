# Spec — upgrade-path-hardening

**Status:** DONE
**Created:** 2026-05-31
**Closed:** 2026-06-01
**Linked decisions:** F1..F8
**Deploy hash:** N/A — framework/template change

## Problem

Verified operator feedback (upgrading WorkHub Managed from an older Flow to 3.5.x) shows the **in-place upgrade path is the gap**: VERSION can advance ahead of content, stale overlay blocks never refresh, recovery silently wires hooks, a clean upgrade reads as RED `CLI_LAYER_DRIFT` for a single-provider project, tooling requires a `.git` clone the docs tell you to delete, and embedded version strings drift. All 8 claims verified against the code.

## Why now

Operator instruction (2026-05-31): "option C — fix/improve everything that's needed." The install path is mature; this closes the upgrade path.

## In scope

- **F1** `hooks/local/upgrade.sh` — atomic content upgrade (refresh canonical from clone → mirror → sync version strings → bump VERSION), backups + dry-run + confirm.
- **F2** version-aware overlay refresh (replace drifted present block, with backup; in upgrade context).
- **F3** opt-in settings.json hook wiring in `post-fusebase-update.sh` (`--wire-hooks`; loud notice; never touch un-added hooks).
- **F4** health/conflict-reporter: benign-absence for whole CLI provider surface (0 present = INFO, not drift); soften wording.
- **F5** `upgrade-engine.sh` (+ upgrade.sh): accept plain `.fusebase-flow-source/` dir (warn, not FATAL).
- **F7** `hooks/local/sync-version-strings.sh` deriving embedded `vX.Y.Z` from VERSION; fix current v3.5.0→v3.5.2.
- **F6** `.pyc` scrub line in upgrade.sh (gitignore rule already present).
- **F8** document canonical→mirror order (upgrade.sh + README).
- README "Health check & recovery"/upgrade section updated; VERSION → 3.6.0; changelog; release notes.

## Out of scope

- Changing the install docs to keep `.git` (F5 makes tools tolerant instead).
- Touching WorkHub Managed or any downstream project (reference only).
- New skills/FRs.

## Acceptance criteria

1. **AC1 (F1)** — `hooks/local/upgrade.sh` exists: refreshes `skills/ agents/ workflows/ policies/ templates/ FLOW_RULES.md` + framework docs from `.fusebase-flow-source/`, runs mirror-skills + mirror-agents + sync-version-strings, bumps VERSION — atomically (all-or-nothing; backups `.pre-upgrade-<ts>`); `--dry-run`, `--auto-yes`; consolidated diff summary; VERSION never written before content refresh succeeds.
2. **AC2 (F2)** — `post-fusebase-update.sh` (and upgrade.sh) detect a *present-but-drifted* AGENTS.md/CLAUDE.md overlay block and offer/perform replace-with-backup (upgrade context); recovery's missing→add path unchanged.
3. **AC3 (F3)** — `post-fusebase-update.sh` does NOT modify `.claude/settings.json` unless `--wire-hooks`; prints a loud notice; never alters a hook entry the merge didn't add. README/CLAUDE "opt-in hooks" claim now true.
4. **AC4 (F4)** — `check-cli-flow-conflicts.sh`: when **0 of N** known CLI provider skills (or agents) are present, emit a single INFO ("not installed — benign for non-FuseBase-Apps / single-provider projects"), NOT per-skill MISSING; **partial** present still → MISSING drift. A Claude-only project with no CLI provider surface → health **HEALTHY** (or benign), never `CLI_LAYER_DRIFT`. Wording no longer says "structurally damaged" for never-installed assets.
5. **AC5 (F5)** — `upgrade-engine.sh` + `upgrade.sh` accept a plain `.fusebase-flow-source/` dir: if no `.git`, WARN + fall back to VERSION-file compare (no FATAL). `.git` present still enables HEAD/diff.
6. **AC6 (F7)** — `hooks/local/sync-version-strings.sh` rewrites embedded self-attestation `vX.Y.Z` from VERSION across AGENTS/CLAUDE/GEMINI + overlay templates (non-historical only); current `v3.5.0` strings corrected to match VERSION; upgrade.sh calls it.
7. **AC7 (F6/F8)** — upgrade.sh scrubs stray `__pycache__`/`.pyc` before commit-advice; README documents the canonical→mirror order and the new upgrade path.
8. **AC8** — VERSION 3.6.0; CHANGELOG + `docs/release-notes/v3.6.md`; plugin manifests bumped.
9. **AC9** — preflight 0/0; run-tests PASS (+ new recovery/health assertions for F2/F3/F4); health HEALTHY; mirror drift 0; plugin validate clean; no competitor names; `internal/`+`repo-polish` not tracked.

## Risks

- **Health-engine change (F4) could mask real drift** → only the *all-absent* case becomes INFO; *partial* stays MISSING. Add a test fixture for 0-present-benign vs partial-drift.
- **Recovery F2/F3 behavior change** → guard with `test-cli-flow-recovery.sh` cases: stale-block-refresh, settings-not-touched-without-flag, settings-wired-with-flag.
- **upgrade.sh atomicity** → stage to a temp/work area or take backups of every touched path before writing; abort+restore on any sub-step failure (mirror order: content first, VERSION last).
- **sync-version-strings over-reach** → only rewrite the attestation/`This repo runs` lines; never touch dated release notes/handoffs/CHANGELOG.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Scope? | Option C — fix all 8 | 2026-05-31 |
| Touch downstream project? | No — WorkHub reference only | 2026-05-31 |
| Install docs keep .git? | No — make tools tolerant (F5) | 2026-05-31 |

## Close-out (2026-06-01)

All AC met; verification gate green.

**Post-release recheck (2026-06-01):** an independent verification against the actual 3.6.0 code (commit `7535e78`, not just the changelog) confirmed 6/8 solid and flagged two needing another pass — both now fixed in a second pass:
- **F2 was fixed-but-buggy:** the refresh was heading-anchored while the templates wrap the heading inside `CUSTOM:SKILL` markers, so the drift check was always-true and `upgrade.sh` (which calls `--refresh-overlays` every run) duplicated the overlay block each run, unbalancing the markers. Re-anchored on the markers, wrapped the CLAUDE.md template the same way, and added no-op/restore/idempotent assertions.
- **F7 was too narrow:** only 5 files were covered, leaving ~12 (incl. `agents/**/AGENT.md` and their mirrors) self-attesting `v3.5.0`. Broadened to all live-attestation surfaces with context-anchored (history-preserving) replacement + re-mirror.

| AC | Evidence |
|---|---|
| AC1 (F1) | `hooks/local/upgrade.sh` — content refresh → mirror → sync-strings → VERSION last; backups + `--dry-run`/`--auto-yes`; dry-run verified against a simulated plain-dir upstream |
| AC2 (F2) | `post-fusebase-update.sh --refresh-overlays` replaces a drifted present overlay block with `.pre-refresh-<ts>` backup; **marker-anchored** (CUSTOM:SKILL:BEGIN/END, not heading) so it is idempotent — no-op on a current block, single balanced BEGIN/END; CLAUDE.md template now marker-wrapped; recovery's missing→append path unchanged |
| AC3 (F3) | settings.json untouched without `--wire-hooks` (loud notice); merged + CLI Stop hooks preserved with it — both asserted in `test-cli-flow-recovery.sh` |
| AC4 (F4) | `check-cli-flow-conflicts.sh` 0-present → single benign INFO (not CLI_LAYER_DRIFT); partial still MISSING — both asserted; "structurally damaged" wording removed for never-installed assets |
| AC5 (F5) | `upgrade-engine.sh` + `upgrade.sh` accept a plain `.fusebase-flow-source/` dir (WARN, VERSION-compare fallback); `.git` still enables HEAD/diff — verified |
| AC6 (F7) | `hooks/local/sync-version-strings.sh` derives `vX.Y.Z` from VERSION across **all** live-attestation surfaces (agents/** + mirrors, workflows, templates, FLOW_RULES, copilot-instructions, .cursor rules, AGENTS/CLAUDE/GEMINI, overlays); **context-anchored** so historical refs (v2.3.0+/v2.4.0/v3.2.0/v2.7.0) are preserved; ~12 v3.5.0 strings corrected to v3.6.0; idempotent re-run is a no-op |
| AC7 (F6/F8) | `.pyc` scrub line in `upgrade.sh`; README documents canonical→mirror order + the new upgrade path |
| AC8 | VERSION 3.6.0; CHANGELOG `[3.6.0]`; `docs/release-notes/v3.6.md`; plugin manifests → 3.6.0 |
| AC9 | preflight 0/0 · run-tests 14/14 · recovery sim PASS (incl. new F3/F4 cases) · health HEALTHY · mirror drift 0 (50 files) · plugin validate clean · no competitor names · `internal/`+`repo-polish` untracked |

## Related

- `docs/specs/upgrade-path-hardening/decisions.md`
- `docs/release-notes/v3.6.md`
- source feedback: verified inline (this session)
