# Tasks — provider-skill-drift-guards

**T-counter going in:** T9 (next task is T10)
**Task range:** T10..T17
**Gate task:** T17
**Deploy task:** N/A — framework/template change, no production deploy
**Linked spec:** `docs/specs/provider-skill-drift-guards/spec.md`
**Linked decisions:** `docs/specs/provider-skill-drift-guards/decisions.md`

## Task chain

| T# | Track | Scope | Cites decision | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T10 | docs | Doc-accuracy: FR-18→FR-19; `run-typecheck-features.js`→`run-typecheck-apps.js` in tracked docs. | B7 | — | b35afa4 | done |
| T11 | manifest/tooling | Pin CLI app-agents by explicit `known_names`; checker iterates list (no glob); update tests. | B4 | — | 5f44d68 | done |
| T12 | hooks | Consolidate Stop hooks onto node; wire node hooks in settings example; deprecate/remove jq/bash duplicates; update docs. | B5 | — | f6fb7ef | done |
| T13 | provenance | Add `audit/cli-vendor-manifest.json` + `hooks/local/stamp-cli-provenance.sh` generator (skills+refs+agents+hooks); optional preflight check. | B2 | — | 22410b9 | done |
| T14 | tooling/health | Make conflict reporter drift-aware (`CLI_SNAPSHOT_STALE`) + CUSTOM:SKILL at-risk scan; update health-check skill text + mirrors; update tests. | B3 | T11, T13 | 9448fb2 | done |
| T15 | docs | Non-clobber install copy for CLI-owned paths; document two-writer hazard in `fusebase-cli-edition.md`. | B6 | — | b09695d | done |
| T16 | release | VERSION→3.2.0; CHANGELOG entry; `docs/release-notes/v3.2.md`; README health/recovery refresh. | B8 | T10..T15 | abb0e11 | done |
| T17 | gate | Run validation gate; produce gate report. No commit. | B1..B8 | T10..T16 | — | done (CLEAN_TO_FLIP) |

## Per-task detail

