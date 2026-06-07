# Spec — handoff-path-migration

**Status:** LOCKED (operator-locked decision; mechanical migration)
**Created:** 2026-06-07
**Lands in:** framework v3.13.0
**Tier:** 4 (cross-cutting, deploy-safety-sensitive migration) per FR-23

## Problem

Handoff artifacts live in two places: active continuity at `docs/tmp/handoff.md` (since v3.12.0) and formal implement/deploy relays at `docs/handoff/*`. Handoffs are operational/transient AI-workflow artifacts, not durable product docs; they should all live under `docs/tmp/handoff`. Deferred from the v3.12.1 patch because formal relays are load-bearing for the deploy-safety gate and must move atomically.

## Decision (operator-locked)

Migrate ALL handoff artifacts under `docs/tmp/handoff`:

```
docs/tmp/handoff.md                              active restart state (overwritten/superseded)
docs/tmp/handoff/<date>-<slug>-implement.md      formal implement relay (when needed)
docs/tmp/handoff/<date>-<slug>-deploy.md         formal deploy relay (when needed)
```

`docs/tmp/` is git-tracked → audit trail preserved.

## Scope (acceptance criteria)

- AC1: `policies/required-artifacts.yml` `before_deploy_command` path_glob and `smoke_results_present` signal → `docs/tmp/handoff/...`.
- AC2: `policies/gate-contracts.yml` smoke-dir pattern → `^docs/tmp/handoff/...`.
- AC3: `hooks/handlers/stop.py` smoke regex → `docs/tmp/handoff/.*-smoke/`.
- AC4: hook fixtures 13 + 14 transcript paths → `docs/tmp/handoff/...` (deploy-gate fixtures stay green).
- AC5: all live workflow / agent (+ mirrors) / template / flow-skill (+ mirrors) references → `docs/tmp/handoff`.
- AC6: baselines (AGENTS.md) + providers (.cursor, .github) + README + live docs → `docs/tmp/handoff`.
- AC7: FLOW_RULES FR-23 row + implication (live text) → `docs/tmp/handoff/*`; amendment log preserved.
- AC8: `sync-version-strings.sh` prune list adds `docs/tmp/handoff` (dated relays protected from version sweep).
- AC9: deploy-safety semantics preserved; **run-tests 16/16 PASS**; preflight 0/0.
- AC10: history preserved — CHANGELOG, release-notes, docs/specs/*, docs/changes/*, FLOW_RULES amendment log, and existing dated artifacts in `docs/handoff/` are NOT rewritten. `docs/handoff/` becomes a historical archive (README redirects to `docs/tmp/handoff/`).

## Non-goals

- Repo-wide version-string attestation sweep (separate, still deferred).
- Relocating the 5 existing dated `docs/handoff/` artifacts (kept as archive).

## Rollback

`git revert <SHA>` — single commit; markdown/yaml/py/json text only, no schema/data. Tag `v3.13.0`.
