# Spec — upgrade-path-hardening-2

**Status:** DONE
**Created:** 2026-06-01
**Closed:** 2026-06-01
**Linked decisions:** U1..U8
**Deploy hash:** N/A — framework/template change
**Source:** verified downstream feedback from an in-place 3.5.2 → 3.7.0 upgrade on a live, customized repo (WorkHub Managed). F2/F3/F4 confirmed solid in practice; 8 upgrade-path gaps surfaced.

## Problem (severity-ranked)

| # | Sev | Finding |
|---|---|---|
| U1 | High | Overlay refresh does a full-block replace, **wiping operator-filled `### Project-specific values`** inside the marker block (data loss). |
| U2 | High | `upgrade.sh` never refreshes `hooks/` → stale hook layer (the tier-aware deploy gate silently doesn't work) and the upgrade tooling (which lives in `hooks/local/`) can't self-update. |
| U3 | Med | `GEMINI.md` (and any adapter) keeps a stale **FR-range / skill-count** after upgrade — `sync-version-strings` bumps the version only; GEMINI has no refresh path → "v3.7.0 … FR-01 through FR-20". |
| U4 | Med | `upgrade.sh` copies 14 framework `docs/*.md` into the **consumer's** `docs/` root — framework-dev docs that collide with consumer doc conventions. |
| U5 | Med | No bootstrap for **pre-3.6.0** installs: `upgrade.sh` ships in the version you need it to reach. |
| U6 | Low | LL ledger hard-coded to `docs/changes/index.md` (repo root) — collides with per-app docs layouts. |
| U7 | Low | Legacy marker-less CLAUDE.md migration leaves a redundant `---` before the block (trailing-blank trim handles blanks, not the rule). |
| U8 | Low | `sync-version-strings.sh` prints `ignored null byte in input` on some scanned file. |

## Why now

Operator forwarded the feedback ("another feedback") after running the real upgrade. U1 is data loss; U2 makes the v3.7.0 tier-aware gate silently inert on upgrade — both block trustworthy in-place upgrades.

## In scope

- **U1** Carve the operator-customizable `### Project-specific values` into an inner **`FLOW:PRESERVE`** sub-region; overlay refresh carries the existing preserve-region forward into the fresh template (merge-preserve). No more clobbering.
- **U2** Add `hooks/` to `upgrade.sh`'s refreshed content (preserving `hooks/local/*.local.*`; `.claude/hooks/**` is CLI-owned and untouched). Engine scripts (`upgrade.sh`, `sync-version-strings.sh`) self-update like `upgrade-engine.sh`.
- **U3** Generalize `sync-version-strings.sh` to sync **derived attestation facts** — version **and** FR-range (`FR-01..FR-NN` derived from `FLOW_RULES.md`) **and** the `(NN canonical skills total)` count — across all adapters incl. GEMINI.
- **U4** Default `upgrade.sh` does **not** copy framework `docs/*.md` into the consumer; behind `--with-framework-docs` (namespaced to `docs/_fusebase-flow/`).
- **U5** `hooks/local/bootstrap-upgrade.sh` + documented one-liner: stage a source clone, copy in the engine scripts, run `upgrade.sh`.
- **U6** LL ledger is opt-in / path-configurable; default guidance is inline-in-commit; skill + template updated.
- **U7** Legacy migration also trims a trailing `---` rule from the preserved pre-block region (begin_line==0 path only — preserves byte-exactness in the marker-wrapped path).
- **U8** `tr -d '\0'` the scanned input in `sync-version-strings.sh`.
- VERSION 3.8.0; CHANGELOG; release notes; plugin manifests; tests.

## Out of scope

- Changing F2/F3/F4 behavior (confirmed solid).
- Touching the downstream project (reference only).
- New lifecycle phases / FR rules.

## Acceptance criteria

1. **AC1 (U1)** — `agents-md-overlay.md` wraps `### Project-specific values` in `<!-- FLOW:PRESERVE:BEGIN -->…<!-- FLOW:PRESERVE:END -->`; `refresh_overlay_block()` carries the existing preserve-region forward, so a refresh of a block with operator-customized project-values updates the surrounding framework prose **without** changing the operator's values. A test proves operator values survive a drift refresh.
2. **AC2 (U2)** — `upgrade.sh` refreshes `hooks/` (handlers, shared, git, tests, local `*.sh`) while preserving `hooks/local/*.local.*`; the dry-run plan lists hook changes; `.claude/hooks/**` untouched. Engine scripts self-update (note: new logic active next run).
3. **AC3 (U3)** — `sync-version-strings.sh` rewrites version + `FR-01..FR-NN` + `(NN canonical skills total)` derived from the repo; running it leaves GEMINI/AGENTS/CLAUDE/adapters internally consistent (no "v3.x … FR-01..FR-(N-1)"). Idempotent.
4. **AC4 (U4)** — default `upgrade.sh` does not write framework docs into the consumer `docs/` root; `--with-framework-docs` namespaces them under `docs/_fusebase-flow/`. Dry-run states which.
5. **AC5 (U5)** — `hooks/local/bootstrap-upgrade.sh` stages `.fusebase-flow-source/`, copies engine scripts, runs `upgrade.sh`; README documents the pre-3.6.0 one-shot.
6. **AC6 (U6)** — LL ledger is opt-in/configurable; `lightweight-lane` skill + `change-note` template default to inline-in-commit and only materialize a ledger on opt-in / at a configurable path.
7. **AC7 (U7)** — legacy marker-less CLAUDE.md migration produces exactly one `---` before the heading (no doubled rule); marker-wrapped byte-exactness (the v3.7.0 F2 lock) still holds.
8. **AC8 (U8)** — `sync-version-strings.sh` emits no null-byte warning.
9. **AC9** — VERSION 3.8.0; CHANGELOG + `docs/release-notes/v3.8.md`; plugin manifests; preflight 0/0; run-tests PASS (+ U1 preserve + U7 legacy-rule assertions); recovery sim PASS; health HEALTHY (24 skills); mirror drift 0; plugin validate clean; no competitor names; `internal/`+`repo-polish` untracked.

## Risks

- **U1 carry-forward could mis-merge** → only the content between `FLOW:PRESERVE` markers is carried; if absent in the existing block (pre-fix installs), fall back to template default (one-time, already-lost case). Guarded by a test.
- **U2 self-update of a running script** → copy is fine (bash is already in memory); print "new logic active next run" like `upgrade-engine.sh`. Preserve `*.local.*`.
- **U3 over-broad FR-range/count replace** → context-anchored to the live `FR-01..FR-N` / `(N canonical skills total)` forms; scan excludes dated dirs (release-notes/handoff/specs/CHANGELOG); historical FR mentions (e.g. "FR-19 rule") are not the range form and are untouched.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Scope | Fix all 8 (U1/U2 are blockers) | 2026-06-01 |
| Touch downstream? | No — reference only | 2026-06-01 |
| U1 strategy | Inner FLOW:PRESERVE merge-preserve (keeps values in AGENTS.md, discoverable) | 2026-06-01 |
| U4 docs | Default off; `--with-framework-docs` → `docs/_fusebase-flow/` | 2026-06-01 |

## Close-out (2026-06-01)

All AC met; verification gate green.

| AC | Evidence |
|---|---|
| AC1 (U1) | `FLOW:PRESERVE` markers in `agents-md-overlay.md`; `refresh_overlay_block()` carries the region forward; recovery-sim "U1: refresh preserves operator FLOW:PRESERVE values while refreshing framework prose" PASS |
| AC2 (U2) | `hooks` in `upgrade.sh` CONTENT_DIRS; dry-run shows `refresh dir: hooks/`; `hooks/local/*.local.*` preserved (copy-over, no delete); `.claude/hooks/**` untouched; engine self-update note printed |
| AC3 (U3) | `sync-version-strings.sh` derives + syncs version + `FR-01..FR-NN` + `(NN canonical skills total)`; idempotent no-op on the repo; GEMINI covered |
| AC4 (U4) | default dry-run prints "framework docs NOT copied"; `--with-framework-docs` → `docs/_fusebase-flow/` (verified) |
| AC5 (U5) | `hooks/local/bootstrap-upgrade.sh` (clone → copy engine → exec upgrade.sh); README one-liner documented |
| AC6 (U6) | `lightweight-lane` skill + `change-note` template reworded: ledger opt-in / path-configurable; canonical agent/workflow refs softened |
| AC7 (U7) | begin-line-0 rebuild trims a trailing `---`; recovery-sim "U7: legacy marker-less CLAUDE.md migrates to a single wrapped block (no doubled ---)" PASS; F2 byte-exact lock still PASS |
| AC8 (U8) | `tr -d '\0'` in the scan; dry-run emits no null-byte warning |
| AC9 | preflight 0/0 · run-tests 16/16 · recovery sim PASS · health HEALTHY (24) · mirror drift 0 · plugin validate clean · no competitor names · internal/+repo-polish untracked |

## Related

- `docs/specs/upgrade-path-hardening-2/decisions.md`
- `docs/release-notes/v3.8.md`
- prior: `docs/specs/upgrade-path-hardening/` (v3.6.0), `docs/specs/lightweight-lane/` (v3.7.0)
