# Decisions — upgrade-path-hardening

**Letter prefix:** F
**Approval status:** Locked by operator ("option C, fix everything") on 2026-05-31
**Linked spec:** `docs/specs/upgrade-path-hardening/spec.md`
**Source:** verified operator feedback from upgrading WorkHub Managed (2026-05-31). All 8 claims checked against code.

| ID | Title | Decision | Lock |
|---|---|---|---|
| F1 | Content upgrade tool | New `hooks/local/upgrade.sh` — refreshes canonical content from clone + re-mirror + bump VERSION as one atomic unit (VERSION never leads content) | LOCKED |
| F2 | Stale-overlay refresh | Recovery/upgrade compares present overlay block to template; offers replace-with-backup when drifted (not skip) | LOCKED |
| F3 | Opt-in hook wiring | settings.json hook merge becomes opt-in (`--wire-hooks` flag); default prints a loud "settings.json NOT modified — run with --wire-hooks" notice; never touches hooks the merge didn't add | LOCKED |
| F4 | Single-provider health | CLI provider skills/agents: 0-present = benign INFO ("not installed"); partial = genuine drift. Absent whole provider surface never → CLI_LAYER_DRIFT | LOCKED |
| F5 | Plain-dir clone | `upgrade-engine.sh` + new `upgrade.sh` accept a plain `.fusebase-flow-source/` dir (warn, not FATAL, if no `.git`); health upstream-compare already soft | LOCKED |
| F6 | .pyc hygiene | gitignore rule already present (verified); add a one-time scrub note + keep | LOCKED |
| F7 | Version-string derivation | Add `hooks/local/sync-version-strings.sh` that rewrites embedded `vX.Y.Z` self-attestation strings from VERSION; call it from upgrade.sh; fix current v3.5.0→v3.5.2 now | LOCKED |
| F8 | Mirror-order docs | Document "refresh canonical skills/ first, then mirror" in upgrade.sh + README | LOCKED |

## F1 — upgrade.sh is the keystone
The install path is mature; the in-place content-upgrade path is missing. `upgrade-engine.sh` deliberately syncs only 3 scripts + VERSION (verified header lines 26-29), so VERSION advances while skills/FLOW_RULES stay stale. `upgrade.sh` closes this: refresh canonical `skills/ agents/ workflows/ policies/ templates/ FLOW_RULES.md docs(framework)` from the clone, then `mirror-skills.sh`+`mirror-agents.sh`, then `sync-version-strings.sh`, then bump VERSION — all-or-nothing, with backups and a consolidated diff. Reuses upgrade-engine's safe patterns (backup suffix, dry-run, confirm).

## F2 — version-aware overlay refresh
`post-fusebase-update.sh` Steps 3/4 use `grep -qF "$MARKER"` → skip if present (verified lines 69, 88). On a version upgrade a present-but-stale block is exactly the case that must refresh. Add: when the marker is present, compare the block to the template; if it differs, in upgrade context offer replace-with-`.pre-refresh` backup. Keep recovery's "missing→add" behavior intact.

## F3 — opt-in hook wiring
`post-fusebase-update.sh` Step 5 auto-merges lifecycle hooks into settings.json (verified) — contradicts CLAUDE.md "hooks are opt-in: nothing runs until you copy settings.json.example." Default recovery must NOT modify settings.json unless `--wire-hooks` is passed; print a loud notice either way; never rewrite a hook the merge didn't add.

## F4 — single-provider benign-absence
Root cause (verified `check-cli-flow-conflicts.sh:331,359`): per-skill `MISSING` for absent CLI provider skills when the mirror dir exists → CLI_LAYER_DRIFT. A Claude-only / Flow-only project that never had the 19 CLI skills gets a RED "structurally damaged" verdict after a clean upgrade. Fix heuristic: count present vs known; **0 present → one INFO line** ("CLI provider skills not installed — benign for non-FuseBase-Apps projects"); **all present → OK**; **partial → MISSING drift** (genuine). Soften MISSING wording from "structurally damaged"/"run CLI refresh" to name the never-installed case. Same for provider agents.

## F5 — plain-dir clone
`upgrade-engine.sh:70` FATALs without `$SOURCE_CLONE/.git`, but install docs copy the clone minus `.git`. Relax: accept a plain dir (use VERSION-only comparison, warn that upstream HEAD/diff is unavailable). Don't change install docs (keeping `.git` is heavier for downstreams); make tools tolerant instead.

## F6–F8
F6: gitignore already has `__pycache__/`,`*.pyc`,`*.pyo` (verified 38-40); add a scrub line to upgrade.sh + note. F7: embedded `v3.5.0` strings in agents/claude/gemini overlays + adapters while VERSION=3.5.2 (verified) — derive at upgrade time + fix now. F8: doc the canonical→mirror order.

## Lock confirmation
All F1..F8 LOCKED 2026-05-31 (operator delegated, "fix everything"). Implementation authorized.