### T10. Doc-accuracy fixes
**Track:** docs
**Scope:** `docs/install-existing-project.md:250` `FR-01..FR-18`→`FR-01..FR-19`. Grep all TRACKED (non-gitignored) files for `run-typecheck-features.js`; replace with `run-typecheck-apps.js` (README.md health-check list + any others). Do NOT touch `docs/fusebase-health/**` (gitignored).
**Files:** `docs/install-existing-project.md`, `README.md`, plus any tracked grep hits.
**Cites:** B7 · **Depends on:** — · **Acceptance:** AC7
**Tests:** `git grep -n "run-typecheck-features.js"` → none in tracked files; `git grep -n "FR-01..FR-18"` → none.
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T11. Pin CLI app-agents by name
**Track:** manifest/tooling
**Scope:** In `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json` replace the two `app-*.md` wildcard entries (`.claude/agents`, `.codex/agents`) with explicit `known_names: ["app-architect","app-create-checker"]` mirroring the skill block shape. Update `hooks/local/check-cli-flow-conflicts.sh` agent branch to iterate `known_names` (remove `glob("app-*.md")`); ensure a non-listed `app-*` agent falls to the flow-agent branch. Update `hooks/tests/test-cli-flow-recovery.sh` expectations.
**Files:** `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json`, `hooks/local/check-cli-flow-conflicts.sh`, `hooks/tests/test-cli-flow-recovery.sh`
**Cites:** B4 · **Depends on:** — · **Acceptance:** AC4
**Tests:** `bash hooks/local/check-cli-flow-conflicts.sh` healthy; recovery test PASS; add a case proving a synthetic `app-foo.md` Flow agent is flow-owned.
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T12. Consolidate Stop hooks onto node
**Track:** hooks
**Scope:** Inspect `.claude/hooks/quality-check-apps.js` to confirm lint+typecheck coverage. Update `.claude/settings.json.example` Stop block to wire node hooks (`run-typecheck-apps.js` + node lint path) and unwire `run-typecheck-on-stop.sh` / `run-lint-on-stop.sh`. If node fully covers both: delete the two `.sh`; else add a deprecation header and leave unwired. Update any docs/hook README referencing the `.sh` hooks.
**Files:** `.claude/settings.json.example`, `.claude/hooks/*` (as decided), `hooks/README.md`/docs as needed
**Cites:** B5 · **Depends on:** — · **Acceptance:** AC5
**Tests:** confirm no wired Stop hook calls `jq`; `node .claude/hooks/run-typecheck-apps.js` parses; preflight clean.
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T13. CLI vendor provenance manifest + generator
**Track:** provenance
**Scope:** Add `hooks/local/stamp-cli-provenance.sh` that enumerates vendored CLI-owned assets (the 19 provider skills incl. `references/**` under `.claude/skills` and `.agents/skills`, the 2 app-agents under `.claude/agents` + `.codex/agents`, the 4 `.claude/hooks/*` files — drive the skill/agent name lists from `agent-surface-ownership.json` `known_names`) and writes `audit/cli-vendor-manifest.json`: `{ generated_at, source_cli_version: "unknown", assets: [{path, sha256}] }`. Read-only/idempotent. Optionally add a preflight info-check that the manifest exists and parses.
**Files:** `hooks/local/stamp-cli-provenance.sh`, `audit/cli-vendor-manifest.json`, `hooks/local/preflight.sh` (optional info check), `audit/README.md` (note new manifest)
**Cites:** B2 · **Depends on:** — · **Acceptance:** AC1
**Tests:** run generator; `python -c "import json,..."` parse; sha of a known file matches `sha256sum`.
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T14. Drift-aware reporter + CUSTOM scan + health text
**Track:** tooling/health
**Scope:** Extend `check-cli-flow-conflicts.sh`: for each present CLI asset, compare sha256 vs `cli-vendor-manifest.json` → advisory `CLI_SNAPSHOT_STALE` (info, non-failing) when changed; keep `MISSING→CLI_LAYER_DRIFT`. Add a `CUSTOM:SKILL` block scan over CLI-owned skills → "at-risk on next refresh" list. Update the health-check verdict/`Recovery Boundary` text in canonical `skills/fusebase-flow-health-check/SKILL.md` and re-mirror to `.claude` + `.agents` + overlay template via `mirror-skills.sh`. Update `hooks/tests/test-cli-flow-recovery.sh` to cover stale + CUSTOM cases.
**Files:** `hooks/local/check-cli-flow-conflicts.sh`, `skills/fusebase-flow-health-check/SKILL.md`, mirrors (via `mirror-skills.sh`), `hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md`, `hooks/tests/test-cli-flow-recovery.sh`, `audit/skill-mirror-manifest.txt` (refreshed by mirror)
**Cites:** B3 · **Depends on:** T11, T13 · **Acceptance:** AC2, AC3
**Tests:** mutate a copied fixture skill → reporter shows `CLI_SNAPSHOT_STALE`; inject a CUSTOM block → reported at-risk; recovery test PASS; preflight clean (mirror drift 0).
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T15. Non-clobber install + two-writer doc
**Track:** docs
**Scope:** Edit `docs/install-existing-project.md` (and `docs/install-fusebase-cli-project.md`) so CLI-owned paths (`.claude/skills/<cli>`, `.claude/hooks`, `.claude/agents/app-*`, `.agents/skills/<cli>`, `.codex/agents/app-*`) copy only-if-absent or are excluded from the recursive `cp -R` / PowerShell `-Force` step; Flow-owned paths copy normally. Add a "Two-writer hazard" subsection to `docs/fusebase-cli-edition.md` (fusebase update vs Flow snapshot; CUSTOM:SKILL risk; point to the drift reporter).
**Files:** `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`, `docs/fusebase-cli-edition.md`
**Cites:** B6 · **Depends on:** — · **Acceptance:** AC6
**Tests:** doc review; commands inspected to confirm no unconditional overwrite of CLI-owned paths.
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T16. Versioning + changelog + release notes + README
**Track:** release
**Scope:** `VERSION` `3.1`→`3.2.0`; prepend `CHANGELOG.md` v3.2 entry; add `docs/release-notes/v3.2.md`; refresh README "Health check & recovery" for new reporter behavior + provenance manifest + the `stamp-cli-provenance.sh` / drift advisory.
**Files:** `VERSION`, `CHANGELOG.md`, `docs/release-notes/v3.2.md`, `README.md`
**Cites:** B8 · **Depends on:** T10..T15 · **Acceptance:** AC8
**Tests:** preflight clean; README links resolve.
**Worker-undisturbed:** none · **SHA:** <captured>

---

### T17. Verification gate
No code change. AI Developer produces gate report per `verification-gate.md`:
- Per-task SHAs (T10..T16)
- Test counts before/after (`run-tests.sh`, `test-cli-flow-recovery.sh`)
- Preflight status; mirror-drift status
- `check-cli-flow-conflicts.sh` + `fusebase-flow-health-check.sh` verdicts
- Provenance manifest presence/parse
- Baseline-protection non-regression confirmation (mirror canonical-only; `flow_write_mode:"never"` intact)
- PO/Architect deviations

After gate report, **stop**. No production deploy applies. Operator reviews; PO runs `code-review` + `security-permissions-review`, then a single docs commit flips spec DRAFT→DONE.

## Task chain audit

| Constitution invariant | Affirmed in tasks |
|---|---|
| Worker-undisturbed | none — all tasks declare no downstream worker paths |
| Mixed-fleet | N/A (edition template; additive) |
| Migration approach | no migration; additive manifest + checker logic + docs |
